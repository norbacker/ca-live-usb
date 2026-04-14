#!/bin/bash
# prepare-usb.sh <iso> <device>
#
# Writes the live image to a USB drive and creates the writable
# CA data partition (LABEL=CA-DATA) in the remaining space.
#
# Requires: dd, parted, sgdisk (gdisk), mkfs.ext4, partprobe

set -euo pipefail

ISO=${1:-}
DEV=${2:-}

usage() {
  echo "Usage: $0 <iso> <device>"
  echo "  e.g. $0 build/live-image-amd64.hybrid.iso /dev/sdb"
  exit 1
}

[[ -f "$ISO" ]] || { echo "ISO not found: $ISO"; usage; }
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
parted -s "$DEV" mkpart primary ext4 $((LAST_END + 1))s 100%

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
echo "==> Formatting $PART with label CA-DATA ..."
mkfs.ext4 -L CA-DATA "$PART"

echo
echo "==> Initialising directory structure on $PART ..."
MNTDIR=$(mktemp -d)
mount "$PART" "$MNTDIR"
mkdir -p \
  "$MNTDIR/ca/private" \
  "$MNTDIR/ca/certs" \
  "$MNTDIR/ca/newcerts" \
  "$MNTDIR/ca/crl" \
  "$MNTDIR/ca/csr" \
  "$MNTDIR/audit"
chmod 700 "$MNTDIR/ca/private"
umount "$MNTDIR"
rmdir "$MNTDIR"

echo
echo "Done. USB is ready: $DEV"
