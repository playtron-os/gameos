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

# ── Auto-install build dependencies (Fedora) ─────────────────────────────────
BUILD_DEPS=(
    # Build tools
    meson ninja-build cmake gcc-c++ git glslang
    # Vulkan
    vulkan-loader-devel vulkan-headers
    # Wayland
    wayland-devel wayland-protocols-devel
    # X11 / XCB
    libX11-devel libxcb-devel xcb-util-wm-devel
    libXdamage-devel libXcomposite-devel libXcursor-devel libXrender-devel
    libXext-devel libXfixes-devel libXxf86vm-devel libXtst-devel
    libXres-devel libXmu-devel libXi-devel
    # Core libs
    libdrm-devel libxkbcommon-devel pixman-devel lcms2-devel
    libinput-devel libseat-devel systemd-devel
    libdecor-devel libeis-devel luajit-devel
    libcap-devel hwdata-devel
    # Optional (enabled when available)
    pipewire-devel sdl2-compat-devel libavif-devel
)

MISSING=()
for pkg in "${BUILD_DEPS[@]}"; do
    rpm -q "$pkg" &>/dev/null || MISSING+=("$pkg")
done
if [ ${#MISSING[@]} -gt 0 ]; then
    echo "Installing missing build dependencies: ${MISSING[*]}"
    sudo dnf install -y --setopt=install_weak_deps=false "${MISSING[@]}"
fi

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
    git submodule update --init --recursive
else
    echo "Cloning gamescope from ${GAMESCOPE_REPO} (branch: ${GAMESCOPE_BRANCH})..."
    git clone --recurse-submodules --branch "${GAMESCOPE_BRANCH}" --depth 1 "${GAMESCOPE_REPO}" "${GAMESCOPE_SRC}"
fi

cd "${GAMESCOPE_SRC}"

echo "Building gamescope..."
# Use meson + ninja (reconfigure if a previous attempt left a stale build dir)
if [ -d build ]; then
    meson setup build --reconfigure --prefix=/usr --buildtype=release || {
        echo "Reconfigure failed, wiping stale build dir..."
        rm -rf build
        meson setup build --prefix=/usr --buildtype=release
    }
else
    meson setup build --prefix=/usr --buildtype=release
fi
ninja -C build -j$(nproc)

# Copy the built binary
cp build/src/gamescope "${OUTPUT_DIR}/gamescope"
chmod +x "${OUTPUT_DIR}/gamescope"

echo "=== gamescope built successfully ==="
echo "Binary: ${OUTPUT_DIR}/gamescope"
