#!/usr/bin/env bash
set -euo pipefail

# Simple script to build all Dockerfile* images and run them sequentially.
# Usage: ./build_and_run_all.sh
# Optionally set DOCKER command: DOCKER=podman ./build_and_run_all.sh

DOCKER=${DOCKER:-docker}
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

FILES=(
  Dockerfile.01.mavenimage
  Dockerfile.02.mavenimagestage
  Dockerfile.03.dockercache
  Dockerfile.05.manual
  Dockerfile.06.jlink
  Dockerfile.06b.jlink-alpine
  Dockerfile.07.graalVM
)

TAGS=(
  javahello:01
  javahello:02
  javahello:03
  javahello:05
  javahello:06
  javahello:06b
  javahello:07
)

echo "Using docker command: $DOCKER"

for i in "${!FILES[@]}"; do
  file=${FILES[$i]}
  tag=${TAGS[$i]}

  if [ ! -f "$file" ]; then
    echo "Skipping $file (not found)"
    continue
  fi

  echo
  echo "=============================================="
  echo "Building $file -> $tag"
  echo "=============================================="

  $DOCKER build -t "$tag" -f "$file" . || { echo "Build failed for $file"; exit 1; }
done

echo
echo "All builds finished. Running images sequentially."

for tag in "${TAGS[@]}"; do
  echo
  echo "--------------------------------"
  echo "Running $tag"
  echo "--------------------------------"
  # Run each container; accept that some may exit quickly. Don't stop the whole script on non-zero exit.
  if ! $DOCKER run --rm "$tag"; then
    echo "Container $tag exited with non-zero status"
  fi
done

echo
echo "Done."
