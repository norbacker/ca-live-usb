#!/bin/bash
set -euo pipefail

mkdir -p build
TEST_USB_IMG=build/test-usb.img
TEST_USB_SIZE=16M

echo "==> Creating test USB image ($TEST_USB_SIZE) ..."
truncate -s "$TEST_USB_SIZE" "$TEST_USB_IMG"

# Write an MBR partition table with one FAT32 partition (type b) spanning the
# whole disk. A partition is required because the udev automount rule matches
# DEVTYPE=partition — a whole-disk format would be invisible to it.
echo ",,b;" | sfdisk "$TEST_USB_IMG"

START=$(sfdisk --dump "$TEST_USB_IMG" | grep -oP 'start=\s*\K[0-9]+')
mformat -i "$TEST_USB_IMG@@$((START * 512))" -v TEST-USB ::
mmd -i "$TEST_USB_IMG@@$((START * 512))" ::requests ::certs

[[ -n "${HOST_UID:-}" ]] && chown "$HOST_UID:${HOST_GID:-$HOST_UID}" "$TEST_USB_IMG"

echo "==> Test USB image ready."
