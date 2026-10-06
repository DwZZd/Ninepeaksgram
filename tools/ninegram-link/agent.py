#!/usr/bin/env python3
"""Opens AyuGram on this PC and keeps its login QR waiting.

Ninegram accepts that QR after a phone login, so the account appears in
AyuGram and the window is already open. Each account gets its own AyuGram
profile because one window cannot hold all of them.
"""

import base64
import json
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

AYUGRAM = Path(r"D:\Home\Desktop\ayu\AyuGram.exe")
ROOT = Path.home() / ".ninegram-link"
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
    for path in sorted(PROFILES.iterdir()):
        if path.is_dir() and path.name.startswith("account-") and not (path / "tdata" / "user_data").exists():
            return path
    existing = [path for path in PROFILES.iterdir() if path.is_dir() and path.name.startswith("account-")]
    return PROFILES / f"account-{len(existing) + 1:03d}"


def launch(profile):
    profile.mkdir(parents=True, exist_ok=True)
    process = subprocess.Popen(
        [str(AYUGRAM), "-many", "-workdir", str(profile)],
        cwd=str(AYUGRAM.parent),
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


def wait_for_login(config, process, hwnd, profile):
    published = None
    published_at = 0.0
    while process.poll() is None:
        if (profile / "tdata" / "user_data").exists():
            user32.SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW)
            print(f"AyuGram opened {profile.name}", flush=True)
            return True
        token = read_token(hwnd)
        now = time.time()
        if token:
            if token != published or now - published_at > 10:
                request(config, "/v1/token", {"token": token})
                if token != published:
                    print(f"waiting in {profile.name}", flush=True)
                published = token
                published_at = now
        else:
            user32.SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW)
            if published and now - published_at > 10:
                request(config, "/v1/token", {"token": published})
                published_at = now
        time.sleep(2)
    return False


def main():
    if not AYUGRAM.exists():
        raise SystemExit(f"AyuGram not found at {AYUGRAM}")
    config = load_config()
    while True:
        profile = next_profile()
        try:
            process, hwnd = launch(profile)
            wait_for_login(config, process, hwnd, profile)
        except Exception as error:
            print(f"agent error: {error}", flush=True)
            time.sleep(5)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
