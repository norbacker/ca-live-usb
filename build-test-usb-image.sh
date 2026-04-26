#!/bin/bash
set -euo pipefail

TEST_USB_IMG=/workspace/test-usb.img
TEST_USB_SIZE=16M

if [[ -f "$TEST_USB_IMG" ]]; then
    echo "Test USB image already exists, skipping creation."
    exit 0
fi

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
