#!/usr/bin/env python3
"""
jarvis-installer/jarvis-pkg.py — custom package & plugin installer.

Usage:
  jarvis-pkg install <plugin>     install a plugin from the registry
  jarvis-pkg remove  <plugin>     remove an installed plugin
  jarvis-pkg list                 list installed plugins
  jarvis-pkg model <url>          download a GGUF local model to /opt/jarvis/models
  jarvis-pkg install-disk         install the running live OS to disk

Plugins are simple Python packages dropped into /opt/jarvis/plugins/<name>
with a manifest.json declaring capabilities the plugin requests.
"""
import os
import sys
import json
import shutil
import subprocess
import urllib.request
from pathlib import Path

PLUGIN_DIR = Path("/opt/jarvis/plugins")
MODEL_DIR = Path("/opt/jarvis/models")
REGISTRY = "https://raw.githubusercontent.com/jarvis-os/registry/main/index.json"


def _ensure_dirs():
    PLUGIN_DIR.mkdir(parents=True, exist_ok=True)
    MODEL_DIR.mkdir(parents=True, exist_ok=True)


def list_plugins():
    _ensure_dirs()
    for p in sorted(PLUGIN_DIR.iterdir()):
        if (p / "manifest.json").exists():
            meta = json.loads((p / "manifest.json").read_text())
            caps = ", ".join(meta.get("capabilities", [])) or "none"
            print(f"  {p.name:20} v{meta.get('version','?'):8} caps: {caps}")


def install_plugin(name):
    _ensure_dirs()
    try:
        with urllib.request.urlopen(REGISTRY, timeout=15) as r:
            index = json.loads(r.read().decode())
    except Exception as e:  # noqa: BLE001
        print(f"! registry unreachable: {e}")
        return 1
    entry = index.get(name)
    if not entry:
        print(f"! plugin '{name}' not found in registry")
        return 1
    dest = PLUGIN_DIR / name
    print(f"installing {name} v{entry['version']} from {entry['url']}")
    archive = f"/tmp/{name}.tar.gz"
    urllib.request.urlretrieve(entry["url"], archive)
    dest.mkdir(parents=True, exist_ok=True)
    subprocess.run(f"tar xzf {archive} -C {dest}", shell=True, check=True)
    print(f"✓ installed {name}. Enable it from the HUD plugin manager.")
    return 0


def remove_plugin(name):
    dest = PLUGIN_DIR / name
    if dest.exists():
        shutil.rmtree(dest)
        print(f"✓ removed {name}")
    else:
        print(f"! {name} is not installed")


def download_model(url):
    _ensure_dirs()
    fname = url.split("/")[-1]
    dest = MODEL_DIR / fname
    print(f"downloading model → {dest}")
    urllib.request.urlretrieve(url, dest)
    print(f"✓ model ready: {dest}")


def install_to_disk():
    """Copy the live squashfs root to a target disk and install GRUB."""
    print("=== JARVIS install-to-disk ===")
    subprocess.run("lsblk -dno NAME,SIZE,MODEL", shell=True)
    target = input("Target disk (e.g. /dev/sda) — THIS WILL BE ERASED: ").strip()
    if not target.startswith("/dev/"):
        print("aborted")
        return 1
    if input(f"Type ERASE to wipe {target}: ").strip() != "ERASE":
        print("aborted")
        return 1
    script = Path("/opt/jarvis/installer/disk_install.sh")
    subprocess.run(f"bash {script} {target}", shell=True, check=True)
    return 0


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 0
    cmd = argv[1]
    if cmd == "list":
        list_plugins()
    elif cmd == "install" and len(argv) > 2:
        return install_plugin(argv[2])
    elif cmd == "remove" and len(argv) > 2:
        remove_plugin(argv[2])
    elif cmd == "model" and len(argv) > 2:
        download_model(argv[2])
    elif cmd == "install-disk":
        return install_to_disk()
    else:
        print(__doc__)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
