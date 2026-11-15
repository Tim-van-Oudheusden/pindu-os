#!/usr/bin/env bash
# Kernel selection.
#
# KERNEL_FLAVOR=fedora keeps the kernel of the base image. It is signed with Fedora's key, so
# it boots with Secure Boot on and nothing has to be done here.
#
# KERNEL_FLAVOR=ogc swaps in the Open Gaming Collective kernel. ghcr.io/ublue-os/akmods ships
# it prebuilt under /kernel-rpms (the image is mounted at /tmp/kernel), and the recipe follows
# Bazzite's 03-install-kernel-akmods.sh. That kernel is signed with Universal Blue's key:
# Secure Boot users enrol the certificate once (docs/runbook.md, "OGC kernel").
set -euo pipefail

case "${KERNEL_FLAVOR}" in
fedora)
    echo "Keeping the base image's kernel: $(rpm -q kernel-core)"
    exit 0
    ;;
ogc) ;;
*)
    echo "ERROR: unknown KERNEL_FLAVOR '${KERNEL_FLAVOR}' (expected fedora or ogc)" >&2
    exit 1
    ;;
esac

rpms=/tmp/kernel/kernel-rpms
[[ -d ${rpms} ]] || {
    echo "ERROR: ${rpms} is missing; the kernel stage did not provide the akmods image" >&2
    exit 1
}

# The kernel packages' scriptlets call kernel-install, whose dracut and rpm-ostree plugins
# expect a booted system. Park them; 70-os-release.sh builds the initramfs explicitly.
plugins=(/usr/lib/kernel/install.d/05-rpmostree.install /usr/lib/kernel/install.d/50-dracut.install)
for plugin in "${plugins[@]}"; do
    [[ -e ${plugin} ]] || continue
    mv "${plugin}" "${plugin}.pindu-parked"
    printf '#!/bin/sh\nexit 0\n' >"${plugin}"
    chmod 0755 "${plugin}"
done

# Remove the Fedora kernel. rpm --nodeps, because dnf protects the running system's kernel
# packages and nothing else in the image depends on this exact build.
mapfile -t installed < <(rpm -qa --qf '%{NAME}\n' 'kernel' 'kernel-core' 'kernel-modules*' | sort -u)
rpm --erase --nodeps "${installed[@]}"
rm -rf /usr/lib/modules

# kernel, kernel-core and kernel-modules (one package there; it provides -core and -extra).
# The kernel-devel packages stay behind: nothing is compiled on the device.
dnf -y install --setopt=install_weak_deps=False \
    "${rpms}"/kernel-[0-9]*.rpm \
    "${rpms}"/kernel-core-[0-9]*.rpm \
    "${rpms}"/kernel-modules-[0-9]*.rpm

# Universal Blue's public certificate, /etc/pki/akmods/certs/akmods-ublue.der, which a Secure
# Boot user enrols with mokutil. The package also carries repository files; those stay out.
# The RPM is unsigned: what vouches for it is the akmods image's pinned digest and its cosign
# signature, which `just verify-inputs` checks.
rpm --install --nosignature \
    --excludepath=/etc/yum.repos.d --excludepath=/usr/share/ublue-os/etc/yum.repos.d \
    /tmp/kernel/rpms/ublue-os/ublue-os-akmods-addons-*.rpm
[[ -s /etc/pki/akmods/certs/akmods-ublue.der ]] || {
    echo "ERROR: the akmods image did not provide Universal Blue's Secure Boot certificate" >&2
    exit 1
}

for plugin in "${plugins[@]}"; do
    [[ -e ${plugin}.pindu-parked ]] || continue
    mv -f "${plugin}.pindu-parked" "${plugin}"
done

kernels=(/usr/lib/modules/*)
if [[ ${#kernels[@]} -ne 1 || ! -e ${kernels[0]}/vmlinuz ]]; then
    echo "ERROR: expected exactly one kernel in /usr/lib/modules, found: ${kernels[*]}" >&2
    exit 1
fi
kver=${kernels[0]##*/}

# 70-os-release.sh builds the initramfs for whichever kernel is installed.
echo "Installed the OGC kernel ${kver}"
