#!/usr/bin/env python3
"""
jarvis-voice/voice.py — wake word, STT, TTS, interrupt (barge-in).

Pipeline:
  mic stream → openWakeWord("jarvis") → record utterance (VAD) →
  faster-whisper STT → send transcript to core over /run/jarvis/voice.sock →
  receive {"type":"tts"} → Piper TTS → playback (interruptible by new wake word)

Every external dependency is optional. If audio libs are missing the daemon
still runs and simply forwards typed input from the core/UI, so the OS boots.
"""
import os
import sys
import json
import time
import socket
import threading
import logging
import subprocess
from pathlib import Path

logging.basicConfig(level=logging.INFO,
                    format='{"ts":%(created)f,"lvl":"%(levelname)s","msg":%(message)r}')
log = logging.getLogger("jarvis.voice")

SOCK = "/run/jarvis/voice.sock"
WAKE_WORD = "jarvis"
MODEL_DIR = Path("/opt/jarvis/voice-models")
PIPER_VOICE = MODEL_DIR / "en_US-jarvis.onnx"
WHISPER_SIZE = os.environ.get("JARVIS_WHISPER", "base.en")


class VoiceDaemon:
    def __init__(self):
        self.sock = None
        self.speaking_proc = None
        self._stop_speaking = threading.Event()
        self.oww = None
        self.whisper = None
        self._init_models()

    # ---------- connection to core ----------
    def connect(self):
        for _ in range(60):
            try:
                self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.sock.connect(SOCK)
                log.info("connected to core")
                return True
            except (FileNotFoundError, ConnectionRefusedError):
                time.sleep(1)
        log.error("could not connect to core socket")
        return False

    def send(self, mtype, payload=None):
        msg = json.dumps({"type": mtype, "ts": time.time(),
                          "payload": payload or {}}) + "\n"
        try:
            self.sock.sendall(msg.encode())
        except Exception as e:  # noqa: BLE001
            log.error(f"send failed: {e}")

    # ---------- model init (all optional) ----------
    def _init_models(self):
        try:
            import openwakeword
            from openwakeword.model import Model
            self.oww = Model(wakeword_models=[str(MODEL_DIR / "jarvis.onnx")]) \
                if (MODEL_DIR / "jarvis.onnx").exists() else Model()
            log.info("wake word model ready")
        except Exception as e:  # noqa: BLE001
            log.info(f"wake word unavailable: {e}")
        try:
            from faster_whisper import WhisperModel
            self.whisper = WhisperModel(WHISPER_SIZE, device="cpu",
                                        compute_type="int8")
            log.info("whisper STT ready")
        except Exception as e:  # noqa: BLE001
            log.info(f"STT unavailable: {e}")

    # ---------- TTS ----------
    def speak(self, text):
        self.interrupt_speech()
        self._stop_speaking.clear()
        if PIPER_VOICE.exists():
            cmd = (f'echo {json.dumps(text)} | piper --model {PIPER_VOICE} '
                   f'--output_raw | aplay -r 22050 -f S16_LE -t raw -')
        else:
            # espeak-ng fallback — always present in the image
            cmd = f'espeak-ng -v en+m3 -s 165 {json.dumps(text)}'
        try:
            self.speaking_proc = subprocess.Popen(cmd, shell=True)
            self.speaking_proc.wait()
        except Exception as e:  # noqa: BLE001
            log.error(f"tts failed: {e}")

    def interrupt_speech(self):
        if self.speaking_proc and self.speaking_proc.poll() is None:
            self._stop_speaking.set()
            try:
                self.speaking_proc.terminate()
            except Exception:
                pass
            self.send("interrupt")

    # ---------- STT ----------
    def transcribe(self, wav_path):
        if not self.whisper:
            return ""
        try:
            segments, _ = self.whisper.transcribe(wav_path, language="en")
            return " ".join(s.text for s in segments).strip()
        except Exception as e:  # noqa: BLE001
            log.error(f"stt failed: {e}")
            return ""

    # ---------- audio capture (VAD-gated) ----------
    def record_utterance(self, seconds=6):
        wav = "/tmp/jarvis_utt.wav"
        try:
            subprocess.run(
                f"arecord -q -f S16_LE -r 16000 -c 1 -d {seconds} {wav}",
                shell=True, check=True, timeout=seconds + 3)
            return wav
        except Exception as e:  # noqa: BLE001
            log.error(f"record failed: {e}")
            return None

    # ---------- main loop ----------
    def listen_loop(self):
        if not self.oww:
            log.info("no wake word engine; voice in passive mode")
            while True:
                time.sleep(3600)
        try:
            import numpy as np
            import pyaudio
        except Exception as e:  # noqa: BLE001
            log.info(f"audio stack unavailable: {e}; passive mode")
            while True:
                time.sleep(3600)

        pa = pyaudio.PyAudio()
        stream = pa.open(rate=16000, channels=1, format=pyaudio.paInt16,
                         input=True, frames_per_buffer=1280)
        log.info("listening for wake word 'jarvis'")
        while True:
            data = stream.read(1280, exception_on_overflow=False)
            audio = np.frombuffer(data, dtype=np.int16)
            preds = self.oww.predict(audio)
            if any(score > 0.5 for score in preds.values()):
                self.interrupt_speech()          # barge-in
                self.send("wake")
                self.send("listening", {"state": True})
                wav = self.record_utterance()
                self.send("listening", {"state": False})
                text = self.transcribe(wav) if wav else ""
                if text:
                    self.send("transcript", {"text": text})
                time.sleep(0.3)

    # ---------- receive TTS requests from core ----------
    def recv_loop(self):
        buf = b""
        while True:
            try:
                chunk = self.sock.recv(4096)
            except Exception:
                break
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                try:
                    msg = json.loads(line.decode())
                except json.JSONDecodeError:
                    continue
                if msg.get("type") == "tts":
                    threading.Thread(
                        target=self.speak,
                        args=(msg["payload"].get("text", ""),),
                        daemon=True).start()

    def run(self):
        if not self.connect():
            sys.exit(1)
        threading.Thread(target=self.recv_loop, daemon=True).start()
        self.listen_loop()


if __name__ == "__main__":
    VoiceDaemon().run()
