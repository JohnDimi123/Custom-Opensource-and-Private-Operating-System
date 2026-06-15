#!/usr/bin/env python3
"""
jarvis-ai/router.py — unified AI router with fallback ladder.

  1. Anthropic Claude  (online + key present)
  2. Local llama.cpp GGUF model (if present)
  3. Deterministic offline responder (always available)
"""
import os
import logging

log = logging.getLogger("jarvis.ai")

SYSTEM_PROMPT = (
    "You are JARVIS, the voice-driven operating system assistant. "
    "You are concise, precise, and a little witty in the style of a capable "
    "AI butler. Replies are spoken aloud, so keep them short (1-3 sentences) "
    "unless asked for detail. You can control the computer, read files, run "
    "vetted commands, and recall the user's history. Never invent command "
    "output you did not receive."
)


class AIRouter:
    def __init__(self, memory):
        self.memory = memory
        self.claude = None
        self.local = None
        try:
            from jarvis_ai.claude_client import ClaudeClient
            self.claude = ClaudeClient()
        except Exception as e:  # noqa: BLE001
            log.info(f"Claude client unavailable: {e}")
        try:
            from jarvis_ai.local_model import LocalModel
            self.local = LocalModel()
        except Exception as e:  # noqa: BLE001
            log.info(f"Local model unavailable: {e}")

    def ask(self, user, text):
        history = self.memory.recent_turns(user, n=8)
        profile = self.memory.profile_summary(user)
        sys_prompt = SYSTEM_PROMPT + (f"\nUser profile: {profile}" if profile else "")

        # 1. Claude
        if self.claude and self.claude.available():
            try:
                return self.claude.chat(sys_prompt, history, text)
            except Exception as e:  # noqa: BLE001
                log.warning(f"Claude failed, falling back: {e}")

        # 2. Local model
        if self.local and self.local.available():
            try:
                return self.local.chat(sys_prompt, history, text)
            except Exception as e:  # noqa: BLE001
                log.warning(f"Local model failed, falling back: {e}")

        # 3. Offline rule-based
        return self._offline(text)

    def _offline(self, text):
        t = text.lower()
        if any(w in t for w in ("hello", "hi ", "hey")):
            return "Hello. Jarvis online and at your service."
        if "time" in t:
            import datetime
            return f"It is {datetime.datetime.now().strftime('%H:%M')}."
        if "thank" in t:
            return "Always a pleasure."
        if "who are you" in t or "your name" in t:
            return "I am Jarvis, your operating system assistant."
        return ("My reasoning core is offline and no API key is configured, "
                "so I can only handle direct system commands right now.")
