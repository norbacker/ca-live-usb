# ca-live-usb

Project for a air-gapped, bootable USB live image for CA key pairs.
Based on Debian [live-build](https://salsa.debian.org/live-team/live-build).

## Requirements

- `docker` if `lb` and requirements are not installed on the local host
- `qemu-system-x86_64` for testing

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
and runs the build. The resulting ISO is written to `build/`.

## Customization

To customise the image, edit files under `config/` before building:

- `config/package-lists/` — extra packages to install (one per line, `*.list.chroot`)
- `config/includes.chroot/` — files copied verbatim into the live system (e.g. `opt/ca/` → `/opt/ca/`)
- `config/hooks/` — scripts run during the build (`*.hook.chroot`)

## Test

```
./test-image.sh
```

Boots `build/live-image-amd64.hybrid.iso` in QEMU with KVM.
