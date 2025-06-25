#!/bin/bash

set -x

# Example output: "/dev/mmcblk0p5" (SD card or eMMC), "/dev/nvme0n1p5" (NVMe), or "/dev/sda5" (SATA)
root_partition=$(mount | grep 'on / ' | awk '{print $1}')
overlay_detected="false"

# When using OCI and bootc builds (not rpm-ostree builds), the file system is overlayed sooner.
if [ "${root_partition}" == "overlay" ] || [ "${root_partition}" == "composefs" ]; then
    root_partition=$(mount | grep 'on /var ' | awk '{print $1}')
    overlay_detected="true"
fi

root_partition_number=$(echo ${root_partition} | grep -o -P "[0-9]+$")

echo ${root_partition} | grep -q nvme
if [ $? -eq 0 ]; then
    root_device=$(echo ${root_partition} | grep -P -o "/dev/nvme[0-9]+n[0-9]+")
else
    echo ${root_partition} | grep -q mmcblk
    if [ $? -eq 0 ]; then
        root_device=$(echo ${root_partition} | grep -P -o "/dev/mmcblk[0-9]+")
    else
        root_device=$(echo ${root_partition} | sed s'/[0-9]//'g)
    fi
 fi

growpart ${root_device} ${root_partition_number}

if [ "${overlay_detected}" == "false" ]; then
    btrfs filesystem resize max /
else
    btrfs filesystem resize max /var
fi
