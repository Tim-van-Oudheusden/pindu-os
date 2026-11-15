#!/usr/bin/env bash
# Installs pindu-launcher from the release RPM that the Containerfile's launcher stage
# downloaded and checked against LAUNCHER_SHA256. dnf resolves its dependencies
# (glycin-loaders, bubblewrap, libmanette, GTK 4, libadwaita) from Fedora.
set -euo pipefail

rpms=(/tmp/launcher/pindu-launcher-"${LAUNCHER_VERSION}"-*.rpm)
if [[ ${#rpms[@]} -ne 1 || ! -f ${rpms[0]} ]]; then
    echo "ERROR: expected one pindu-launcher ${LAUNCHER_VERSION} RPM in /tmp/launcher, found: ${rpms[*]}" >&2
    exit 1
fi

dnf -y install --setopt=install_weak_deps=False "${rpms[0]}"

installed=$(rpm -q --qf '%{VERSION}' pindu-launcher)
if [[ ${installed} != "${LAUNCHER_VERSION}" ]]; then
    echo "ERROR: pindu-launcher ${installed} is installed, LAUNCHER_VERSION is ${LAUNCHER_VERSION}" >&2
    exit 1
fi

if missing=$(ldd /usr/bin/pindu-launcher | grep 'not found'); then
    echo "ERROR: pindu-launcher has unresolved libraries:" >&2
    echo "${missing}" >&2
    exit 1
fi
