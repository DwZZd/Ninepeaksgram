#!/usr/bin/env python3
import subprocess
from pathlib import Path

unit = """[Unit]
Description=Ninegram desktop login relay
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/ninegram-link/server.py
WorkingDirectory=/opt/ninegram-link
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
"""
Path("/etc/systemd/system/ninegram-link.service").write_text(unit)

path = Path("/etc/nginx/sites-available/ninepeaks")
text = path.read_text()
marker = "location /ninegram-link/"
if marker not in text:
    snippet = """    location /ninegram-link/ {
        proxy_pass http://127.0.0.1:8791/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 30s;
    }

"""
    needle = "    location /api/ {\n        limit_req zone=np_api burst=15 nodelay;"
    if needle not in text:
        raise SystemExit("nginx anchor not found")
    path.with_suffix(".bak.ninegram-link").write_text(text)
    path.write_text(text.replace(needle, snippet + needle, 1))
    print("nginx location inserted")
else:
    print("nginx location already present")

subprocess.check_call(["nginx", "-t"])
subprocess.check_call(["systemctl", "daemon-reload"])
subprocess.check_call(["systemctl", "enable", "--now", "ninegram-link.service"])
subprocess.check_call(["systemctl", "reload", "nginx"])
print(subprocess.check_output(["systemctl", "is-active", "ninegram-link.service"], text=True).strip())
