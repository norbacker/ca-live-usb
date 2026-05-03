SHELL := /bin/bash

IMAGE    := live-build
VOLUME   := live-build-cache
PLATFORM := linux/amd64
LIVE_IMG          := build/live-image-amd64.hybrid.img
TEST_USB_IMG      := build/test-usb.img
TEST_USB_MOUNT    := mnt/test-usb

DOCKER_IMAGE_STAMP := .docker-image
DOCKER_SRCS        := Dockerfile build-image.sh build-test-usb-image.sh $(shell find config -type f)

# Volume at /workspace/cache: lb stores downloaded packages there by default,
# so they survive across runs without covering the rest of /workspace.
# Bind-mount build/ so output lands on the host directly (no docker cp needed).
RUN_FLAGS = \
  --platform $(PLATFORM) \
  --privileged \
  -v $(VOLUME):/workspace/cache \
  -v $(CURDIR)/build:/workspace/build \
  -e HOST_UID=$$(id -u) \
  -e HOST_GID=$$(id -g)

KVM_FLAGS   := $(if $(wildcard /dev/kvm),-enable-kvm -cpu host,-cpu Nehalem)
DISPLAY_ARG := $(if $(filter Darwin,$(shell uname -s)),cocoa,gtk)


.PHONY: all install test mount-usb umount-usb interactive clean distclean help

all: $(LIVE_IMG)

install: $(LIVE_IMG)
	@[ -n "$(DEV)" ] || { echo "Usage: make install DEV=/dev/sdX"; exit 1; }
	@[ -b "$(DEV)" ] || { echo "Not a block device: $(DEV)"; exit 1; }
	@echo "Target device: $(DEV)"
	@lsblk "$(DEV)"
	@echo
	@read -rp "This will DESTROY all data on $(DEV). Type 'yes' to continue: " confirm; \
	[ "$$confirm" = "yes" ] || { echo "Aborted."; exit 1; }
	@echo
	@echo "==> Writing image to $(DEV) ..."
	dd if=$(LIVE_IMG) of=$(DEV) bs=4M status=progress conv=fsync
	sync
	@echo "Done. USB is ready: $(DEV)"

test: $(LIVE_IMG) $(TEST_USB_IMG)
	qemu-system-x86_64 \
	  -m 2048 \
	  -cdrom "$(LIVE_IMG)" \
	  -boot d \
	  -drive "file=$(LIVE_IMG),format=raw,if=virtio,media=disk,file.locking=off" \
	  -drive "if=none,id=usbstick,file=$(TEST_USB_IMG),format=raw" \
	  -device qemu-xhci \
	  -device usb-storage,drive=usbstick \
	  $(KVM_FLAGS) \
	  -smp 2 \
	  -vga virtio \
	  -display $(DISPLAY_ARG)

mount-usb: $(TEST_USB_IMG)
	@mkdir -p $(TEST_USB_MOUNT)
	if [ "$$(uname -s)" = "Darwin" ]; then \
		DISK=$$(sudo hdiutil attach -imagekey diskimage-class=CRawDiskImage -nomount $(TEST_USB_IMG) | awk '/FAT/{print $$1}'); \
		sudo mount -t msdos $$DISK $(TEST_USB_MOUNT); \
	else \
		LOOP=$$(sudo losetup --find --show --partscan $(TEST_USB_IMG)); \
		sudo mount $${LOOP}p1 $(TEST_USB_MOUNT); \
	fi
	@echo "Mounted at $(TEST_USB_MOUNT)"

umount-usb:
	if [ "$$(uname -s)" = "Darwin" ]; then \
		sudo hdiutil detach $(TEST_USB_MOUNT); \
	else \
		PART=$$(findmnt -n -o SOURCE $(TEST_USB_MOUNT)); \
		LOOP=/dev/$$(lsblk -no PKNAME $$PART); \
		sudo umount $(TEST_USB_MOUNT); \
		sudo losetup -d $$LOOP; \
	fi
	@echo "Unmounted $(TEST_USB_MOUNT)"

$(LIVE_IMG): $(DOCKER_IMAGE_STAMP)
	mkdir -p build
	docker run --rm $(RUN_FLAGS) $(IMAGE)

$(TEST_USB_IMG): $(DOCKER_IMAGE_STAMP)
	mkdir -p build
	docker run --rm $(RUN_FLAGS) --entrypoint build-test-usb-image.sh $(IMAGE)

$(DOCKER_IMAGE_STAMP): $(DOCKER_SRCS)
	docker build --platform $(PLATFORM) -t $(IMAGE) .
	touch $@

interactive: $(DOCKER_IMAGE_STAMP)
	mkdir -p build
	docker run --rm -it $(RUN_FLAGS) --entrypoint /bin/bash $(IMAGE)

clean:
	rm -rf build/

distclean: clean
	docker ps -a --filter "ancestor=$(IMAGE)" -q | xargs -r docker rm -f
	docker image rm -f $(IMAGE)
	docker volume rm -f $(VOLUME)
	rm -f $(DOCKER_IMAGE_STAMP)

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  all          Build the live image to build/ (default)"
	@echo "  install      Write the image to a USB drive (requires DEV=/dev/sdX)"
	@echo "  test         Boot the image in QEMU"
	@echo "  mount-usb    Mount the test USB image (override path: TEST_USB_MOUNT=...)"
	@echo "  umount-usb   Unmount the test USB image and detach loop device"
	@echo "  interactive  Drop into the build container with /bin/bash"
	@echo "  clean        Remove build output"
	@echo "  distclean    Remove build output, Docker image, and package cache"
	@echo "  help         Print this help message"
