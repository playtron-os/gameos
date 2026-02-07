#!/bin/bash
# Raspberry Pi 5 disk image customization script (minimal - console boot only)
# This script customizes a generic ARM Fedora disk image for Pi 5 boot
#
# Prerequisites (handled by Taskfile):
#   - Kernel modules downloaded and extracted via 'task download:pi5'
#   - Initramfs built via 'task build-initramfs:pi5'
#
# Usage: ./customize.sh <target-name>
#   The script expects output/image/<target-name>.raw to exist

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../.."
CACHE_DIR="$SCRIPT_DIR/build-cache"

# Configuration
PI_KERNEL_VERSION="${PI_KERNEL_VERSION:-6.12.62+rpt-rpi-2712}"
PI_KERNEL_PKG_VERSION="${PI_KERNEL_PKG_VERSION:-6.12.62-1+rpt1}"

# Cleanup on exit
cleanup() {
    local exit_code=$?
    if [ -n "$ROOT_MOUNT" ] && mountpoint -q "$ROOT_MOUNT" 2>/dev/null; then
        umount "$ROOT_MOUNT" || true
    fi
    if [ -n "$EFI_MOUNT" ] && mountpoint -q "$EFI_MOUNT" 2>/dev/null; then
        umount "$EFI_MOUNT" || true
    fi
    if [ -n "$BOOT_MOUNT" ] && mountpoint -q "$BOOT_MOUNT" 2>/dev/null; then
        umount "$BOOT_MOUNT" || true
    fi
    [ -n "$ROOT_MOUNT" ] && rmdir "$ROOT_MOUNT" 2>/dev/null || true
    [ -n "$EFI_MOUNT" ] && rmdir "$EFI_MOUNT" 2>/dev/null || true
    [ -n "$BOOT_MOUNT" ] && rmdir "$BOOT_MOUNT" 2>/dev/null || true
    [ -n "$KPARTX_OUT" ] && kpartx -d "$DISK_IMAGE" 2>/dev/null || true
    exit $exit_code
}
trap cleanup EXIT

# Validate arguments
TARGET="$1"
if [ -z "$TARGET" ]; then
    echo "Usage: $0 <target-name>"
    echo "  e.g., $0 pi5"
    exit 1
fi

DISK_IMAGE="$REPO_ROOT/output/image/${TARGET}.raw"
if [ ! -f "$DISK_IMAGE" ]; then
    echo "ERROR: Disk image not found: $DISK_IMAGE"
    exit 1
fi

# Validate prerequisites
echo "Checking prerequisites..."
# Raspberry Pi packages use /usr/lib/modules/ instead of /lib/modules/
MODULES_DIR="$CACHE_DIR/modules-extracted/usr/lib/modules/$PI_KERNEL_VERSION"
[ -d "$MODULES_DIR" ] || { echo "ERROR: Kernel modules not found at $MODULES_DIR. Run 'task download:pi5'"; exit 1; }
[ -f "$CACHE_DIR/initramfs-pi5.img" ] || { echo "ERROR: Initramfs not found. Run 'task build-initramfs:pi5'"; exit 1; }

echo "Customizing disk image: $DISK_IMAGE"

# Mount disk image partitions
KPARTX_OUT=$(kpartx -av "$DISK_IMAGE")
echo "kpartx: $KPARTX_OUT"

EFI_DEV=$(echo "$KPARTX_OUT" | grep 'p1 ' | cut -d' ' -f3)
BOOT_DEV=$(echo "$KPARTX_OUT" | grep 'p2 ' | cut -d' ' -f3)
ROOT_DEV=$(echo "$KPARTX_OUT" | grep 'p3 ' | cut -d' ' -f3)

# Fallback for 2-partition layout
[ -z "$ROOT_DEV" ] && ROOT_DEV="$BOOT_DEV" && BOOT_DEV=""

echo "EFI: $EFI_DEV, Boot: $BOOT_DEV, Root: $ROOT_DEV"

# Mount root filesystem
ROOT_MOUNT=$(mktemp -d)
mount "/dev/mapper/$ROOT_DEV" "$ROOT_MOUNT"

# Find ostree root if applicable
if [ -d "$ROOT_MOUNT/ostree/deploy" ]; then
    OSTREE_ROOT=$(find "$ROOT_MOUNT/ostree/deploy" -maxdepth 4 -name "*.0" -type d 2>/dev/null | head -1)
    [ -n "$OSTREE_ROOT" ] && ROOTFS="$OSTREE_ROOT" || ROOTFS="$ROOT_MOUNT"
else
    ROOTFS="$ROOT_MOUNT"
fi
echo "Using rootfs: $ROOTFS"

# Mount EFI partition
EFI_MOUNT=$(mktemp -d)
mount "/dev/mapper/$EFI_DEV" "$EFI_MOUNT"

# Get ostree deploy hash from boot partition
DEPLOY_HASH=""
if [ -n "$BOOT_DEV" ]; then
    BOOT_MOUNT=$(mktemp -d)
    mount -o ro "/dev/mapper/$BOOT_DEV" "$BOOT_MOUNT"
    OSTREE_DIR=$(find "$BOOT_MOUNT/ostree" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)
    if [ -n "$OSTREE_DIR" ]; then
        DEPLOY_HASH="${OSTREE_DIR##*default-}"
        echo "Ostree deploy hash: $DEPLOY_HASH"
    fi
    umount "$BOOT_MOUNT"
    rmdir "$BOOT_MOUNT"
    BOOT_MOUNT=""
fi

# === Kernel modules location ===
KERNEL_EXTRACT="$CACHE_DIR/modules-extracted"
echo "Using kernel modules from: $KERNEL_EXTRACT"

# === Setup EFI partition ===
echo "Setting up EFI partition..."

# Download and copy firmware if needed
FIRMWARE_DIR="$CACHE_DIR/firmware"
if [ ! -d "$FIRMWARE_DIR" ] || [ ! -f "$FIRMWARE_DIR/start4.elf" ]; then
    echo "Downloading Pi 5 firmware..."
    mkdir -p "$FIRMWARE_DIR"
    for f in start4.elf start4x.elf start4cd.elf start4db.elf fixup4.dat fixup4x.dat fixup4cd.dat fixup4db.dat; do
        wget -q -O "$FIRMWARE_DIR/$f" "https://github.com/raspberrypi/firmware/raw/master/boot/$f" || true
    done
fi

# Copy firmware
cp "$FIRMWARE_DIR/"*.elf "$FIRMWARE_DIR/"*.dat "$EFI_MOUNT/" 2>/dev/null || echo "Warning: Some firmware files missing"

# Copy kernel
KERNEL_IMG="$KERNEL_EXTRACT/boot/vmlinuz-${PI_KERNEL_VERSION}"
if [ -f "$KERNEL_IMG" ]; then
    cp "$KERNEL_IMG" "$EFI_MOUNT/vmlinuz"
else
    echo "ERROR: Kernel not found at $KERNEL_IMG"
    exit 1
fi

# Copy DTB
DTB_PATH="$KERNEL_EXTRACT/usr/lib/linux-image-${PI_KERNEL_VERSION}/broadcom/bcm2712-rpi-5-b.dtb"
if [ -f "$DTB_PATH" ]; then
    cp "$DTB_PATH" "$EFI_MOUNT/"
else
    echo "ERROR: DTB not found at $DTB_PATH"
    exit 1
fi

# Copy overlays
OVERLAYS_PATH="$KERNEL_EXTRACT/usr/lib/linux-image-${PI_KERNEL_VERSION}/overlays"
if [ -d "$OVERLAYS_PATH" ]; then
    mkdir -p "$EFI_MOUNT/overlays"
    cp "$OVERLAYS_PATH/"*.dtbo "$EFI_MOUNT/overlays/"
else
    echo "Warning: Overlays not found at $OVERLAYS_PATH"
fi

# Copy initramfs
cp "$CACHE_DIR/initramfs-pi5.img" "$EFI_MOUNT/initramfs.img"

# Create config.txt
cat > "$EFI_MOUNT/config.txt" << 'EOF'
# Raspberry Pi 5 config for Playtron GameOS
arm_64bit=1
enable_uart=1
uart_2ndstage=1

# Kernel and initramfs - direct boot (not UEFI)
kernel=vmlinuz
initramfs initramfs.img followkernel

# Force HDMI output
hdmi_force_hotplug=1

# Device tree
device_tree=bcm2712-rpi-5-b.dtb

# Enable V3D GPU driver for graphics
dtoverlay=vc4-kms-v3d-pi5

# Boot command line
cmdline=cmdline.txt
EOF

# Create cmdline.txt
if [ -n "$DEPLOY_HASH" ]; then
    cat > "$EFI_MOUNT/cmdline.txt" << EOF
root=/dev/sda3 rw rootfstype=ext4 rootwait rootdelay=5 console=tty1 loglevel=7 ostree=/ostree/boot.1/default/${DEPLOY_HASH}/0
EOF
else
    cat > "$EFI_MOUNT/cmdline.txt" << 'EOF'
root=/dev/sda3 rw rootfstype=ext4 rootwait rootdelay=5 console=tty1 loglevel=7
EOF
fi

echo "EFI partition configured"

# === Setup root filesystem ===
echo "Configuring root filesystem..."

# Install kernel modules
if [ -f "$ROOTFS/.ostree.cfs" ]; then
    echo "Composefs detected - installing modules to /var/lib/modules"
    # For ostree, /var is a shared persistent directory at ostree/deploy/<stateroot>/var
    # NOT in the deploy directory itself
    OSTREE_VAR="$ROOT_MOUNT/ostree/deploy/default/var"
    MODULES_DEST="$OSTREE_VAR/lib/modules/$PI_KERNEL_VERSION"
    mkdir -p "$MODULES_DEST"
    cp -a "$KERNEL_EXTRACT/usr/lib/modules/$PI_KERNEL_VERSION"/* "$MODULES_DEST/"
    
    # For immutable systems, we need to use an overlay mount since /usr is read-only
    # Create the modules overlay service - must run very early before systemd-modules-load
    cat > "$ROOTFS/etc/systemd/system/pi5-modules-overlay.service" << EOF
[Unit]
Description=Overlay Pi5 Kernel Modules
DefaultDependencies=no
Before=systemd-modules-load.service sysinit.target
After=-.mount var.mount
Wants=var.mount
ConditionPathExists=/var/lib/modules/$PI_KERNEL_VERSION

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/mkdir -p /run/pi5-modules-overlay/upper /run/pi5-modules-overlay/work
ExecStart=/bin/mount -t overlay overlay -o lowerdir=/var/lib/modules:/usr/lib/modules,upperdir=/run/pi5-modules-overlay/upper,workdir=/run/pi5-modules-overlay/work /usr/lib/modules
ExecStart=/sbin/depmod -a $PI_KERNEL_VERSION

[Install]
WantedBy=sysinit.target
EOF
    mkdir -p "$ROOTFS/etc/systemd/system/sysinit.target.wants"
    ln -sf ../pi5-modules-overlay.service "$ROOTFS/etc/systemd/system/sysinit.target.wants/pi5-modules-overlay.service"
    
    # Create binfmt setup service (loads binfmt_misc module and registers box64)
    cat > "$ROOTFS/etc/systemd/system/pi5-binfmt-setup.service" << EOF
[Unit]
Description=Load binfmt_misc and register box64 for Pi5
DefaultDependencies=no
After=pi5-modules-overlay.service local-fs.target
Before=basic.target
Requires=pi5-modules-overlay.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/modprobe binfmt_misc
ExecStart=/bin/mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
ExecStart=/usr/lib/systemd/systemd-binfmt

[Install]
WantedBy=basic.target
EOF
    mkdir -p "$ROOTFS/etc/systemd/system/basic.target.wants"
    ln -sf ../pi5-binfmt-setup.service "$ROOTFS/etc/systemd/system/basic.target.wants/pi5-binfmt-setup.service"
else
    echo "Traditional rootfs - installing modules to /usr/lib/modules"
    mkdir -p "$ROOTFS/usr/lib/modules"
    cp -a "$KERNEL_EXTRACT/usr/lib/modules/$PI_KERNEL_VERSION" "$ROOTFS/usr/lib/modules/"
fi

# Mask services that don't work on Pi 5
mkdir -p "$ROOTFS/etc/systemd/system"
# akmods is for NVIDIA kernel module building - not applicable to Pi
ln -sf /dev/null "$ROOTFS/etc/systemd/system/akmods-keygen@akmods-keygen.service"
# systemd-binfmt races with our pi5-binfmt-setup.service - mask it since we handle binfmt ourselves
ln -sf /dev/null "$ROOTFS/etc/systemd/system/systemd-binfmt.service"

# Install box64-rpi5 (the base image has box64-sd888 which doesn't work on Pi 5's Cortex-A76)
echo "Installing box64-rpi5..."
BOX64_RPI5_CACHE="$CACHE_DIR/box64-rpi5"
if [ ! -f "$BOX64_RPI5_CACHE/usr/bin/box64.rpi5" ]; then
    mkdir -p "$BOX64_RPI5_CACHE"
    # Download from Fedora aarch64 repo (host may be x86_64)
    BOX64_URL="https://download.fedoraproject.org/pub/fedora/linux/releases/42/Everything/aarch64/os/Packages/b/"
    BOX64_RPM=$(curl -sL "$BOX64_URL" | grep -oP 'box64-rpi5-[^"]+\.rpm' | head -1)
    if [ -n "$BOX64_RPM" ]; then
        wget -q -O "$BOX64_RPI5_CACHE/$BOX64_RPM" "${BOX64_URL}${BOX64_RPM}" || true
    fi
    if [ -f "$BOX64_RPI5_CACHE"/box64-rpi5*.rpm ]; then
        (cd "$BOX64_RPI5_CACHE" && rpm2cpio box64-rpi5*.rpm | cpio -idm 2>/dev/null)
    fi
fi
if [ -f "$BOX64_RPI5_CACHE/usr/bin/box64.rpi5" ]; then
    # For ostree, we can't modify /usr, so install to /var and update alternatives
    OSTREE_VAR="$ROOT_MOUNT/ostree/deploy/default/var"
    cp "$BOX64_RPI5_CACHE/usr/bin/box64.rpi5" "$OSTREE_VAR/lib/box64.rpi5"
    chmod +x "$OSTREE_VAR/lib/box64.rpi5"
    # Update alternatives symlink to point to rpi5 version
    mkdir -p "$ROOTFS/etc/alternatives"
    ln -sf /var/lib/box64.rpi5 "$ROOTFS/etc/alternatives/box64"
    echo "box64-rpi5 installed"
else
    echo "Warning: Could not download box64-rpi5 package"
fi

# ==============================
# Custom gamescope for Pi 5
# (V3D/VC4 split-GPU dmabuf support from Ericky14/gamescope pi5 branch)
# ==============================
GAMESCOPE_BINARY="${SCRIPT_DIR}/build-cache/gamescope-pi5/gamescope"
if [ -f "$GAMESCOPE_BINARY" ]; then
    echo "Installing custom Pi 5 gamescope binary..."
    cp "$GAMESCOPE_BINARY" "$ROOTFS/usr/bin/gamescope"
    chmod 755 "$ROOTFS/usr/bin/gamescope"
    echo "Custom gamescope installed to /usr/bin/gamescope"
else
    echo "Warning: Custom gamescope binary not found at ${GAMESCOPE_BINARY}"
    echo "  The stock gamescope will be used (may not work on Pi 5)."
    echo "  To build: ./arm/pi5/build-gamescope.sh"
    echo "  Or copy a pre-built binary to: ${GAMESCOPE_BINARY}"
fi

# Set empty root password
[ -f "$ROOTFS/etc/shadow" ] && sed -i 's/^root:[^:]*:/root::/' "$ROOTFS/etc/shadow"

# Create playtron user if not exists
if ! grep -q "^playtron:" "$ROOTFS/etc/passwd" 2>/dev/null; then
    echo "Creating playtron user..."
    chroot "$ROOTFS" useradd -m -G wheel,video,render,input -s /bin/bash playtron 2>/dev/null || true
    echo "playtron:playtron" | chroot "$ROOTFS" chpasswd 2>/dev/null || true
fi

# Console autologin to playtron user
mkdir -p "$ROOTFS/etc/systemd/system/getty@tty1.service.d"
cat > "$ROOTFS/etc/systemd/system/getty@tty1.service.d/autologin.conf" << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin playtron --noclear %I $TERM
EOF

# Disable SDDM/graphical target - boot to console
mkdir -p "$ROOTFS/etc/systemd/system"
ln -sf /usr/lib/systemd/system/multi-user.target "$ROOTFS/etc/systemd/system/default.target" 2>/dev/null || true

# Cleanup temporary mounts
sync
umount "$EFI_MOUNT"
rmdir "$EFI_MOUNT"
EFI_MOUNT=""

# Fix FAT dirty bit
fsck.fat -a "/dev/mapper/$EFI_DEV" 2>/dev/null || true

umount "$ROOT_MOUNT"
rmdir "$ROOT_MOUNT"
ROOT_MOUNT=""

kpartx -d "$DISK_IMAGE"
KPARTX_OUT=""

# Resolve path for cleaner output
DISK_IMAGE_RESOLVED="$(realpath "$DISK_IMAGE")"

echo ""
echo "Pi 5 customization complete (minimal console boot): $DISK_IMAGE_RESOLVED"
echo "Write to SD card with: sudo dd if=$DISK_IMAGE_RESOLVED of=/dev/sdX bs=4M status=progress"
echo ""
echo "After boot:"
echo "  - Auto-login as 'playtron' user"
