FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    live-build \
    debootstrap \
    squashfs-tools \
    xorriso \
    isolinux \
    syslinux-utils \
    grub-pc-bin \
    grub-efi-amd64-bin \
    mtools \
    dosfstools \
    curl \
    git \
    ca-certificates \
    && apt-get clean

# Optional: nicer debugging tools
RUN apt-get install -y \
    vim less tree

WORKDIR /workspace

COPY build-image.sh /usr/local/bin/build-image.sh
COPY config /workspace/config

CMD ["build-image.sh"]