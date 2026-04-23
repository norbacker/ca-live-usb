This project creates a bootable USB live image containing tools for generating a CA keypair and to sign intermediate certificates. The image will run air-gapped on a AMD64 host computer - without access to the host's storage or network devices. A small writable mount with the CA keypair and audit logs etc is hosted on the USB. The rest of the filesystem is read-only (with just a writable overlay).

The USB image is built with Debian live-build in a reproducible way. The image build environment is hosted in a Docker container (see @Dockerfile).



This project uses git. Exclude the `.git` folder when searching the file system.

Use `docker` commands when necessary.