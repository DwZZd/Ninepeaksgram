#!/usr/bin/env python3
"""Relay between the phone and the PC agent. Binds to localhost; nginx publishes it."""

import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
PORT = 8791
TTL_SECONDS = 90
CONFIG_PATH = "/opt/ninegram-link/config.json"


PASSWORD = {"value": None, "at": 0.0}
PASSWORD_LOCK = threading.Lock()
PASSWORD_TTL = 300


def store_password(password):
    with PASSWORD_LOCK:
        PASSWORD["value"] = password
        PASSWORD["at"] = time.time()


def take_password():
    with PASSWORD_LOCK:
        if not PASSWORD["value"] or time.time() - PASSWORD["at"] > PASSWORD_TTL:
            PASSWORD["value"] = None
            return None
        value = PASSWORD["value"]
        PASSWORD["value"] = None
        return value
LAST_WANT = 0.0
WANT_LOCK = threading.Lock()


def note_want():
    global LAST_WANT
    with WANT_LOCK:
        LAST_WANT = time.time()


def want_age():
    with WANT_LOCK:
        if LAST_WANT <= 0:
            return None
        return time.time() - LAST_WANT


class TokenBox:
    def __init__(self):
        self._lock = threading.Lock()
        self._token = None
        self._stored_at = 0.0

    def put(self, token):
        with self._lock:
            self._token = token
            self._stored_at = time.time()

    def get(self):
        with self._lock:
            if not self._token or time.time() - self._stored_at > TTL_SECONDS:
                return None
            return self._token

    def clear(self):
        with self._lock:
            self._token = None
            self._stored_at = 0.0


TOKENS = TokenBox()


def load_config():
    with open(CONFIG_PATH, "r", encoding="utf-8-sig") as handle:
        config = json.load(handle)
    if not config.get("read_secret") or not config.get("write_secret"):
        raise SystemExit("config.json needs read_secret and write_secret")
    return config


CONFIG = load_config()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        return

    def _key(self):
        return self.headers.get("X-Ninegram-Key", "")

    def _body(self):
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0:
            return {}
        raw = self.rfile.read(length)
        return json.loads(raw.decode("utf-8"))

    def _send(self, code, payload=None):
        body = b""
        if payload is not None:
            body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0].rstrip("/")
        if path == "/health":
            self._send(200, {"ok": True})
            return
        if path != "/v1/token":
            self._send(404, {"error": "not_found"})
            return
        if self._key() != CONFIG["read_secret"]:
            self._send(401, {"error": "unauthorized"})
            return
        token = TOKENS.get()
        if not token:
            note_want()
            self._send(204)
            return
        self._send(200, {"token": token})

    def do_POST(self):
        path = self.path.split("?", 1)[0].rstrip("/")
        try:
            payload = self._body()
        except Exception:
            self._send(400, {"error": "bad_json"})
            return
        token = payload.get("token") or ""
        if path == "/v1/password":
            if self._key() != CONFIG["read_secret"]:
                self._send(401, {"error": "unauthorized"})
                return
            password = payload.get("password") or ""
            if not password:
                self._send(400, {"error": "missing_password"})
                return
            store_password(password)
            self._send(200, {"ok": True})
            return
        if path == "/v1/password/take":
            if self._key() != CONFIG["write_secret"]:
                self._send(401, {"error": "unauthorized"})
                return
            password = take_password()
            if not password:
                self._send(204)
                return
            self._send(200, {"password": password})
            return
        if path == "/v1/want":
            if self._key() != CONFIG["write_secret"]:
                self._send(401, {"error": "unauthorized"})
                return
            age = want_age()
            self._send(200, {"wanted": age is not None and age < 20, "age": age})
            return
        if path == "/v1/token":
            if self._key() != CONFIG["write_secret"]:
                self._send(401, {"error": "unauthorized"})
                return
            if not token:
                self._send(400, {"error": "missing_token"})
                return
            TOKENS.put(token)
            self._send(200, {"ok": True})
            return
        if path == "/v1/consume":
            if self._key() != CONFIG["read_secret"]:
                self._send(401, {"error": "unauthorized"})
                return
            TOKENS.clear()
            self._send(200, {"ok": True})
            return
        if path == "/v1/clear":
            if self._key() != CONFIG["write_secret"]:
                self._send(401, {"error": "unauthorized"})
                return
            TOKENS.clear()
            self._send(200, {"ok": True})
            return
        self._send(404, {"error": "not_found"})


def main():
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
