# AuroraOS Architecture

## TL;DR

AuroraOS is a Debian 12 live distribution with an original branding layer and a custom Win11-inspired desktop stack. It boots on UEFI directly (Hyper-V Generation 2 compatible), runs entirely from RAM via a SquashFS + overlayfs live system, and ships a graphical installer for committing to disk.

## Boot path (matches Hyper-V Gen 2)

```
Hyper-V UEFI firmware
  -> reads ISO9660+GPT hybrid disc
  -> finds EFI System Partition image (boot/grub/efi.img)
  -> loads EFI/BOOT/BOOTX64.EFI
        (a self-contained GRUB2 EFI binary built with grub2-mkstandalone)
  -> GRUB reads boot/grub/grub.cfg from the ISO
  -> menu entry runs: linux /live/vmlinuz boot=live components quiet splash
  -> Linux kernel loads with built-in Hyper-V drivers:
        hv_vmbus, hv_storvsc, hv_netvsc, hyperv_drm, hyperv_keyboard, hv_balloon
  -> initramfs (live-boot scripts) finds the .iso volume
        and mounts /live/filesystem.squashfs as the root
  -> overlayfs writes go to RAM (tmpfs)
  -> systemd PID 1 takes over
  -> NetworkManager + LightDM + autologin -> Openbox session
  -> autostart: feh, picom, dunst, tint2, jgmenu, pcmanfm --desktop, aurora-welcome
```

## Component map

| Layer            | What we use                          | Why                                                  |
|------------------|--------------------------------------|------------------------------------------------------|
| Bootloader       | GRUB 2 EFI (x86_64-efi)              | Hyper-V Gen 2 is UEFI-only; standalone EFI binary    |
| Firmware shim    | none                                 | We ship Debian's `firmware-linux*` for safety        |
| Kernel           | Debian `linux-image-amd64`           | Hyper-V drivers in-tree, no rebuild needed           |
| Live infra       | `live-boot`, `live-config`           | Squashfs + overlayfs RAM live boot                   |
| Init             | systemd                              | Standard, works with live-config                     |
| Network          | NetworkManager                       | Drives `hv_netvsc` automatically                     |
| Display server   | Xorg                                 | Reliable on the Hyper-V `hyperv_drm` framebuffer     |
| Compositor       | picom (`dual_kawase` blur, rounded)  | Acrylic, transparency, fade animations               |
| Window manager   | Openbox                              | Lightweight, scriptable, clean keybinds              |
| Panel            | tint2 (centered, pill-shaped)        | Win11 layout                                         |
| Start menu       | jgmenu                               | Pop-up, themed, fast                                 |
| Launcher/search  | rofi                                 | Win+S spotlight                                      |
| Notifications    | dunst                                | Win11-style toasts, rounded                          |
| File manager     | PCManFM (`--desktop` for icons)      | Desktop icons + file browsing in one app             |
| Terminal         | xfce4-terminal                       | Modern, transparent, themable                        |
| Sound            | PipeWire + WirePlumber + pipewire-pulse | Modern audio stack                                |
| Display manager  | LightDM + lightdm-gtk-greeter        | Autologin to live `aurora` user                      |
| Installer        | Calamares                            | Offline graphical OS installer                       |
| Toolkit          | GTK 3 (Aurora theme)                 | Custom CSS theme, Inter font                         |
| Custom apps      | Python + GTK3                        | No compile step, fast iteration: Settings, Welcome, About |

## Repository layout

```
.
├── Makefile                 # `make iso`, `make test`, etc.
├── README.md                # Project overview
├── build/                   # Numbered build stages
│   ├── 00-config.sh         #   Variables and helpers
│   ├── 05-prereqs.sh        #   Tool checks; fetches debootstrap if missing
│   ├── 10-bootstrap.sh      #   debootstrap Debian minbase
│   ├── 20-packages.sh       #   apt-installs kernel, X, DE, apps, installer
│   ├── 30-customize.sh      #   Layers overlay/, runs in-chroot config
│   ├── 40-clean.sh          #   Caches, locales, docs purged; initramfs rebuilt
│   ├── 50-squashfs.sh       #   mksquashfs xz+x86 BCJ; stages ISO tree
│   ├── 60-iso.sh            #   GRUB EFI + FAT image + xorriso hybrid ISO
│   ├── 90-test.sh           #   Boots ISO under QEMU+OVMF, scans serial log
│   ├── build.sh             #   Orchestrator
│   └── assets/              #   Asset generators (theme, icons, plymouth, wallpaper)
├── overlay/                 # Files copied verbatim into the rootfs
│   ├── etc/skel/.config/...     # Per-user DE configs (openbox, picom, tint2, etc.)
│   ├── usr/share/applications/  # Custom .desktop entries
│   └── usr/share/...        # Themes, icons, backgrounds, plymouth
├── apps/                    # Python+GTK3 sources for our apps
│   ├── aurora-settings/
│   ├── aurora-welcome/
│   └── aurora-about/
├── docs/                    # ARCHITECTURE.md (this file), BUILDING.md, etc.
└── .github/workflows/       # CI: builds the ISO on push
```

## Why these choices

* **Debian base** — production-grade, in-tree Hyper-V support since kernel 3.x, mature `live-boot`/`live-config`, large package archive available on a single mirror.
* **Openbox + tint2 over a heavier DE** — every Win11 cue (centered taskbar, rounded panel, transparent overlay) is achievable with smaller config surface than KDE/GNOME, and resource use stays modest (good for VMs).
* **picom backend `glx` + `dual_kawase` blur** — gives true acrylic-style blur and fade animations without proprietary code.
* **Calamares for install** — the only mature offline graphical installer that works from a live ISO and is happy producing Debian-like installs.
* **Python+GTK for apps** — zero compile step in the pipeline, easy to iterate, available out-of-the-box on the rootfs.

## Hyper-V specifics

The Debian kernel ships these in-tree:

* `hv_vmbus`        — VMBus channel transport
* `hv_storvsc`      — synthetic SCSI disk
* `hv_netvsc`       — synthetic network adapter
* `hyperv_keyboard` — synthetic keyboard
* `hyperv_drm`      — synthetic GPU framebuffer (DRM/KMS) -> dynamic resolution
* `hv_balloon`      — memory balloon
* `hv_utils`        — host integration (heartbeat, KVP, time sync, shutdown)

These load automatically when the kernel detects Hyper-V via CPUID. No additional drivers or "linux integration services" packages are required on Hyper-V Gen 2.

## Originality and licensing

Code authored here is MIT-licensed. The branding, theme CSS, icon SVGs, wallpapers, and Plymouth scripts are all original (procedurally generated or hand-written for this project). No Microsoft trademarks, logos, or proprietary assets are used.

Upstream components keep their own licenses:
* Linux kernel — GPLv2 (with syscall exception)
* Debian base packages — DFSG-compliant; full license metadata is in `/usr/share/doc/<pkg>/copyright` inside the rootfs.
* GRUB 2 — GPLv3
* Inter font — SIL OFL 1.1
