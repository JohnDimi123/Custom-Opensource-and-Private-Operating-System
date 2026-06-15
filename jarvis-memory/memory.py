#!/usr/bin/env python3
"""
jarvis-memory/memory.py — long-term memory, user profiles, plugins.

SQLite-backed. Stores every conversation turn, derives lightweight per-user
profile facts, and tracks installed plugins. Designed to survive reboots when
installed to disk; in pure-live mode it lives in tmpfs (cleared on shutdown).
"""
import os
import json
import time
import sqlite3
import logging
from pathlib import Path

log = logging.getLogger("jarvis.memory")
DB_PATH = os.environ.get("JARVIS_DB", "/var/lib/jarvis/memory.db")


class Memory:
    def __init__(self, db_path=DB_PATH):
        Path(db_path).parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(db_path, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self._init_schema()

    def _init_schema(self):
        c = self.db.cursor()
        c.executescript("""
        CREATE TABLE IF NOT EXISTS turns(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user TEXT, ts REAL, user_text TEXT, jarvis_text TEXT);
        CREATE TABLE IF NOT EXISTS profile(
            user TEXT, key TEXT, value TEXT,
            PRIMARY KEY(user, key));
        CREATE TABLE IF NOT EXISTS facts(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user TEXT, ts REAL, fact TEXT);
        CREATE TABLE IF NOT EXISTS plugins(
            name TEXT PRIMARY KEY, enabled INTEGER, meta TEXT);
        """)
        self.db.commit()

    # ---------- conversation ----------
    def store_turn(self, user, user_text, jarvis_text):
        self.db.execute(
            "INSERT INTO turns(user, ts, user_text, jarvis_text) VALUES(?,?,?,?)",
            (user, time.time(), user_text, jarvis_text))
        self.db.commit()
        self._extract_facts(user, user_text)

    def recent_turns(self, user, n=8):
        rows = self.db.execute(
            "SELECT user_text, jarvis_text FROM turns WHERE user=? "
            "ORDER BY id DESC LIMIT ?", (user, n)).fetchall()
        return [{"user": r["user_text"], "jarvis": r["jarvis_text"]}
                for r in reversed(rows)]

    # ---------- profile ----------
    def set_profile(self, user, key, value):
        self.db.execute(
            "INSERT INTO profile(user,key,value) VALUES(?,?,?) "
            "ON CONFLICT(user,key) DO UPDATE SET value=excluded.value",
            (user, key, value))
        self.db.commit()

    def profile_summary(self, user):
        rows = self.db.execute(
            "SELECT key, value FROM profile WHERE user=?", (user,)).fetchall()
        if not rows:
            return ""
        return "; ".join(f"{r['key']}={r['value']}" for r in rows)

    def _extract_facts(self, user, text):
        import re
        m = re.search(r"my name is\s+(\w+)", text, re.I)
        if m:
            self.set_profile(user, "name", m.group(1))
        if re.search(r"\bi like\b", text, re.I):
            self.db.execute("INSERT INTO facts(user,ts,fact) VALUES(?,?,?)",
                            (user, time.time(), text))
            self.db.commit()
        m = re.search(r"call me\s+(\w+)", text, re.I)
        if m:
            self.set_profile(user, "nickname", m.group(1))

    def recall_facts(self, user, n=20):
        rows = self.db.execute(
            "SELECT fact FROM facts WHERE user=? ORDER BY id DESC LIMIT ?",
            (user, n)).fetchall()
        return [r["fact"] for r in rows]

    # ---------- plugins ----------
    def list_plugins(self):
        rows = self.db.execute("SELECT name, enabled, meta FROM plugins").fetchall()
        return [{"name": r["name"], "enabled": bool(r["enabled"]),
                 "meta": json.loads(r["meta"] or "{}")} for r in rows]

    def set_plugin(self, name, enabled, meta=None):
        self.db.execute(
            "INSERT INTO plugins(name,enabled,meta) VALUES(?,?,?) "
            "ON CONFLICT(name) DO UPDATE SET enabled=excluded.enabled",
            (name, int(enabled), json.dumps(meta or {})))
        self.db.commit()
