#!/bin/bash
# Raspberry Pi 5 disk image customization script
# This script customizes a generic ARM Fedora disk image for Pi 5 boot
# Sets up: gamescope session + SDDM autologin + Grid + SSH
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
# If a custom 4KB-page kernel was built, use it; otherwise fall back to pre-built RPi kernel
CUSTOM_KERNEL_DIR="$CACHE_DIR/kernel-4k"
if [ -f "$CUSTOM_KERNEL_DIR/.kernel-version" ]; then
    PI_KERNEL_VERSION="$(cat "$CUSTOM_KERNEL_DIR/.kernel-version")"
    KERNEL_EXTRACT="$CUSTOM_KERNEL_DIR"
    echo "Using custom 4KB-page kernel: $PI_KERNEL_VERSION"
else
    PI_KERNEL_VERSION="${PI_KERNEL_VERSION:-6.12.62+rpt-rpi-2712}"
    KERNEL_EXTRACT="$CACHE_DIR/modules-extracted"
    echo "Using pre-built RPi kernel: $PI_KERNEL_VERSION"
fi
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
MODULES_DIR="$KERNEL_EXTRACT/usr/lib/modules/$PI_KERNEL_VERSION"
[ -d "$MODULES_DIR" ] || { echo "ERROR: Kernel modules not found at $MODULES_DIR. Run 'task build-kernel:pi5' or 'task download:pi5'"; exit 1; }
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
# KERNEL_EXTRACT was set above (custom 4KB kernel or pre-built RPi kernel)
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

# Install box64 for Pi 5
# The base image ships box64-sd888 (0.4.0) which uses ARM instructions not available
# on Cortex-A76 → SIGILL. We cross-compile box64 0.4.0 with -DRPI5ARM64=1 instead.
echo "Installing box64 for Pi 5..."
BOX64_PI5_BINARY="$CACHE_DIR/box64-pi5/box64"
if [ -f "$BOX64_PI5_BINARY" ]; then
    # For ostree/composefs, /usr is read-only. Install to /var and update alternatives.
    OSTREE_VAR="$ROOT_MOUNT/ostree/deploy/default/var"
    cp "$BOX64_PI5_BINARY" "$OSTREE_VAR/lib/box64.pi5"
    chmod +x "$OSTREE_VAR/lib/box64.pi5"
    # Update alternatives symlink to point to pi5 version
    mkdir -p "$ROOTFS/etc/alternatives"
    ln -sf /var/lib/box64.pi5 "$ROOTFS/etc/alternatives/box64"
    echo "box64 Pi5 (cross-compiled 0.4.0) installed"
else
    echo "ERROR: box64 Pi5 binary not found at $BOX64_PI5_BINARY"
    echo "  Run 'task build-box64:pi5' first."
    exit 1
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

# Ensure playtron is in video/render/input/seat groups
# On ostree, usermod -aG may not work because groups live in /usr/lib/group
# We add overrides to /etc/group directly
# seat group (GID 973) is needed for seatd socket access
if ! grep -q "^seat:" "$ROOTFS/etc/group" 2>/dev/null; then
    echo "seat:x:973:playtron" >> "$ROOTFS/etc/group"
fi
for grp in "video:x:39" "render:x:105" "input:x:104"; do
    grp_name="${grp%%:*}"
    if ! grep -q "^${grp_name}:.*playtron" "$ROOTFS/etc/group" 2>/dev/null; then
        echo "${grp}:playtron" >> "$ROOTFS/etc/group"
    fi
done
echo "User groups configured"

# ==============================
# Pi5 overrides for config.toml defaults
# (config.toml is shared with installer builds - undo installer-specific settings)
# ==============================
echo "Applying Pi5 config overrides..."

# Boot into regular Grid (not installer mode)
cat > "$ROOTFS/etc/environment.d/playtron-installer.conf" << 'EOF'
GRID_INSTALL_MODE=0
EOF

# Re-enable resize-root-file-system (config.toml masks it with an empty file)
rm -f "$ROOTFS/etc/systemd/system/resize-root-file-system.service"

# Fix resize script for ext4 (Pi5 uses ext4 not btrfs)
# The stock script calls "btrfs filesystem resize max" which fails on ext4.
# Replace with a version that detects the filesystem type.
cat > "$ROOTFS/bin/resize-root-file-system.sh" << 'RESIZEOF'
#!/bin/bash
set -x

root_partition=$(mount | grep 'on / ' | awk '{print $1}')
overlay_detected="false"

if [ "${root_partition}" == "overlay" ] || [ "${root_partition}" == "composefs" ]; then
    root_partition=$(mount | grep 'on /var ' | awk '{print $1}')
    overlay_detected="true"
fi

root_partition_number=$(echo ${root_partition} | grep -o -P "[0-9]+$")

echo ${root_partition} | grep -q nvme
if [ $? -eq 0 ]; then
    root_device=$(echo ${root_partition} | grep -P -o "/dev/nvme[0-9]+n[0-9]+")
else
    echo ${root_partition} | grep -q mmcblk
    if [ $? -eq 0 ]; then
        root_device=$(echo ${root_partition} | grep -P -o "/dev/mmcblk[0-9]+")
    else
        root_device=$(echo ${root_partition} | sed s'/[0-9]//'g)
    fi
fi

growpart ${root_device} ${root_partition_number}

# Detect filesystem type and resize accordingly
fs_type=$(findmnt -n -o FSTYPE /var 2>/dev/null || findmnt -n -o FSTYPE / 2>/dev/null)
case "${fs_type}" in
    btrfs)
        if [ "${overlay_detected}" == "false" ]; then
            btrfs filesystem resize max /
        else
            btrfs filesystem resize max /var
        fi
        ;;
    ext4|ext3|ext2)
        resize2fs ${root_partition}
        ;;
    xfs)
        xfs_growfs /var 2>/dev/null || xfs_growfs /
        ;;
    *)
        echo "Unknown filesystem type: ${fs_type}, trying resize2fs"
        resize2fs ${root_partition} || btrfs filesystem resize max /var
        ;;
esac
RESIZEOF
chmod +x "$ROOTFS/bin/resize-root-file-system.sh"

# Re-enable media automount
rm -f "$ROOTFS/etc/udev/rules.d/99-media-automount.rules"

echo "Pi5 config overrides applied"

# ==============================
# Graphical session: SDDM + gamescope + Grid
# ==============================
echo "Configuring graphical session..."

# Enable graphical target (SDDM)
mkdir -p "$ROOTFS/etc/systemd/system"
ln -sf /usr/lib/systemd/system/graphical.target "$ROOTFS/etc/systemd/system/default.target" 2>/dev/null || true

# Enable SDDM service
mkdir -p "$ROOTFS/etc/systemd/system/display-manager.service.d"
ln -sf /usr/lib/systemd/system/sddm.service "$ROOTFS/etc/systemd/system/display-manager.service" 2>/dev/null || true

# SDDM autologin for playtron → gamescope session
mkdir -p "$ROOTFS/etc/sddm.conf.d"
cat > "$ROOTFS/etc/sddm.conf.d/autologin.conf" << 'EOF'
[Autologin]
Relogin=true
Session=gamescope-session-playtron.desktop
User=playtron
EOF

# Pi5 environment: Vulkan ICD and libseat backend (seatd for proper VT/seat management)
mkdir -p "$ROOTFS/etc/environment.d"
cat > "$ROOTFS/etc/environment.d/pi5-gamescope.conf" << 'EOF'
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/broadcom_icd.aarch64.json
LIBSEAT_BACKEND=seatd
EOF

# Gamescope session overrides for Pi5 (DRM backend, no switcherooctl)
# ORIENTATION="" overrides the device-quirks bug (empty SYS_ID matches AYANEO AIR trailing colon)
mkdir -p "$ROOTFS/etc/gamescope-session-plus/sessions.d"
cat > "$ROOTFS/etc/gamescope-session-plus/sessions.d/playtron" << 'EOF'
# Pi5 overrides for gamescope session
BACKEND=drm
ORIENTATION=""
OUTPUT_CONNECTOR=HDMI-A-1
SCREEN_WIDTH=1280
SCREEN_HEIGHT=720
INTERNAL_WIDTH=1280
INTERNAL_HEIGHT=720
CLIENTCMD="grid"
CLIENTCMD="grid"
EOF

# Enable seatd for VT-based seat management (replaces LIBSEAT_BACKEND=noop)
# seatd allows gamescope to properly manage DRM devices and VT switching,
# working around the logind session scope mismatch from SDDM→systemctl --user
mkdir -p "$ROOTFS/etc/systemd/system/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/seatd.service "$ROOTFS/etc/systemd/system/multi-user.target.wants/seatd.service" 2>/dev/null || true

# Enable SSH for remote access
ln -sf /usr/lib/systemd/system/sshd.service "$ROOTFS/etc/systemd/system/multi-user.target.wants/sshd.service" 2>/dev/null || true

# Pre-generate SSH host keys (ostree/composefs may have read-only /etc/ssh at first boot)
mkdir -p "$ROOTFS/etc/ssh"
if [ ! -f "$ROOTFS/etc/ssh/ssh_host_rsa_key" ]; then
    ssh-keygen -t rsa -f "$ROOTFS/etc/ssh/ssh_host_rsa_key" -N "" -q
    ssh-keygen -t ecdsa -f "$ROOTFS/etc/ssh/ssh_host_ecdsa_key" -N "" -q
    ssh-keygen -t ed25519 -f "$ROOTFS/etc/ssh/ssh_host_ed25519_key" -N "" -q
    echo "SSH host keys pre-generated"
fi

echo "Graphical session configured (SDDM → gamescope → Grid)"
echo "SSH enabled for remote access"

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
echo "Pi 5 customization complete: $DISK_IMAGE_RESOLVED"
echo "Write to SD card with: sudo dd if=$DISK_IMAGE_RESOLVED of=/dev/sdX bs=4M status=progress"
echo ""
echo "After boot:"
echo "  - SDDM auto-login as 'playtron' → gamescope session → Grid"
echo "  - SSH enabled: ssh playtron@<ip> (password: playtron)"
