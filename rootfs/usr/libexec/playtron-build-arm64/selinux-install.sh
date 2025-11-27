#!/bin/bash

set -e -x

echo "Setting SELinux to permissive mode on Arm..."

rm -f \
  /usr/share/selinux/playtron-modules/dontaudit-powerprofiles_t-passwd_file_t.te \
  /usr/share/selinux/playtron-modules/systemd_timedated_t-etc_t-lnk_file.te \
  /usr/lib/systemd/system/restorecon-bootc.service \
  /usr/bin/restorecon-bootc

sed -i 's/enable restorecon-bootc.service/disable restorecon-bootc.service/g' /usr/lib/systemd/system-preset/50-playtron.preset

sed -E -i 's/SELINUX=.+/SELINUX=permissive/g' /etc/sysconfig/selinux
