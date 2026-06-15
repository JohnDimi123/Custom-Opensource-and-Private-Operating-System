#!/usr/bin/env python3
"""
jarvis-core/vision.py — screenshot understanding, webcam capture, OCR.

Gracefully degrades when optional libs are missing so the OS still boots.
"""
import os
import time
import logging
import subprocess
from pathlib import Path

log = logging.getLogger("jarvis.vision")
CAP_DIR = Path("/var/lib/jarvis/captures")
CAP_DIR.mkdir(parents=True, exist_ok=True)


class Vision:
    def screenshot(self):
        path = CAP_DIR / f"shot_{int(time.time())}.png"
        for cmd in (f"scrot {path}", f"import -window root {path}",
                    f"grim {path}"):
            try:
                subprocess.run(cmd, shell=True, check=True, timeout=10,
                               capture_output=True)
                if path.exists():
                    return str(path)
            except Exception:
                continue
        log.warning("no screenshot tool available")
        return None

    def webcam(self, device="/dev/video0"):
        path = CAP_DIR / f"cam_{int(time.time())}.jpg"
        try:
            subprocess.run(
                f"fswebcam -d {device} -r 1280x720 --no-banner {path}",
                shell=True, check=True, timeout=10, capture_output=True)
            return str(path) if path.exists() else None
        except Exception as e:  # noqa: BLE001
            log.warning(f"webcam capture failed: {e}")
            return None

    def ocr(self, image_path):
        if not image_path or not os.path.exists(image_path):
            return ""
        # Prefer tesseract CLI (small footprint).
        try:
            out = subprocess.run(f"tesseract {image_path} stdout",
                                 shell=True, capture_output=True, text=True,
                                 timeout=30)
            return out.stdout.strip()
        except Exception as e:  # noqa: BLE001
            log.warning(f"ocr failed: {e}")
            return ""

    def describe_screen(self, ai_router=None, user="operator"):
        """Capture screen + OCR; optionally ask the AI to describe it."""
        shot = self.screenshot()
        text = self.ocr(shot)
        if ai_router and text:
            prompt = (f"This text was extracted from the user's screen via OCR. "
                      f"Summarise what is on screen in one sentence:\n{text[:1500]}")
            try:
                return ai_router.ask(user, prompt)
            except Exception:
                pass
        return text[:500] if text else "I couldn't read anything on screen."
