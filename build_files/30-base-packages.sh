#!/usr/bin/env bash
# Hardware and system packages: what a PC needs before a session can start. Every group says
# why it is in the image; weak dependencies are off so nothing else rides along.
#
#   30-base-packages.sh             install (during the image build)
#   30-base-packages.sh --list      print the installed package names, one per line
#   30-base-packages.sh --removed   print the removed package names, one per line
#
# tests/container/packages.sh uses the two list modes, so the lists here are the only copy.
set -euo pipefail

packages=(
    # Graphics. Mesa's GL, EGL and Vulkan drivers for AMD and Intel GPUs. gamescope does not
    # start without a Vulkan driver; llvmpipe from mesa-dri-drivers is what cage draws with in
    # a VM.
    mesa-dri-drivers
    mesa-vulkan-drivers
    vulkan-loader

    # GPU and CPU firmware. Already in the base image; listed so that a base image change
    # cannot drop them without the package test noticing.
    linux-firmware
    amd-gpu-firmware
    intel-gpu-firmware
    amd-ucode-firmware
    microcode_ctl

    # Audio. PipeWire with WirePlumber is the sound server, with its ALSA and PulseAudio
    # front ends for games. alsa-ucm and the SOF and codec firmware make the sound cards of
    # current laptops and mini PCs work, and rtkit gives PipeWire real-time priority so audio
    # does not crackle while a game loads the CPU.
    pipewire
    pipewire-alsa
    pipewire-pulseaudio
    wireplumber
    alsa-ucm
    alsa-sof-firmware
    intel-audio-firmware
    cirrus-audio-firmware
    rtkit

    # Network. NetworkManager handles wired connections out of the box; the Wi-Fi plugin, its
    # supplicant, the regulatory database and the firmware of the common Intel, Realtek,
    # MediaTek, Qualcomm Atheros and Broadcom chips are there so Wi-Fi works once it is set up.
    NetworkManager
    NetworkManager-wifi
    wpa_supplicant
    wireless-regdb
    iwlwifi-dvm-firmware
    iwlwifi-mvm-firmware
    iwlwifi-mld-firmware
    realtek-firmware
    mt7xxx-firmware
    atheros-firmware
    brcmfmac-firmware

    # Bluetooth, for wireless controllers and headsets.
    bluez

    # Controllers. udev rules that give the logged-in user access to the raw HID interfaces
    # of Steam, PlayStation, Switch and other controllers (rumble, gyro, Steam Input).
    steam-devices

    # Fonts. Adwaita Sans and Mono are libadwaita's interface fonts; Noto covers the scripts
    # they lack (game titles are in any language), CJK and emoji.
    adwaita-sans-fonts
    adwaita-mono-fonts
    google-noto-sans-vf-fonts
    google-noto-sans-cjk-vf-fonts
    google-noto-color-emoji-fonts

    # Locale. The base image has only C.UTF-8; GTK and games expect en_US.UTF-8 to exist.
    glibc-langpack-en
)

# Removed from the base image: the production image has no remote shell and no way to become
# root. 80-variant-dev.sh installs both again for the dev image.
removed=(
    openssh-server
    sudo
)

case "${1:-}" in
--list)
    printf '%s\n' "${packages[@]}"
    exit 0
    ;;
--removed)
    printf '%s\n' "${removed[@]}"
    exit 0
    ;;
esac

# dnf protects sudo from removal on a normal system; here its removal is the point.
dnf -y remove --setopt=protected_packages= "${removed[@]}"
dnf -y install --setopt=install_weak_deps=False "${packages[@]}"
