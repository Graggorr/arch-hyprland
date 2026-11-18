#!/usr/bin/env python3
"""Discord RPC bridge for the dynamic island.

Discord's desktop client listens on a local socket and speaks a small framed
JSON protocol. That is the only way to reach its real self-mute and self-deafen
state from outside: the PipeWire scripts this replaces mute the *device*, so the
far end hears silence while Discord still shows you as unmuted.

What this deliberately does NOT do is screen share. The documented RPC command
set has nineteen commands and none of them touch Go Live, streaming or video,
so there is nothing to call. Keystroke injection was already ruled out on this
machine on 2026-08-21 (Discord's Linux build ignores its own keybinds under
native Wayland even when the compositor provably delivers the key).

Modes:
    auth      one-time consent + token exchange, writes the token store
    serve     long-running: JSON state lines on stdout, commands on stdin
    mute|deaf on|off|toggle   one-shot, for a keybind

Credentials:
    client_id     ~/.config/quickshell/discord-rpc.json   (not secret)
    client_secret gnome-keyring, via secret-tool          (secret)
    tokens        ~/.local/state/quickshell/discord-rpc-token.json, mode 600

The authorization-code grant is used rather than the implicit one purely for
the refresh token: implicit needs no client_secret, but Discord never issues a
refresh token with it, so access would lapse in a week and the consent popup
would come back every time.
"""
import json
import os
import re
import select
import socket
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

OP_HANDSHAKE, OP_FRAME, OP_CLOSE, OP_PING, OP_PONG = 0, 1, 2, 3, 4

SCOPES = ["rpc", "rpc.voice.read", "rpc.voice.write"]
API = "https://discord.com/api/v10"

# Cloudflare sits in front of discord.com/api and drops urllib's default
# User-Agent outright: the token exchange comes back 403 with a body of
# "error code: 1010" — a Cloudflare browser-signature ban, not anything
# Discord said. Any explicit UA gets through; measured 2026-08-27, the
# default was the only one refused. This is the documented format.
USER_AGENT = "DiscordBot (https://quickshell.org, 1.0)"

CONFIG = os.path.expanduser("~/.config/quickshell/discord-rpc.json")
TOKENS = os.path.expanduser("~/.local/state/quickshell/discord-rpc-token.json")

# Discord answers on the first free index; a second client (or a stale socket)
# pushes it along, so all ten are worth trying rather than assuming -0.
def socket_paths():
    base = os.environ.get("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid())
    for i in range(10):
        yield os.path.join(base, "discord-ipc-%d" % i)


def load_config():
    try:
        with open(CONFIG) as f:
            cfg = json.load(f)
    except FileNotFoundError:
        return None
    if not cfg.get("client_id"):
        return None
    cfg.setdefault("redirect_uri", "http://localhost:1337/callback")
    return cfg


def client_secret():
    try:
        out = subprocess.run(
            ["secret-tool", "lookup", "service", "discord-rpc", "key", "client_secret"],
            capture_output=True, text=True, timeout=10,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None
    return out.stdout.strip() or None


# A Discord OAuth2 client secret is 32 characters of [A-Za-z0-9_-]. Checked
# before anything else because the failure it prevents is expensive and
# misleading: a malformed secret sails through the handshake and the consent
# popup, then dies on the exchange as a bare 401 invalid_client that reads like
# a permissions problem. Shell quoting is the usual culprit — a value that
# starts with a quote character never came from the prompt.
def check_secret(sec):
    if len(sec) == 32 and re.fullmatch(r"[A-Za-z0-9_-]+", sec):
        return
    why = []
    if len(sec) != 32:
        why.append("length %d, expected 32" % len(sec))
    bad = sorted(set(re.findall(r"[^A-Za-z0-9_-]", sec)))
    if bad:
        why.append("illegal characters: %s" % " ".join(repr(c) for c in bad))
    raise SystemExit(
        "the stored client_secret is not a Discord client secret (%s).\n"
        "Re-store it — OAuth2 -> Client Secret -> Reset Secret, then:\n"
        "  secret-tool clear service discord-rpc key client_secret\n"
        "  secret-tool store --label='Discord RPC' "
        "service discord-rpc key client_secret\n"
        "The prompt is hidden, so paste and press Enter; nothing will echo."
        % "; ".join(why))


def load_tokens():
    try:
        with open(TOKENS) as f:
            return json.load(f)
    except (FileNotFoundError, ValueError):
        return None


def save_tokens(tok):
    os.makedirs(os.path.dirname(TOKENS), exist_ok=True)
    # Written 600 before anything lands in it: the refresh token is a
    # long-lived credential and the home directory is not encrypted.
    fd = os.open(TOKENS, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(tok, f)


class Rpc:
    """One connection to the Discord client."""

    def __init__(self, client_id):
        self.client_id = client_id
        self.sock = None
        self.nonce = 0

    def connect(self):
        for path in socket_paths():
            if not os.path.exists(path):
                continue
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(10)
            try:
                s.connect(path)
            except OSError:
                s.close()
                continue
            self.sock = s
            self.send(OP_HANDSHAKE, {"v": 1, "client_id": self.client_id})
            op, msg = self.recv()
            if op == OP_CLOSE:
                self.close()
                raise RuntimeError(msg.get("message", "handshake refused"))
            return msg
        raise FileNotFoundError("no discord-ipc socket; is Discord running?")

    def close(self):
        if self.sock:
            try:
                self.sock.close()
            except OSError:
                pass
            self.sock = None

    def send(self, op, payload):
        data = json.dumps(payload).encode()
        self.sock.sendall(struct.pack("<II", op, len(data)) + data)

    def recv(self):
        hdr = self._exact(8)
        op, length = struct.unpack("<II", hdr)
        return op, json.loads(self._exact(length).decode())

    def _exact(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise ConnectionError("discord closed the socket")
            buf += chunk
        return buf

    def command(self, cmd, args=None, evt=None):
        """Send a command and return the reply that carries its nonce.

        Replies are not ordered with respect to event dispatches, so anything
        arriving while we wait is an event; it is drained off the socket so
        the reply match cannot jam, and dropped — serve_loop re-polls state
        rather than replaying missed events.
        """
        self.nonce += 1
        nonce = str(self.nonce)
        frame = {"cmd": cmd, "args": args or {}, "nonce": nonce}
        if evt:
            frame["evt"] = evt
        self.send(OP_FRAME, frame)
        while True:
            op, msg = self.recv()
            if op == OP_PING:
                self.send(OP_PONG, msg)
                continue
            if op == OP_CLOSE:
                raise ConnectionError(msg.get("message", "closed"))
            if msg.get("nonce") == nonce:
                if msg.get("evt") == "ERROR":
                    raise RuntimeError(msg["data"].get("message", "rpc error"))
                return msg.get("data")


def exchange(cfg, secret, grant):
    body = dict(grant)
    body["client_id"] = cfg["client_id"]
    body["client_secret"] = secret
    req = urllib.request.Request(
        API + "/oauth2/token",
        data=urllib.parse.urlencode(body).encode(),
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "User-Agent": USER_AGENT,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            tok = json.load(r)
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:300]
        if "1010" in detail:
            detail += ("  <- Cloudflare refused the User-Agent, not Discord. "
                       "The request never reached the API.")
        raise SystemExit("token exchange failed (%s): %s" % (e.code, detail))
    tok["expires_at"] = time.time() + int(tok.get("expires_in", 0)) - 120
    return tok


def ensure_token(cfg):
    """A usable access token, refreshed if it is close to expiring."""
    tok = load_tokens()
    if not tok:
        return None
    if tok.get("expires_at", 0) > time.time():
        return tok["access_token"]
    secret = client_secret()
    if not secret:
        return None
    tok = exchange(cfg, secret, {
        "grant_type": "refresh_token",
        "refresh_token": tok["refresh_token"],
    })
    save_tokens(tok)
    return tok["access_token"]


def cmd_auth():
    cfg = load_config()
    if not cfg:
        raise SystemExit("no client_id — write %s first (see --help)" % CONFIG)
    secret = client_secret()
    if not secret:
        raise SystemExit(
            "no client_secret in the keyring. Store it with:\n"
            "  secret-tool store --label='Discord RPC' service discord-rpc key client_secret"
        )
    check_secret(secret)

    rpc = Rpc(cfg["client_id"])
    rpc.connect()
    print("connected — approve the popup in Discord", file=sys.stderr)
    # AUTHORIZE blocks on the user clicking through Discord's own consent
    # dialog, so it gets a long timeout rather than the default.
    rpc.sock.settimeout(180)
    data = rpc.command("AUTHORIZE", {
        "client_id": cfg["client_id"],
        "scopes": SCOPES,
    })
    tok = exchange(cfg, secret, {
        "grant_type": "authorization_code",
        "code": data["code"],
        "redirect_uri": cfg["redirect_uri"],
    })
    save_tokens(tok)
    rpc.command("AUTHENTICATE", {"access_token": tok["access_token"]})
    print("authorized; token stored at %s" % TOKENS, file=sys.stderr)
    rpc.close()


def voice_state(rpc):
    settings = rpc.command("GET_VOICE_SETTINGS")
    # Every key is always present, empties included. serve_loop merges this into
    # the running state, so a key that is simply absent once the user leaves a
    # channel leaves the previous channel name standing and the island keeps
    # showing a call that ended.
    out = {"mute": bool(settings.get("mute")), "deaf": bool(settings.get("deaf")),
           "channel": "", "users": 0, "guild": ""}
    try:
        chan = rpc.command("GET_SELECTED_VOICE_CHANNEL")
    except RuntimeError:
        chan = None
    if chan:
        out["channel"] = chan.get("name", "")
        out["users"] = len(chan.get("voice_states") or [])
        out["guild"] = (chan.get("guild_id") or "")
    return out


def apply(rpc, field, value, current):
    if value == "toggle":
        value = not current.get(field, False)
    value = bool(value) if not isinstance(value, str) else value in ("on", "true", "1")
    rpc.command("SET_VOICE_SETTINGS", {field: value})
    return value


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def cmd_serve():
    """Hold the connection open, print state, take commands on stdin.

    One process rather than a command per click: AUTHENTICATE costs a round
    trip and Discord rate-limits reconnections, so a button that reconnected
    every time would feel slow and eventually get refused.
    """
    cfg = load_config()
    while True:
        if not cfg:
            emit({"connected": False, "authed": False, "reason": "no client_id"})
            time.sleep(15)
            cfg = load_config()
            continue

        rpc = Rpc(cfg["client_id"])
        try:
            rpc.connect()
        except (FileNotFoundError, RuntimeError, OSError, ConnectionError) as e:
            emit({"connected": False, "authed": False, "reason": str(e)})
            time.sleep(5)
            continue

        token = ensure_token(cfg)
        if not token:
            emit({"connected": True, "authed": False, "reason": "not authorized"})
            rpc.close()
            time.sleep(15)
            continue

        try:
            rpc.command("AUTHENTICATE", {"access_token": token})
            for evt in ("VOICE_SETTINGS_UPDATE", "VOICE_CHANNEL_SELECT"):
                rpc.command("SUBSCRIBE", {}, evt=evt)
            state = voice_state(rpc)
            emit(dict(state, connected=True, authed=True))
            rpc.sock.settimeout(None)
            serve_loop(rpc, state)
        except (ConnectionError, RuntimeError, OSError, ValueError) as e:
            emit({"connected": False, "authed": False, "reason": str(e)})
        finally:
            rpc.close()
        time.sleep(3)


def serve_loop(rpc, state):
    """select() over the socket and stdin — both are just file descriptors."""
    stdin = sys.stdin
    while True:
        ready, _, _ = select.select([rpc.sock, stdin], [], [], 30)
        if not ready:
            # The events are the fast path, this is the floor: a
            # VOICE_CHANNEL_SELECT that never arrives would otherwise strand the
            # island in a call until the bridge restarts. Emitting only on a
            # change keeps the idle case silent.
            fresh = voice_state(rpc)
            if fresh != state:
                state.update(fresh)
                emit(dict(state, connected=True, authed=True))
            continue

        if rpc.sock in ready:
            op, msg = rpc.recv()
            if op == OP_PING:
                rpc.send(OP_PONG, msg)
            elif op == OP_CLOSE:
                raise ConnectionError(msg.get("message", "closed"))
            elif msg.get("evt") in ("VOICE_SETTINGS_UPDATE", "VOICE_CHANNEL_SELECT"):
                state.update(voice_state(rpc))
                emit(dict(state, connected=True, authed=True))

        if stdin in ready:
            line = stdin.readline()
            if not line:
                raise SystemExit(0)
            line = line.strip()
            if not line:
                continue
            try:
                req = json.loads(line)
            except ValueError:
                continue
            field = req.get("cmd")
            if field in ("mute", "deaf"):
                apply(rpc, field, req.get("value", "toggle"), state)
                state.update(voice_state(rpc))
                emit(dict(state, connected=True, authed=True))


def cmd_oneshot(field, value):
    cfg = load_config()
    if not cfg:
        raise SystemExit("no client_id — write %s first" % CONFIG)
    token = ensure_token(cfg)
    if not token:
        raise SystemExit("not authorized — run: discord-rpc.py auth")
    rpc = Rpc(cfg["client_id"])
    rpc.connect()
    rpc.command("AUTHENTICATE", {"access_token": token})
    state = voice_state(rpc)
    now = apply(rpc, field, value, state)
    rpc.close()
    print("%s %s" % (field, "on" if now else "off"))


USAGE = """usage: discord-rpc.py {auth|serve|mute|deaf} [on|off|toggle]

Setup, once:
  1. https://discord.com/developers/applications -> New Application
  2. OAuth2 -> add redirect URI  http://localhost:1337/callback
  3. echo '{"client_id":"YOUR_ID"}' > ~/.config/quickshell/discord-rpc.json
  4. secret-tool store --label='Discord RPC' \\
       service discord-rpc key client_secret
  5. discord-rpc.py auth        # approve the popup in Discord

There is no tester step, and the portal is right to refuse you one.
Discord: "unless the application is approved for general RPC access,
the rpc scope is allowed for the application owner and whitelisted
users only" -- owning the app already qualifies. The tester list is
for granting access to other people, so an owner cannot be added to
their own.

Screen share is not reachable: the RPC command set has no Go Live,
streaming or video command at all.
"""


def main():
    argv = sys.argv[1:]
    if not argv or argv[0] in ("-h", "--help"):
        sys.stdout.write(USAGE)
        return
    mode = argv[0]
    if mode == "auth":
        cmd_auth()
    elif mode == "serve":
        cmd_serve()
    elif mode in ("mute", "deaf"):
        cmd_oneshot(mode, argv[1] if len(argv) > 1 else "toggle")
    else:
        sys.stdout.write(USAGE)
        raise SystemExit(2)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
