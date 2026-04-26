#!/bin/bash
set -euo pipefail

# ── Sync config ───────────────────────────────────────────────────────────────
rm -rf /workspace/config
cp -r /build-config /workspace/config

# ── Generate LUKS UUID ────────────────────────────────────────────────────────
# A fresh UUID is generated every build and stored in the live image. The
# ca-menu init function reads this UUID and passes it to luksFormat so that
# subsequent boots can find the partition by UUID when opening it.
LUKS_UUID=$(python3 -c "import uuid; print(uuid.uuid4())")

echo "==> Generating LUKS UUID ..."

install -D -m 444 /dev/stdin \
  /workspace/config/includes.chroot/etc/cadata-uuid <<< "$LUKS_UUID"

# ── Build live image ──────────────────────────────────────────────────────────
cd /workspace

lb clean

lb config \
  --distribution bookworm \
  --architectures amd64 \
  --binary-images iso-hybrid \
  --debian-installer none \
  --bootloaders "grub-efi" \
  --bootappend-live "boot=live components quiet" \
  --mirror-bootstrap "http://ftp.se.debian.org/debian/" \
  --mirror-binary "http://ftp.se.debian.org/debian/"

lb build

# ── CA data partition image ───────────────────────────────────────────────────
# Empty raw image written as partition 2 of the combined USB image.
# The operator formats it with LUKS2 at first use via the CA menu.
CA_DATA_IMG=/workspace/cadata.img
CA_DATA_SIZE=512M

echo "==> Creating CA data partition image ($CA_DATA_SIZE) ..."
rm -f "$CA_DATA_IMG"
truncate -s "$CA_DATA_SIZE" "$CA_DATA_IMG"

# ── Combined USB disk image ───────────────────────────────────────────────────
# Append the CA data image to the ISO as a second MBR partition, producing a
# single file that can be dd'd to USB. The live system boots from partition 1
# (El Torito / ISO 9660); partition 2 is formatted with LUKS2 at first use.
ISO=/workspace/live-image-amd64.hybrid.iso
COMBINED_IMG=/workspace/live-image-amd64.hybrid.img

echo "==> Creating combined USB disk image ..."
cp "$ISO" "$COMBINED_IMG"

ISO_BYTES=$(stat -c %s "$ISO")
CADATA_BYTES=$(stat -c %s "$CA_DATA_IMG")

# Align partition 2 start to 1 MiB (in 512-byte sectors)
ISO_SECTORS=$(( (ISO_BYTES + 511) / 512 ))
PART2_START=$(( ((ISO_SECTORS + 2047) / 2048) * 2048 ))
PART2_SECTORS=$(( (CADATA_BYTES + 511) / 512 ))

truncate -s $(( PART2_START * 512 + CADATA_BYTES )) "$COMBINED_IMG"
dd if="$CA_DATA_IMG" of="$COMBINED_IMG" bs=512 seek="$PART2_START" conv=notrunc status=none

# Write MBR partition table into the ISO 9660 system area (bytes 0-511 are
# guaranteed zero in any live-build hybrid ISO — ISO 9660 starts at sector 16).
python3 - <<EOF
import struct

def mbr_entry(ptype, start, size):
    e = bytearray(16)
    e[0] = 0x00
    e[1:4] = b'\xff\xff\xff'   # CHS: LBA mode
    e[4] = ptype
    e[5:8] = b'\xff\xff\xff'   # CHS: LBA mode
    struct.pack_into('<I', e, 8, start)
    struct.pack_into('<I', e, 12, size)
    return bytes(e)

with open('$COMBINED_IMG', 'r+b') as f:
    mbr = bytearray(f.read(512))
    mbr[446:462] = mbr_entry(0x83, 0,             $PART2_START)
    mbr[462:478] = mbr_entry(0x83, $PART2_START,  $PART2_SECTORS)
    mbr[478:494] = bytes(16)
    mbr[494:510] = bytes(16)
    mbr[510] = 0x55
    mbr[511] = 0xAA
    f.seek(0)
    f.write(mbr)
EOF

echo "==> Combined disk image ready: $(du -h "$COMBINED_IMG" | cut -f1)"

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

echo "==> Build complete."
