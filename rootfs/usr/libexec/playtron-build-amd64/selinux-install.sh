#!/bin/bash

set -e -x

echo "Setting SELinux to enforcing mode on x86..."

mkdir -p /usr/share/selinux/playtron-modules
cd /usr/share/selinux/playtron-modules/

checkmodule -M -m \
  -o dontaudit-powerprofiles_t-passwd_file_t.mod \
  dontaudit-powerprofiles_t-passwd_file_t.te
semodule_package \
  -o dontaudit-powerprofiles_t-passwd_file_t.pp \
  -m dontaudit-powerprofiles_t-passwd_file_t.mod

checkmodule -M -m \
  -o systemd_timedated_t-etc_t-lnk_file.mod \
  systemd_timedated_t-etc_t-lnk_file.te
semodule_package \
  -o systemd_timedated_t-etc_t-lnk_file.pp \
  -m systemd_timedated_t-etc_t-lnk_file.mod

semodule -i ./*.pp
rm -f ./*.mod ./*.pp

sed -E -i 's/SELINUX=.+/SELINUX=enforcing/g' /etc/sysconfig/selinux
