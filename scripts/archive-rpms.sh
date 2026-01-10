#!/bin/bash

WORKING_DIR="$(mktemp -d)"
cd "${WORKING_DIR}" || exit 1

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
      "nvidia-driver-libs.i686"
      "valve-firmware"
    )
elif [ "${ARCH}" == aarch64 ]; then
    package_names+=(
      "box64-sd888"
      "box64-binfmts"
      "box64-data"
      "python3-edl"
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
  "nvidia-driver-cuda-libs"
  "nvidia-driver-libs"
  "nvidia-driver-kmod-common"
  "nvidia-driver-modprobe"
  "nvidia-driver"
)

# RPM Fusion Steam https://mirrors.rpmfusion.org/metalink?repo=nonfree-fedora-steam-$releasever&arch=x86_64
package_names+=(
  "steam-devices"
)
## This allows us to get the Steam package used for both x86 and Arm builds.
curl --location --remote-name "$(repoquery --location "$(rpm -q steam.i686)" | tail -n 1)" --output-dir "${WORKING_DIR}"

for package_name in "${package_names[@]}"; do
    # Includes the version in the name.
    package_name_installed="$(rpm -q "${package_name}")"
    if ! dnf download "${package_name_installed}"; then
        echo "Failed to download ${package_name_installed}"
        rm -r -f "${WORKING_DIR}"
        exit 1
    fi
done

createrepo "${WORKING_DIR}"

echo "Packages have been downloaded to: ${WORKING_DIR}"
