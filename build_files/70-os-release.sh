#!/usr/bin/env bash
# Identity of the image: os-release, /usr/share/pindu-os/image-info.json, and an initramfs
# that carries the same os-release.
#
# ID becomes pindu-os with ID_LIKE=fedora, and VERSION_ID stays Fedora's release number, so
# tools that key on the Fedora release (bootc-image-builder among them) keep working.
set -euo pipefail

os_release=/usr/lib/os-release

# The Fedora release, carried over from the base image.
# shellcheck source=/dev/null
fedora_version_id=$(. "${os_release}" && echo "${VERSION_ID}")
if [[ ${fedora_version_id} != "${FEDORA_VERSION}" ]]; then
    echo "ERROR: the base image is Fedora ${fedora_version_id}, image.env says ${FEDORA_VERSION}" >&2
    exit 1
fi

if [[ ${VARIANT} == prod ]]; then
    image_name=pindu-os
    pretty_name="Pindu OS ${IMAGE_VERSION}"
else
    image_name=pindu-os-${VARIANT}
    pretty_name="Pindu OS ${IMAGE_VERSION} (${VARIANT})"
fi

repo_url=https://github.com/Tim-van-Oudheusden/pindu-os

cat >"${os_release}" <<EOF
NAME="Pindu OS"
VERSION="${IMAGE_VERSION}"
ID=pindu-os
ID_LIKE=fedora
VERSION_ID=${fedora_version_id}
PRETTY_NAME="${pretty_name}"
VARIANT_ID=${VARIANT}
IMAGE_ID=${image_name}
IMAGE_VERSION=${IMAGE_VERSION}
DEFAULT_HOSTNAME=pindu
ANSI_COLOR="0;38;2;53;132;228"
HOME_URL="${repo_url}"
DOCUMENTATION_URL="${repo_url}/tree/main/docs"
SUPPORT_URL="${repo_url}/issues"
BUG_REPORT_URL="${repo_url}/issues"
EOF
chmod 0644 "${os_release}"

install -d -m 0755 /usr/share/pindu-os
jq --null-input \
    --arg name "${image_name}" \
    --arg version "${IMAGE_VERSION}" \
    --arg variant "${VARIANT}" \
    --arg fedora "${FEDORA_VERSION}" \
    --arg kernel_flavor "${KERNEL_FLAVOR}" \
    --arg kernel "$(basename /usr/lib/modules/*)" \
    --arg launcher "${LAUNCHER_VERSION}" \
    '{
        "image-name": $name,
        "image-version": $version,
        "variant": $variant,
        "fedora-version": $fedora,
        "kernel-flavor": $kernel_flavor,
        "kernel": $kernel,
        "launcher-version": $launcher
    }' >/usr/share/pindu-os/image-info.json

# The initramfs holds a copy of os-release, and systemd sets the hostname from its
# DEFAULT_HOSTNAME before the real root is mounted: with the base image's initramfs the
# machine is called "fedora". Rebuild it for the installed kernel, which also covers a kernel
# that 20-kernel.sh swapped in. The base image's dracut.conf.d makes it generic and adds the
# ostree and bootc modules.
kver=$(basename /usr/lib/modules/*)
# dracut resolves /root, a dangling link to /var/roothome in the build container
# (90-cleanup.sh removes the directory again).
mkdir -p /var/roothome
dracut --force --kver "${kver}" "/usr/lib/modules/${kver}/initramfs.img"
