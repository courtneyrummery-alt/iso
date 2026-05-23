#!/usr/bin/env bash
# Runs INSIDE the chroot during ISO build. Installs kernel + live tooling,
# applies branding, sets up the live user.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8

echo "[chroot] mountpoints"
mount -t proc proc /proc 2>/dev/null || true

echo "[chroot] apt update"
apt-get update

echo "[chroot] installing base system"
apt-get install -y --no-install-recommends \
    ubuntu-standard \
    linux-image-generic \
    linux-firmware \
    casper \
    initramfs-tools \
    systemd-sysv \
    netplan.io \
    network-manager \
    sudo less nano vim-tiny \
    bash-completion \
    locales tzdata \
    iproute2 iputils-ping \
    openssh-client \
    curl wget ca-certificates \
    cron rsyslog \
    util-linux \
    fdisk parted \
    htop tmux

echo "[chroot] locale + timezone"
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8
ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime
echo "Etc/UTC" >/etc/timezone

echo "[chroot] live user"
# casper creates the live user automatically, but we add an isoos account
# as the default sudo user with passwordless login on tty.
useradd -m -s /bin/bash -G sudo,adm,audio,video,plugdev isoos || true
echo "isoos:isoos" | chpasswd
echo "isoos ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/90-isoos
chmod 0440 /etc/sudoers.d/90-isoos
# default root password (live image only)
echo "root:isoos" | chpasswd

echo "[chroot] welcome on login"
cat >/etc/profile.d/99-isoos-welcome.sh <<'EOS'
if [ -t 1 ] && [ -x /usr/local/bin/isoos-welcome ] && [ -z "${ISOOS_WELCOMED:-}" ]; then
  export ISOOS_WELCOMED=1
  /usr/local/bin/isoos-welcome
fi
EOS
chmod 0755 /etc/profile.d/99-isoos-welcome.sh

echo "[chroot] networking (NetworkManager for live env)"
cat >/etc/netplan/01-network-manager-all.yaml <<'EOY'
network:
  version: 2
  renderer: NetworkManager
EOY
chmod 0600 /etc/netplan/01-network-manager-all.yaml

echo "[chroot] rebuilding initramfs with casper"
update-initramfs -u -k all

echo "[chroot] cleaning apt caches"
apt-get -y autoremove --purge
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Truncate machine-id so it regenerates on first live boot
: >/etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

echo "[chroot] done"
