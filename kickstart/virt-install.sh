#!/bin/sh

sudo virt-install \
  --connect qemu:///system \
  --virt-type kvm --graphics spice --video vga\
  --name playtron-os \
  --os-variant fedora-unknown \
  --boot uefi \
  --vcpus 4 --ram 16384 \
  --disk=/var/lib/libvirt/images/playtron-os.img,bus=virtio,format=raw,size=12 \
  --location=https://archives.fedoraproject.org/pub/archive/fedora/linux/releases/41/Everything/x86_64/os/ \
  --initrd-inject ./playtron-os_kickstart.cfg \
  --extra-args="inst.ks=file:/playtron-os_kickstart.cfg net.ifnames=0 biosdevname=0" \
  --noreboot
