#!/usr/bin/env bash
set -euo pipefail

DOCKER=${DOCKER:-docker}
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

BASE_IMAGE_NAME="javahello"

echo "Using docker command: $DOCKER"

# ------------------------------------------------------------
# Discover all Dockerfiles dynamically
# ------------------------------------------------------------
mapfile -t FILES < <(find . -maxdepth 1 -type f -name "Dockerfile.*" | sort)

if [ ${#FILES[@]} -eq 0 ]; then
  echo "No Dockerfile.* found"
  exit 1
fi

# ------------------------------------------------------------
# BUILD PHASE
# ------------------------------------------------------------
for file in "${FILES[@]}"; do
  file="${file#./}"

  [ ! -f "$file" ] && continue

  # consistent tag generation
  suffix="${file#Dockerfile.}"
  suffix="${suffix//./-}"
  tag="${BASE_IMAGE_NAME}:${suffix}"

  echo
  echo "=============================================="
  echo "Building $file -> $tag"
  echo "=============================================="

  $DOCKER build -t "$tag" -f "$file" . || {
    echo "Build failed for $file"
    exit 1
  }
done

echo
echo "All builds finished. Running images sequentially."

# ------------------------------------------------------------
# RUN PHASE
# ------------------------------------------------------------
for file in "${FILES[@]}"; do
  file="${file#./}"

  [ ! -f "$file" ] && continue

  suffix="${file#Dockerfile.}"
  suffix="${suffix//./-}"
  tag="${BASE_IMAGE_NAME}:${suffix}"

  echo
  echo "--------------------------------"
  echo "Running $tag"
  echo "--------------------------------"

  $DOCKER run --rm "$tag" || true
done

echo
echo "Done."