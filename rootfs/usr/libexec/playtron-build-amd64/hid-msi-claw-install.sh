#!/bin/bash

set -e -x

dnf5 -y install git
git clone --depth=1 https://github.com/NeroReflex/hid-msi-claw-dkms.git /usr/src/hid-msi-claw
cd /usr/src/hid-msi-claw
export TARGET
TARGET=$(find /lib/modules -mindepth 1 -maxdepth | tail -n 1)
make all
make install
