#!/usr/bin/env bash
set -euo pipefail

# Build and run all Dockerfile* images automatically.
# Tag is derived from filename:
#   Dockerfile.30.cache -> javahello:30-cache

DOCKER=${DOCKER:-docker}
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

echo "Using docker command: $DOCKER"
echo

# Collect Dockerfiles dynamically
FILES=($(ls Dockerfile.* 2>/dev/null | sort || true))

if [ ${#FILES[@]} -eq 0 ]; then
  echo "No Dockerfile.* found"
  exit 1
fi

# Build and run
for file in "${FILES[@]}"; do

  # Extract suffix after "Dockerfile."
  suffix="${file#Dockerfile.}"

  # Convert to tag-friendly format (just in case)
  tag_suffix=$(echo "$suffix" | tr '[:upper:]' '[:lower:]')

  tag="javahello:${tag_suffix}"

  echo
  echo "=============================================="
  echo "Building $file -> $tag"
  echo "=============================================="

  $DOCKER build -t "$tag" -f "$file" . \
    || { echo "Build failed for $file"; exit 1; }

done

echo
echo "All builds finished. Running images sequentially."

for file in "${FILES[@]}"; do
  suffix="${file#Dockerfile.}"
  tag="javahello:${suffix,,}"

  echo
  echo "--------------------------------"
  echo "Running $tag"
  echo "--------------------------------"

  if ! $DOCKER run --rm "$tag"; then
    echo "Container $tag exited with non-zero status"
  fi
done

echo
echo "Done."