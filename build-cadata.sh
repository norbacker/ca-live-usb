#!/bin/bash
set -euo pipefail

# Create the CA data image if it does not already exist in the work volume.
# Preserving an existing image avoids wiping CA data across incremental builds.
CA_DATA_IMG=/workspace/cadata.img
CA_DATA_SIZE=512M

if [[ -f "$CA_DATA_IMG" ]]; then
  echo "CA data image already exists, skipping creation."
  exit 0
fi

echo "==> Creating CA data image ($CA_DATA_SIZE) ..."
truncate -s "$CA_DATA_SIZE" "$CA_DATA_IMG"
mkfs.f2fs -l CA-DATA "$CA_DATA_IMG"

echo "==> Initialising directory structure ..."
MNTDIR=$(mktemp -d)
LOOP=$(losetup --find --show "$CA_DATA_IMG")
mount "$LOOP" "$MNTDIR"
mkdir -p \
  "$MNTDIR/ca/private" \
  "$MNTDIR/ca/certs" \
  "$MNTDIR/ca/newcerts" \
  "$MNTDIR/ca/crl" \
  "$MNTDIR/ca/csr" \
  "$MNTDIR/audit"
chmod 700 "$MNTDIR/ca/private"
umount "$MNTDIR"
losetup -d "$LOOP"
rmdir "$MNTDIR"

echo "==> CA data image ready."
