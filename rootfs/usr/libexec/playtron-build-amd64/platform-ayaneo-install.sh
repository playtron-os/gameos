#!/usr/bin/bash

set -e -x

GIT_COMMIT="9b2a602d1869b2b687c35845ab540012d54a933e"

curl -L "https://github.com/ShadowBlip/ayaneo-platform/archive/${GIT_COMMIT}.tar.gz" \
  -o /tmp/ayaneo-platform.tar.gz
mkdir -p /usr/src/platform-ayaneo
tar xvfz /tmp/ayaneo-platform.tar.gz --strip-components=1 -C /usr/src/platform-ayaneo

cd /usr/src/platform-ayaneo
export TARGET
TARGET="$(find /lib/modules -maxdepth 1 -printf '%P\n' | tail -n 1)"
make
zstd ayaneo-platform.ko
MOD_DEST_DIR="/lib/modules/${TARGET}/kernel/drivers/leds"
cp ./ayaneo-platform.ko.zst "${MOD_DEST_DIR}"
depmod -a "${TARGET}"
