#!/bin/bash

set -e -x

GIT_COMMIT="f63771d21806aefd93364506bb9087f2f4961609"

mkdir -p /usr/src/hid-msi-claw/
cd /usr/src/hid-msi-claw/
git init
git remote add origin https://github.com/NeroReflex/hid-msi-claw-dkms.git
git fetch origin "${GIT_COMMIT}"
git checkout "${GIT_COMMIT}"
TARGET=$(basename "$(find /lib/modules -mindepth 1 -maxdepth 1 | tail -n 1)")
export TARGET
make modules
make install
