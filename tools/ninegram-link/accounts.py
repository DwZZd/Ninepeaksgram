#!/usr/bin/env python3
"""List AyuGram profiles created by Ninegram and open the right window."""

import ctypes
import json
import subprocess
import tkinter as tk
from pathlib import Path

from ctypes import wintypes

ROOT = Path.home() / ".ninegram-link" / "ayugram"
EXE = Path(r"D:\Home\Desktop\ayu\AyuGram-ninegram.exe")
FALLBACK_EXE = Path(r"D:\Home\Desktop\ayu\AyuGram.exe")

user32 = ctypes.windll.user32
SW_RESTORE = 9

BG = "#17212b"
CARD = "#232e3c"
TEXT = "#ffffff"
MUTED = "#8b9bab"
ACCENT = "#2ea6ff"


def exe_path():
    return EXE if EXE.exists() else FALLBACK_EXE


def profiles():
    if not ROOT.exists():
        return []
    found = []
    for path in sorted(ROOT.iterdir()):
        if not path.is_dir() or not path.name.startswith("account-"):
            continue
        if not (path / "tdata" / "user_data").exists():
            continue
        meta_path = path / "account.json"
        title = path.name
        if meta_path.exists():
            try:
                meta = json.loads(meta_path.read_text(encoding="utf-8-sig"))
                title = meta.get("title") or title
            except Exception:
                pass
        found.append((path, title))
    return found


def save_title(path, title):
    meta_path = path / "account.json"
    meta = {}
    if meta_path.exists():
        try:
            meta = json.loads(meta_path.read_text(encoding="utf-8-sig"))
        except Exception:
            meta = {}
    meta["title"] = title.strip() or path.name
    meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")


kernel32 = ctypes.windll.kernel32
ntdll = ctypes.windll.ntdll
PROCESS_QUERY_INFORMATION = 0x0400
PROCESS_VM_READ = 0x0010
TH32CS_SNAPPROCESS = 0x00000002


class PROCESSENTRY32W(ctypes.Structure):
    _fields_ = [
        ("dwSize", wintypes.DWORD),
        ("cntUsage", wintypes.DWORD),
        ("th32ProcessID", wintypes.DWORD),
        ("th32DefaultHeapID", ctypes.POINTER(ctypes.c_ulong)),
        ("th32ModuleID", wintypes.DWORD),
        ("cntThreads", wintypes.DWORD),
        ("th32ParentProcessID", wintypes.DWORD),
        ("pcPriClassBase", ctypes.c_long),
        ("dwFlags", wintypes.DWORD),
        ("szExeFile", wintypes.WCHAR * 260),
    ]


kernel32.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
kernel32.Process32FirstW.argtypes = [wintypes.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]
kernel32.Process32NextW.argtypes = [wintypes.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]
kernel32.Process32FirstW.restype = wintypes.BOOL
kernel32.Process32NextW.restype = wintypes.BOOL


class PROCESS_BASIC_INFORMATION(ctypes.Structure):
    _fields_ = [
        ("Reserved1", ctypes.c_void_p),
        ("PebBaseAddress", ctypes.c_void_p),
        ("Reserved2", ctypes.c_void_p * 2),
        ("UniqueProcessId", ctypes.c_void_p),
        ("Reserved3", ctypes.c_void_p),
    ]


def command_line(pid):
    handle = kernel32.OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, False, pid)
    if not handle:
        return ""
    try:
        info = PROCESS_BASIC_INFORMATION()
        status = ntdll.NtQueryInformationProcess(
            handle, 0, ctypes.byref(info), ctypes.sizeof(info), None
        )
        if status != 0 or not info.PebBaseAddress:
            return ""
        params = ctypes.c_void_p()
        read = ctypes.c_size_t()
        if not kernel32.ReadProcessMemory(
            handle, ctypes.c_void_p(info.PebBaseAddress + 0x20),
            ctypes.byref(params), ctypes.sizeof(params), ctypes.byref(read),
        ):
            return ""
        raw = (ctypes.c_byte * 16)()
        if not kernel32.ReadProcessMemory(
            handle, ctypes.c_void_p(params.value + 0x70),
            ctypes.byref(raw), 16, ctypes.byref(read),
        ):
            return ""
        length = int.from_bytes(bytes(raw[:2]), "little")
        pointer = int.from_bytes(bytes(raw[8:16]), "little")
        if length <= 0 or pointer == 0:
            return ""
        blob = (ctypes.c_char * length)()
        if not kernel32.ReadProcessMemory(
            handle, ctypes.c_void_p(pointer), ctypes.byref(blob), length, ctypes.byref(read),
        ):
            return ""
        return bytes(blob).decode("utf-16le", errors="replace")
    finally:
        kernel32.CloseHandle(handle)


def running_paths():
    snapshot = kernel32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    if snapshot == ctypes.c_void_p(-1).value or snapshot == -1:
        return {}
    entry = PROCESSENTRY32W()
    entry.dwSize = ctypes.sizeof(entry)
    found = {}
    ok = kernel32.Process32FirstW(snapshot, ctypes.byref(entry))
    while ok:
        name = entry.szExeFile.lower()
        if name.startswith("ayugram"):
            line = command_line(entry.th32ProcessID)
            if "-workdir" in line.lower():
                workdir = line.lower().split("-workdir", 1)[1].strip().strip('"')
                found[workdir] = entry.th32ProcessID
        ok = kernel32.Process32NextW(snapshot, ctypes.byref(entry))
    kernel32.CloseHandle(snapshot)
    return found


def hwnd_for_pid(pid):
    found = []

    @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def callback(hwnd, _lparam):
        process_id = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(process_id))
        if process_id.value == pid and user32.IsWindowVisible(hwnd):
            found.append(hwnd)
        return True

    user32.EnumWindows(callback, 0)
    return found[0] if found else None


def open_profile(path):
    pid = running_paths().get(str(path).lower())
    if pid:
        hwnd = hwnd_for_pid(pid)
        if hwnd:
            user32.ShowWindow(hwnd, SW_RESTORE)
            user32.SetForegroundWindow(hwnd)
            return
    exe = exe_path()
    subprocess.Popen(
        [str(exe), "-many", "-workdir", str(path)],
        cwd=str(exe.parent),
    )


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Ninegram")
        self.configure(bg=BG)
        self.geometry("520x640")
        self.minsize(420, 320)
        header = tk.Label(
            self,
            text="Аккаунты на этом ПК",
            bg=BG,
            fg=TEXT,
            font=("Segoe UI", 18, "bold"),
            anchor="w",
        )
        header.pack(fill="x", padx=20, pady=(18, 4))
        hint = tk.Label(
            self,
            text="Подпись можно поменять. Кнопка открывает AyuGram этого аккаунта.",
            bg=BG,
            fg=MUTED,
            font=("Segoe UI", 10),
            anchor="w",
        )
        hint.pack(fill="x", padx=20, pady=(0, 12))
        self.list_frame = tk.Frame(self, bg=BG)
        self.list_frame.pack(fill="both", expand=True, padx=16, pady=(0, 16))
        self.rows = {}
        self.after(200, self.refresh)

    def refresh(self):
        current = profiles()
        keys = [str(path) for path, _title in current]
        for key in list(self.rows):
            if key not in keys:
                self.rows[key].destroy()
                del self.rows[key]
        if not current:
            if not hasattr(self, "empty"):
                self.empty = tk.Label(
                    self.list_frame,
                    text="Пока пусто. Как перенесёшь аккаунт с телефона, он появится здесь.",
                    bg=BG,
                    fg=MUTED,
                    font=("Segoe UI", 11),
                    wraplength=440,
                    justify="left",
                )
                self.empty.pack(anchor="w", padx=4, pady=8)
        else:
            if hasattr(self, "empty"):
                self.empty.destroy()
                del self.empty
        open_paths = {key.lower() for key in running_paths()}
        for path, title in current:
            key = str(path)
            if key not in self.rows:
                self.rows[key] = self.make_row(path, title)
            self.rows[key].set_running(str(path).lower() in open_paths)
        self.after(3000, self.refresh)

    def make_row(self, path, title):
        frame = tk.Frame(self.list_frame, bg=CARD, padx=12, pady=10)
        frame.pack(fill="x", pady=6)
        entry = tk.Entry(
            frame,
            bg=CARD,
            fg=TEXT,
            insertbackground=TEXT,
            relief="flat",
            font=("Segoe UI", 13),
        )
        entry.insert(0, title)
        entry.pack(side="left", fill="x", expand=True, padx=(0, 12))

        def commit(_event=None):
            save_title(path, entry.get())

        entry.bind("<FocusOut>", commit)
        entry.bind("<Return>", commit)
        button = tk.Button(
            frame,
            text="Открыть",
            command=lambda: open_profile(path),
            bg=ACCENT,
            fg="#041018",
            activebackground="#59bdff",
            activeforeground="#041018",
            relief="flat",
            font=("Segoe UI", 11, "bold"),
            padx=14,
            pady=6,
        )
        button.pack(side="right")
        frame.set_running = lambda running: button.configure(
            text="Показать" if running else "Открыть"
        )
        return frame


if __name__ == "__main__":
    App().mainloop()
