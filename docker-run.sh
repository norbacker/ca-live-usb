#!/bin/bash
set -euo pipefail

IMAGE=live-build
VOLUME=live-build-work
PLATFORM=linux/amd64

cmd_build() {
  docker build -t "$IMAGE" .
}

cmd_run() {
  local entrypoint=${1:-}
  cmd_build
  docker volume create "$VOLUME"
  docker run --rm -it \
    --platform $PLATFORM \
    --privileged \
    -v "$VOLUME":/workspace \
    ${entrypoint:+--entrypoint "$entrypoint"} \
    "$IMAGE"
}

cmd_install() {
  cmd_run
  mkdir -p build
  local cid
  cid=$(docker create --platform $PLATFORM -v "$VOLUME":/workspace "$IMAGE")
  docker cp "$cid":/workspace/live-image-amd64.hybrid.iso build/
  docker cp "$cid":/workspace/cadata.img build/
  docker rm "$cid"
}

cmd_prune() {
  docker volume rm -f "$VOLUME"
}

cmd_clean() {
  docker ps -a --filter "ancestor=$IMAGE" -q | xargs -r docker rm -f
  docker image rm -f "$IMAGE"
  cmd_prune
  rm build/live-image-amd64.hybrid.iso
  rm build/cadata.img
}

cmd_help() {
  cat <<EOF
Usage: $0 <target>

Targets:
  install      Build, run, and copy the ISO to build/ (default)
  build        Build the Docker image
  run          Build the image and run the live-build container
  interactive  Like run, but drops into the container with /bin/bash
  prune        Remove the persistent work volume
  clean        Remove related containers, the image, and prune the volume
  help         Print this help message
EOF
}

TARGET=${1:-install}

case "$TARGET" in
  install)     cmd_install ;;
  build)       cmd_build ;;
  run)         cmd_run ;;
  interactive) cmd_run /bin/bash ;;
  prune)       cmd_prune ;;
  clean)       cmd_clean ;;
  help)        cmd_help ;;
  *)
    echo "Unknown target: $TARGET" >&2
    cmd_help
    exit 1
    ;;
esac
