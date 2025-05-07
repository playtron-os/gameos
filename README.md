# Playtron GameOS

Table of Contents:
- [Introduction](#introduction)
- [Minimum Hardware Requirements](#minimum-hardware-requirements)
- [Sideloading Games](#sideloading-games)
- [Build](#build)
- [Linux Developer Tips](#linux-developer-tips)

## Introduction

Turn your PC into a game console. GameOS has native integration with Epic Games Store, GOG.com, and Steam. Your library of games is accessible via a simple gamer-focused interface.

Read more about Playtron GameOS on our official [website](https://www.playtron.one/).

## Minimum Hardware Requirements

- CPU
    - x86
        - AMD Ryzen or Intel 6th Gen Kaby Lake
- GPU
    - AMD Navi
        - For the best results, we recommend using an AMD GPU.
    - Intel Xe
    - NVIDIA Turing

## Sideloading Games

Local games can be copied over to GameOS and integrated using the [local](https://github.com/playtron-os/plugin-local) plugin. It is installed by default as of GameOS Beta 1.

## Build

Install the required build dependencies.

Fedora Atomic Desktop:

```
$ sudo rpm-ostree install \
    go-task \
    qemu-kvm \
    virt-install \
    virt-manager
```

Fedora Workstation:

```
$ sudo dnf install \
    go-task \
    qemu-kvm \
    rpm-ostree \
    virt-install \
    virt-manager
```

Enable and start the `libvirtd` service.

```
$ sudo systemctl enable --now libvirtd
```

Define a container image tag.

```
$ export TAG=replace-me
```

Build an unstable development container image. Alternatively, build a stable container image based on the previous release.

```
$ go-task container-image:build:unstable
```

```
$ go-task container-image:build:stable
```

Optionally authenticate to a container registry.

```
$ export REGISTRY=ghcr.io
$ export PROJECT=playtron-os
$ export IMAGE=playtron-os
$ export REGISTRY_TOKEN="replace-me"
$ go-task container-image:auth
```

Push the image to a container registry and either create a `:testing` tag or a `:latest` tag automatically.

```
$ go-task container-image:push
```

```
$ go-task container-image:release
```

Then build the raw operating system image. Use Virtual Machine Manager (`virt-manager`) to check the installation progress of the `playtron-os` virtual machine.

```
$ sudo -E go-task disk-image:kickstart
```

## Linux Developer Tips

Playtron GameOS container images are published to the GitHub Container Registry (GHCR). These can be found [here](https://github.com/orgs/playtron-os/packages/container/package/playtron-os) at the GitHub organization level (not the GitHub repository level).

On an existing Fedora Atomic Desktop, it is possible to switch to Playtron GameOS.

```
$ sudo bootc switch ghcr.io/playtron-os/playtron-os:latest
```

The default user account is `playtron` with the password `playtron`. It can be accessed by enabling SSH in the Developer page. The IP address will also be listed there. Alternatively, open up a TTY console by pressing `CTRL`, `ALT`, and `F3` at the same time.

```
Settings > Developer > Enable > Enable SSH Access: On
```

```
$ ssh -l playtron $IP_ADDRESS
```

This user has elevated privileges via the use of `sudo`.

```
$ sudo whoami
```

There is no password for the `root` user account. Set one to help with troubleshooting boot issues.

```
$ sudo passwd root
```

Switch to a minimal Weston desktop environment.

```
$ sudo playtronos-session-select dev
```

Switch back to the Playtron experience.

```
$ sudo playtronos-session-select user
```

Enable Flathub.

```
$ flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
```

Enable LanCache support for Epic Games Store. Steam already supports LanCache. GOG.com does not support LanCache.

```
$ crudini --set ~/.config/legendary/config.ini Legendary disable_https true
```

Create and use a container for development purposes.

```
$ distrobox create --init --additional-packages systemd --image fedora:41 --pull --name fedora41
$ distrobox enter fedora41
```

Install a full desktop environment and other additional packages.

```
$ sudo bootc image copy-to-storage
$ nano Containerfile
FROM localhost/bootc
RUN dnf5 group install -y kde-desktop && echo -e '[Autologin]\nSession=plasma' > /etc/sddm.conf.d/60-playtron-session-override.conf
RUN dnf5 install -y firefox
RUN dnf5 clean all && bootc container lint
$ sudo podman build --tag desktop .
$ sudo bootc switch --transport containers-storage localhost/desktop
```
