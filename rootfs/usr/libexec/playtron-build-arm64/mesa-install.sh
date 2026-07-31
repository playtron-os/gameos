#!/bin/bash

set -e -x

MESA_VERSION=26.2.0-0.8.git79e16e7.fc43

dnf install -y --enablerepo=mesa-git \
  "mesa-dri-drivers-${MESA_VERSION}" \
  "mesa-filesystem-${MESA_VERSION}" \
  "mesa-libEGL-${MESA_VERSION}" \
  "mesa-libgbm-${MESA_VERSION}" \
  "mesa-libGL-${MESA_VERSION}" \
  "mesa-vulkan-drivers-${MESA_VERSION}"
