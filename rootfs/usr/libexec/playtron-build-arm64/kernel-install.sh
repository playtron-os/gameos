#!/bin/bash

set -e -x

dnf remove -y \
  kernel \
  kernel-core \
  kernel-devel \
  kernel-devel-matched \
  kernel-headers \
  kernel-modules \
  kernel-modules-core

# Ensure we don't leave behind an old kernel directory
rm -rf /usr/lib/modules/*

dnf install -y \
  https://kojipkgs.fedoraproject.org//packages/kernel/6.16.3/200.fc42/aarch64/kernel-6.16.3-200.fc42.aarch64.rpm \
  https://kojipkgs.fedoraproject.org//packages/kernel/6.16.3/200.fc42/aarch64/kernel-core-6.16.3-200.fc42.aarch64.rpm \
  https://kojipkgs.fedoraproject.org//packages/kernel/6.16.3/200.fc42/aarch64/kernel-devel-6.16.3-200.fc42.aarch64.rpm \
  https://kojipkgs.fedoraproject.org//packages/kernel/6.16.3/200.fc42/aarch64/kernel-devel-matched-6.16.3-200.fc42.aarch64.rpm \
  https://kojipkgs.fedoraproject.org//packages/kernel-headers/6.16.2/200.fc42/aarch64/kernel-headers-6.16.2-200.fc42.aarch64.rpm \
  https://kojipkgs.fedoraproject.org//packages/kernel/6.16.3/200.fc42/aarch64/kernel-modules-6.16.3-200.fc42.aarch64.rpm \
  https://kojipkgs.fedoraproject.org//packages/kernel/6.16.3/200.fc42/aarch64/kernel-modules-core-6.16.3-200.fc42.aarch64.rpm \
  https://kojipkgs.fedoraproject.org//packages/kernel/6.16.3/200.fc42/aarch64/kernel-modules-extra-6.16.3-200.fc42.aarch64.rpm \
  https://kojipkgs.fedoraproject.org//packages/kernel/6.16.3/200.fc42/aarch64/kernel-modules-extra-matched-6.16.3-200.fc42.aarch64.rpm
dnf versionlock add \
  kernel \
  kernel-core \
  kernel-devel \
  kernel-devel-matched \
  kernel-headers \
  kernel-modules \
  kernel-modules-core \
  kernel-modules-extra \
  kernel-modules-extra-matched
