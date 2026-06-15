# JARVIS OS — File Manifest

## Root
- `build_jarvis_iso.sh` — master build orchestrator → produces `dist/jarvis-os.iso`
- `ARCHITECTURE.md` — full design, boot chain, IPC contract, security model
- `README.md` — build + boot + usage guide
- `MANIFEST.md` — this file

## jarvis-core/ — orchestrator daemon
- `core.py`     — async orchestrator; WebSocket(UI) + Unix socket(voice)
- `sandbox.py`  — allow/deny-list + firejail + timeouts; capability gating
- `intents.py`  — deterministic system-control routing (open app, run cmd, status…)
- `sysmon.py`   — CPU/mem/uptime/net telemetry (psutil + /proc fallback)
- `vision.py`   — screenshot / webcam / OCR

## jarvis-ai/ — reasoning backends (fallback ladder)
- `router.py`         — Claude → local → offline responder
- `claude_client.py`  — Anthropic Claude (SDK + raw-HTTP fallback)
- `local_model.py`    — llama.cpp GGUF offline model

## jarvis-memory/
- `memory.py`   — SQLite long-term memory, profiles, plugins

## jarvis-voice/
- `voice.py`    — wake word, whisper STT, Piper/espeak TTS, barge-in

## jarvis-ui/ — Iron-Man HUD (Electron kiosk)
- `main.js`, `preload.js`, `package.json`
- `renderer/index.html`, `renderer/hud.css`, `renderer/hud.js`

## jarvis-services/ — systemd + boot integration
- `jarvis-prep.service`, `jarvis-core.service`, `jarvis-voice.service`, `jarvis-ui.service`
- `jarvis-recovery.target`
- `xinitrc` — Xorg kiosk session
- `plymouth/jarvis.script`, `plymouth/jarvis.plymouth` — arc-reactor splash

## jarvis-installer/
- `jarvis-pkg.py`     — package/plugin/model installer + install-to-disk
- `disk_install.sh`   — copy live OS to a disk + install GRUB

## jarvis-build/ — ISO pipeline (each stage runnable standalone)
- `config.sh`        — shared build configuration
- `00_deps.sh`       — host build tools
- `10_bootstrap.sh`  — debootstrap minimal Debian
- `20_provision.sh`  — kernel, X, runtimes, Jarvis code
- `30_configure.sh`  — enable services, splash, recovery, kiosk
- `40_squashfs.sh`   — compress root filesystem
- `50_bootloader.sh` — ISOLINUX (BIOS) + GRUB (UEFI)
- `60_iso.sh`        — xorriso → jarvis-os.iso
- `requirements.txt` — python deps baked into the image

## Quick start
    sudo ./build_jarvis_iso.sh            # → dist/jarvis-os.iso
    sudo JARVIS_FULL_VOICE=1 ./build_jarvis_iso.sh   # with full local voice
