FROM ubuntu:24.04

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        debootstrap \
        squashfs-tools \
        xorriso \
        isolinux \
        syslinux-common \
        grub-pc-bin \
        grub-efi-amd64-bin \
        grub2-common \
        mtools \
        dosfstools \
        ca-certificates \
        file \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /iso
ENTRYPOINT ["/iso/build.sh"]
