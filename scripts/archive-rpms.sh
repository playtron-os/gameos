#!/bin/bash

set -e -x

if [ -z "${1}" ]; then
    echo "ERROR: missing required tag argument"
    exit 1
fi

WORKING_DIR="/output/repo-archive-${1}"
rm -r -f "${WORKING_DIR}"
mkdir "${WORKING_DIR}"
cd "${WORKING_DIR}"

package_names=()

# Miscellaneous architecture-specific packages.
ARCH="$(uname --machine)"
if [ "${ARCH}" == x86_64 ]; then
    package_names+=(
      "kernel"
      "kernel-core"
      "kernel-devel"
      "kernel-devel-matched"
      "kernel-headers"
      "kernel-modules"
      "libpact"
      "libplaytron"
      "mesa-dri-drivers.i686"
      "mesa-filesystem.i686"
      "mesa-libEGL.i686"
      "mesa-libGL.i686"
      "mesa-libgbm.i686"
      "mesa-vulkan-drivers.i686"
      "nvidia-driver-libs.i686"
      "steam-devices"
      "valve-firmware"
    )
elif [ "${ARCH}" == aarch64 ]; then
    package_names+=(
      "box64-sd888"
      "box64-binfmts"
      "box64-data"
    )
fi

# Playtron Gaming https://copr.fedorainfracloud.org/coprs/playtron/gaming/packages/
# InputPlumber https://download.copr.fedorainfracloud.org/results/shadowblip/InputPlumber/
package_names+=(
  "gamescope-session"
  "gamescope-session-playtron"
  "inputplumber"
  "legendary"
  "mangohud"
  "mesa-dri-drivers"
  "mesa-filesystem"
  "mesa-libEGL"
  "mesa-libGL"
  "mesa-libgbm"
  "mesa-vulkan-drivers"
  "reaper"
  "tzupdate"
  "udev-media-automount"
  "xdg-desktop-portal-openuri"
)

# Playtron App https://playtron-dev2-global-os-public.s3.us-west-2.amazonaws.com/repos/playtron-app/$basearch/
package_names+=(
  "gamescope-dbus"
  "grid"
  "playserve"
  "playtron-plugin-local"
  "plugin-egs"
  "plugin-gog"
  "powerstation"
  "SteamBus"
)

# negativo17 NVIDIA https://negativo17.org/repos/nvidia/fedora-$releasever/$basearch/
package_names+=(
  "akmod-nvidia"
  "libnvidia-cfg"
  "libnvidia-fbc"
  "libnvidia-gpucomp"
  "libnvidia-ml"
  "nvidia-driver"
  "nvidia-driver-cuda-libs"
  "nvidia-driver-libs"
  "nvidia-kmod-common"
  "nvidia-modprobe"
)

# RPM Fusion Steam https://mirrors.rpmfusion.org/metalink?repo=nonfree-fedora-steam-$releasever&arch=x86_64
## This allows us to get the Steam package used for both x86 and Arm builds.
dnf -y install repoquery
curl --location --remote-name "$(repoquery --location "$(rpm -q steam.i686)" | tail -n 1)" --output-dir "${WORKING_DIR}"

for package_name in "${package_names[@]}"; do
    # Includes the version in the name.
    # If both the x86_64 and i686 packages are installed, the first package listed is x86_64.
    package_name_installed="$(rpm -q "${package_name}" | head -n 1)"
    if ! dnf download "${package_name_installed}"; then
        echo "Failed to download ${package_name_installed}"
        rm -r -f "${WORKING_DIR}"
        exit 1
    fi
done

dnf -y install createrepo_c
createrepo "${WORKING_DIR}"

echo "Packages have been downloaded to: ${WORKING_DIR}"
