#!/usr/bin/env bash
# VARIANT=dev: the image for hardware testing. On top of the production image it has an SSH
# server, passwordless sudo for the pindu user, a shell on VT 2 and debugging tools. v0 has
# no settings UI, so this is how a tester sets up Wi-Fi and reads logs.
#
#   80-variant-dev.sh           install (during the image build)
#   80-variant-dev.sh --list    print the package names, one per line
set -euo pipefail

packages=(
    # Remote access and root. The production image removes both (30-base-packages.sh).
    openssh-server
    sudo

    # nmtui, to join a Wi-Fi network until the launcher has a network panel.
    NetworkManager-tui

    # Graphics and input diagnosis: vulkaninfo, lspci, lsusb, evtest and libinput's tools
    # answer "why does gamescope not start" and "why does this controller do nothing";
    # vainfo lists what the GPU decodes in hardware.
    vulkan-tools
    pciutils
    usbutils
    evtest
    libinput-utils
    libva-utils

    # secret-tool, to inspect the Secret Service keyring the launcher uses.
    libsecret

    # Debugging a running session.
    gdb
    strace
    htop
    tmux
    vim-minimal
    less
)

if [[ ${1:-} == --list ]]; then
    printf '%s\n' "${packages[@]}"
    exit 0
fi

dnf -y install --setopt=install_weak_deps=False "${packages[@]}"

# Passwordless sudo, through the wheel group.
cat >/usr/lib/sysusers.d/pindu-dev.conf <<'EOF'
# Dev image only: the pindu user may use sudo (see /etc/sudoers.d/10-pindu-dev).
m pindu wheel
EOF
systemd-sysusers

cat >/etc/sudoers.d/10-pindu-dev <<'EOF'
# Dev image only: no password exists to ask for.
%wheel ALL=(ALL) NOPASSWD: ALL
EOF
chmod 0440 /etc/sudoers.d/10-pindu-dev
visudo --check --quiet

# SSH with keys only; the accounts have no passwords anyway.
cat >/etc/ssh/sshd_config.d/10-pindu-dev.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
systemctl enable sshd.service

# A shell on VT 2 (Ctrl+Alt+F2). The account has no password, so the getty logs it in.
install -d -m 0755 /usr/lib/systemd/system/getty@tty2.service.d
cat >/usr/lib/systemd/system/getty@tty2.service.d/10-pindu-dev-autologin.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/usr/sbin/agetty --autologin pindu --noreset --noclear - ${TERM}
EOF
