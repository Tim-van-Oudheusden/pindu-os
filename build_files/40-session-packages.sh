#!/usr/bin/env bash
# Session packages: everything between the login and the launcher's window. Every group says
# why it is in the image; weak dependencies are off so no desktop environment rides along.
#
#   40-session-packages.sh          install (during the image build)
#   40-session-packages.sh --list   print the package names, one per line
set -euo pipefail

packages=(
    # Login. greetd logs the pindu user in on VT 1 without a display manager stack; its
    # SELinux module lets it start the session.
    greetd
    greetd-selinux

    # Compositors. gamescope on the DRM backend is the session; the launcher is an X11 client
    # on its Xwayland. cage is the fallback where gamescope cannot start (VMs, GPUs without
    # usable Vulkan).
    gamescope
    xorg-x11-server-Xwayland
    cage

    # Portals. The launcher and GTK use them for file dialogs and settings; the GTK backend
    # is selected for XDG_CURRENT_DESKTOP=gamescope by gamescope-portals.conf.
    xdg-desktop-portal
    xdg-desktop-portal-gtk

    # Settings and secrets. dconf stores GSettings (the launcher's and GTK's own, whose
    # schemas are in gsettings-desktop-schemas); gnome-keyring is the Secret Service provider
    # that keeps the launcher's SteamGridDB key.
    dconf
    gsettings-desktop-schemas
    gnome-keyring

    # Session plumbing. dbus-update-activation-environment hands the compositor's display to
    # D-Bus-activated services such as the portals.
    dbus-tools

    # Icons and cursors for GTK.
    adwaita-icon-theme

    # Media. GTK plays the launcher's animated Home background, a WebM file with VP9 video,
    # through GStreamer; the Matroska demuxer and the VP9 decoder are in plugins-good.
    gstreamer1-plugins-good
    # Hardware decoding of that background. plugins-bad-free has GStreamer's VA plug-in, whose
    # decoders (vavp9dec) outrank the software ones wherever the GPU decodes the format. Mesa's
    # VA driver for AMD comes with mesa-dri-drivers (30-base-packages.sh); the Intel one, for
    # Broadwell and later, is libva-intel-media-driver.
    gstreamer1-plugins-bad-free
    libva-intel-media-driver

    # Game helpers. Games and launchers switch MangoHud's overlay and GameMode's performance
    # tweaks on themselves; pindu-launcher recommends gamemode.
    mangohud
    gamemode

    # Game stores. The launcher's "add a store" flow installs Steam, Heroic or Lutris from
    # Flathub into the system installation (docs/decisions/0013-game-sources.md).
    flatpak

    # Store links. Play hands a store game to its store as a steam://, heroic:// or lutris:
    # link, which GLib resolves through mimeinfo.cache in the installation's exports. flatpak
    # writes that file after an app install by running update-desktop-database from the host,
    # and skips the step when it is missing.
    desktop-file-utils
)

if [[ ${1:-} == --list ]]; then
    printf '%s\n' "${packages[@]}"
    exit 0
fi

dnf -y install --setopt=install_weak_deps=False "${packages[@]}"
