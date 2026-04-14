#!/bin/bash
set -euo pipefail

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