#!/usr/bin/env bash
#
# Build a Glymur / Snapdragon X2 Elite kernel RPM from Qualcomm's qcom-next tree.
#
# WHY THIS EXISTS
#   Playtron's shipping aarch64 kernels are built from https://github.com/qualcomm-linux/kernel
#   (branch qcom-next). Its weekly snapshot tags carry the out-of-tree Glymur device tree -- GPU,
#   GMU, gpucc, sound card, q6apm, soundwire, fastrpc, adsp/cdsp -- that mainline does not get
#   until 7.3. Mainline builds of the same version boot to a display with NO GPU and NO audio, so
#   the tree matters more than the version number.
#
# WHERE TO RUN IT
#   On an aarch64 host with podman. The Glymur CRD itself is ideal (18 cores, 30 GiB RAM) and
#   avoids cross-compiling entirely. It has no toolchain and a read-only /usr, hence the container.
#
#     scp build-glymur-kernel.sh playtron@<crd>:~/
#     ssh playtron@<crd> 'sudo ~/build-glymur-kernel.sh'
#
#   Takes roughly 30-45 minutes on the CRD. Output RPMs land in $WORKDIR.
#

set -euo pipefail

# ---------------------------------------------------------------------------- tunables

TAG="${TAG:-qcom-next-7.2-rc3-20260722}"
WORKDIR="${WORKDIR:-/var/home/playtron/kbuild}"
BUILDER_IMAGE="${BUILDER_IMAGE:-docker.io/library/fedora:43}"
JOBS="${JOBS:-$(nproc)}"

# Base .config. Defaults to the running kernel's, which is the right choice on the CRD: it is a
# known-good config for this board and already enables every driver GameOS needs. Starting from a
# vendor config instead means silently inheriting whatever they stripped out.
BASE_CONFIG="${BASE_CONFIG:-/proc/config.gz}"

REPO_URL="https://github.com/qualcomm-linux/kernel.git"

# ---------------------------------------------------------------------------- preflight

command -v podman >/dev/null || { echo "podman is required" >&2; exit 1; }

mkdir -p "$WORKDIR"
cd "$WORKDIR"

if [ ! -f "$WORKDIR/base.config" ]; then
  case "$BASE_CONFIG" in
    *.gz) zcat "$BASE_CONFIG" > "$WORKDIR/base.config" ;;
    *)    cp   "$BASE_CONFIG"   "$WORKDIR/base.config" ;;
  esac
fi
echo "base config: $(wc -l < "$WORKDIR/base.config") lines (from $BASE_CONFIG)"

avail=$(df -BG --output=avail "$WORKDIR" | tail -1 | tr -dc '0-9')
[ "${avail:-0}" -ge 40 ] || { echo "need >=40G free in $WORKDIR, have ${avail}G" >&2; exit 1; }

# ---------------------------------------------------------------------------- container script

cat > "$WORKDIR/_build-inner.sh" <<'INNER'
#!/bin/bash
set -e -x

# Every one of these was discovered by a failed build. Keep the list intact:
#   hostname                      scripts/package/mkspec calls it
#   elfutils-devel, openssl       rpmbuild BuildRequires (openssl the BINARY, not just -devel)
#   dwarves                       pahole, for BTF generation
dnf install -y --setopt=install_weak_deps=false \
  gcc make flex bison bc elfutils-libelf-devel elfutils-devel openssl-devel openssl \
  rpm-build git dwarves perl python3 python3-devel diffutils findutils xz zstd kmod \
  tar gawk cpio hostname rsync bzip2 gzip which

cd /work
if [ ! -d linux ]; then
  git clone --depth 1 --branch "$TAG" "$REPO_URL" linux
fi
cd linux
git log -1 --format="HEAD: %H %s"

# --- device tree fix ---------------------------------------------------------------------------
#
# qcom-next 7.2 enables usb_0/usb_1 on the CRD but sets no dr_mode on either, so both USB-C ports
# default to OTG and wait for a Type-C role switch to make them hosts. That never happens on this
# board -- /sys/class/typec is empty, the PD stack never enumerates -- so the ports stay in
# peripheral mode, no xHCI child is created, and nothing plugged into them appears. If you boot
# from a USB disk, as the CRD does, the root device never shows up and you land in the dracut
# emergency shell.
#
# Only usb_hs and usb_mp carry dr_mode = "host" in glymur.dtsi, and those are exactly the two
# controllers that came up. The 7.0 kernel's DTB sets dr_mode = "host" on usb@a600000, so this
# restores the behaviour that works rather than inventing one.
#
# Appended rather than edited in place: later property assignments win in DT, so this overrides
# whatever the included files set, and stays correct if upstream adds its own dr_mode later.
DTSI=arch/arm64/boot/dts/qcom/glymur-crd.dtsi
if ! grep -q 'PLAYTRON: force USB-C ports to host mode' "$DTSI"; then
  cat >> "$DTSI" <<'DTS'

/* PLAYTRON: force USB-C ports to host mode -- see build-glymur-kernel.sh.
 * Without this the CRD cannot boot from a USB disk. */
&usb_0 {
	dr_mode = "host";
};

&usb_1 {
	dr_mode = "host";
};
DTS
fi

cp /work/base.config .config

# --- config fixes -----------------------------------------------------------------------------
#
# DRM_WERROR: qcom-next is an -rc tree with in-flight code. At 7.2-rc3 it fails to build
# dp_mst_drm.o because dpu_encoder.h uses struct msm_display_topology in a parameter list without
# a forward declaration. Harmless at runtime, fatal with warnings-as-errors. This is a
# developer-only option and has no business in a product build.
./scripts/config --disable DRM_WERROR
./scripts/config --disable WERROR

# QCOM_PDC is an interrupt controller and MUST be built in -- 10 nodes in glymur.dtsi route
# interrupts through &pdc (22 references in total, nearly all interrupts-extended), including PCIe. In 7.2 it gained "depends on QCOM_AOSS_QMP", and because
# AOSS_QMP is modular, `make olddefconfig` silently demoted PDC from =y to =m when migrating a 7.0
# config forward. A built-in PCIe controller probing against a not-yet-loaded modular irqchip hangs:
# the boot dies in qcom_pcie_driver_init and never returns, with no console output past that point.
./scripts/config --enable  QCOM_AOSS_QMP
./scripts/config --enable  QCOM_PDC

# Controllers + hidraw. Vendor configs routinely drop these; a gaming OS cannot ship without them.
# InputPlumber needs hidraw, and so does Wine's winebus backend for gamepads under Proton.
./scripts/config --enable  HIDRAW
./scripts/config --module  HID_PLAYSTATION
./scripts/config --module  HID_NINTENDO
./scripts/config --module  HID_STEAM
./scripts/config --module  HID_SONY
./scripts/config --module  JOYSTICK_XPAD
./scripts/config --module  INPUT_JOYDEV
./scripts/config --module  INPUT_UINPUT
./scripts/config --module  UHID

make olddefconfig

echo "=== CONFIG CHECK ==="
for o in QCOM_PDC QCOM_AOSS_QMP HIDRAW HID_PLAYSTATION HID_NINTENDO HID_STEAM HID_SONY \
         JOYSTICK_XPAD INPUT_JOYDEV INPUT_UINPUT UHID DRM_MSM DRM_MSM_DP SND_SOC_X1E80100 \
         ATH12K QCOM_Q6V5_PAS PCIE_QCOM DRM_WERROR; do
  printf "  %-20s %s\n" "$o" "$(grep -E "^CONFIG_$o=" .config || echo 'not set')"
done

# QCOM_PDC as a module is a boot hang, not a warning. Fail here rather than after a reboot.
if ! grep -q "^CONFIG_QCOM_PDC=y" .config; then
  echo "FATAL: CONFIG_QCOM_PDC is not built in -- this kernel will hang in qcom_pcie_driver_init" >&2
  exit 1
fi

make -j"$JOBS" binrpm-pkg

# binrpm-pkg writes into an IN-TREE rpmbuild/ ($objtree/rpmbuild), not ~/rpmbuild. Check both, but
# only search directories that exist -- passing find a missing path makes it exit non-zero, which
# under `set -e` kills this script before it reports success.
for d in /work/linux/rpmbuild/RPMS /root/rpmbuild/RPMS; do
  [ -d "$d" ] && find "$d" -name '*.rpm' -exec cp -v {} /work/ \;
done
ls /work/*.rpm >/dev/null 2>&1 || { echo "no RPMs were produced" >&2; exit 1; }
echo "BUILD COMPLETE"
INNER
chmod +x "$WORKDIR/_build-inner.sh"

# ---------------------------------------------------------------------------- build

echo "building $TAG with $JOBS jobs -> $WORKDIR"
podman run --rm --name glymur-kbuild \
  -v "$WORKDIR:/work:z" -w /work \
  -e TAG="$TAG" -e REPO_URL="$REPO_URL" -e JOBS="$JOBS" \
  "$BUILDER_IMAGE" /work/_build-inner.sh 2>&1 | tee "$WORKDIR/build.log"

# ---------------------------------------------------------------------------- verify

# Newest by mtime, not alphabetical: rebuilds accumulate in $WORKDIR and `-4` sorts before `-5`,
# so a naive `head -1` verifies the PREVIOUS build and reports a stale result.
KRPM=$(ls -1t "$WORKDIR"/kernel-*.rpm 2>/dev/null | grep -v -- '-devel\|-headers' | head -1)
[ -n "$KRPM" ] || { echo "VERIFY: no kernel RPM produced" >&2; exit 1; }
echo
echo "=== verifying $(basename "$KRPM") ==="

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
rpm2cpio "$KRPM" | (cd "$tmp" && cpio -idm --quiet \
  './lib/modules/*/dtb/qcom/glymur-crd.dtb' \
  './lib/modules/*/kernel/drivers/gpu/drm/msm/msm.ko' \
  './lib/modules/*/modules.builtin' 2>/dev/null) || true

fail=0

dtb=$(find "$tmp" -name glymur-crd.dtb | head -1)
if [ -z "$dtb" ]; then
  echo "  FAIL  no glymur-crd.dtb in the RPM"; fail=1
else
  echo "  glymur-crd.dtb: $(stat -c %s "$dtb") bytes"
  for node in adreno gmu gpucc sndcard q6apm soundwire; do
    n=$(strings "$dtb" | grep -ic "$node" || true)
    if [ "$n" -eq 0 ]; then
      echo "  FAIL  device tree has no '$node' nodes (mainline DT? no GPU/audio)"; fail=1
    else
      printf "  ok    %-10s %s nodes\n" "$node" "$n"
    fi
  done
fi

# Both USB-C ports must be host-mode or the board cannot boot from a USB disk. Count the
# NUL-terminated "host" property values in the DTB directly -- `strings` runs adjacent text
# together, so grepping its output for an exact "host" line undercounts.
if [ -n "$dtb" ]; then
  hosts=$(python3 -c 'import sys; print(open(sys.argv[1],"rb").read().count(b"host\x00"))' "$dtb")
  if [ "$hosts" -lt 4 ]; then
    echo "  FAIL  only $hosts dr_mode=host USB nodes (want >=4) -- usb_0/usb_1 will not enumerate a boot disk"
    fail=1
  else
    echo "  ok    dr_mode=host on $hosts USB nodes"
  fi
fi

# The VM_BIND use-after-free that kills Xwayland under gamescope. 03084ea9 is
# 'ldp x3, x2, [x0, #0xe0]' -- the buggy argument pair. Its absence means the fix is in.
msm=$(find "$tmp" -name msm.ko | head -1)
if [ -n "$msm" ]; then
  if grep -qUaP '\x03\x08\x4e\xa9' "$msm"; then
    echo "  FAIL  msm.ko still has the VM_BIND bug (upstream 85042c2cd970 missing)"; fail=1
  else
    echo "  ok    msm.ko has the VM_BIND fix"
  fi
fi

# Collect the file lists ONCE, then match with here-strings.
#
# Do NOT pipe `rpm -qlp` into `grep -q`: grep exits at the first match and closes the pipe, rpm
# dies with SIGPIPE, and `set -o pipefail` turns that into a failed test -- so the check reports
# "missing" exactly when the module IS present. That bug marked all seven controllers absent in a
# kernel that shipped every one of them.
builtin=$(find "$tmp" -name modules.builtin | head -1)
modlist=$(rpm -qlp "$KRPM" 2>/dev/null || true)
[ -n "$builtin" ] && modlist="$modlist
$(cat "$builtin")"

for m in hid-playstation hid-nintendo hid-steam hid-sony xpad joydev uinput; do
  if grep -qE "/${m}\.ko" <<<"$modlist"; then
    printf "  ok    %-16s present\n" "$m"
  else
    echo "  FAIL  $m missing (neither module nor builtin)"; fail=1
  fi
done

echo
if [ "$fail" -ne 0 ]; then
  echo "VERIFICATION FAILED -- do not boot this kernel."
  exit 1
fi

cat <<EOF
VERIFICATION PASSED.

RPMs in $WORKDIR:
$(ls -1 "$WORKDIR"/*.rpm | sed 's/^/  /')

To test it WITHOUT risking the board (see gameos/GLYMUR-BRINGUP.md §3):

  sudo rpm -Uvh --oldpackage $WORKDIR/kernel-*.rpm
  sudo grub2-editenv - set saved_entry=<known-good-entry-id>   # e.g. ostree-1
  sudo grub2-editenv - set next_entry=<new-entry-id>           # boots ONCE
  sudo systemctl reboot

If it fails to boot, the next power cycle returns to saved_entry automatically.
Match /proc/cmdline's bootcsum against each loader entry's 'linux' line to identify
entry ids -- never assume the numbering.
EOF
