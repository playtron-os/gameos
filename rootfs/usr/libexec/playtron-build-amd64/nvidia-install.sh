#!/bin/bash

set -e -x

# Install Nvidia
${CMD_INSTALL} \
  akmod-nvidia \
  gcc-c++ \
  nvidia-driver \
  nvidia-driver-NvFBCOpenGL

${CMD_INSTALL} nvidia-driver-libs.i686

# Build the Nvidia kernel modules for every installed kernel.
# `pam_limits.so` is temporarily disabled because it fails inside the build container.
cp -r /etc/pam.d /etc/pam.d.bak
sed -i -r 's/^(session\s+required\s+pam_limits.so)/#\1/' /etc/pam.d/*
mkdir -p /run/akmods
for k in $(ls -1 /usr/src/kernels); do
  akmods --force --kernels "${k}" --kmod "nvidia" || exit 1
  ls /var/cache/akmods/nvidia/*.failed.log > /dev/null 2>&1 && cat /var/cache/akmods/nvidia/*.failed.log || true
  ls /usr/lib/modules/"${k}"/extra/nvidia/nvidia.ko.xz || exit 1
done
rm -rf /run/akmods
rm -rf /etc/pam.d
mv /etc/pam.d.bak /etc/pam.d
