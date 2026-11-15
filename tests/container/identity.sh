#!/usr/bin/env bash
# The image says what it is: os-release and image-info.json name the variant and the pins it
# was built from, and the Fedora release still shows for tools that key on it.
set -euo pipefail
# shellcheck source=tests/container/lib.sh
source /tests/lib.sh

# shellcheck source=/dev/null
source /usr/lib/os-release
expected_name=pindu-os
[[ ${VARIANT} == prod ]] || expected_name=pindu-os-${VARIANT}

check_eq "os-release ID" pindu-os "${ID}"
check_eq "os-release ID_LIKE" fedora "${ID_LIKE}"
check_eq "os-release VERSION_ID is the Fedora release" "${FEDORA_VERSION}" "${VERSION_ID}"
check_eq "os-release IMAGE_ID" "${expected_name}" "${IMAGE_ID}"
check "os-release IMAGE_VERSION is <fedora>.<date>.<n>" \
    grep -qE "^${FEDORA_VERSION}\.[0-9]{8}\.[0-9]+\$" <<<"${IMAGE_VERSION}"
check_eq "/etc/os-release is the same file" /usr/lib/os-release "$(readlink -f /etc/os-release)"

info=/usr/share/pindu-os/image-info.json
check_eq "image-info.json image-name" "${expected_name}" "$(jq -r '."image-name"' "${info}")"
check_eq "image-info.json image-version" "${IMAGE_VERSION}" "$(jq -r '."image-version"' "${info}")"
check_eq "image-info.json variant" "${VARIANT}" "$(jq -r .variant "${info}")"
check_eq "image-info.json launcher-version" "${LAUNCHER_VERSION}" "$(jq -r '."launcher-version"' "${info}")"
check_eq "image-info.json kernel is the installed kernel" \
    "$(basename /usr/lib/modules/*)" "$(jq -r .kernel "${info}")"

finish
