# Playtron GameOS

Table of Contents:
- [Introduction](#introduction)
- [Minimum Hardware Requirements](#minimum-hardware-requirements)
- [Game Compatibility](#game-compatibility)
- [Sideloading Games](#sideloading-games)
- [Build](#build)
- [Linux Developer Tips](#linux-developer-tips)

## Introduction

Turn your PC into a game console. Playtron GameOS has native integration with Epic Games Store, GOG.com, and Steam. Your library of games is accessible via a simple gamer-focused interface.

Read more about Playtron on [our official website](https://www.playtron.one/).

[Download Playtron GameOS here](https://www.playtron.one/game-os#download-playtron-os).

## Minimum Hardware Requirements

- CPU
    - x86
        - AMD Ryzen or Intel 6th Gen Kaby Lake
- GPU
    - AMD Navi
        - For the best results, we recommend using an AMD GPU.
    - Intel Xe
    - NVIDIA Turing

Devices tested on Playtron GameOS are reported in [this document](DEVICES.md).

## Game Compatibility

Most games are expected to work. For problematic games, you can help our community by using [GameLAB](https://github.com/playtron-os/gamelab) to create custom launch configurations and/or controller configurations. Our team will work to get these fixes upstream into [umu-protonfixes](https://github.com/Open-Wine-Components/umu-protonfixes) for everyone to benefit. Full guides on how to use GameLAB can be found [here](https://www.playtron.one/contribute).

## Sideloading Games

Local games can be copied over to Playtron GameOS and integrated using the [local](https://github.com/playtron-os/plugin-local) plugin.

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

Default Linux user account credentials:

- Username: `playtron`
- Password: `playtron`

Developers can access a terminal two different ways:

- Enable remote SSH access.
    - Settings > Advanced > Remote Access: On
    - Settings > Internet > Registered Wi-Fi networks > (select the connected Wi-Fi network and take note of the "IP Address")
    ```
    $ ssh -l playtron $IP_ADDRESS
    ```
- Or open a TTY console.
    - Connect a keyboard and then press `CTRL`, `ALT`, and `F3` at the same time.

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
$ distrobox create --init --additional-packages systemd --image fedora:42 --pull --name fedora42
$ distrobox enter fedora42
```
