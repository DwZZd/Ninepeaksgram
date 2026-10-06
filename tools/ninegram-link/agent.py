#!/usr/bin/env python3
"""Opens AyuGram on this PC and keeps its login QR waiting.

Ninegram accepts that QR after a phone login, so the account appears in
AyuGram and the window is already open. Each account gets its own AyuGram
profile because one window cannot hold all of them.
"""

import base64
import json
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import numpy as np
import zxingcpp
from PIL import ImageGrab

import ctypes
from ctypes import wintypes

ROOT = Path.home() / ".ninegram-link"
AYUGRAM_SOURCE = Path(r"D:\Home\Desktop\ayu\AyuGram.exe")
AYUGRAM = AYUGRAM_SOURCE.with_name("AyuGram-ninegram.exe")
CONFIG_PATH = ROOT / "config.json"
PROFILES = ROOT / "ayugram"

user32 = ctypes.windll.user32
user32.SetWindowPos.argtypes = [
    wintypes.HWND,
    wintypes.HWND,
    ctypes.c_int,
    ctypes.c_int,
    ctypes.c_int,
    ctypes.c_int,
    ctypes.c_uint,
]

SW_RESTORE = 9
SW_SHOW = 5
HWND_TOPMOST = wintypes.HWND(-1)
SWP_NOSIZE = 0x0001
SWP_NOMOVE = 0x0002
SWP_SHOWWINDOW = 0x0040


def load_config():
    with CONFIG_PATH.open("r", encoding="utf-8-sig") as handle:
        config = json.load(handle)
    for key in ("write_secret", "base_url"):
        if not config.get(key):
            raise SystemExit(f"config.json is missing {key}")
    return config


def request(config, path, payload):
    data = json.dumps(payload).encode("utf-8")
    url = config["base_url"].rstrip("/") + path
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "X-Ninegram-Key": config["write_secret"],
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            response.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"POST {path} failed: {error.code} {detail}") from error


def normalize_token(url):
    if "token=" not in url:
        return None
    token = url.split("token=", 1)[1].split("&", 1)[0].strip()
    token = token.replace("-", "+").replace("_", "/")
    token += "=" * ((-len(token)) % 4)
    base64.b64decode(token, validate=True)
    return token


def hwnds_for_pid(pid):
    found = []

    @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def callback(hwnd, _lparam):
        process_id = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(process_id))
        if process_id.value == pid and user32.IsWindowVisible(hwnd):
            found.append(hwnd)
        return True

    user32.EnumWindows(callback, 0)
    return found


def capture(hwnd):
    rect = wintypes.RECT()
    if not user32.GetWindowRect(hwnd, ctypes.byref(rect)):
        return None
    if user32.IsIconic(hwnd):
        user32.ShowWindow(hwnd, SW_RESTORE)
        time.sleep(0.2)
        user32.GetWindowRect(hwnd, ctypes.byref(rect))
    width = rect.right - rect.left
    height = rect.bottom - rect.top
    if width < 50 or height < 50:
        return None
    image = ImageGrab.grab(bbox=(rect.left, rect.top, rect.right, rect.bottom), all_screens=True)
    return np.array(image)


def read_token(hwnd):
    image = capture(hwnd)
    if image is None:
        return None
    for result in zxingcpp.read_barcodes(image):
        token = normalize_token(result.text or "")
        if token:
            return token
    return None


def next_profile():
    PROFILES.mkdir(parents=True, exist_ok=True)
    numbers = []
    for path in PROFILES.iterdir():
        if path.is_dir() and path.name.startswith("account-"):
            digits = "".join(ch for ch in path.name if ch.isdigit())
            if digits:
                numbers.append(int(digits))
    return PROFILES / f"account-{max(numbers, default=0) + 1:03d}"


def prepare_binary(config):
    api_hash = str(config["api_hash"]).encode("ascii")
    api_id = int(config["api_id"]).to_bytes(4, "little")
    if len(api_hash) != 32:
        raise SystemExit("api_hash must be 32 characters")
    if not AYUGRAM.exists():
        shutil.copy2(AYUGRAM_SOURCE, AYUGRAM)
    data = bytearray(AYUGRAM.read_bytes())
    official = b"b18441a1ff607e10a989891a5462e627"
    if official in data:
        data = data.replace(official, api_hash)
    elif api_hash not in data:
        raise SystemExit("AyuGram API hash was not found")
    for rva, prefix in (
        (0x2641990, bytes.fromhex("41b8")),
        (0x167464b, bytes.fromhex("ba")),
        (0x265033f, bytes.fromhex("ba")),
    ):
        off = 0x400 + (rva - 0x1000)
        if data[off - len(prefix):off] != prefix:
            raise SystemExit(f"API id instruction changed at {hex(off)}")
        if data[off:off + 4] == bytes.fromhex("f8070000"):
            data[off:off + 4] = api_id
        elif data[off:off + 4] != api_id:
            raise SystemExit(f"unexpected API id at {hex(off)}")
    AYUGRAM.write_bytes(data)
    return AYUGRAM


def phone_wants(config):
    data = b"{}"
    url = config["base_url"].rstrip("/") + "/v1/want"
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "X-Ninegram-Key": config["write_secret"],
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as response:
        payload = json.loads(response.read().decode("utf-8"))
    return bool(payload.get("wanted"))


def fetch_password(config):
    url = config["base_url"].rstrip("/") + "/v1/password/take"
    req = urllib.request.Request(
        url,
        data=b"{}",
        headers={
            "X-Ninegram-Key": config["write_secret"],
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            if response.status == 204:
                return None
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        if error.code == 204:
            return None
        raise
    return payload.get("password") or None


def clear_token(config):
    try:
        request(config, "/v1/clear", {"token": ""})
    except Exception:
        pass


def type_password(hwnd, password):
    user32.ShowWindow(hwnd, SW_RESTORE)
    user32.SetForegroundWindow(hwnd)
    time.sleep(0.4)

    KEYEVENTF_KEYUP = 0x0002
    KEYEVENTF_UNICODE = 0x0004

    class KEYBDINPUT(ctypes.Structure):
        _fields_ = [
            ("wVk", ctypes.c_ushort),
            ("wScan", ctypes.c_ushort),
            ("dwFlags", ctypes.c_uint),
            ("time", ctypes.c_uint),
            ("dwExtraInfo", ctypes.c_ulonglong),
        ]

    class INPUT(ctypes.Structure):
        _fields_ = [("type", ctypes.c_uint), ("ki", KEYBDINPUT)]

    def key(scan, flags):
        item = INPUT(type=1, ki=KEYBDINPUT(0, scan, flags, 0, 0))
        ctypes.windll.user32.SendInput(1, ctypes.byref(item), ctypes.sizeof(item))

    for char in password:
        key(ord(char), KEYEVENTF_UNICODE)
        key(ord(char), KEYEVENTF_UNICODE | KEYEVENTF_KEYUP)
    key(0x0D, 0)
    key(0x0D, KEYEVENTF_KEYUP)
    print("entered the saved cloud password", flush=True)


def wait_for_login(config, process, hwnd, profile):
    published = None
    published_at = 0.0
    password_sent = False
    qr_missing = 0
    while process.poll() is None:
        token = read_token(hwnd)
        now = time.time()
        if token:
            qr_missing = 0
            if token != published or now - published_at > 10:
                request(config, "/v1/token", {"token": token})
                if token != published:
                    print(f"waiting in {profile.name}", flush=True)
                published = token
                published_at = now
        else:
            qr_missing += 1
            if (profile / "tdata" / "user_data").exists() and qr_missing >= 2:
                clear_token(config)
                print(f"AyuGram opened {profile.name}", flush=True)
                return True
            if qr_missing >= 2 and not password_sent:
                password = fetch_password(config)
                if password:
                    type_password(hwnd, password)
                    password_sent = True
            elif published and now - published_at > 10:
                request(config, "/v1/token", {"token": published})
                published_at = now
        time.sleep(2)
    return False


def main():
    if not AYUGRAM_SOURCE.exists():
        raise SystemExit(f"AyuGram not found at {AYUGRAM_SOURCE}")
    config = load_config()
    prepare_binary(config)
    while True:
        try:
            if not phone_wants(config):
                time.sleep(2)
                continue
            profile = next_profile()
            process, hwnd = launch(profile)
            wait_for_login(config, process, hwnd, profile)
            time.sleep(90)
        except Exception as error:
            print(f"agent error: {error}", flush=True)
            time.sleep(5)


def launch(profile):
    profile.mkdir(parents=True, exist_ok=True)
    process = subprocess.Popen(
        [str(AYUGRAM), "-many", "-workdir", str(profile)],
        cwd=str(AYUGRAM_SOURCE.parent),
    )
    deadline = time.time() + 30
    hwnd = None
    while time.time() < deadline:
        found = hwnds_for_pid(process.pid)
        if found:
            hwnd = found[0]
            break
        if process.poll() is not None:
            raise RuntimeError("AyuGram exited before showing a window")
        time.sleep(0.4)
    if hwnd is None:
        process.kill()
        raise RuntimeError("AyuGram window did not appear")
    user32.ShowWindow(hwnd, SW_SHOW)
    user32.SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW)
    return process, hwnd


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
