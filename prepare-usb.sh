#!/bin/bash
# prepare-usb.sh <device>
#
# Writes the combined USB disk image to a USB drive. The image already contains
# both the live system (partition 1) and the CA data partition (partition 2),
# so no post-flash partition manipulation is needed.
#
# Requires: dd

set -euo pipefail

COMBINED_IMG=$(dirname "$0")/build/live-image-amd64.hybrid.img
DEV=${1:-}

usage() {
  echo "Usage: $0 <device>"
  echo "  e.g. $0 /dev/sdb"
  exit 1
}

[[ -f "$COMBINED_IMG" ]] || { echo "Disk image not found: $COMBINED_IMG  (run ./docker-run.sh install first)"; usage; }
[[ -b "$DEV" ]] || { echo "Not a block device: $DEV"; usage; }

echo "Target device: $DEV"
lsblk "$DEV"
echo
read -rp "This will DESTROY all data on $DEV. Type 'yes' to continue: " confirm
[[ "$confirm" == "yes" ]] || { echo "Aborted."; exit 1; }

echo
echo "==> Writing image to $DEV ..."
dd if="$COMBINED_IMG" of="$DEV" bs=4M status=progress conv=fsync
sync

echo
echo "Done. USB is ready: $DEV"
