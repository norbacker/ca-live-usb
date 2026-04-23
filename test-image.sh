#!/bin/bash
set -euo pipefail

ISO=build/live-image-amd64.hybrid.iso
CA_DATA_IMG=build/cadata.img

[[ -f "$ISO" ]] || { echo "ISO not found: $ISO  (run ./docker-run.sh install first)"; exit 1; }
[[ -f "$CA_DATA_IMG" ]] || { echo "CA data image not found: $CA_DATA_IMG  (run ./docker-run.sh install first)"; exit 1; }

if [[ -r /dev/kvm ]]; then
  kvm_flags=(-enable-kvm -cpu host)
else
  kvm_flags=(-cpu Nehalem)
fi

qemu-system-x86_64 \
  -m 2048 \
  -cdrom "$ISO" \
  -boot d \
  -drive "file=$CA_DATA_IMG,format=raw,if=virtio,media=disk" \
  "${kvm_flags[@]}" \
  -smp 2 \
  -vga virtio \
  -display gtk \
  -bios /usr/share/ovmf/x64/OVMF.4m.fd
