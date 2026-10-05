#!/usr/bin/env python3
"""Keeps a Telegram login waiting on this PC.

When Ninegram accepts the token after a phone login, the resulting session is
stored locally. Each account gets its own session file.
"""

import asyncio
import base64
import json
import shutil
import sys
import urllib.error
import urllib.request
from pathlib import Path

from telethon import TelegramClient
from telethon.errors import SessionPasswordNeededError

ROOT = Path.home() / ".ninegram-link"
CONFIG_PATH = ROOT / "config.json"
SESSION_DIR = ROOT / "sessions"


def load_config():
    with CONFIG_PATH.open("r", encoding="utf-8-sig") as handle:
        config = json.load(handle)
    for key in ("api_id", "api_hash", "write_secret", "base_url"):
        if not config.get(key):
            raise SystemExit(f"config.json is missing {key}")
    return config


def request(config, method, path, payload=None):
    data = None
    headers = {"X-Ninegram-Key": config["write_secret"]}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    url = config["base_url"].rstrip("/") + path
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            response.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"{method} {path} failed: {error.code} {detail}") from error


async def wait_for_one_account(config):
    SESSION_DIR.mkdir(parents=True, exist_ok=True)
    pending = SESSION_DIR / "pending"
    for suffix in (".session", ".session-journal"):
        leftover = Path(str(pending) + suffix)
        if leftover.exists():
            leftover.unlink()

    client = TelegramClient(
        str(pending),
        int(config["api_id"]),
        config["api_hash"],
        device_model="Ninegram PC",
        system_version="Windows",
        app_version="1.0",
        lang_code="ru",
        system_lang_code="ru",
    )
    await client.connect()
    try:
        qr = await client.qr_login()
        while True:
            encoded = base64.b64encode(qr.token).decode("ascii")
            request(config, "POST", "/v1/token", {"token": encoded})
            print("waiting for Ninegram to accept the PC login", flush=True)
            try:
                await qr.wait(timeout=25)
                break
            except asyncio.TimeoutError:
                await qr.recreate()
            except SessionPasswordNeededError:
                print("this account asked for the cloud password on the PC; skipping", flush=True)
                return

        me = await client.get_me()
        user_id = me.id
        print(f"PC session created for {user_id}", flush=True)
    finally:
        await client.disconnect()

    destination = SESSION_DIR / f"{user_id}.session"
    source = Path(str(pending) + ".session")
    if source.exists():
        if destination.exists():
            destination.unlink()
        shutil.move(str(source), str(destination))
        print(f"saved {destination}", flush=True)


async def main():
    config = load_config()
    while True:
        try:
            await wait_for_one_account(config)
        except Exception as error:
            print(f"agent error: {error}", flush=True)
            await asyncio.sleep(5)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        sys.exit(0)
