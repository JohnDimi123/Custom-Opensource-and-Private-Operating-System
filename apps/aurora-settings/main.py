#!/usr/bin/env python3
"""AuroraOS Settings - a GTK3 control center.

Sections:
  - Personalization: theme (light/dark/auto), accent color, wallpaper picker
  - Display: resolution (xrandr-driven; supports Hyper-V dynamic resolution)
  - Sound: default sink + volume (PipeWire/Pulse)
  - Network: launch nm-connection-editor
  - Accounts: change live-user password
  - About: show distro info

Pure stdlib + GTK3.  No external network calls.
"""
from __future__ import annotations

import gi, os, subprocess, json, shutil, pathlib, signal, sys
gi.require_version("Gtk", "3.0")
gi.require_version("Pango", "1.0")
from gi.repository import Gtk, Gdk, GLib, Pango

WALLPAPER_DIR = "/usr/share/backgrounds/aurora"
CONFIG_DIR = pathlib.Path.home() / ".config" / "aurora"
CONFIG_DIR.mkdir(parents=True, exist_ok=True)
CONFIG_FILE = CONFIG_DIR / "settings.json"


def load_cfg():
    if CONFIG_FILE.exists():
        try: return json.loads(CONFIG_FILE.read_text())
        except Exception: return {}
    return {}


def save_cfg(cfg):
    CONFIG_FILE.write_text(json.dumps(cfg, indent=2))


def run(cmd):
    try:
        return subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError as e:
        return e.output or ""
    except FileNotFoundError:
        return ""


# ---- Sections ---------------------------------------------------------------
def make_card(title):
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
    box.get_style_context().add_class("aurora-card")
    lbl = Gtk.Label(label=title, xalign=0)
    lbl.get_style_context().add_class("aurora-section-title")
    box.pack_start(lbl, False, False, 0)
    return box


def section_personalization(cfg):
    sec = make_card("Personalization")

    # Theme variant
    row = Gtk.Box(spacing=12)
    row.pack_start(Gtk.Label(label="Theme", xalign=0), True, True, 0)
    combo = Gtk.ComboBoxText()
    for v in ("Dark", "Light"): combo.append_text(v)
    combo.set_active(0 if cfg.get("theme", "dark") == "dark" else 1)
    def on_theme(c):
        prefer_dark = c.get_active_text() == "Dark"
        Gtk.Settings.get_default().set_property("gtk-application-prefer-dark-theme", prefer_dark)
        cfg["theme"] = "dark" if prefer_dark else "light"
        save_cfg(cfg)
        # Switch wallpaper to match
        wp = "aurora-default.png" if prefer_dark else "aurora-light.png"
        wp_path = os.path.join(WALLPAPER_DIR, wp)
        if os.path.exists(wp_path):
            subprocess.Popen(["feh", "--bg-fill", wp_path])
    combo.connect("changed", on_theme)
    row.pack_start(combo, False, False, 0)
    sec.pack_start(row, False, False, 0)

    # Wallpaper picker
    sec.pack_start(Gtk.Label(label="Wallpaper", xalign=0), False, False, 0)
    flow = Gtk.FlowBox()
    flow.set_max_children_per_line(4)
    flow.set_selection_mode(Gtk.SelectionMode.SINGLE)
    if os.path.isdir(WALLPAPER_DIR):
        for f in sorted(os.listdir(WALLPAPER_DIR)):
            if not f.lower().endswith((".png", ".jpg", ".jpeg")): continue
            path = os.path.join(WALLPAPER_DIR, f)
            try:
                pb = Gtk.Image.new_from_file(path)
                pb.set_pixel_size(110)
                btn = Gtk.Button()
                btn.set_image(pb)
                btn.set_relief(Gtk.ReliefStyle.NONE)
                btn.set_tooltip_text(f)
                btn.connect("clicked", lambda b, p=path: subprocess.Popen(["feh", "--bg-fill", p]))
                flow.add(btn)
            except Exception:
                pass
    sec.pack_start(flow, False, False, 0)
    return sec


def section_display():
    sec = make_card("Display")
    info = run(["xrandr"])
    primary = ""
    modes = []
    current = ""
    for line in info.splitlines():
        if " connected " in line and "primary" in line:
            primary = line.split()[0]
        if line.startswith("   "):  # mode line
            parts = line.split()
            modes.append(parts[0])
            if "*" in line: current = parts[0]
    lbl = Gtk.Label(xalign=0)
    lbl.set_markup(f"<b>Output:</b> {primary or 'unknown'}\n<b>Current:</b> {current or 'unknown'}")
    sec.pack_start(lbl, False, False, 0)

    if primary and modes:
        row = Gtk.Box(spacing=12)
        row.pack_start(Gtk.Label(label="Resolution", xalign=0), True, True, 0)
        combo = Gtk.ComboBoxText()
        for m in modes: combo.append_text(m)
        if current in modes: combo.set_active(modes.index(current))
        def on_change(c):
            mode = c.get_active_text()
            if mode and primary:
                subprocess.Popen(["xrandr", "--output", primary, "--mode", mode])
        combo.connect("changed", on_change)
        row.pack_start(combo, False, False, 0)
        sec.pack_start(row, False, False, 0)

    btn = Gtk.Button(label="Open advanced display tool (arandr)")
    btn.connect("clicked", lambda *_: subprocess.Popen(["arandr"]))
    sec.pack_start(btn, False, False, 0)
    return sec


def section_sound():
    sec = make_card("Sound")
    sinks = run(["pactl", "list", "short", "sinks"]).strip().splitlines()
    if not sinks:
        sec.pack_start(Gtk.Label(label="PipeWire/PulseAudio not running.", xalign=0), False, False, 0)
        return sec

    sec.pack_start(Gtk.Label(label="Output device", xalign=0), False, False, 0)
    combo = Gtk.ComboBoxText()
    default = run(["pactl", "get-default-sink"]).strip()
    for line in sinks:
        parts = line.split("\t")
        if len(parts) >= 2:
            combo.append_text(parts[1])
    # set active to default
    text_to_idx = {t: i for i, t in enumerate(combo.get_model()) for t in ([t[0]] if False else [t[0]])}
    # Set active on default
    items = [c[0] for c in combo.get_model()]
    if default in items: combo.set_active(items.index(default))
    combo.connect("changed", lambda c: subprocess.Popen(["pactl", "set-default-sink", c.get_active_text()]))
    sec.pack_start(combo, False, False, 0)

    # Volume
    row = Gtk.Box(spacing=8)
    row.pack_start(Gtk.Label(label="Volume", xalign=0), False, False, 0)
    adj = Gtk.Adjustment(value=70, lower=0, upper=150, step_increment=1)
    scale = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL, adjustment=adj)
    scale.set_value_pos(Gtk.PositionType.RIGHT)
    scale.set_hexpand(True)
    def on_vol(s):
        v = int(s.get_value())
        sink = combo.get_active_text() or "@DEFAULT_SINK@"
        subprocess.Popen(["pactl", "set-sink-volume", sink, f"{v}%"])
    scale.connect("value-changed", on_vol)
    row.pack_start(scale, True, True, 0)
    sec.pack_start(row, False, False, 0)

    btn = Gtk.Button(label="Open advanced sound mixer (pavucontrol)")
    btn.connect("clicked", lambda *_: subprocess.Popen(["pavucontrol"]))
    sec.pack_start(btn, False, False, 0)
    return sec


def section_network():
    sec = make_card("Network")
    state = run(["nmcli", "-t", "general", "status"]).strip() or "NetworkManager not running"
    sec.pack_start(Gtk.Label(label=f"Status: {state}", xalign=0), False, False, 0)
    devs = run(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "device"]).strip().splitlines()
    if devs:
        for d in devs[:6]:
            sec.pack_start(Gtk.Label(label=d, xalign=0), False, False, 0)
    btn = Gtk.Button(label="Manage connections (nm-connection-editor)")
    btn.connect("clicked", lambda *_: subprocess.Popen(["nm-connection-editor"]))
    sec.pack_start(btn, False, False, 0)
    return sec


def section_accounts():
    sec = make_card("Accounts")
    user = os.environ.get("USER", "aurora")
    sec.pack_start(Gtk.Label(label=f"Signed in as: {user}", xalign=0), False, False, 0)
    btn = Gtk.Button(label=f"Change password for {user}")
    def change_pw(_):
        subprocess.Popen(["xfce4-terminal", "-e", f"bash -c 'passwd; read -p Press_Enter'"])
    btn.connect("clicked", change_pw)
    sec.pack_start(btn, False, False, 0)
    return sec


def section_about():
    sec = make_card("About")
    info = {}
    try:
        for line in pathlib.Path("/etc/os-release").read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                info[k] = v.strip('"')
    except Exception: pass
    kernel = run(["uname", "-r"]).strip()
    cpu = run(["bash", "-c", "lscpu | awk -F: '/Model name/{gsub(/^[ \\t]+/,\"\",$2); print $2; exit}'"]).strip() or "unknown CPU"
    mem = run(["bash", "-c", "free -h | awk '/Mem:/ {print $2}'"]).strip()
    text = (
        f"<big><b>{info.get('PRETTY_NAME', 'AuroraOS')}</b></big>\n"
        f"\n"
        f"Kernel: {kernel}\n"
        f"CPU:    {cpu}\n"
        f"Memory: {mem}\n"
        f"Distribution: {info.get('NAME','Aurora')}\n"
        f"Version: {info.get('VERSION','1.0')}\n"
        f"\n"
        f"AuroraOS is built on the Linux kernel and Debian userspace.\n"
        f"All branding, theme, icons, wallpapers and custom apps are original.\n"
    )
    lbl = Gtk.Label(xalign=0)
    lbl.set_markup(text)
    lbl.set_line_wrap(True)
    sec.pack_start(lbl, False, False, 0)
    return sec


class SettingsWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="Settings")
        self.set_default_size(900, 620)
        self.set_position(Gtk.WindowPosition.CENTER)

        cfg = load_cfg()

        hb = Gtk.HeaderBar(show_close_button=True, title="Settings")
        self.set_titlebar(hb)

        paned = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)
        self.add(paned)

        # Sidebar
        sidebar = Gtk.ListBox()
        sidebar.set_selection_mode(Gtk.SelectionMode.SINGLE)
        for name in ("Personalization", "Display", "Sound", "Network", "Accounts", "About"):
            r = Gtk.ListBoxRow()
            r.add(Gtk.Label(label=name, xalign=0, margin=10))
            sidebar.add(r)
        sw = Gtk.ScrolledWindow()
        sw.set_size_request(220, -1)
        sw.add(sidebar)
        paned.pack1(sw, False, False)

        # Stack of sections
        stack = Gtk.Stack()
        stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        stack.set_transition_duration(200)
        stack.add_named(self._scroll(section_personalization(cfg)), "Personalization")
        stack.add_named(self._scroll(section_display()),            "Display")
        stack.add_named(self._scroll(section_sound()),              "Sound")
        stack.add_named(self._scroll(section_network()),            "Network")
        stack.add_named(self._scroll(section_accounts()),           "Accounts")
        stack.add_named(self._scroll(section_about()),              "About")
        paned.pack2(stack, True, True)

        sidebar.connect("row-selected", lambda lb, r: stack.set_visible_child_name(
            r.get_child().get_text() if r else "Personalization"))
        sidebar.select_row(sidebar.get_row_at_index(0))

        self._load_css()
        self.connect("destroy", Gtk.main_quit)

    def _scroll(self, w):
        sw = Gtk.ScrolledWindow()
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=18)
        box.pack_start(w, False, False, 0)
        sw.add(box)
        return sw

    def _load_css(self):
        css = b"""
        .aurora-card {
            background-color: alpha(@theme_fg_color, 0.06);
            border-radius: 12px;
            padding: 16px;
        }
        .aurora-section-title {
            font-weight: bold;
            font-size: 14px;
        }
        """
        provider = Gtk.CssProvider()
        provider.load_from_data(css)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)


def main():
    signal.signal(signal.SIGINT, lambda *_: Gtk.main_quit())
    win = SettingsWindow()
    win.show_all()
    Gtk.main()


if __name__ == "__main__":
    main()
