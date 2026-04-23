#!/bin/bash
set -euo pipefail

# ── CA data image ────────────────────────────────────────────────────────────
# Preserved across builds to avoid wiping CA data.
CA_DATA_IMG=/workspace/cadata.img
CA_DATA_SIZE=512M

if [[ -f "$CA_DATA_IMG" ]]; then
  echo "CA data image already exists, skipping creation."
else
  echo "==> Creating CA data image ($CA_DATA_SIZE) ..."
  truncate -s "$CA_DATA_SIZE" "$CA_DATA_IMG"
  mkfs.f2fs -l CA-DATA "$CA_DATA_IMG"

  echo "==> Initialising directory structure ..."
  MNTDIR=$(mktemp -d)
  LOOP=$(losetup --find --show "$CA_DATA_IMG")
  mount "$LOOP" "$MNTDIR"
  mkdir -p \
    "$MNTDIR/ca/private" \
    "$MNTDIR/ca/certs" \
    "$MNTDIR/ca/newcerts" \
    "$MNTDIR/ca/crl" \
    "$MNTDIR/ca/csr" \
    "$MNTDIR/audit"
  chmod 700 "$MNTDIR/ca/private"
  umount "$MNTDIR"
  losetup -d "$LOOP"
  rmdir "$MNTDIR"

  echo "==> CA data image ready."
fi

# ── Test USB image ────────────────────────────────────────────────────────────
# Small FAT32 image used by test-image.sh to exercise USB automount.
# Preserved across builds so test files added to it are not wiped.
TEST_USB_IMG=/workspace/test-usb.img
TEST_USB_SIZE=16M

if [[ -f "$TEST_USB_IMG" ]]; then
  echo "Test USB image already exists, skipping creation."
else
  echo "==> Creating test USB image ($TEST_USB_SIZE) ..."
  truncate -s "$TEST_USB_SIZE" "$TEST_USB_IMG"

  # Write an MBR partition table with one FAT32 partition (type b) spanning the
  # whole disk. A partition is required because the udev automount rule matches
  # DEVTYPE=partition — a whole-disk format would be invisible to it.
  echo ",,b;" | sfdisk "$TEST_USB_IMG"

  # Attach only the first partition via --offset rather than --partscan.
  # --partscan relies on partition device nodes (loopNp1) that are not reliably
  # available inside Docker containers.
  START=$(sfdisk --dump "$TEST_USB_IMG" | grep -oP 'start=\s*\K[0-9]+')
  LOOP=$(losetup --find --show --offset $((START * 512)) "$TEST_USB_IMG")
  mkfs.vfat -n TEST-USB "$LOOP"
  losetup -d "$LOOP"
  echo "==> Test USB image ready."
fi
