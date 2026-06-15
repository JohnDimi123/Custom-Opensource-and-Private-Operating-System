#!/usr/bin/env python3
"""
jarvis-ai/claude_client.py — Anthropic Claude integration.

Reads the API key from JARVIS_ANTHROPIC_KEY or ANTHROPIC_API_KEY, or from
/etc/jarvis/anthropic.key. Uses the official anthropic SDK if installed,
otherwise falls back to a raw HTTPS request via urllib (no extra deps).
"""
import os
import json
import logging
import urllib.request
from pathlib import Path

log = logging.getLogger("jarvis.ai.claude")

DEFAULT_MODEL = os.environ.get("JARVIS_CLAUDE_MODEL", "claude-opus-4-8")
KEY_FILE = Path("/etc/jarvis/anthropic.key")
API_URL = "https://api.anthropic.com/v1/messages"
API_VERSION = "2023-06-01"


def _load_key():
    for env in ("JARVIS_ANTHROPIC_KEY", "ANTHROPIC_API_KEY"):
        if os.environ.get(env):
            return os.environ[env].strip()
    if KEY_FILE.exists():
        return KEY_FILE.read_text().strip()
    return None


class ClaudeClient:
    def __init__(self):
        self.key = _load_key()
        self.model = DEFAULT_MODEL
        self._sdk = None
        if self.key:
            try:
                import anthropic
                self._sdk = anthropic.Anthropic(api_key=self.key)
            except Exception:
                self._sdk = None

    def available(self):
        return bool(self.key) and self._online()

    def _online(self):
        try:
            urllib.request.urlopen("https://api.anthropic.com", timeout=2)
            return True
        except Exception:
            # api.anthropic.com may refuse GET; a connection error other than
            # DNS/timeout still means we reached the network.
            return True if self.key else False

    def _messages(self, history, text):
        msgs = []
        for turn in history:
            msgs.append({"role": "user", "content": turn["user"]})
            msgs.append({"role": "assistant", "content": turn["jarvis"]})
        msgs.append({"role": "user", "content": text})
        return msgs

    def chat(self, system_prompt, history, text):
        messages = self._messages(history, text)
        if self._sdk:
            resp = self._sdk.messages.create(
                model=self.model, max_tokens=512,
                system=system_prompt, messages=messages)
            return "".join(b.text for b in resp.content if b.type == "text").strip()
        return self._raw(system_prompt, messages)

    def _raw(self, system_prompt, messages):
        body = json.dumps({
            "model": self.model, "max_tokens": 512,
            "system": system_prompt, "messages": messages,
        }).encode()
        req = urllib.request.Request(API_URL, data=body, method="POST")
        req.add_header("x-api-key", self.key)
        req.add_header("anthropic-version", API_VERSION)
        req.add_header("content-type", "application/json")
        with urllib.request.urlopen(req, timeout=30) as r:
            data = json.loads(r.read().decode())
        return "".join(b.get("text", "") for b in data.get("content", [])
                       if b.get("type") == "text").strip()
