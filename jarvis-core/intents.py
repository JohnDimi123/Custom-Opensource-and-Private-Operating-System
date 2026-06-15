#!/usr/bin/env python3
"""
jarvis-core/intents.py — maps spoken/typed text to system-control actions.

Recognised intents (deterministic, run before the AI):
  open app, run command, read/write file, system status, volume/brightness,
  lock/recovery, plugins. Anything unmatched falls through to the AI.
"""
import re
import logging

log = logging.getLogger("jarvis.intents")


class IntentRouter:
    def __init__(self, sandbox, memory):
        self.sandbox = sandbox
        self.memory = memory
        self.app_map = {
            "browser": "xdg-open https://duckduckgo.com",
            "firefox": "firefox",
            "files": "nautilus",
            "file manager": "nautilus",
            "terminal": "gnome-terminal",
            "code": "code",
            "editor": "code",
        }
        self.patterns = [
            ("open_app", re.compile(r"\b(open|launch|start)\s+(?:the\s+)?(?P<app>[a-z ]+)", re.I)),
            ("run_cmd", re.compile(r"\b(run|execute)\s+(command\s+)?(?P<cmd>.+)", re.I)),
            ("read_file", re.compile(r"\bread\s+(the\s+)?file\s+(?P<path>\S+)", re.I)),
            ("status", re.compile(r"\b(system\s+status|how('?s| is)\s+the\s+system|resource|cpu|memory|ram)\b", re.I)),
            ("volume", re.compile(r"\b(set\s+)?volume\s+(?:to\s+)?(?P<level>\d+)", re.I)),
            ("brightness", re.compile(r"\bbrightness\s+(?:to\s+)?(?P<level>\d+)", re.I)),
            ("recovery", re.compile(r"\b(recovery mode|safe mode)\b", re.I)),
        ]

    def match(self, text):
        for name, pat in self.patterns:
            m = pat.search(text)
            if m:
                return {"name": name, "groups": m.groupdict(), "raw": text}
        return None

    def execute(self, intent):
        name = intent["name"]
        g = intent["groups"]
        try:
            if name == "open_app":
                app = g["app"].strip().lower()
                # match longest key contained in phrase
                target = None
                for key in sorted(self.app_map, key=len, reverse=True):
                    if key in app:
                        target = self.app_map[key]
                        break
                if not target:
                    return {"speech": f"I don't know how to open {app}."}
                r = self.sandbox.run(target)
                ok = r["ok"]
                return {"speech": f"Opening {app}." if ok else f"I couldn't open {app}."}

            if name == "run_cmd":
                r = self.sandbox.run(g["cmd"].strip())
                if r["ok"]:
                    out = r["stdout"].strip() or "Command completed."
                    return {"speech": out[:300], "data": r}
                return {"speech": f"Command failed: {r['stderr'][:120]}", "data": r}

            if name == "read_file":
                try:
                    content = self.sandbox.read_file(g["path"])
                    return {"speech": content[:400], "data": {"content": content}}
                except Exception as e:  # noqa: BLE001
                    return {"speech": f"I couldn't read that file: {e}"}

            if name == "status":
                from jarvis_core.sysmon import SystemMonitor
                s = SystemMonitor().snapshot()
                return {"speech": (f"CPU at {s['cpu']} percent, "
                                   f"memory at {s['mem']} percent, "
                                   f"{s['uptime']} uptime."), "data": s}

            if name == "volume":
                lvl = g["level"]
                self.sandbox.run(f"pactl set-sink-volume @DEFAULT_SINK@ {lvl}%")
                return {"speech": f"Volume set to {lvl} percent."}

            if name == "brightness":
                lvl = g["level"]
                self.sandbox.run(f"brightnessctl set {lvl}%")
                return {"speech": f"Brightness set to {lvl} percent."}

            if name == "recovery":
                return {"speech": "Reboot and choose recovery mode from the boot menu to enter safe mode."}

        except Exception as e:  # noqa: BLE001
            log.error(f"intent error: {e}")
            return {"speech": "Something went wrong running that."}
        return {"speech": "Done."}

    def plugin_action(self, payload):
        action = payload.get("action")
        name = payload.get("name", "")
        if action == "list":
            return {"action": "list", "plugins": self.memory.list_plugins()}
        if action == "enable":
            self.memory.set_plugin(name, True)
            return {"action": "enabled", "name": name}
        if action == "disable":
            self.memory.set_plugin(name, False)
            return {"action": "disabled", "name": name}
        return {"action": "noop"}
