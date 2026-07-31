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

dnf install -y --enablerepo=agentos \
  "kernel-7.2.0_rc3+-6.fc43" \
  "kernel-headers-7.2.0_rc3+-6.fc43"
dnf versionlock add \
  kernel \
  kernel-headers
