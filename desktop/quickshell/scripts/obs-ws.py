#!/usr/bin/env python3
"""Minimal obs-websocket v5 client over the standard library.

Exists because neither obs-cli nor a python websocket library is installed, and
OBS's own CLI can only ever *start* a recording (--startrecording) — there is no
flag to stop one, so a toggle button needs the websocket protocol.

Usage: obs-ws.py <status|toggle|start|stop>
Always prints one JSON object; never raises to the caller.
"""
import base64
import hashlib
import json
import os
import socket
import struct
import sys
import time

HOST = "127.0.0.1"
CONFIG = os.path.expanduser("~/.config/obs-studio/plugin_config/obs-websocket/config.json")


def load_config():
    with open(CONFIG) as fh:
        c = json.load(fh)
    return c.get("server_port", 4455), c.get("server_password", "")


class WS:
    """Just enough RFC6455 for one short-lived request/response session."""

    def __init__(self, host, port, timeout=4.0):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall(
            f"GET / HTTP/1.1\r\nHost: {host}:{port}\r\nUpgrade: websocket\r\n"
            f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
            f"Sec-WebSocket-Version: 13\r\n\r\n".encode()
        )
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ConnectionError("handshake closed")
            buf += chunk
        if b"101" not in buf.split(b"\r\n", 1)[0]:
            raise ConnectionError("handshake refused")
        self.rest = buf.split(b"\r\n\r\n", 1)[1]

    def _read(self, n):
        while len(self.rest) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("closed")
            self.rest += chunk
        out, self.rest = self.rest[:n], self.rest[n:]
        return out

    def recv(self):
        while True:
            b0, b1 = self._read(2)
            opcode = b0 & 0x0F
            length = b1 & 0x7F
            if length == 126:
                length = struct.unpack(">H", self._read(2))[0]
            elif length == 127:
                length = struct.unpack(">Q", self._read(8))[0]
            payload = self._read(length)
            if opcode == 0x8:
                raise ConnectionError("server closed")
            if opcode == 0x9:          # ping -> pong
                self._send_frame(payload, 0xA)
                continue
            if opcode in (0x1, 0x2):
                return json.loads(payload.decode())

    def _send_frame(self, payload, opcode=0x1):
        mask = os.urandom(4)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        header = bytes([0x80 | opcode])
        n = len(payload)
        if n < 126:
            header += bytes([0x80 | n])
        elif n < 1 << 16:
            header += bytes([0x80 | 126]) + struct.pack(">H", n)
        else:
            header += bytes([0x80 | 127]) + struct.pack(">Q", n)
        self.sock.sendall(header + mask + masked)

    def send(self, obj):
        self._send_frame(json.dumps(obj).encode())

    def close(self):
        try:
            self._send_frame(b"", 0x8)
            self.sock.close()
        except Exception:
            pass


def connect():
    port, password = load_config()
    ws = WS(HOST, port)
    hello = ws.recv()
    d = hello.get("d", {})
    ident = {"rpcVersion": d.get("rpcVersion", 1)}
    auth = d.get("authentication")
    if auth:
        secret = base64.b64encode(
            hashlib.sha256((password + auth["salt"]).encode()).digest()
        ).decode()
        ident["authentication"] = base64.b64encode(
            hashlib.sha256((secret + auth["challenge"]).encode()).digest()
        ).decode()
    ws.send({"op": 1, "d": ident})
    got = ws.recv()
    if got.get("op") != 2:
        raise ConnectionError("identify refused")
    return ws


def request(ws, kind, data=None):
    ws.send({"op": 6, "d": {"requestType": kind, "requestId": "1",
                            "requestData": data or {}}})
    while True:
        msg = ws.recv()
        if msg.get("op") == 7:
            return msg["d"]


def main():
    verb = sys.argv[1] if len(sys.argv) > 1 else "status"
    try:
        ws = connect()
    except Exception:
        # Not running, or the websocket server is off — both mean "no session",
        # which is a state the caller renders rather than an error.
        print(json.dumps({"running": False, "recording": False}))
        return

    try:
        if verb in ("toggle", "start", "stop"):
            def active():
                rd = request(ws, "GetRecordStatus").get("responseData") or {}
                return bool(rd.get("outputActive"))

            # OBS acknowledges the request before the output has actually
            # flipped, so reading the status straight after reports the state we
            # just left — a start answers "not recording", and the button would
            # paint the wrong thing until the next poll. Wait for the flip.
            # A toggle has no target state of its own, so it is measured against
            # what was true before the request.
            was = active()
            want = (verb == "start") if verb in ("start", "stop") else (not was)
            request(ws, {"toggle": "ToggleRecord", "start": "StartRecord",
                         "stop": "StopRecord"}[verb])
            for _ in range(40):
                if active() == want:
                    break
                time.sleep(0.05)
        res = request(ws, "GetRecordStatus")
        rd = res.get("responseData", {}) or {}
        print(json.dumps({
            "running": True,
            "recording": bool(rd.get("outputActive")),
            "paused": bool(rd.get("outputPaused")),
            "timecode": (rd.get("outputTimecode") or "")[:8],
        }))
    except Exception as exc:
        print(json.dumps({"running": True, "recording": False, "error": str(exc)}))
    finally:
        ws.close()


if __name__ == "__main__":
    main()
