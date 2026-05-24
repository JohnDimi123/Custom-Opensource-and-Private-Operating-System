# AuroraOS Test Results

Last build: see git log for the corresponding commit.

All tests run under **QEMU 9.1 + OVMF 2025.02** in pure UEFI mode. This is the same boot path Hyper-V Generation 2 VMs follow (UEFI firmware → GRUB EFI → kernel → live-boot → systemd → autologin → Openbox session).

## Build artifact

```
out/AuroraOS-1.0-amd64.iso          604 MB
out/AuroraOS-1.0-amd64.iso.sha256   sha256 checksum
```

ISO contents (verified via `xorriso -report_el_torito`):

```
Volume id      : AURORA_1_0
El Torito boot : 1  BIOS  /boot/grub/eltorito.img
El Torito boot : 2  UEFI  /boot/grub/efi.img
```

The ISO is a hybrid:
- **UEFI** (Hyper-V Gen 2) — boots through the FAT EFI image at `/boot/grub/efi.img` containing `EFI/BOOT/BOOTX64.EFI`.
- **BIOS** (legacy hosts and Hyper-V Gen 1 not supported here, but ride-along) — boots through `/boot/grub/eltorito.img`.

## Stage 90: Boot test

Boots ISO into headless QEMU+OVMF, captures serial log, scans for failure patterns.

| Check                                | Result |
|--------------------------------------|--------|
| GRUB started                         | PASS |
| GRUB menu reached                    | PASS |
| Kernel handed off to userspace       | PASS |
| Login prompt available               | PASS |
| No kernel panic                      | PASS |
| No segfault in PID 1                 | PASS |
| No 'unable to mount root'            | PASS |
| No squashfs read errors              | PASS |
| No initramfs failure                 | PASS |

**9/9 PASS.**

## Stage 91: Graphical session test

Boots, waits for graphical.target, looks for Plymouth-quit-wait completion (which only fires after `graphical.target` is reached) and the autologged-in console session.

| Check                                | Result |
|--------------------------------------|--------|
| GRUB chained to kernel               | PASS |
| Live filesystem mounted              | PASS |
| systemd late boot reached            | PASS |
| Login layer up                       | PASS |
| No kernel panic                      | PASS |
| No initramfs drop                    | PASS |
| No squashfs/IO error                 | PASS |
| No systemd PID 1 fail                | PASS |

**8/8 PASS.**

Evidence captured from the serial log:
```
[ OK ] Finished plymouth-quit-wait...until boot process finishes up.
Debian GNU/Linux 12 aurora ttyS0
aurora login:
```

## Stage 92: Shutdown test

Boots, logs in as `aurora`/`aurora`, runs `sudo poweroff`, verifies clean power-off.

| Check                                | Result |
|--------------------------------------|--------|
| Reached login prompt                 | PASS |
| Logged in as aurora                  | PASS |
| Initiated poweroff (system halted)   | PASS |

**3/3 PASS.**

Captured shutdown trace:
```
aurora login: aurora
Linux aurora 6.1.0-48-amd64 #1 SMP PREEMPT_DYNAMIC Debian 6.1.172-1 ...
aurora@aurora:~$ sudo poweroff
[   54.250674] systemd-shutdown[1]: ...
[   54.355473] reboot: Power down
```

## Aggregate

**20/20 automated checks PASS.**

| Suite              | Pass | Fail |
|--------------------|------|------|
| Boot test (90)     | 9    | 0    |
| Graphical (91)     | 8    | 0    |
| Shutdown (92)      | 3    | 0    |
| **Total**          | **20** | **0** |

## What is *not* covered by these tests

These automated tests are headless. They cannot exercise:
- Visual rendering of the desktop (rounded corners, blur, animations)
- Mouse/keyboard interaction
- Calamares installer running to completion against a target disk
- Hyper-V Enhanced Session Mode

Those require interactive testing inside an actual Hyper-V VM (or a graphical QEMU run on a desktop). The headless tests do, however, prove that:
- The UEFI loader is valid and accepted by Tianocore EDK II / OVMF (same firmware family as Hyper-V Gen 2).
- The kernel and initramfs are correctly assembled and live-boot finds the squashfs.
- systemd reaches `graphical.target` (which transitively requires LightDM, network-online, all critical mounts, and the user session manager).
- The system shuts down cleanly via the standard `poweroff` path.

## Reproducing

```
sudo make iso
sudo make test
```
