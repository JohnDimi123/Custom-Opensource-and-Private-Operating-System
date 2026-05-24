#!/usr/bin/env python3
"""AuroraOS Welcome - first-run greeter shown automatically on the live session.
Offers quick links to: Install, Settings, Files, Terminal, About. Win11-style hero card."""
import gi, os, subprocess, pathlib
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, GdkPixbuf

CFG_DIR = pathlib.Path.home() / ".config" / "aurora"
CFG_DIR.mkdir(parents=True, exist_ok=True)
MARK_FILE = CFG_DIR / "welcome-shown"


def card(icon_name, label, on_click):
    btn = Gtk.Button()
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=12)
    img = Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.DIALOG)
    img.set_pixel_size(48)
    box.pack_start(img, False, False, 0)
    box.pack_start(Gtk.Label(label=label), False, False, 0)
    btn.add(box)
    btn.set_relief(Gtk.ReliefStyle.NORMAL)
    btn.connect("clicked", lambda *_: on_click())
    return btn


class Welcome(Gtk.Window):
    def __init__(self):
        super().__init__(title="Welcome to AuroraOS")
        self.set_default_size(720, 520)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_titlebar(Gtk.HeaderBar(show_close_button=True, title="Welcome"))

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=20, margin=24)

        # Hero
        hero = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        title = Gtk.Label()
        title.set_markup("<span size='xx-large' weight='bold'>Welcome to AuroraOS</span>")
        title.set_xalign(0)
        sub = Gtk.Label()
        sub.set_markup("<span size='medium' alpha='80%'>A modern, polished desktop. Pick where to begin.</span>")
        sub.set_xalign(0)
        hero.pack_start(title, False, False, 0)
        hero.pack_start(sub, False, False, 0)
        outer.pack_start(hero, False, False, 0)

        grid = Gtk.Grid(column_spacing=14, row_spacing=14, halign=Gtk.Align.CENTER)
        grid.attach(card("system-software-install", "Install AuroraOS",
                         lambda: subprocess.Popen(["sudo", "-E", "calamares"])), 0, 0, 1, 1)
        grid.attach(card("preferences-system", "Open Settings",
                         lambda: subprocess.Popen(["aurora-settings"])), 1, 0, 1, 1)
        grid.attach(card("system-file-manager", "Files",
                         lambda: subprocess.Popen(["pcmanfm"])), 2, 0, 1, 1)
        grid.attach(card("utilities-terminal", "Terminal",
                         lambda: subprocess.Popen(["xfce4-terminal"])), 0, 1, 1, 1)
        grid.attach(card("help-browser", "Tour",
                         self._tour), 1, 1, 1, 1)
        grid.attach(card("help-about", "About",
                         lambda: subprocess.Popen(["aurora-about"])), 2, 1, 1, 1)
        outer.pack_start(grid, True, True, 0)

        # Footer
        footer = Gtk.Box(spacing=8)
        cb = Gtk.CheckButton(label="Show this on every start")
        cb.set_active(not MARK_FILE.exists())
        def on_toggle(c):
            if c.get_active():
                if MARK_FILE.exists(): MARK_FILE.unlink()
            else:
                MARK_FILE.touch()
        cb.connect("toggled", on_toggle)
        footer.pack_start(cb, False, False, 0)
        outer.pack_start(footer, False, False, 0)

        self.add(outer)
        self.connect("destroy", Gtk.main_quit)

        # Mark as shown right away so subsequent boots skip
        if not MARK_FILE.exists():
            MARK_FILE.touch()

    def _tour(self):
        d = Gtk.MessageDialog(
            transient_for=self, modal=True,
            message_type=Gtk.MessageType.INFO, buttons=Gtk.ButtonsType.CLOSE,
            text="AuroraOS quick tour")
        d.format_secondary_markup(
            "<b>Taskbar</b>: centered at the bottom. Click Start (left) for apps; clock is on the right.\n\n"
            "<b>Search</b>: press <tt>Win+S</tt> or <tt>Win+R</tt>.\n\n"
            "<b>Tile windows</b>: <tt>Win+Left</tt> / <tt>Win+Right</tt> snap; <tt>Win+Up</tt> maximises.\n\n"
            "<b>Terminal</b>: <tt>Ctrl+Alt+T</tt>.\n\n"
            "<b>Files</b>: <tt>Win+E</tt>.\n\n"
            "<b>Themes</b>: switch dark/light in Settings &gt; Personalization.\n\n"
            "<b>Install</b>: choose 'Install AuroraOS' from this welcome screen or the menu.")
        d.run(); d.destroy()


def main():
    Welcome().show_all()
    Gtk.main()


if __name__ == "__main__":
    main()
