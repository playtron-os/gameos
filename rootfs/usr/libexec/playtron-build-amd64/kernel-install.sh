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
