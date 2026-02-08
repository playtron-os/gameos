#!/bin/bash
# Build custom gamescope for Pi 5 from the pi5 branch
# This builds gamescope with V3D/VC4 split-GPU support
#
# Cross-compiles for aarch64 using podman + qemu-user-static emulation.
# Uses a persistent builder container image to avoid reinstalling deps each time.
# Requires: podman, qemu-user-static (binfmt_misc)
#
# Usage: ./build-gamescope.sh [output-dir]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${SCRIPT_DIR}/build-cache"
OUTPUT_DIR="${1:-${CACHE_DIR}/gamescope-pi5}"

GAMESCOPE_REPO="https://github.com/Ericky14/gamescope.git"
GAMESCOPE_BRANCH="pi5"
BUILDER_IMAGE="localhost/gamescope-pi5-builder"

echo "=== Building custom gamescope for Pi 5 ==="
echo "Output: ${OUTPUT_DIR}"

mkdir -p "${OUTPUT_DIR}"

# Check if we already have a cached build
if [ -f "${OUTPUT_DIR}/gamescope" ]; then
    cached_arch=$(file "${OUTPUT_DIR}/gamescope" | grep -o 'ARM aarch64' || true)
    if [ -n "$cached_arch" ]; then
        echo "Cached gamescope binary found at ${OUTPUT_DIR}/gamescope (aarch64)"
        echo "Delete it to force a rebuild."
        exit 0
    else
        echo "Cached gamescope is not aarch64, rebuilding..."
        rm -f "${OUTPUT_DIR}/gamescope"
    fi
fi

# Clone or update source on host (faster than inside container)
GAMESCOPE_SRC="${CACHE_DIR}/gamescope-src"
if [ -d "${GAMESCOPE_SRC}/.git" ]; then
    echo "Updating gamescope source..."
    cd "${GAMESCOPE_SRC}"
    git fetch origin
    git checkout "${GAMESCOPE_BRANCH}"
    git reset --hard "origin/${GAMESCOPE_BRANCH}"
    git submodule update --init --recursive
else
    echo "Cloning gamescope from ${GAMESCOPE_REPO} (branch: ${GAMESCOPE_BRANCH})..."
    git clone --recurse-submodules --branch "${GAMESCOPE_BRANCH}" --depth 1 "${GAMESCOPE_REPO}" "${GAMESCOPE_SRC}"
fi

# Build or reuse the builder container image with all deps pre-installed
if ! podman image exists "${BUILDER_IMAGE}" 2>/dev/null; then
    echo "Creating aarch64 builder image (one-time, deps will be cached)..."
    podman build --arch arm64 -t "${BUILDER_IMAGE}" -f - <<'DOCKERFILE'
FROM fedora:42
RUN dnf install -y --setopt=install_weak_deps=false \
    meson ninja-build cmake gcc-c++ git glslang \
    vulkan-loader-devel vulkan-headers \
    wayland-devel wayland-protocols-devel \
    libX11-devel libxcb-devel xcb-util-wm-devel xcb-util-errors-devel \
    libXdamage-devel libXcomposite-devel libXcursor-devel libXrender-devel \
    libXext-devel libXfixes-devel libXxf86vm-devel libXtst-devel \
    libXres-devel libXmu-devel libXi-devel \
    libdrm-devel libxkbcommon-devel pixman-devel lcms2-devel \
    libinput-devel libseat-devel systemd-devel \
    libdecor-devel libeis-devel luajit-devel \
    libcap-devel hwdata-devel \
    pipewire-devel sdl2-compat-devel libavif-devel \
    xorg-x11-server-Xwayland-devel xcb-util-errors-devel \
    file \
    && dnf clean all
DOCKERFILE
else
    echo "Using cached builder image: ${BUILDER_IMAGE}"
fi

echo "Building gamescope in aarch64 container..."

# Build inside the persistent builder container
# Mount source and output; keep the build dir inside /src for incremental builds
podman run --rm --arch arm64 \
    -v "${GAMESCOPE_SRC}:/src:Z" \
    -v "${OUTPUT_DIR}:/output:Z" \
    "${BUILDER_IMAGE}" bash -exc '
cd /src

# Only reconfigure if build dir is missing or was from a different arch
if [ -d build ] && [ -f build/build.ninja ]; then
    echo "Reusing existing build directory (incremental build)"
else
    rm -rf build
    meson setup build --prefix=/usr --buildtype=release
fi

ninja -C build -j$(nproc)

cp build/src/gamescope /output/gamescope
chmod +x /output/gamescope
echo "Build complete: $(file /output/gamescope)"
'

# Verify the output is aarch64
echo "=== Verifying binary architecture ==="
file "${OUTPUT_DIR}/gamescope"
file "${OUTPUT_DIR}/gamescope" | grep -q 'ARM aarch64' || {
    echo "ERROR: Built binary is not aarch64!"
    rm -f "${OUTPUT_DIR}/gamescope"
    exit 1
}

echo "=== gamescope built successfully (aarch64) ==="
echo "Binary: ${OUTPUT_DIR}/gamescope"
