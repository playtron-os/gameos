#!/bin/bash

set -e -x

dnf install -y \
  mesa-dri-drivers.x86_64 \
  mesa-filesystem.x86_64 \
  mesa-libEGL.x86_64 \
  mesa-libgbm.x86_64 \
  mesa-libGL.x86_64 \
  mesa-vulkan-drivers.x86_64 \
  mesa-dri-drivers.i686 \
  mesa-filesystem.i686 \
  mesa-libEGL.i686 \
  mesa-libgbm.i686 \
  mesa-libGL.i686 \
  mesa-vulkan-drivers.i686
