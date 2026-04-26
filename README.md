# ca-live-usb

Project for a air-gapped, bootable USB live image for CA key pairs.
Based on Debian [live-build](https://salsa.debian.org/live-team/live-build).

## Requirements

- `docker` if `lb` and requirements are not installed on the local host
- `qemu-system-x86_64` and `ovmf` for testing
- `gptfdisk` for flashing the USB (`prepare-usb.sh`)

## Build

Either build direclty with:
```
./build-image.sh
```

Or through docker:
```
./docker-run.sh
```
This builds the Docker image, creates a persistent volume for the build workspace,
and runs the build. The resulting ISO, CA-DATA image, and test USB image are
written to `build/`.

## Customization

Customizations live in `config/` using the standard live-build mechanisms:
`package-lists/` for extra packages, `hooks/` for build-time scripts, and
`includes.chroot/` for files placed verbatim into the image.

### Air-gap

The image is hardened to prevent access to the host's storage and network.
Internal disk controllers (SATA, NVMe, IDE) and network adapters (Wi-Fi,
Bluetooth, common wired NICs) are blacklisted at the kernel module level.
Network-management services are disabled and a default-deny firewall blocks all
traffic.

### Writable CA-DATA partition

The root filesystem is read-only. A separate LUKS2-encrypted partition is used
as a live-boot persistence layer, bind-mounted at `/mnt/cadata`, and holds the
CA keypair, audit logs, and other persistent data.

The partition (partition 2 of the USB image) is written as empty raw space at
build time. On first boot the CA menu offers an **Initialize CA data partition**
option that formats it with LUKS2 and prompts the operator to choose a
passphrase. The passphrase is not stored anywhere — it must be entered at every
boot. live-boot detects the LUKS partition automatically and prompts for the
passphrase during early boot before the CA menu starts.

### USB automount

Inserting a USB storage device automatically mounts it at `/media/usb`. Only
one device may be mounted at a time, exotic filesystems are rejected, and all
mount and unmount events are audit logged to `/mnt/cadata/audit/usb-mount.log`.

### CA application

At boot, a CA management menu is launched automatically as root on the main
console. The menu allows the operator to create CA keypairs, export public
keys to a USB device, inspect issuer keys presented on USB, and sign them.
All activity is audit logged to `/mnt/cadata/audit/menu.log`.

The CA tooling is installed under `/opt/ca/`.

## Flash

```
./prepare-usb.sh build/live-image-amd64.hybrid.iso /dev/sdX
```

Writes the ISO and CA-DATA image to a USB drive and creates a writable partition
for the CA-DATA in the remaining space.

## Test

```
./test-image.sh
```

Boots `build/live-image-amd64.hybrid.iso` in QEMU with UEFI and KVM. The
CA-DATA image is attached as a virtio disk and the test USB image as a USB
mass storage device to exercise automount.
