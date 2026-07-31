#!/bin/bash

set -e -x

# Stock alsa-ucm already ships the Glymur UCM profiles
# (/usr/share/alsa/ucm2/Qualcomm/glymur/ and conf.d/glymur/GLYMUR-CRD.conf), so nothing needs to be
# fetched or built. ALSA picks a profile by DMI string, though, and the Glymur reference boards
# report several different ones depending on BIOS revision -- none of which is "GLYMUR-CRD".
# Point each known spelling at the shipped profile.
UCM_DIR=/usr/share/alsa/ucm2/conf.d/glymur

if [ ! -f "${UCM_DIR}/GLYMUR-CRD.conf" ]; then
  echo "ERROR: ${UCM_DIR}/GLYMUR-CRD.conf is missing; alsa-ucm no longer ships the Glymur profile" >&2
  exit 1
fi

for dmi in \
  LENOVO-INVALID-INVALID-LNVNB161216 \
  HUMAIN-HorizonUltraX-HUMAINHorizonUltraX \
  HUMAIN-INVALID-INVALID-HorizonUltraX \
  HUMAIN-HorizonUltra-HUMAINHorizonUltra; do
  ln --symbolic --force GLYMUR-CRD.conf "${UCM_DIR}/${dmi}.conf"
done
