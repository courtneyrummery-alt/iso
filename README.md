# IsoOS

A real, bootable live ISO built on top of Ubuntu 24.04 (Noble).

- Hybrid boot: BIOS (isolinux) + UEFI (GRUB), `isohybrid` MBR/GPT.
- Live root via `casper` + `squashfs` (xz compressed).
- Default live user: `isoos` / `isoos` (sudo, NOPASSWD).
- Kernel: Ubuntu `linux-image-generic` (whatever Noble currently ships).

## Build

### Linux host (Ubuntu 22.04+)

~8 GB scratch, network access to `archive.ubuntu.com`, root:

```sh
sudo apt-get install -y debootstrap squashfs-tools xorriso isolinux \
    syslinux-common grub-pc-bin grub-efi-amd64-bin mtools dosfstools
sudo ./build.sh
```

### Windows host (Docker Desktop)

The build tools (`debootstrap`, `mksquashfs`, `xorriso`, …) are Linux-only,
so the Windows path runs them inside a privileged Ubuntu 24.04 container.
Requires Docker Desktop with the WSL2 backend enabled.

```powershell
.\build.ps1
```

`build.ps1` builds the `isoos-builder` image, then runs `build.sh` inside
it with the repo bind-mounted. The chroot scratch lives in a named Docker
volume (`isoos-work`) because NTFS can't represent the device nodes and
Unix permissions debootstrap creates; only the finished ISO is written
back to `out\` on the host.

Output: `out/isoos-0.1.0-amd64.iso`.

## Layout

| Path                  | Purpose                                         |
|-----------------------|-------------------------------------------------|
| `build.sh`            | Top-level build script (debootstrap → ISO).     |
| `build.ps1`           | Windows wrapper that runs `build.sh` in Docker. |
| `Dockerfile`          | Ubuntu 24.04 builder image used by `build.ps1`. |
| `chroot-setup.sh`     | Runs inside the chroot to install live tooling. |
| `branding/`           | `os-release`, `motd`, login banner, etc.        |
| `boot/isolinux.cfg`   | BIOS boot menu (syslinux).                      |
| `boot/grub.cfg`       | UEFI / GRUB boot menu.                          |
| `work/`               | Build scratch (chroot, image staging). Cached.  |
| `out/`                | Final ISO.                                      |

## Run the ISO

```sh
qemu-system-x86_64 -m 2G -cdrom out/isoos-0.1.0-amd64.iso        # BIOS
qemu-system-x86_64 -m 2G -bios /usr/share/OVMF/OVMF_CODE.fd \
    -cdrom out/isoos-0.1.0-amd64.iso                              # UEFI
```

Or `dd` to a USB stick — the ISO is isohybrid.
