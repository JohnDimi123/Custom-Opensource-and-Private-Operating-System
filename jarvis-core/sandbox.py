#!/usr/bin/env python3
"""
jarvis-core/sandbox.py — sandboxed command execution + permission system.

Every shell/system action passes through here. Default-deny: a command must
match the allow-list AND must not match the deny-list. Runs under firejail
when available, with a hard timeout, and logs every attempt.
"""
import os
import re
import shlex
import shutil
import subprocess
import logging
import time
from pathlib import Path

log = logging.getLogger("jarvis.sandbox")

# Capabilities granted to the assistant by default.
DEFAULT_CAPS = {"files.read", "shell.exec", "net.access"}

# Whitelisted base executables the assistant may run.
ALLOW_BINARIES = {
    "ls", "cat", "echo", "pwd", "whoami", "date", "uptime", "df", "free",
    "ps", "top", "uname", "ip", "ping", "grep", "head", "tail", "wc",
    "find", "du", "lsblk", "nproc", "hostnamectl", "systemctl",
    "xdg-open", "firefox", "chromium", "code", "nautilus", "gnome-terminal",
    "feh", "mpv", "amixer", "pactl", "brightnessctl",
}

# Hard deny patterns (regex) — destructive / privilege escalation.
DENY_PATTERNS = [
    r"\brm\b.*-[a-z]*r[a-z]*f", r":\(\)\s*\{", r"\bmkfs\b", r"\bdd\b",
    r">\s*/dev/sd", r"\bshutdown\b", r"\breboot\b", r"\bchmod\b\s+777\s+/",
    r"\bchown\b\s+.*\s+/", r"\bpasswd\b", r"\buseradd\b", r"\bsudo\b\s+su",
    r"/etc/shadow", r"\bcurl\b.*\|\s*(ba)?sh", r"\bwget\b.*\|\s*(ba)?sh",
]


class PermissionError_(Exception):
    pass


class Sandbox:
    def __init__(self, caps=None, timeout=20):
        self.caps = set(caps) if caps else set(DEFAULT_CAPS)
        self.timeout = timeout
        self.firejail = shutil.which("firejail")
        self.log_path = Path("/var/log/jarvis/sandbox.log")
        self.log_path.parent.mkdir(parents=True, exist_ok=True)

    def has(self, cap):
        return cap in self.caps

    def _audit(self, command, decision, detail=""):
        line = f'{{"ts":{time.time()},"cmd":{command!r},"decision":"{decision}","detail":{detail!r}}}\n'
        try:
            with open(self.log_path, "a") as f:
                f.write(line)
        except Exception:
            pass
        log.info(f"sandbox {decision}: {command}")

    def _denied(self, command):
        for pat in DENY_PATTERNS:
            if re.search(pat, command):
                return pat
        return None

    def check(self, command):
        if not self.has("shell.exec"):
            raise PermissionError_("shell.exec capability not granted")
        bad = self._denied(command)
        if bad:
            self._audit(command, "denied", bad)
            raise PermissionError_(f"command blocked by policy: {bad}")
        try:
            tokens = shlex.split(command)
        except ValueError:
            raise PermissionError_("unparseable command")
        if not tokens:
            raise PermissionError_("empty command")
        base = os.path.basename(tokens[0])
        if base not in ALLOW_BINARIES:
            self._audit(command, "denied", f"binary {base} not allowed")
            raise PermissionError_(f"'{base}' is not in the allow-list")
        return tokens

    def run(self, command):
        """Run a vetted command. Returns dict(ok, stdout, stderr, code)."""
        try:
            self.check(command)
        except PermissionError_ as e:
            return {"ok": False, "stdout": "", "stderr": str(e), "code": 126}

        argv = command
        if self.firejail:
            argv = f"{self.firejail} --quiet --net=none --private-tmp -- {command}"
            # net=none unless net.access — keep simple: allow net for ping/curl
            if "net.access" in self.caps and re.search(r"\b(ping|ip|firefox|chromium|curl)\b", command):
                argv = f"{self.firejail} --quiet --private-tmp -- {command}"

        self._audit(command, "allowed")
        try:
            proc = subprocess.run(argv, shell=True, capture_output=True,
                                  text=True, timeout=self.timeout)
            return {"ok": proc.returncode == 0,
                    "stdout": proc.stdout[-4000:],
                    "stderr": proc.stderr[-2000:],
                    "code": proc.returncode}
        except subprocess.TimeoutExpired:
            return {"ok": False, "stdout": "", "stderr": "timeout", "code": 124}
        except Exception as e:  # noqa: BLE001
            return {"ok": False, "stdout": "", "stderr": str(e), "code": 1}

    # ---- file helpers with capability gating ----
    def read_file(self, path, maxbytes=20000):
        if not self.has("files.read"):
            raise PermissionError_("files.read not granted")
        p = Path(path).expanduser()
        return p.read_text(errors="replace")[:maxbytes]

    def write_file(self, path, content):
        if not self.has("files.write"):
            raise PermissionError_("files.write not granted")
        p = Path(path).expanduser()
        p.write_text(content)
        return True
