#!/usr/bin/env bash
# Build a real, bootable IsoOS live ISO on top of Ubuntu 24.04 (noble).
# Output: out/isoos-<version>-amd64.iso  (hybrid BIOS + UEFI, casper live).

set -euo pipefail

# ------------------------------------------------------------------ config
OS_NAME="IsoOS"
OS_ID="isoos"
OS_VERSION="0.1.0"
OS_CODENAME="genesis"
BASE_SUITE="noble"
BASE_MIRROR="${BASE_MIRROR:-http://archive.ubuntu.com/ubuntu/}"
ARCH="amd64"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${WORK_DIR:-$ROOT_DIR/work}"
CHROOT_DIR="$WORK_DIR/chroot"
IMAGE_DIR="$WORK_DIR/image"
OUT_DIR="$ROOT_DIR/out"
ISO_NAME="${OS_ID}-${OS_VERSION}-${ARCH}.iso"

log()  { printf '\033[1;36m[build]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "must run as root (sudo $0)"

# ------------------------------------------------------------------ checks
for bin in debootstrap mksquashfs xorriso grub-mkstandalone mformat; do
  command -v "$bin" >/dev/null || die "missing tool: $bin"
done

mkdir -p "$WORK_DIR" "$IMAGE_DIR" "$OUT_DIR"

# ------------------------------------------------------------------ stage 1: debootstrap minimal Ubuntu
if [[ ! -f "$CHROOT_DIR/.bootstrapped" ]]; then
  log "debootstrapping Ubuntu $BASE_SUITE into $CHROOT_DIR"
  rm -rf "$CHROOT_DIR"
  mkdir -p "$CHROOT_DIR"
  debootstrap --arch="$ARCH" --variant=minbase \
      --components=main,universe \
      --include=ca-certificates,gnupg \
      "$BASE_SUITE" "$CHROOT_DIR" "$BASE_MIRROR"
  touch "$CHROOT_DIR/.bootstrapped"
else
  log "reusing existing chroot ($CHROOT_DIR)"
fi

# ------------------------------------------------------------------ stage 2: configure chroot
log "configuring chroot"

# Sources
cat >"$CHROOT_DIR/etc/apt/sources.list" <<EOF
deb $BASE_MIRROR $BASE_SUITE main restricted universe multiverse
deb $BASE_MIRROR $BASE_SUITE-updates main restricted universe multiverse
deb $BASE_MIRROR $BASE_SUITE-security main restricted universe multiverse
EOF

# Branding files
install -D -m 0644 "$ROOT_DIR/branding/os-release"   "$CHROOT_DIR/etc/os-release"
install -D -m 0644 "$ROOT_DIR/branding/lsb-release"  "$CHROOT_DIR/etc/lsb-release"
install -D -m 0644 "$ROOT_DIR/branding/issue"        "$CHROOT_DIR/etc/issue"
install -D -m 0644 "$ROOT_DIR/branding/issue.net"    "$CHROOT_DIR/etc/issue.net"
install -D -m 0644 "$ROOT_DIR/branding/motd"         "$CHROOT_DIR/etc/motd"
install -D -m 0755 "$ROOT_DIR/branding/isoos-welcome" "$CHROOT_DIR/usr/local/bin/isoos-welcome"
echo "$OS_ID" >"$CHROOT_DIR/etc/hostname"

# Chroot setup script
install -m 0755 "$ROOT_DIR/chroot-setup.sh" "$CHROOT_DIR/root/chroot-setup.sh"

# Bind mounts
mount --bind /dev     "$CHROOT_DIR/dev"
mount --bind /dev/pts "$CHROOT_DIR/dev/pts"
mount -t proc  proc   "$CHROOT_DIR/proc"
mount -t sysfs sysfs  "$CHROOT_DIR/sys"
trap '
  umount -lf "$CHROOT_DIR/sys"     2>/dev/null || true
  umount -lf "$CHROOT_DIR/proc"    2>/dev/null || true
  umount -lf "$CHROOT_DIR/dev/pts" 2>/dev/null || true
  umount -lf "$CHROOT_DIR/dev"     2>/dev/null || true
' EXIT

DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 \
  chroot "$CHROOT_DIR" /root/chroot-setup.sh

# Clean up
rm -f "$CHROOT_DIR/root/chroot-setup.sh"

# Capture kernel + initrd before squashing
KVER="$(basename "$(ls -1 "$CHROOT_DIR"/boot/vmlinuz-* | sort -V | tail -1)" | sed 's/vmlinuz-//')"
log "kernel found: $KVER"

mkdir -p "$IMAGE_DIR/casper" "$IMAGE_DIR/boot/grub" "$IMAGE_DIR/isolinux" "$IMAGE_DIR/EFI/boot"
cp "$CHROOT_DIR/boot/vmlinuz-$KVER" "$IMAGE_DIR/casper/vmlinuz"
cp "$CHROOT_DIR/boot/initrd.img-$KVER" "$IMAGE_DIR/casper/initrd"

# Unmount before squashing
umount -lf "$CHROOT_DIR/sys"     || true
umount -lf "$CHROOT_DIR/proc"    || true
umount -lf "$CHROOT_DIR/dev/pts" || true
umount -lf "$CHROOT_DIR/dev"     || true
trap - EXIT

# ------------------------------------------------------------------ stage 3: squashfs root
log "creating squashfs (this takes a few minutes)"
rm -f "$IMAGE_DIR/casper/filesystem.squashfs"
mksquashfs "$CHROOT_DIR" "$IMAGE_DIR/casper/filesystem.squashfs" \
    -noappend -comp xz -e boot \
    -wildcards -e 'var/cache/apt/archives/*.deb' 'var/lib/apt/lists/*' \
                'tmp/*' 'root/.bash_history' '.bootstrapped'

# Manifests required by casper
chroot "$CHROOT_DIR" dpkg-query -W --showformat='${Package} ${Version}\n' \
    >"$IMAGE_DIR/casper/filesystem.manifest"
cp "$IMAGE_DIR/casper/filesystem.manifest" "$IMAGE_DIR/casper/filesystem.manifest-desktop"
printf '%s\n' \
  ubiquity ubiquity-frontend-gtk casper lupin-casper \
  >"$IMAGE_DIR/casper/filesystem.manifest-remove"
printf '%s' "$(du -sx --block-size=1 "$CHROOT_DIR" | cut -f1)" \
  >"$IMAGE_DIR/casper/filesystem.size"

# ------------------------------------------------------------------ stage 4: bootloaders
log "installing bootloader files"

# ISOLINUX (BIOS)
cp /usr/lib/ISOLINUX/isolinux.bin            "$IMAGE_DIR/isolinux/"
cp /usr/lib/syslinux/modules/bios/ldlinux.c32 "$IMAGE_DIR/isolinux/"
cp /usr/lib/syslinux/modules/bios/libcom32.c32 "$IMAGE_DIR/isolinux/"
cp /usr/lib/syslinux/modules/bios/libutil.c32  "$IMAGE_DIR/isolinux/"
cp /usr/lib/syslinux/modules/bios/menu.c32     "$IMAGE_DIR/isolinux/"
cp /usr/lib/syslinux/modules/bios/vesamenu.c32 "$IMAGE_DIR/isolinux/" 2>/dev/null || true

sed "s/@OS_NAME@/$OS_NAME/g; s/@OS_VERSION@/$OS_VERSION/g" \
    "$ROOT_DIR/boot/isolinux.cfg" >"$IMAGE_DIR/isolinux/isolinux.cfg"

# GRUB (UEFI + BIOS shared config)
sed "s/@OS_NAME@/$OS_NAME/g; s/@OS_VERSION@/$OS_VERSION/g" \
    "$ROOT_DIR/boot/grub.cfg" >"$IMAGE_DIR/boot/grub/grub.cfg"

# EFI bootloader - standalone GRUB image embedding our grub.cfg
cat >"$WORK_DIR/grub-embed.cfg" <<'EOF'
search --no-floppy --set=root --label ISOOS_LIVE
set prefix=($root)/boot/grub
configfile $prefix/grub.cfg
EOF

grub-mkstandalone \
    --format=x86_64-efi \
    --output="$IMAGE_DIR/EFI/boot/bootx64.efi" \
    --locales="" --fonts="" \
    "boot/grub/grub.cfg=$WORK_DIR/grub-embed.cfg"

# efiboot.img FAT image for El Torito UEFI entry
EFIBOOT="$WORK_DIR/efiboot.img"
dd if=/dev/zero of="$EFIBOOT" bs=1M count=10 status=none
mkfs.vfat -n ISOOS_EFI "$EFIBOOT" >/dev/null
mmd -i "$EFIBOOT" ::/EFI ::/EFI/boot
mcopy -i "$EFIBOOT" "$IMAGE_DIR/EFI/boot/bootx64.efi" ::/EFI/boot/bootx64.efi
mkdir -p "$IMAGE_DIR/boot/grub"
cp "$EFIBOOT" "$IMAGE_DIR/boot/grub/efi.img"

# ------------------------------------------------------------------ stage 5: assemble ISO
log "assembling ISO -> $OUT_DIR/$ISO_NAME"
mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR/$ISO_NAME"

xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "ISOOS_LIVE" \
    -appid "$OS_NAME $OS_VERSION ($OS_CODENAME)" \
    -publisher "$OS_NAME project" \
    -preparer "built with xorriso on $(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    -eltorito-boot isolinux/isolinux.bin \
      -eltorito-catalog isolinux/boot.cat \
      -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot \
      -e boot/grub/efi.img -no-emul-boot \
      -isohybrid-gpt-basdat \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -output "$OUT_DIR/$ISO_NAME" \
    "$IMAGE_DIR"

log "done: $OUT_DIR/$ISO_NAME"
ls -lh "$OUT_DIR/$ISO_NAME"
file "$OUT_DIR/$ISO_NAME" || true
