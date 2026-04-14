#!/bin/bash
set -euo pipefail

ISO=build/live-image-amd64.hybrid.iso
CA_DATA_IMG=build/cadata.img
CA_DATA_SIZE=512M

[[ -f "$ISO" ]] || { echo "ISO not found: $ISO  (run ./docker-run.sh install first)"; exit 1; }

# Create and format the CA data disk image if it does not exist yet.
# mkfs.ext4 can format a plain file without root access or loop devices.
if [[ ! -f "$CA_DATA_IMG" ]]; then
  echo "Creating $CA_DATA_IMG ($CA_DATA_SIZE) ..."
  truncate -s "$CA_DATA_SIZE" "$CA_DATA_IMG"
  mkfs.ext4 -L CA-DATA "$CA_DATA_IMG"
  echo "Note: directory structure will be initialised on first boot."
fi

qemu-system-x86_64 \
  -m 2048 \
  -cdrom "$ISO" \
  -boot d \
  -drive "file=$CA_DATA_IMG,format=raw,if=virtio,media=disk" \
  -enable-kvm \
  -cpu host \
  -smp 2 \
  -vga virtio \
  -display gtk \
  -bios /usr/share/ovmf/x64/OVMF.4m.fd
