SHELL := /bin/bash

IMAGE    := live-build
VOLUME   := live-build-work
PLATFORM := linux/amd64
LIVE_IMG     := build/live-image-amd64.hybrid.img
TEST_USB_IMG := build/test-usb.img

DOCKER_IMAGE_STAMP    := .docker-image
DOCKER_RUN_STAMP      := .docker-run
DOCKER_TEST_USB_STAMP := .docker-test-usb
DOCKER_SRCS           := Dockerfile build-image.sh build-test-usb-image.sh $(shell find config -type f)

RUN_FLAGS = \
  --platform $(PLATFORM) \
  --privileged \
  -v $(VOLUME):/workspace

KVM_FLAGS := $(if $(wildcard /dev/kvm),-enable-kvm -cpu host,-cpu Nehalem)

.PHONY: all install test run interactive prune clean help

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
	  -display gtk \
	  -bios /usr/share/ovmf/x64/OVMF.4m.fd

$(LIVE_IMG): $(DOCKER_RUN_STAMP)
	mkdir -p build
	cid=$$(docker create --platform $(PLATFORM) -v $(VOLUME):/workspace $(IMAGE)); \
	docker cp $$cid:/workspace/live-image-amd64.hybrid.img build/; \
	docker rm $$cid
	touch $@

$(TEST_USB_IMG): $(DOCKER_TEST_USB_STAMP)
	mkdir -p build
	cid=$$(docker create --platform $(PLATFORM) -v $(VOLUME):/workspace $(IMAGE)); \
	docker cp $$cid:/workspace/test-usb.img build/; \
	docker rm $$cid
	touch $@

$(DOCKER_RUN_STAMP): $(DOCKER_IMAGE_STAMP)
	docker run --rm $(RUN_FLAGS) $(IMAGE)
	touch $@

$(DOCKER_TEST_USB_STAMP): $(DOCKER_IMAGE_STAMP)
	docker run --rm $(RUN_FLAGS) --entrypoint build-test-usb-image.sh $(IMAGE)
	touch $@

$(DOCKER_IMAGE_STAMP): $(DOCKER_SRCS)
	docker build --platform $(PLATFORM) -t $(IMAGE) .
	touch $@

run: $(DOCKER_RUN_STAMP)

interactive: $(DOCKER_IMAGE_STAMP)
	docker run --rm -it $(RUN_FLAGS) --entrypoint /bin/bash $(IMAGE)

prune:
	docker volume rm -f $(VOLUME)

clean: prune
	docker ps -a --filter "ancestor=$(IMAGE)" -q | xargs -r docker rm -f
	docker image rm -f $(IMAGE)
	rm -f $(LIVE_IMG) $(TEST_USB_IMG) \
	  $(DOCKER_IMAGE_STAMP) $(DOCKER_RUN_STAMP) $(DOCKER_TEST_USB_STAMP)

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  all          Build and copy the live image to build/ (default)"
	@echo "  install      Write the image to a USB drive (requires DEV=/dev/sdX)"
	@echo "  test         Boot the image in QEMU"
	@echo "  run          Run the live-build container"
	@echo "  interactive  Like run, but drops into the container with /bin/bash"
	@echo "  prune        Remove the persistent work volume"
	@echo "  clean        Remove related containers, image, volume, and build artifacts"
	@echo "  help         Print this help message"
