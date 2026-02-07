#!/bin/bash
# Build custom gamescope for Pi 5 from the pi5 branch
# This builds gamescope with V3D/VC4 split-GPU support
#
# The build is done natively on the Pi 5 target or in a matching aarch64 environment.
# For disk image customization, we cross-compile or use cached artifacts.
#
# Usage: ./build-gamescope.sh <output-dir>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${SCRIPT_DIR}/build-cache"
OUTPUT_DIR="${1:-${CACHE_DIR}/gamescope-pi5}"

GAMESCOPE_REPO="https://github.com/Ericky14/gamescope.git"
GAMESCOPE_BRANCH="pi5"

echo "=== Building custom gamescope for Pi 5 ==="
echo "Output: ${OUTPUT_DIR}"

mkdir -p "${OUTPUT_DIR}"

# Check if we already have a cached build
if [ -f "${OUTPUT_DIR}/gamescope" ]; then
    echo "Cached gamescope binary found at ${OUTPUT_DIR}/gamescope"
    echo "Delete it to force a rebuild."
    exit 0
fi

# Clone or update
GAMESCOPE_SRC="${CACHE_DIR}/gamescope-src"
if [ -d "${GAMESCOPE_SRC}/.git" ]; then
    echo "Updating gamescope source..."
    cd "${GAMESCOPE_SRC}"
    git fetch origin
    git checkout "${GAMESCOPE_BRANCH}"
    git reset --hard "origin/${GAMESCOPE_BRANCH}"
else
    echo "Cloning gamescope from ${GAMESCOPE_REPO} (branch: ${GAMESCOPE_BRANCH})..."
    git clone --branch "${GAMESCOPE_BRANCH}" --depth 1 "${GAMESCOPE_REPO}" "${GAMESCOPE_SRC}"
fi

cd "${GAMESCOPE_SRC}"

echo "Building gamescope..."
# Use meson + ninja
if [ ! -d build ]; then
    meson setup build --prefix=/usr --buildtype=release
fi
ninja -C build -j$(nproc)

# Copy the built binary
cp build/src/gamescope "${OUTPUT_DIR}/gamescope"
chmod +x "${OUTPUT_DIR}/gamescope"

echo "=== gamescope built successfully ==="
echo "Binary: ${OUTPUT_DIR}/gamescope"
