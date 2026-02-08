#!/bin/bash
# Build Pi 5 initramfs by injecting kernel modules into Fedora initramfs
# This preserves ostree boot support while adding Pi 5 hardware support
#
# Usage: ./build-initramfs.sh <disk-image> <output-initramfs>
#
# Prerequisites:
#   - Pi 5 kernel package extracted to build-cache/pi5/modules-extracted/
#   - kpartx, cpio, zstd installed
#   - Run as root

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If a custom 4KB-page kernel was built, use it; otherwise fall back to pre-built RPi kernel
CUSTOM_KERNEL_DIR="$SCRIPT_DIR/build-cache/kernel-4k"
if [ -f "$CUSTOM_KERNEL_DIR/.kernel-version" ]; then
    PI_KERNEL_VERSION="$(cat "$CUSTOM_KERNEL_DIR/.kernel-version")"
    PI_MODULES="$CUSTOM_KERNEL_DIR/usr/lib/modules/$PI_KERNEL_VERSION"
    echo "Using custom 4KB-page kernel: $PI_KERNEL_VERSION"
else
    PI_KERNEL_VERSION="${PI_KERNEL_VERSION:-6.12.62+rpt-rpi-2712}"
    PI_MODULES="$SCRIPT_DIR/build-cache/modules-extracted/usr/lib/modules/$PI_KERNEL_VERSION"
    echo "Using pre-built RPi kernel: $PI_KERNEL_VERSION"
fi

DISK_IMAGE="$1"
OUTPUT="$2"

if [ -z "$DISK_IMAGE" ] || [ -z "$OUTPUT" ]; then
    echo "Usage: $0 <disk-image> <output-initramfs>"
    echo "  e.g., $0 output/image/disk.raw arm/pi5/build-cache/initramfs-pi5.img"
    exit 1
fi

# Convert relative paths to absolute
[[ "$DISK_IMAGE" != /* ]] && DISK_IMAGE="$(pwd)/$DISK_IMAGE"
[[ "$OUTPUT" != /* ]] && OUTPUT="$(pwd)/$OUTPUT"

[ -f "$DISK_IMAGE" ] || { echo "ERROR: Disk image not found: $DISK_IMAGE"; exit 1; }
[ "$EUID" -eq 0 ] || { echo "ERROR: Must run as root"; exit 1; }

# PI_MODULES was set above based on whether custom kernel exists
[ -d "$PI_MODULES" ] || { echo "ERROR: Pi modules not found at $PI_MODULES"; echo "Run 'task build-kernel:pi5' or 'task download:pi5' first"; exit 1; }

echo "Building Pi 5 initramfs..."
echo "  Disk image: $DISK_IMAGE"
echo "  Output: $OUTPUT"
echo "  Kernel: $PI_KERNEL_VERSION"

# Cleanup on exit
cleanup() {
    [ -n "$BOOT_MOUNT" ] && mountpoint -q "$BOOT_MOUNT" 2>/dev/null && umount "$BOOT_MOUNT"
    [ -n "$BOOT_MOUNT" ] && rmdir "$BOOT_MOUNT" 2>/dev/null || true
    [ -n "$WORK_DIR" ] && rm -rf "$WORK_DIR"
    [ -n "$KPARTX_DONE" ] && kpartx -d "$DISK_IMAGE" 2>/dev/null || true
}
trap cleanup EXIT

# Mount disk image
KPARTX_OUT=$(kpartx -av "$DISK_IMAGE")
KPARTX_DONE=1
BOOT_DEV=$(echo "$KPARTX_OUT" | grep 'p2 ' | cut -d' ' -f3)

[ -n "$BOOT_DEV" ] || { echo "ERROR: Could not find boot partition"; exit 1; }

BOOT_MOUNT=$(mktemp -d)
mount "/dev/mapper/$BOOT_DEV" "$BOOT_MOUNT"

# Find Fedora initramfs
FEDORA_INITRAMFS=$(find "$BOOT_MOUNT/ostree" -name "initramfs-*.img" 2>/dev/null | head -1)
[ -n "$FEDORA_INITRAMFS" ] || { echo "ERROR: Could not find Fedora initramfs"; exit 1; }
echo "Found Fedora initramfs: $FEDORA_INITRAMFS"

# Extract initramfs
WORK_DIR=$(mktemp -d)
EXTRACTED="$WORK_DIR/extracted"
mkdir -p "$EXTRACTED"
cd "$EXTRACTED"

if zstd -d < "$FEDORA_INITRAMFS" 2>/dev/null | cpio -idm 2>/dev/null; then
    echo "Extracted with zstd"
elif gzip -d < "$FEDORA_INITRAMFS" 2>/dev/null | cpio -idm 2>/dev/null; then
    echo "Extracted with gzip"
elif xz -d < "$FEDORA_INITRAMFS" 2>/dev/null | cpio -idm 2>/dev/null; then
    echo "Extracted with xz"
else
    echo "ERROR: Could not extract initramfs"
    exit 1
fi
cd - > /dev/null

[ -d "$EXTRACTED/usr" ] || { echo "ERROR: Extraction failed"; exit 1; }

# Remove Fedora modules, inject Pi modules
echo "Injecting Pi 5 kernel modules..."
rm -rf "$EXTRACTED/usr/lib/modules/"* 2>/dev/null || true
rm -rf "$EXTRACTED/lib/modules" 2>/dev/null || true
mkdir -p "$EXTRACTED/lib/modules" "$EXTRACTED/usr/lib/modules"

cp -a "$PI_MODULES" "$EXTRACTED/usr/lib/modules/"
ln -sf "../usr/lib/modules/$PI_KERNEL_VERSION" "$EXTRACTED/lib/modules/$PI_KERNEL_VERSION"
depmod -b "$EXTRACTED" -a "$PI_KERNEL_VERSION" 2>/dev/null || true

# Add hook to load zram module early (before pivot_root)
# This is needed because zram-generator runs before the modules overlay service
echo "Adding early module loading hook..."
mkdir -p "$EXTRACTED/usr/lib/dracut/hooks/pre-pivot"
cat > "$EXTRACTED/usr/lib/dracut/hooks/pre-pivot/99-load-zram.sh" << 'EOF'
#!/bin/sh
# Load zram before pivot_root so it's available when zram-generator runs
modprobe zram 2>/dev/null || true
EOF
chmod +x "$EXTRACTED/usr/lib/dracut/hooks/pre-pivot/99-load-zram.sh"

# Inject WiFi firmware (Pi kernel doesn't support compressed firmware)
# This allows brcmfmac to load firmware during initramfs before root is mounted
echo "Injecting WiFi firmware..."
FIRMWARE_DEST="$EXTRACTED/lib/firmware/brcm"
mkdir -p "$FIRMWARE_DEST"
CYPRESS_FW="$SCRIPT_DIR/build-cache/modules-extracted/usr/lib/firmware/cypress"
BRCM_FW="$SCRIPT_DIR/build-cache/modules-extracted/usr/lib/firmware/brcm"
# Check if firmware exists in extracted kernel package, otherwise use system firmware
if [ -f "$CYPRESS_FW/cyfmac43455-sdio.bin" ]; then
    cp "$CYPRESS_FW/cyfmac43455-sdio.bin" "$FIRMWARE_DEST/brcmfmac43455-sdio.bin"
    cp "$CYPRESS_FW/cyfmac43455-sdio.clm_blob" "$FIRMWARE_DEST/brcmfmac43455-sdio.clm_blob"
elif [ -f "/usr/lib/firmware/cypress/cyfmac43455-sdio.bin.xz" ]; then
    xz -dk "/usr/lib/firmware/cypress/cyfmac43455-sdio.bin.xz" -c > "$FIRMWARE_DEST/brcmfmac43455-sdio.bin"
    xz -dk "/usr/lib/firmware/cypress/cyfmac43455-sdio.clm_blob.xz" -c > "$FIRMWARE_DEST/brcmfmac43455-sdio.clm_blob"
else
    echo "Warning: WiFi firmware not found, skipping"
fi
if [ -f "$FIRMWARE_DEST/brcmfmac43455-sdio.bin" ]; then
    cp "$FIRMWARE_DEST/brcmfmac43455-sdio.bin" "$FIRMWARE_DEST/brcmfmac43455-sdio.raspberrypi,5-model-b.bin"
    # Get the board-specific txt file
    if [ -f "$BRCM_FW/brcmfmac43455-sdio.raspberrypi,4-model-b.txt" ]; then
        cp "$BRCM_FW/brcmfmac43455-sdio.raspberrypi,4-model-b.txt" "$FIRMWARE_DEST/brcmfmac43455-sdio.raspberrypi,5-model-b.txt"
    elif [ -f "/usr/lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.txt.xz" ]; then
        xz -dk "/usr/lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.txt.xz" -c > "$FIRMWARE_DEST/brcmfmac43455-sdio.raspberrypi,5-model-b.txt"
    fi
    echo "WiFi firmware injected"
fi

# Inject regulatory database for cfg80211 (needed for proper WiFi channel support)
echo "Injecting regulatory database..."
REG_DEST="$EXTRACTED/lib/firmware"
if [ -f "/usr/lib/firmware/regulatory.db" ]; then
    cp "/usr/lib/firmware/regulatory.db" "$REG_DEST/"
    cp "/usr/lib/firmware/regulatory.db.p7s" "$REG_DEST/"
    echo "Regulatory database injected"
elif [ -f "/lib/firmware/regulatory.db" ]; then
    cp "/lib/firmware/regulatory.db" "$REG_DEST/"
    cp "/lib/firmware/regulatory.db.p7s" "$REG_DEST/"
    echo "Regulatory database injected"
else
    echo "Warning: regulatory.db not found, WiFi channel selection may be limited"
fi

# Repack with zstd
echo "Repacking initramfs..."
mkdir -p "$(dirname "$OUTPUT")"
cd "$EXTRACTED"
find . -print0 | cpio --null -o -H newc 2>/dev/null | zstd -19 -T0 > "$OUTPUT"
cd - > /dev/null

echo "Initramfs built: $OUTPUT"
ls -lh "$OUTPUT"
