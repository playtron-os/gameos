#!/bin/bash

# Archive packages from:
# InputPlumber https://download.copr.fedorainfracloud.org/results/shadowblip/InputPlumber/
#TODO: negativo17 NVIDIA https://negativo17.org/repos/nvidia/fedora-$releasever/$basearch/
#TODO: Playtron App https://playtron-dev2-global-os-public.s3.us-west-2.amazonaws.com/repos/playtron-app/$basearch/
# Playtron Gaming https://copr.fedorainfracloud.org/coprs/playtron/gaming/packages/
#TODO: RPM Fusion Steam https://mirrors.rpmfusion.org/metalink?repo=nonfree-fedora-steam-$releasever&arch=x86_64

WORKING_DIR="$(mktemp -d)"
cd "${WORKING_DIR}"

#TODO: download "box64" and "python3-edl" for Arm only.
#TODO: download "valve-firmware" for x86 only.
#TODO: download all relevant "kernel*" packages.
#TODO: download all relevant "mesa*" packages.
for package_name in \
  gamescope-session \
  gamescope-session-playtron \
  inputplumber \
  legendary \
  mangohud \
  reaper \
  tzupdate \
  udev-media-automount \
  xdg-desktop-portal-openuri; do
    # Includes the version in the name.
    package_name_installed="$(rpm -q ${package_name})"
    if ! dnf download "${package_name_installed}"; then
        echo "Failed to download ${package_name_installed}"
        rm -r -f "${WORKING_DIR}"
        exit 1
    fi
done

createrepo "${WORKING_DIR}"

echo "Packages have been downloaded to: ${WORKING_DIR}"
