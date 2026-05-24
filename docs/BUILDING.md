# Building AuroraOS

## Hosts the build pipeline supports

Tested on:
* **Amazon Linux 2023** (the build host used to produce the reference ISO)
* **Fedora 38+**, **RHEL 9 / Rocky 9 / AlmaLinux 9**
* **Debian 12 / Ubuntu 22.04+** (drop the `dnf` lines from `05-prereqs.sh` and use `apt` instead)

You need: ~10 GB free disk, ~2 GB RAM, root, and internet during the build.

## One-command build

```
sudo make iso
```

That runs every stage in `build/` and ends with the ISO at:

```
out/AuroraOS-1.0-amd64.iso
out/AuroraOS-1.0-amd64.iso.sha256
```

It also runs `90-test.sh` automatically — boot under QEMU+OVMF and scan the kernel/serial log for panics, broken filesystems, and confirm graphical session start. Set `SKIP_TEST=1` to skip.

## Stage-by-stage

```
build/05-prereqs.sh   # apt/dnf installs xorriso, mksquashfs, grub2-tools, mtools,
                      # dosfstools, rsync, etc. Fetches debootstrap if absent.
build/10-bootstrap.sh # debootstrap a Debian minbase rootfs into work/rootfs
build/20-packages.sh  # apt-get install kernel + X + DE + Calamares
build/30-customize.sh # Generates wallpapers/icons/plymouth, copies overlay/,
                      # and configures inside the chroot
build/40-clean.sh     # Updates initramfs (live-boot), purges caches, locales, docs
build/50-squashfs.sh  # mksquashfs (xz + x86 BCJ) -> work/iso/live/filesystem.squashfs
build/60-iso.sh       # Builds BOOTX64.EFI, EFI image, and the hybrid xorriso ISO
build/90-test.sh      # Boots ISO under QEMU+OVMF and reports PASS/FAIL
```

Re-running `make iso` is incremental: stages 10 and 20 skip if their checkpoints exist (`work/rootfs/.bootstrapped`, `.packages-installed`).

## Running the ISO

### Hyper-V (target environment)
1. Open Hyper-V Manager. **New > Virtual Machine**.
2. **Generation 2**.
3. Memory ≥ 2048 MB. Network: any virtual switch.
4. **Hard disk**: any new VHDX (only used if you choose to install).
5. **Installation options**: *Install from a bootable image file* → select `AuroraOS-1.0-amd64.iso`.
6. After creation, **Settings > Security**: turn off Secure Boot, **or** keep it on and select the *Microsoft UEFI Certificate Authority* template (we ship an unsigned EFI binary by default).
7. Start the VM. The GRUB menu appears, then AuroraOS boots to the desktop.

### QEMU (development)

```
qemu-system-x86_64 -machine q35,accel=kvm -m 2048 -smp 2 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
  -drive if=pflash,format=raw,file=ovmf_vars.fd \
  -drive media=cdrom,readonly=on,file=out/AuroraOS-1.0-amd64.iso
```

## Rebuilding only one stage

```
sudo build/30-customize.sh    # re-apply overlay (after editing theme/configs)
sudo build/50-squashfs.sh     # rebuild squashfs
sudo build/60-iso.sh          # repack ISO
```

## CI

`.github/workflows/build.yml` runs the same pipeline on every push and uploads the ISO as a workflow artefact, plus a release asset on tag pushes.
