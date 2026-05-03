#!/bin/bash
set -euo pipefail

mkdir -p build

# ── Build live image ──────────────────────────────────────────────────────────
lb clean

lb config \
  --distribution bookworm \
  --architectures amd64 \
  --binary-images iso-hybrid \
  --debian-installer none \
  --bootloaders "grub-efi,syslinux" \
  --bootappend-live "boot=live components quiet" \
  --mirror-bootstrap "http://ftp.se.debian.org/debian/" \
  --mirror-binary "http://ftp.se.debian.org/debian/"

lb build

# ── CA data partition image ───────────────────────────────────────────────────
# Empty raw image written as partition 2 of the combined USB image.
# The operator formats it with LUKS2 at first use via the CA menu.
CA_DATA_IMG=build/cadata.img
CA_DATA_SIZE=512M

echo "==> Creating CA data partition image ($CA_DATA_SIZE) ..."
rm -f "$CA_DATA_IMG"
truncate -s "$CA_DATA_SIZE" "$CA_DATA_IMG"

# ── Combined USB disk image ───────────────────────────────────────────────────
# Concatenate ISO and CA data. The ISO is always sector-aligned so the CA data
# lands at exactly ISO_SECTORS. sfdisk writes only the partition table (bytes
# 446-511), preserving the isohybrid BIOS boot code at bytes 0-445.
ISO=live-image-amd64.hybrid.iso
COMBINED_IMG=build/live-image-amd64.hybrid.img

echo "==> Creating combined USB disk image ..."
cat "$ISO" "$CA_DATA_IMG" > "$COMBINED_IMG"

ISO_SECTORS=$(( $(stat -c %s "$ISO") / 512 ))
CADATA_SECTORS=$(( $(stat -c %s "$CA_DATA_IMG") / 512 ))

sfdisk --no-reread --force --wipe=never "$COMBINED_IMG" << EOF
label: dos
unit: sectors
1: start=64, size=$(( ISO_SECTORS - 64 )), type=83
2: start=${ISO_SECTORS}, size=${CADATA_SECTORS}, type=83
EOF

echo "==> Combined disk image ready: $(du -h "$COMBINED_IMG" | cut -f1)"

[[ -n "${HOST_UID:-}" ]] && chown -R "$HOST_UID:${HOST_GID:-$HOST_UID}" build/

echo "==> Build complete."
