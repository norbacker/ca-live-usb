#!/bin/bash
set -euo pipefail

COMBINED_IMG=build/live-image-amd64.hybrid.img
TEST_USB_IMG=build/test-usb.img

[[ -f "$COMBINED_IMG" ]] || { echo "Disk image not found: $COMBINED_IMG  (run ./docker-run.sh install first)"; exit 1; }
[[ -f "$TEST_USB_IMG" ]] || { echo "Test USB image not found: $TEST_USB_IMG  (run ./docker-run.sh install first)"; exit 1; }

if [[ -r /dev/kvm ]]; then
  kvm_flags=(-enable-kvm -cpu host)
else
  kvm_flags=(-cpu Nehalem)
fi

# Boot via El Torito (cdrom). The same image is also attached as a virtio disk
# so the live kernel sees the MBR partition table and can reach partition 2
# (CA data). This is two separate QEMU devices rather than one, unlike real
# USB, but it correctly exercises the CA data partition workflow.
# On first boot partition 2 is empty; use "Initialize CA data partition" in
# the CA menu to format it with LUKS2, then reboot to activate persistence.
qemu-system-x86_64 \
  -m 2048 \
  -cdrom "$COMBINED_IMG" \
  -boot d \
  -drive "file=$COMBINED_IMG,format=raw,if=virtio,media=disk,file.locking=off" \
  -drive "if=none,id=usbstick,file=$TEST_USB_IMG,format=raw" \
  -device qemu-xhci \
  -device usb-storage,drive=usbstick \
  "${kvm_flags[@]}" \
  -smp 2 \
  -vga virtio \
  -display gtk \
  -bios /usr/share/ovmf/x64/OVMF.4m.fd
