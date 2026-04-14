#!/bin/bash
# prepare-usb.sh <iso> <device>
#
# Writes the live image to a USB drive and writes the pre-built
# CA data image (cadata.img) to a new partition in the remaining space.
#
# Requires: dd, parted, sgdisk (gdisk), partprobe

set -euo pipefail

ISO=${1:-}
DEV=${2:-}
CA_DATA_IMG=$(dirname "${ISO:-x}")/cadata.img

usage() {
  echo "Usage: $0 <iso> <device>"
  echo "  e.g. $0 build/live-image-amd64.hybrid.iso /dev/sdb"
  exit 1
}

[[ -f "$ISO" ]] || { echo "ISO not found: $ISO"; usage; }
[[ -f "$CA_DATA_IMG" ]] || { echo "CA data image not found: $CA_DATA_IMG"; usage; }
[[ -b "$DEV" ]] || { echo "Not a block device: $DEV"; usage; }

echo "Target device: $DEV"
lsblk "$DEV"
echo
read -rp "This will DESTROY all data on $DEV. Type 'yes' to continue: " confirm
[[ "$confirm" == "yes" ]] || { echo "Aborted."; exit 1; }

echo
echo "==> Writing ISO to $DEV ..."
dd if="$ISO" of="$DEV" bs=4M status=progress conv=fsync
sync

echo
echo "==> Relocating GPT backup header to end of disk ..."
# After dd, the GPT backup header sits at the end of the ISO, not the disk.
# sgdisk -e moves it to the actual end so we can add partitions freely.
sgdisk -e "$DEV"

echo
echo "==> Creating CA data partition in remaining space ..."
# Find the last sector used by existing partitions
LAST_END=$(parted -s "$DEV" unit s print \
  | awk '/^ [0-9]/{last=$3} END{print last}' \
  | tr -d 's')
parted -s "$DEV" mkpart primary linux-data $((LAST_END + 1))s 100%

# Re-read partition table
partprobe "$DEV"
sleep 1

# Determine new partition device node
# /dev/sdb  -> /dev/sdb3   /dev/nvme0n1 -> /dev/nvme0n1p3
if [[ "$DEV" =~ [0-9]$ ]]; then
  PART="${DEV}p$(partx --noheadings "$DEV" | wc -l)"
else
  PART="${DEV}$(partx --noheadings "$DEV" | wc -l)"
fi

echo
echo "==> Writing CA data image to $PART ..."
dd if="$CA_DATA_IMG" of="$PART" bs=4M status=progress conv=fsync

echo
echo "Done. USB is ready: $DEV"
