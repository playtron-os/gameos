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
  kernel \
  kernel-core \
  kernel-devel \
  kernel-devel-matched \
  kernel-headers \
  kernel-modules
dnf versionlock add \
  kernel \
  kernel-core \
  kernel-devel \
  kernel-devel-matched \
  kernel-headers \
  kernel-modules
