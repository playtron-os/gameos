#!/bin/bash

set -e -x

dnf install -y \
  mesa-dri-drivers \
  mesa-filesystem \
  mesa-libEGL \
  mesa-libgbm \
  mesa-libGL \
  mesa-vulkan-drivers
