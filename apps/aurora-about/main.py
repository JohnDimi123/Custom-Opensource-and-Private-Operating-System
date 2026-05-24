#!/usr/bin/env python3
"""AuroraOS About - simple, focused system info dialog."""
import gi, subprocess, pathlib
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

def run(cmd):
    try: return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception: return ""

def main():
    win = Gtk.Window(title="About AuroraOS")
    win.set_default_size(520, 460)
    win.set_position(Gtk.WindowPosition.CENTER)
    win.set_titlebar(Gtk.HeaderBar(show_close_button=True, title="About"))

    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14, margin=24)

    img = Gtk.Image.new_from_icon_name("aurora-logo", Gtk.IconSize.DIALOG)
    img.set_pixel_size(96)
    box.pack_start(img, False, False, 0)

    info = {}
    try:
        for line in pathlib.Path("/etc/os-release").read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1); info[k] = v.strip('"')
    except Exception: pass

    title = Gtk.Label()
    title.set_markup(f"<span size='xx-large' weight='bold'>{info.get('PRETTY_NAME','AuroraOS')}</span>")
    box.pack_start(title, False, False, 0)

    facts = (
        ("Version",    info.get("VERSION", "1.0")),
        ("Codename",   info.get("VERSION_CODENAME", "lumen")),
        ("Kernel",     run(["uname", "-r"])),
        ("Hostname",   run(["hostname"])),
        ("CPU",        run(["bash","-c","lscpu | awk -F: '/Model name/{gsub(/^[ \\t]+/,\"\",$2); print $2; exit}'"])),
        ("Memory",     run(["bash","-c","free -h | awk '/Mem:/ {print $2}'"])),
        ("Architecture", run(["uname","-m"])),
    )
    grid = Gtk.Grid(column_spacing=18, row_spacing=6, halign=Gtk.Align.CENTER)
    for i,(k,v) in enumerate(facts):
        kl = Gtk.Label(xalign=1)
        kl.set_markup(f"<span alpha='70%'>{k}</span>")
        vl = Gtk.Label(label=v or "—", xalign=0)
        grid.attach(kl, 0, i, 1, 1)
        grid.attach(vl, 1, i, 1, 1)
    box.pack_start(grid, False, False, 0)

    credits = Gtk.Label()
    credits.set_markup(
        "<span alpha='75%'>AuroraOS is built on the Linux kernel and Debian userspace.\n"
        "Branding, themes, icons, wallpapers and apps are original to AuroraOS.\n"
        "Released under the MIT license. No proprietary trademarks are used.</span>")
    credits.set_justify(Gtk.Justification.CENTER)
    credits.set_line_wrap(True)
    box.pack_start(credits, False, False, 8)

    btn = Gtk.Button(label="Close")
    btn.connect("clicked", lambda *_: Gtk.main_quit())
    box.pack_end(btn, False, False, 0)

    win.add(box)
    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    Gtk.main()

if __name__ == "__main__":
    main()
