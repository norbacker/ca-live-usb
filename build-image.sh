#!/bin/bash
set -euo pipefail

# ── Sync config ───────────────────────────────────────────────────────────────
rm -rf /workspace/config
cp -r /build-config /workspace/config

# ── Generate LUKS keyfile and UUID ────────────────────────────────────────────
# A fresh key is generated every build. It is baked into the ISO and used to
# format the CA data partition, then shredded from the workspace. The key lives
# only inside the read-only squashfs and in the encrypted partition it unlocks.
CADATA_KEY=/workspace/cadata.key
LUKS_UUID=$(python3 -c "import uuid; print(uuid.uuid4())")

echo "==> Generating LUKS keyfile ..."
dd if=/dev/urandom bs=64 count=1 of="$CADATA_KEY" status=none
chmod 600 "$CADATA_KEY"

install -D -m 400 "$CADATA_KEY" \
  /workspace/config/includes.chroot/etc/luks/cadata.key

cat > /workspace/config/includes.chroot/etc/crypttab <<CRYPTTAB
cadata  UUID=$LUKS_UUID  /etc/luks/cadata.key  luks,nofail,x-systemd.device-timeout=10
CRYPTTAB

# ── Build live image ──────────────────────────────────────────────────────────
cd /workspace

lb clean

lb config \
  --distribution bookworm \
  --architectures amd64 \
  --binary-images iso-hybrid \
  --debian-installer none \
  --bootloaders "grub-efi" \
  --mirror-bootstrap "http://ftp.se.debian.org/debian/" \
  --mirror-binary "http://ftp.se.debian.org/debian/"

lb build

# ── LUKS CA data image ────────────────────────────────────────────────────────
CA_DATA_IMG=/workspace/cadata.img
CA_DATA_SIZE=512M

echo "==> Creating LUKS CA data image ($CA_DATA_SIZE) ..."
rm -f "$CA_DATA_IMG"
truncate -s "$CA_DATA_SIZE" "$CA_DATA_IMG"

cryptsetup luksFormat \
  --type luks2 \
  --uuid "$LUKS_UUID" \
  --batch-mode \
  --key-file "$CADATA_KEY" \
  "$CA_DATA_IMG"

echo "==> Initialising directory structure ..."
MNTDIR=$(mktemp -d)
cryptsetup open --key-file "$CADATA_KEY" "$CA_DATA_IMG" cadata-build
mkfs.ext4 -L CA-DATA /dev/mapper/cadata-build
mount /dev/mapper/cadata-build "$MNTDIR"
mkdir -p \
  "$MNTDIR/ca/private" \
  "$MNTDIR/ca/certs" \
  "$MNTDIR/ca/newcerts" \
  "$MNTDIR/ca/crl" \
  "$MNTDIR/ca/csr" \
  "$MNTDIR/audit"
chmod 700 "$MNTDIR/ca/private"
umount "$MNTDIR"
cryptsetup close cadata-build
rmdir "$MNTDIR"

echo "==> LUKS CA data image ready."

# ── Remove keyfile ────────────────────────────────────────────────────────────
echo "==> Removing LUKS keyfile from workspace ..."
shred -u "$CADATA_KEY"

# ── Combined USB disk image ───────────────────────────────────────────────────
# Append the CA data image to the ISO as a second MBR partition, producing a
# single file that can be dd'd to USB or booted in QEMU (-cdrom for El Torito
# boot, virtio disk for partition 2 / CA data access).
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
