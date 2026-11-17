#!/usr/bin/env bash
# Last step: drops build-only repositories and caches, then checks that the image is the one
# the earlier steps meant to build. A failed check fails the build.
set -euo pipefail

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

# Build-only repositories (10-repos.sh) do not ship.
rm -f /etc/yum.repos.d/pindu-build-*.repo
dnf --quiet repolist --enabled | awk 'NR > 1 { print $1 }' | sort >/tmp/pindu-build/final-repos
diff -u /tmp/pindu-build/base-repos /tmp/pindu-build/final-repos ||
    fail "the enabled repositories differ from the base image's"

# /var and /boot belong to the installed system, not to the image. /var/cache/libdnf5 is the
# build's cache mount: its content never reaches the image, and the mount point cannot go.
find /var/log /var/tmp /boot -mindepth 1 -delete
find /var/cache -mindepth 1 -maxdepth 1 ! -name libdnf5 -exec rm -rf {} +
rm -rf /var/lib/dnf /var/roothome
# State directories that packages ship without a tmpfiles.d entry, which bootc would copy on
# installation only. bluetooth.service, geoclue and accounts-daemon (which flatpak's parental
# controls library pulls in) create theirs when they start; greetd's is a portal mask for its
# greeter user, which this image does not use.
rm -rf /var/lib/bluetooth /var/lib/geoclue /var/lib/AccountsService /var/lib/greetd/.config

# Exactly one kernel, with its initramfs.
kernels=(/usr/lib/modules/*)
[[ ${#kernels[@]} -eq 1 ]] || fail "expected one kernel, found: ${kernels[*]}"
[[ -s ${kernels[0]}/vmlinuz && -s ${kernels[0]}/initramfs.img ]] ||
    fail "${kernels[0]} lacks vmlinuz or initramfs.img"

# The pieces of the boot chain: bootc, greetd, the compositors, the launcher.
rpm -q bootc greetd gamescope cage pindu-launcher >/dev/null ||
    fail "a package of the boot chain is missing"
[[ $(systemctl is-enabled greetd.service) == enabled ]] || fail "greetd.service is not enabled"
[[ $(systemctl get-default) == graphical.target ]] || fail "the default target is not graphical.target"
[[ -x /usr/bin/pindu-session ]] || fail "/usr/bin/pindu-session is not executable"
getent passwd pindu >/dev/null || fail "the pindu user does not exist"

# No desktop environment came in through a dependency.
for package in gnome-shell plasma-workspace; do
    if rpm -q "${package}" >/dev/null; then
        fail "${package} is installed; a dependency pulled in a desktop"
    fi
done
