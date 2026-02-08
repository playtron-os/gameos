#!/bin/bash
# Cross-compile box64 v0.4.0 for Raspberry Pi 5
#
# The base container image ships box64-sd888 (Snapdragon 888 build) which uses
# ARM instructions not available on the Pi 5's Cortex-A76 (SIGILL on launch).
# The Fedora box64-rpi5 package is v0.3.4, which has known bugs:
#   - wctype symbol resolution failure → steamui.so fails to load
#   - signal handler crashes (my_unwrap_signal_offset SIGSEGV)
#
# This script cross-compiles box64 0.4.0 with -DRPI5ARM64=1 (Cortex-A76 tuning)
# and outputs the binary to build-cache/box64-pi5/box64.
#
# Prerequisites:
#   - aarch64-linux-gnu-gcc cross-compiler
#   - cmake, make
#
# Usage: ./build-box64.sh [output-dir]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${SCRIPT_DIR}/build-cache"
OUTPUT_DIR="${1:-${CACHE_DIR}/box64-pi5}"

# Configuration
BOX64_REPO="https://github.com/ptitSeb/box64.git"
BOX64_TAG="${BOX64_TAG:-v0.4.0}"
CROSS_COMPILE="aarch64-linux-gnu-"
NPROC="${NPROC:-$(nproc)}"

echo "=== Building box64 ${BOX64_TAG} for Pi 5 ==="
echo "  Output: ${OUTPUT_DIR}"
echo "  Jobs: ${NPROC}"

# ── Auto-install build dependencies (Fedora) ─────────────────────────────────
BUILD_DEPS=(
    gcc-aarch64-linux-gnu
    cmake make git
    sysroot-aarch64-fc42-glibc
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
if [ -f "${OUTPUT_DIR}/box64" ]; then
    CACHED_VER=$("${OUTPUT_DIR}/box64" --version 2>&1 | grep -oP 'v[\d.]+' | head -1 || true)
    echo "Cached box64 binary found at ${OUTPUT_DIR}/box64 (${CACHED_VER:-unknown version})"
    echo "Delete it to force a rebuild."
    exit 0
fi

# Clone or update source
BOX64_SRC="${CACHE_DIR}/box64-src"
if [ -d "${BOX64_SRC}/.git" ]; then
    echo "Updating box64 source..."
    cd "${BOX64_SRC}"
    git fetch origin --tags
    git checkout "${BOX64_TAG}"
else
    echo "Cloning box64 from ${BOX64_REPO} (tag: ${BOX64_TAG})..."
    git clone --branch "${BOX64_TAG}" --depth 1 "${BOX64_REPO}" "${BOX64_SRC}"
fi

cd "${BOX64_SRC}"

# Build with cmake cross-compilation for Pi5
BUILD_DIR="${BOX64_SRC}/build-pi5"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Find aarch64 sysroot (Fedora cross-compilation packages)
SYSROOT=""
for candidate in \
    /usr/aarch64-redhat-linux/sys-root/fc42 \
    /usr/aarch64-redhat-linux/sys-root \
    /usr/aarch64-linux-gnu/sys-root \
    /usr/aarch64-linux-gnu; do
    if [ -f "${candidate}/usr/lib64/crt1.o" ] || [ -f "${candidate}/usr/lib/crt1.o" ]; then
        SYSROOT="${candidate}"
        break
    fi
done
[ -z "$SYSROOT" ] && { echo "ERROR: Cannot find aarch64 sysroot. Install: sudo dnf install sysroot-aarch64-fc42-glibc"; exit 1; }
echo "Using sysroot: ${SYSROOT}"

echo "Configuring box64 for Pi 5 (Cortex-A76)..."
cmake .. \
    -DRPI5ARM64=1 \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_C_COMPILER="${CROSS_COMPILE}gcc" \
    -DCMAKE_SYSROOT="${SYSROOT}" \
    -DCMAKE_SYSTEM_NAME=Linux \
    -DCMAKE_SYSTEM_PROCESSOR=aarch64

echo "Building box64 (${NPROC} jobs)..."
make -j"${NPROC}"

# Verify the binary
file box64 | grep -q "aarch64" || { echo "ERROR: Built binary is not aarch64"; exit 1; }

# Copy to output
cp box64 "${OUTPUT_DIR}/box64"
chmod +x "${OUTPUT_DIR}/box64"

echo ""
echo "=== box64 ${BOX64_TAG} built successfully ==="
echo "  Binary: ${OUTPUT_DIR}/box64"
echo "  Size: $(du -h "${OUTPUT_DIR}/box64" | cut -f1)"
