# AuroraOS

A Linux distribution with a Windows 11–inspired desktop, packaged as a single bootable ISO that runs natively on Hyper-V Generation 2 (UEFI) virtual machines.

* **Bootloader** – GRUB 2 (x86_64-efi), self-contained EFI binary
* **Kernel** – Linux (Debian `linux-image-amd64`, Hyper-V drivers in-tree)
* **Init** – systemd
* **Live** – `live-boot` + SquashFS + overlayfs (RAM)
* **Display** – Xorg + picom (rounded corners, blur, fade animations)
* **Window Manager** – Openbox + tint2 (centered taskbar) + jgmenu (start menu) + rofi (search) + dunst (notifications)
* **Apps** – PCManFM (files + desktop icons), xfce4-terminal, custom Settings / Welcome / About (Python+GTK3)
* **Installer** – Calamares (offline, graphical)
* **Audio / Network / Storage** – PipeWire / NetworkManager / standard Linux

Branding, theme, icons, wallpapers, Plymouth boot splash and custom apps are all original to this project. No Microsoft trademarks or proprietary assets are used.

## Build

```
sudo make iso
```

Builds `out/AuroraOS-1.0-amd64.iso` and runs an automated QEMU+OVMF boot test.

## Run on Hyper-V

1. Hyper-V Manager → **New > Virtual Machine** → **Generation 2**.
2. Memory ≥ 2048 MB. Network: any switch.
3. **Installation options** → install from a bootable image file → choose `AuroraOS-1.0-amd64.iso`.
4. After the VM is created: **Settings → Security** → either disable Secure Boot, or change the template to *Microsoft UEFI Certificate Authority*.
5. Start the VM. AuroraOS boots to the Live desktop.

## Documentation

* [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — full architecture overview
* [docs/BUILDING.md](docs/BUILDING.md) — build instructions for various hosts
* [docs/LIMITATIONS.md](docs/LIMITATIONS.md) — known limitations and honest caveats
* [docs/TEST-RESULTS.md](docs/TEST-RESULTS.md) — automated test report from the latest build

## License

MIT for original work in this repository. Upstream packages retain their own licenses; see [LICENSE](LICENSE).
