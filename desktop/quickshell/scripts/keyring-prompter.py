#!/usr/bin/python3
"""Keyring prompter for the island.

gnome-keyring never asks for a password itself: it calls whoever owns
org.gnome.keyring.SystemPrompter, which is normally the GTK dialog from
/usr/lib/gcr-prompter (D-Bus activated). This process owns that name instead
and forwards each prompt to the shell as JSON lines on stdout; the shell
answers on stdin. While the shell is down the name is free again and the
stock dialog is activated as before, so nothing depends on this running.

stdout: {"op":"show","id":N,"type":"password"|"confirm",...} / {"op":"hide"}
stdin:  {"id":N,"ok":true,"password":"...","choice":false} / {"id":N,"ok":false}

The password crosses the bus encrypted with gcr's "sx-aes-1" secret exchange
(DH over the 1536-bit IKE group, HKDF-SHA256, AES-128-CBC).
"""
import base64
import json
import os
import secrets
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from cryptography.hazmat.primitives import hashes, padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from gi.repository import GLib

BUS_NAME = "org.gnome.keyring.SystemPrompter"
PATH = "/org/gnome/keyring/Prompter"
IFACE = "org.gnome.keyring.internal.Prompter"
CALLBACK_IFACE = "org.gnome.keyring.internal.Prompter.Callback"
SECTION = "sx-aes-1"

PRIME = int(
    "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74"
    "020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F1437"
    "4FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED"
    "EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF05"
    "98DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C62F356208552BB"
    "9ED529077096966D670C354E4ABC9804F1746C08CA237327FFFFFFFFFFFFFFFF", 16)


class SecretExchange:
    def __init__(self):
        self.priv = secrets.randbits(1528) | 1
        self.pub = pow(2, self.priv, PRIME)
        self.key = None

    def _public(self):
        raw = self.pub.to_bytes((self.pub.bit_length() + 7) // 8, "big")
        return base64.b64encode(raw).decode()

    def begin(self):
        return "[%s]\npublic=%s\n" % (SECTION, self._public())

    def receive(self, text):
        """Take the peer's message; returns the secret it carried, or None."""
        fields = {}
        section = None
        for line in (text or "").splitlines():
            line = line.strip()
            if line.startswith("[") and line.endswith("]"):
                section = line[1:-1]
            elif section == SECTION and "=" in line:
                k, v = line.split("=", 1)
                fields[k.strip()] = v.strip()
        if "public" in fields:
            peer = int.from_bytes(base64.b64decode(fields["public"]), "big")
            if not 1 < peer < PRIME - 1:
                raise ValueError("bad peer key")
            shared = pow(peer, self.priv, PRIME)
            ikm = shared.to_bytes((shared.bit_length() + 7) // 8, "big")
            self.key = HKDF(hashes.SHA256(), 16, None, None).derive(ikm)
        if "secret" in fields and "iv" in fields and self.key:
            dec = Cipher(algorithms.AES(self.key),
                         modes.CBC(base64.b64decode(fields["iv"]))).decryptor()
            padded = dec.update(base64.b64decode(fields["secret"])) + dec.finalize()
            unpad = padding.PKCS7(128).unpadder()
            return unpad.update(padded) + unpad.finalize()
        return None

    def send(self, secret=None):
        out = "[%s]\npublic=%s\n" % (SECTION, self._public())
        if secret is not None:
            if self.key is None:
                raise ValueError("no transport key")
            iv = os.urandom(16)
            pad = padding.PKCS7(128).padder()
            padded = pad.update(secret) + pad.finalize()
            enc = Cipher(algorithms.AES(self.key), modes.CBC(iv)).encryptor()
            data = enc.update(padded) + enc.finalize()
            out += "secret=%s\niv=%s\n" % (base64.b64encode(data).decode(),
                                           base64.b64encode(iv).decode())
        return out


class Active:
    def __init__(self, sender, path):
        self.sender = sender
        self.path = path
        self.exchange = SecretExchange()
        self.received = False
        self.props = {}
        self.kind = None
        self.prompt_id = 0


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


class Prompter(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, PATH)
        self.bus = bus
        self.active = None
        self.waiting = []
        self.counter = 0
        bus.add_signal_receiver(self.on_owner_changed, "NameOwnerChanged",
                                "org.freedesktop.DBus", "org.freedesktop.DBus",
                                "/org/freedesktop/DBus")

    def call_callback(self, who, method, signature, args, on_error=None):
        self.bus.call_async(who.sender, who.path, CALLBACK_IFACE, method,
                            signature, args,
                            lambda *a: None,
                            on_error or (lambda e: None))

    def send_ready(self, who, reply, secret=None, changed=None):
        if who.received:
            exchange = who.exchange.send(secret)
        else:
            exchange = who.exchange.begin()
        props = dbus.Dictionary(changed or {}, signature="sv")
        self.call_callback(who, "PromptReady", "sa{sv}s", (reply, props, exchange),
                           lambda e: self.drop(who, False))

    def next_ready(self):
        if self.active is None and self.waiting:
            self.active = self.waiting.pop(0)
            self.send_ready(self.active, "")

    def drop(self, who, send_done):
        if who is self.active:
            self.active = None
            emit({"op": "hide"})
        elif who in self.waiting:
            self.waiting.remove(who)
        else:
            return
        if send_done:
            self.call_callback(who, "PromptDone", "", ())
        self.next_ready()

    def find(self, sender, path):
        for who in [self.active] + self.waiting:
            if who and who.sender == sender and who.path == path:
                return who
        return None

    def on_owner_changed(self, name, old, new):
        if new != "":
            return
        for who in [self.active] + list(self.waiting):
            if who and who.sender == name:
                self.drop(who, False)

    @dbus.service.method(IFACE, in_signature="o", out_signature="",
                         sender_keyword="sender")
    def BeginPrompting(self, callback, sender=None):
        if self.find(sender, callback):
            raise dbus.DBusException("Already begun prompting for this prompt callback",
                                     name="org.gnome.keyring.Prompter.InProgress")
        self.waiting.append(Active(sender, str(callback)))
        GLib.idle_add(lambda: self.next_ready() and False)

    @dbus.service.method(IFACE, in_signature="osa{sv}s", out_signature="",
                         sender_keyword="sender")
    def PerformPrompt(self, callback, kind, properties, exchange, sender=None):
        who = self.active
        if who is None or who.sender != sender or who.path != callback:
            raise dbus.DBusException("Not begun prompting for this prompt callback",
                                     name="org.gnome.keyring.Prompter.NotHappening")
        if kind not in ("password", "confirm"):
            raise dbus.DBusException("Invalid type argument",
                                     name="org.freedesktop.DBus.Error.InvalidArgs")
        try:
            who.exchange.receive(str(exchange))
        except Exception:
            raise dbus.DBusException("The secret exchange argument was invalid",
                                     name="org.freedesktop.DBus.Error.InvalidArgs")
        who.received = True
        for k, v in properties.items():
            who.props[str(k)] = v
        who.kind = str(kind)
        self.counter += 1
        who.prompt_id = self.counter
        p = who.props

        def text(key):
            return str(p.get(key, "") or "")

        emit({
            "op": "show",
            "id": who.prompt_id,
            "type": who.kind,
            "title": text("title"),
            "message": text("message"),
            "description": text("description"),
            "warning": text("warning"),
            "choiceLabel": text("choice-label"),
            "choiceChosen": bool(p.get("choice-chosen", False)),
            "passwordNew": bool(p.get("password-new", False)),
            "continueLabel": text("continue-label"),
            "cancelLabel": text("cancel-label"),
        })

    @dbus.service.method(IFACE, in_signature="o", out_signature="",
                         sender_keyword="sender")
    def StopPrompting(self, callback, sender=None):
        who = self.find(sender, callback)
        if who:
            self.drop(who, True)

    def answer(self, msg):
        who = self.active
        if who is None or who.kind is None or msg.get("id") != who.prompt_id:
            return
        who.prompt_id = 0
        if not msg.get("ok"):
            self.send_ready(who, "no")
            return
        changed = {}
        if who.props.get("choice-label"):
            chosen = bool(msg.get("choice"))
            who.props["choice-chosen"] = dbus.Boolean(chosen)
            changed["choice-chosen"] = dbus.Boolean(chosen, variant_level=2)
        secret = None
        if who.kind == "password":
            secret = str(msg.get("password", "")).encode()
        self.send_ready(who, "yes", secret, changed)

    def cancel_all(self):
        for who in [self.active] + list(self.waiting):
            if who:
                self.call_callback(who, "PromptReady", "sa{sv}s",
                                   ("no", dbus.Dictionary({}, signature="sv"),
                                    who.exchange.send() if who.received else who.exchange.begin()))
                self.call_callback(who, "PromptDone", "", ())
        self.active = None
        self.waiting = []


def main():
    name = BUS_NAME
    if len(sys.argv) > 2 and sys.argv[1] == "--name":
        name = sys.argv[2]

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    prompter = Prompter(bus)
    owned = dbus.service.BusName(name, bus, allow_replacement=False,
                                 replace_existing=True, do_not_queue=False)
    loop = GLib.MainLoop()

    def on_stdin(channel, cond):
        if cond & (GLib.IO_HUP | GLib.IO_ERR) and not cond & GLib.IO_IN:
            loop.quit()
            return False
        line = sys.stdin.readline()
        if line == "":
            loop.quit()
            return False
        try:
            msg = json.loads(line)
        except ValueError:
            return True
        if isinstance(msg, dict):
            prompter.answer(msg)
        return True

    GLib.io_add_watch(sys.stdin.fileno(), GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR,
                      on_stdin)
    try:
        loop.run()
    finally:
        prompter.cancel_all()
        bus.flush()
        del owned


if __name__ == "__main__":
    main()
