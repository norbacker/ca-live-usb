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
    f2fs-tools \
    curl \
    git \
    ca-certificates \
    && apt-get clean

# Optional: nicer debugging tools
RUN apt-get install -y \
    vim less tree

WORKDIR /workspace

COPY build-image.sh /usr/local/bin/build-image.sh
COPY build-cadata.sh /usr/local/bin/build-cadata.sh
COPY config /build-config

CMD ["bash", "-c", "build-image.sh && build-cadata.sh"]