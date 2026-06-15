#!/usr/bin/env python3
"""
jarvis-ai/local_model.py — offline fallback using llama-cpp-python.

Looks for a GGUF model in /opt/jarvis/models. If llama-cpp-python and a model
are present it serves responses fully offline; otherwise reports unavailable
and the router drops to the deterministic responder.
"""
import os
import glob
import logging

log = logging.getLogger("jarvis.ai.local")
MODEL_DIR = os.environ.get("JARVIS_MODEL_DIR", "/opt/jarvis/models")


class LocalModel:
    def __init__(self):
        self.llm = None
        self.model_path = self._find_model()
        if self.model_path:
            try:
                from llama_cpp import Llama
                self.llm = Llama(
                    model_path=self.model_path,
                    n_ctx=4096, n_threads=os.cpu_count() or 4,
                    verbose=False)
                log.info(f"local model loaded: {self.model_path}")
            except Exception as e:  # noqa: BLE001
                log.info(f"could not load local model: {e}")
                self.llm = None

    def _find_model(self):
        files = glob.glob(os.path.join(MODEL_DIR, "*.gguf"))
        return files[0] if files else None

    def available(self):
        return self.llm is not None

    def chat(self, system_prompt, history, text):
        msgs = [{"role": "system", "content": system_prompt}]
        for turn in history:
            msgs.append({"role": "user", "content": turn["user"]})
            msgs.append({"role": "assistant", "content": turn["jarvis"]})
        msgs.append({"role": "user", "content": text})
        out = self.llm.create_chat_completion(messages=msgs, max_tokens=400,
                                              temperature=0.6)
        return out["choices"][0]["message"]["content"].strip()
