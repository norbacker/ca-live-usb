# ca-live-usb

Project for a air-gapped, bootable USB live image for CA key pairs.
Based on Debian [live-build](https://salsa.debian.org/live-team/live-build).

## Requirements

- `make`
- `docker` if `lb` and requirements are not installed on the local host
- `qemu-system-x86_64` for testing

### macOS (Apple Silicon)

The image targets `linux/amd64`. On Apple Silicon, use
[Colima](https://github.com/abiosoft/colima) with Virtualization.framework.
A named profile keeps it separate from any existing Colima VM:

```
colima start --profile x86 --vm-type vz
colima stop --profile x86
```

Edit `~/.colima/x86/colima.yaml` and add a provision script that installs
QEMU user-mode emulation for x86_64:

```yaml
provision:
  - mode: system
    script: |
      apt-get install -y -qq qemu-user-static
      update-binfmts --enable qemu-x86_64
```

Then start the VM and switch Docker context:

```
colima start --profile x86
docker context use colima-x86
```

Switch back to your default Docker context when done:

```
docker context use colima
```

## Build

Either build directly with:
```
./build-image.sh
```

Or through Docker:
```
make
```
This builds the Docker image, creates a persistent volume for the build workspace,
and runs the build. The resulting live image and test USB image are written to `build/`.

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
make install DEV=/dev/sdX
```

Writes the image to a USB drive. Prompts for confirmation before writing.

## Test

```
make test
```

Boots `build/live-image-amd64.hybrid.img` in QEMU with KVM (if available).
The test USB image (`build/test-usb.img`) is attached as a USB mass storage device
to exercise the automount and issuer-signing workflows. It contains two directories:
`requests/` for incoming issuer signing requests and `certs/` for signed certificates
written back by the CA menu.

### Placing issuer signing requests on the test USB

To stage a signing request on the test USB before booting, mount it with:

```
make mount-usb
```

This mounts the FAT32 partition at `mnt/test-usb`. Copy a `.csr.json` request file
into `mnt/test-usb/requests/`, then unmount:

```
make umount-usb
```

An issuer signing request looks like this:

```json
{
	"publicKey": "-----BEGIN PUBLIC KEY-----\nMIHNMA0GCSqGSIb3DQEBAQUAA4G7ADCBtwKBsQC7lrW31URpa+KoJUuZs7bu+ich\nKzKBhUlJ1VTPV52j+eB/gLEgz7E4D4CiO7ZlLgKd08/MyuGHJxf+i6TrEKGOLtVJ\nCv57bLWbSohsOPKa0kd5ahJ01Gq/iX2w+cKfe5Ehy7mekGq2w0IIGoCjvdlDvDB8\n/t1nRgi3t76vLVnKkiOgcun4Ikz9nLLdBDyqQ6e8EX5aSAtu1HxfAE+Th572vQnE\ntNcLSkXaA/Tiz3txWwIBAw==\n-----END PUBLIC KEY-----",
	"applicationPan": "123456",
	"certificateSequenceNumber": 1
}
```
