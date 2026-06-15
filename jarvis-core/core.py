#!/usr/bin/env python3
"""
jarvis-core/core.py — JARVIS OS orchestrator daemon.

Routes intents between voice, AI, memory and system control.
Exposes a WebSocket (127.0.0.1:8765) the UI subscribes to, and a Unix
socket (/run/jarvis/voice.sock) the voice daemon connects to.
"""
import asyncio
import json
import os
import sys
import time
import signal
import logging
from pathlib import Path

sys.path.insert(0, "/opt/jarvis")
from jarvis_ai.router import AIRouter            # noqa: E402
from jarvis_memory.memory import Memory          # noqa: E402
from jarvis_core.sandbox import Sandbox          # noqa: E402
from jarvis_core.intents import IntentRouter     # noqa: E402
from jarvis_core.sysmon import SystemMonitor     # noqa: E402

LOG_DIR = Path("/var/log/jarvis")
LOG_DIR.mkdir(parents=True, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format='{"ts":%(created)f,"lvl":"%(levelname)s","msg":%(message)r}',
    handlers=[logging.FileHandler(LOG_DIR / "core.log"),
              logging.StreamHandler()],
)
log = logging.getLogger("jarvis.core")

WS_HOST, WS_PORT = "127.0.0.1", 8765
VOICE_SOCK = "/run/jarvis/voice.sock"


def envelope(mtype, payload=None):
    return json.dumps({"type": mtype, "ts": time.time(),
                       "payload": payload or {}}) + "\n"


class JarvisCore:
    def __init__(self):
        self.ui_clients = set()
        self.memory = Memory()
        self.ai = AIRouter(self.memory)
        self.sandbox = Sandbox()
        self.intents = IntentRouter(self.sandbox, self.memory)
        self.sysmon = SystemMonitor()
        self.user = os.environ.get("JARVIS_USER", "operator")
        self._speaking = False
        self._interrupt = asyncio.Event()

    # ---------- broadcast to UI ----------
    async def push(self, mtype, payload=None):
        if not self.ui_clients:
            return
        msg = envelope(mtype, payload)
        dead = []
        for ws in self.ui_clients:
            try:
                await ws.send(msg)
            except Exception:
                dead.append(ws)
        for d in dead:
            self.ui_clients.discard(d)

    # ---------- the heart: handle a transcript ----------
    async def handle_utterance(self, text, voice_writer=None):
        text = (text or "").strip()
        if not text:
            return
        log.info(f"utterance: {text}")
        await self.push("transcript", {"text": text, "who": "user"})

        # 1. try system-control intent (open app, run cmd, files, hardware)
        intent = self.intents.match(text)
        if intent:
            await self.push("intent", {"name": intent["name"]})
            await self.push("thinking", {"state": True})
            result = await asyncio.get_event_loop().run_in_executor(
                None, self.intents.execute, intent)
            await self.push("thinking", {"state": False})
            reply = result.get("speech", "Done.")
            self.memory.store_turn(self.user, text, reply)
            await self.speak(reply, voice_writer)
            await self.push("reply", {"text": reply, "who": "jarvis"})
            return

        # 2. otherwise ask the AI
        await self.push("thinking", {"state": True})
        try:
            reply = await asyncio.get_event_loop().run_in_executor(
                None, self.ai.ask, self.user, text)
        except Exception as e:  # noqa: BLE001
            log.error(f"ai error: {e}")
            reply = "I hit an error reaching my reasoning core."
        await self.push("thinking", {"state": False})
        self.memory.store_turn(self.user, text, reply)
        await self.speak(reply, voice_writer)
        await self.push("reply", {"text": reply, "who": "jarvis"})

    async def speak(self, text, voice_writer):
        self._speaking = True
        self._interrupt.clear()
        await self.push("speaking", {"state": True, "text": text})
        if voice_writer is not None:
            try:
                voice_writer.write(envelope("tts", {"text": text}).encode())
                await voice_writer.drain()
            except Exception:
                pass
        self._speaking = False
        await self.push("speaking", {"state": False})

    # ---------- voice daemon connection (Unix socket) ----------
    async def voice_server(self):
        os.makedirs("/run/jarvis", exist_ok=True)
        if os.path.exists(VOICE_SOCK):
            os.remove(VOICE_SOCK)

        async def handle(reader, writer):
            log.info("voice daemon connected")
            while not reader.at_eof():
                line = await reader.readline()
                if not line:
                    break
                try:
                    msg = json.loads(line.decode())
                except json.JSONDecodeError:
                    continue
                t = msg.get("type")
                p = msg.get("payload", {})
                if t == "wake":
                    await self.push("wake", {})
                elif t == "listening":
                    await self.push("listening", {"state": p.get("state", True)})
                elif t == "transcript":
                    await self.handle_utterance(p.get("text", ""), writer)
                elif t == "interrupt":
                    self._interrupt.set()
                    await self.push("interrupt", {})
            writer.close()

        server = await asyncio.start_unix_server(handle, path=VOICE_SOCK)
        os.chmod(VOICE_SOCK, 0o660)
        async with server:
            await server.serve_forever()

    # ---------- WebSocket server for the UI ----------
    async def ws_server(self):
        import websockets

        async def handler(ws):
            self.ui_clients.add(ws)
            log.info("UI connected")
            await ws.send(envelope("hello", {"user": self.user}))
            try:
                async for raw in ws:
                    try:
                        msg = json.loads(raw)
                    except json.JSONDecodeError:
                        continue
                    t = msg.get("type")
                    p = msg.get("payload", {})
                    if t == "text":          # typed input from UI
                        await self.handle_utterance(p.get("text", ""))
                    elif t == "interrupt":
                        self._interrupt.set()
                    elif t == "plugin":
                        await self.push("plugin",
                                        self.intents.plugin_action(p))
            finally:
                self.ui_clients.discard(ws)
                log.info("UI disconnected")

        async with websockets.serve(handler, WS_HOST, WS_PORT):
            await asyncio.Future()

    # ---------- system stats loop ----------
    async def stats_loop(self):
        while True:
            await self.push("stat", self.sysmon.snapshot())
            await asyncio.sleep(2)

    async def run(self):
        log.info("JARVIS core starting")
        await self.push("notify", {"text": "Jarvis core online"})
        await asyncio.gather(
            self.voice_server(),
            self.ws_server(),
            self.stats_loop(),
        )


def main():
    core = JarvisCore()
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    for s in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(s, loop.stop)
    try:
        loop.run_until_complete(core.run())
    except (KeyboardInterrupt, RuntimeError):
        pass
    finally:
        log.info("JARVIS core stopped")


if __name__ == "__main__":
    main()
