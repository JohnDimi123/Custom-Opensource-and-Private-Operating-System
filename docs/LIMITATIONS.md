# Known Limitations

This is an honest list. AuroraOS aims for stability and presentation quality, not feature parity with Windows 11.

## Honest framing

* The Linux kernel and Debian-derived userspace are **upstream open-source software**, not authored here. The original work in this repository is the build pipeline, branding, theming, custom GTK apps (Settings, Welcome, About), DE configuration, and the live/install integration.
* Visual design is **inspired by** Windows 11 (rounded corners, centered taskbar, transparency). It is not Windows. No Microsoft trademarks or copyrighted assets are used.

## What works

* Boot on **Hyper-V Generation 2** (UEFI). Confirmed boot path tested under QEMU + OVMF, which uses the same UEFI loader → kernel → live-boot pipeline.
* Mouse, keyboard, dynamic resolution (`hyperv_drm` framebuffer DRM/KMS).
* Network via `hv_netvsc` + NetworkManager (DHCP by default).
* Storage: read ISO9660 from the virtual DVD, write to RAM via overlayfs in live mode; write to disk via Calamares installer.
* Sound: PipeWire is configured but Hyper-V's synthetic audio device is limited; works best on hardware.
* Light/dark themes via Settings → Personalization.
* Live session autologin; install to disk via Calamares.

## Limitations

1. **Secure Boot**: the EFI binary we ship is **unsigned**. Hyper-V Gen 2 enables Secure Boot by default — turn it off, or set the *Microsoft UEFI Certificate Authority* template (we are not on it). A future release can ship a shim signed by an enrolled MOK.
2. **Hyper-V audio**: the synthetic audio device (`hda` emulation) is hit-or-miss across Windows host versions. Sound in Hyper-V VMs is generally limited to RDP/Enhanced-Session mode, which needs `xrdp` configuration we have not enabled by default.
3. **Enhanced Session Mode** (RDP into the VM with clipboard/USB redirection): not enabled. Requires `hyperv-daemons` plus an `xrdp` profile; we ship `hyperv-daemons` but not the xrdp wiring.
4. **Calamares offline profile**: uses `calamares-settings-debian` defaults. The first install may need you to confirm partition layout. The installer reads the running squashfs and unpacks to disk; no internet is required.
5. **No GPU acceleration in VMs**: `picom`'s GLX backend uses software rendering on the `hyperv_drm` device. Animations stay smooth at 1080p but heavy compositing (4K, many windows) is CPU-bound.
6. **No package signing key for our own additions**: AuroraOS is intended as a single-shot live image. There is no AuroraOS apt repository.
7. **Fonts**: Inter is bundled (OFL). Some apps may fall back to DejaVu where Inter glyphs don't cover the needed characters.
8. **Plymouth**: works in the live ISO when running on real or fully-virtualised graphics. In some Hyper-V firmwares the splash flickers briefly during the framebuffer handover; the boot itself is unaffected.
9. **Localisation**: only `en_US.UTF-8` is generated to keep the ISO small. Adding more is a one-line change in `30-customize.sh`.
10. **Build-time downloads**: the *build host* needs internet access to pull Debian packages. The *resulting ISO* runs entirely offline; nothing is downloaded during install or first boot.

## Where it might break

* Very old Hyper-V versions (Windows 8.1 / Server 2012 R2) may not support all the DRM features the kernel expects. Use Windows 10/11 or Server 2016+.
* If Secure Boot is enforced and unsigned UEFI binaries are blocked, the ISO won't boot. See item 1.
* If your host CPU lacks SSSE3 (very rare), Plymouth's animations may glitch.
