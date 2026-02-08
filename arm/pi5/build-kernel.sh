#!/bin/bash
# Cross-compile Raspberry Pi 5 kernel with 4KB page size
#
# The stock RPi kernel uses 16KB pages, which causes Wine/Proton (via box64)
# to crash: Wine's ntdll.so does MAP_FIXED mmap at 4KB-aligned addresses that
# are not 16KB-aligned, resulting in EINVAL → SIGSEGV.
#
# This script cross-compiles the RPi kernel from source with CONFIG_ARM64_4K_PAGES=y,
# producing kernel image, modules, DTBs, and overlays in a layout compatible with
# customize.sh and build-initramfs.sh.
#
# Prerequisites:
#   - aarch64-linux-gnu-gcc cross-compiler
#   - Standard build tools: make, bc, bison, flex, libssl-dev, etc.
#
# Usage: ./build-kernel.sh [output-dir]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${SCRIPT_DIR}/build-cache"
OUTPUT_DIR="${1:-${CACHE_DIR}/kernel-4k}"

# Configuration - use latest stable tag for Pi5
KERNEL_REPO="https://github.com/raspberrypi/linux.git"
KERNEL_BRANCH="${KERNEL_BRANCH:-rpi-6.12.y}"
KERNEL_TAG="${KERNEL_TAG:-stable_20250916}"
DEFCONFIG="bcm2712_defconfig"
CROSS_COMPILE="aarch64-linux-gnu-"
LOCALVERSION="-rpi-2712-4k"
NPROC="${NPROC:-$(nproc)}"

echo "=== Building Pi 5 kernel with 4KB page size ==="
echo "  Branch: ${KERNEL_BRANCH}"
echo "  Tag: ${KERNEL_TAG:-latest}"
echo "  Output: ${OUTPUT_DIR}"
echo "  Jobs: ${NPROC}"

# Check prerequisites
for tool in ${CROSS_COMPILE}gcc make bc bison flex; do
    if ! command -v "$tool" &>/dev/null; then
        echo "ERROR: Required tool not found: $tool"
        echo "Install with: sudo dnf install gcc-aarch64-linux-gnu make bc bison flex"
        exit 1
    fi
done

# Check if we already have a cached build
KERNEL_VERSION_FILE="${OUTPUT_DIR}/.kernel-version"
if [ -f "${KERNEL_VERSION_FILE}" ] && [ -f "${OUTPUT_DIR}/boot/vmlinuz-"* ]; then
    CACHED_VERSION=$(cat "${KERNEL_VERSION_FILE}")
    echo "Cached kernel found: ${CACHED_VERSION}"
    echo "Delete ${OUTPUT_DIR} to force a rebuild."
    exit 0
fi

mkdir -p "${OUTPUT_DIR}" "${CACHE_DIR}"

# === Clone or update kernel source ===
KERNEL_SRC="${CACHE_DIR}/linux-rpi"
if [ -d "${KERNEL_SRC}/.git" ]; then
    echo "Updating kernel source..."
    cd "${KERNEL_SRC}"
    git fetch origin
    if [ -n "${KERNEL_TAG}" ]; then
        git checkout "${KERNEL_TAG}"
    else
        git checkout "${KERNEL_BRANCH}"
        git reset --hard "origin/${KERNEL_BRANCH}"
    fi
else
    echo "Cloning kernel from ${KERNEL_REPO} (branch: ${KERNEL_BRANCH})..."
    if [ -n "${KERNEL_TAG}" ]; then
        git clone --depth 1 --branch "${KERNEL_TAG}" "${KERNEL_REPO}" "${KERNEL_SRC}"
    else
        git clone --depth 1 --branch "${KERNEL_BRANCH}" "${KERNEL_REPO}" "${KERNEL_SRC}"
    fi
fi

cd "${KERNEL_SRC}"
echo "Kernel source at: $(git log --oneline -1 2>/dev/null || echo 'unknown')"

# === Configure kernel ===
echo "Configuring kernel (${DEFCONFIG})..."
make ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE} ${DEFCONFIG}

# Modify config for 4KB pages instead of 16KB
echo "Switching to 4KB page size..."
./scripts/config --file .config --disable ARM64_16K_PAGES
./scripts/config --file .config --enable ARM64_4K_PAGES
./scripts/config --file .config --set-val ARM64_VA_BITS 48
./scripts/config --file .config --set-str LOCALVERSION "${LOCALVERSION}"

# HAS_DMA and related depend on page size - let olddefconfig resolve
make ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE} olddefconfig

# Verify the page size setting
if ! grep -q "CONFIG_ARM64_4K_PAGES=y" .config; then
    echo "ERROR: Failed to set CONFIG_ARM64_4K_PAGES=y"
    grep "ARM64.*PAGE" .config
    exit 1
fi
echo "Config verified: $(grep 'CONFIG_ARM64_4K_PAGES' .config)"

# === Build kernel ===
echo "Building kernel image..."
make ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE} -j${NPROC} Image

echo "Building modules..."
make ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE} -j${NPROC} modules

echo "Building device trees..."
make ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE} -j${NPROC} dtbs

# === Determine kernel version ===
KERNEL_RELEASE=$(make ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE} -s kernelrelease)
echo "Kernel version: ${KERNEL_RELEASE}"

# === Install to output directory ===
# Layout matches dpkg-deb extraction so customize.sh/build-initramfs.sh work unchanged:
#   boot/vmlinuz-VERSION
#   usr/lib/modules/VERSION/
#   usr/lib/linux-image-VERSION/broadcom/bcm2712-rpi-5-b.dtb
#   usr/lib/linux-image-VERSION/overlays/

echo "Installing to ${OUTPUT_DIR}..."
rm -rf "${OUTPUT_DIR:?}"/*

# Kernel image (compressed)
mkdir -p "${OUTPUT_DIR}/boot"
gzip -9 -c arch/arm64/boot/Image > "${OUTPUT_DIR}/boot/vmlinuz-${KERNEL_RELEASE}"
echo "Installed vmlinuz-${KERNEL_RELEASE}"

# Modules
make ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE} \
    INSTALL_MOD_PATH="${OUTPUT_DIR}/usr" \
    modules_install
# Remove build/source symlinks (they point to the build machine)
rm -f "${OUTPUT_DIR}/usr/lib/modules/${KERNEL_RELEASE}/build"
rm -f "${OUTPUT_DIR}/usr/lib/modules/${KERNEL_RELEASE}/source"
echo "Installed modules"

# DTBs - match the Debian package layout
DTB_DIR="${OUTPUT_DIR}/usr/lib/linux-image-${KERNEL_RELEASE}/broadcom"
mkdir -p "${DTB_DIR}"
cp arch/arm64/boot/dts/broadcom/bcm2712-rpi-5-b.dtb "${DTB_DIR}/"
# Also copy other bcm2712 DTBs if present
for dtb in arch/arm64/boot/dts/broadcom/bcm2712*.dtb; do
    [ -f "$dtb" ] && cp "$dtb" "${DTB_DIR}/"
done
echo "Installed DTBs"

# Overlays
OVERLAY_DIR="${OUTPUT_DIR}/usr/lib/linux-image-${KERNEL_RELEASE}/overlays"
mkdir -p "${OVERLAY_DIR}"
if [ -d arch/arm64/boot/dts/overlays ]; then
    cp arch/arm64/boot/dts/overlays/*.dtbo "${OVERLAY_DIR}/" 2>/dev/null || true
    echo "Installed overlays ($(ls "${OVERLAY_DIR}/" | wc -l) files)"
fi

# Write version metadata
echo "${KERNEL_RELEASE}" > "${KERNEL_VERSION_FILE}"

# Summary
echo ""
echo "=== Pi 5 kernel built successfully ==="
echo "  Version:  ${KERNEL_RELEASE}"
echo "  Pages:    4KB (CONFIG_ARM64_4K_PAGES=y)"
echo "  Image:    ${OUTPUT_DIR}/boot/vmlinuz-${KERNEL_RELEASE}"
echo "  Modules:  ${OUTPUT_DIR}/usr/lib/modules/${KERNEL_RELEASE}/"
echo "  DTBs:     ${DTB_DIR}/"
echo "  Overlays: ${OVERLAY_DIR}/"
echo ""
echo "Set PI_KERNEL_VERSION=${KERNEL_RELEASE} when running customize.sh"
