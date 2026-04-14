#!/bin/bash
set -euo pipefail

# Sync config from Docker image into the (potentially cached) workspace volume.
# This ensures config changes take effect without requiring a full volume prune.
rm -rf /workspace/config
cp -r /build-config /workspace/config

# Clean chroot and binary stages before each build so config changes (hooks,
# includes.chroot, package lists) are always applied. The package download cache
# in cache/ is preserved, so packages are reinstalled from disk — not re-downloaded.
lb clean

lb config \
  --distribution bookworm \
  --architectures amd64 \
  --binary-images iso-hybrid \
  --debian-installer none \
  --bootloaders "grub-efi" \
  --mirror-bootstrap "http://ftp.se.debian.org/debian/" \
  --mirror-binary "http://ftp.se.debian.org/debian/" #\
#  --apt-recommends false

lb build