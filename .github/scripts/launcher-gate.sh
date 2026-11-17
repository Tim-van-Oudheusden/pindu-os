#!/usr/bin/env bash
# Promote gate for launcher bumps (docs/runbook.md, "Launcher hardware check").
#
# Usage: launcher-gate.sh <image to promote> <current stable image>
#
# Allows the promotion when both images contain the same launcher. When the launcher differs,
# or there is no stable image yet, it allows it only if the launcher's hardware check passed:
# the pindu-launcher issue titled exactly "Release X.Y.Z" carries the hardware-check:passed
# label (open or closed). A launcher pre-release never passes.
#
# The launcher version of an image is LAUNCHER_VERSION in image.env at the commit named by the
# image's org.opencontainers.image.revision label, so this runs in a clone with full history.
# Needs skopeo, git, jq and gh (with GH_TOKEN set). Exits 1 when it refuses.
set -euo pipefail
shopt -s inherit_errexit

launcher_repository=Tim-van-Oudheusden/pindu-launcher
passed_label=hardware-check:passed

# LAUNCHER_VERSION of the image $1, or nothing if the image does not exist.
launcher_version() {
    local revision
    revision=$(skopeo inspect --no-tags --format '{{index .Labels "org.opencontainers.image.revision"}}' \
        "docker://$1") || return 0
    if ! [[ ${revision} =~ ^[0-9a-f]{40}$ ]]; then
        echo "::error::$1 has no commit in its org.opencontainers.image.revision label ('${revision}')" >&2
        return 1
    fi
    git show "${revision}:image.env" | sed -n 's/^LAUNCHER_VERSION=//p'
}

# The URL of the release issue of launcher version $1 if its hardware check passed, else nothing.
hardware_check() {
    gh issue list --repo "${launcher_repository}" --state all --label "${passed_label}" \
        --search "\"Release $1\" in:title" --limit 100 --json title,url |
        jq --raw-output --arg title "Release $1" '.[] | select(.title == $title) | .url'
}

if (($# != 2)); then
    echo "usage: $0 <image to promote> <current stable image>" >&2
    exit 2
fi
candidate_image=$1
stable_image=$2

candidate=$(launcher_version "${candidate_image}")
if [[ -z ${candidate} ]]; then
    echo "::error::Cannot read the launcher version of ${candidate_image}" >&2
    exit 1
fi
stable=$(launcher_version "${stable_image}")

if [[ ${candidate} == "${stable}" ]]; then
    echo "Launcher ${candidate} is already on stable: no hardware check needed."
    exit 0
fi

echo "Launcher ${stable:-(no stable image)} -> ${candidate}: needs a passed hardware check."
if ! [[ ${candidate} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "::error::Launcher ${candidate} is a pre-release; only a final launcher release goes to stable" >&2
    exit 1
fi
issue=$(hardware_check "${candidate}")
if [[ -z ${issue} ]]; then
    echo "::error::No passed hardware check for launcher ${candidate}: label the issue \"Release ${candidate}\" in ${launcher_repository} ${passed_label} once the checklist passes (docs/runbook.md, \"Launcher hardware check\")" >&2
    exit 1
fi
echo "Hardware check for launcher ${candidate} passed: ${issue}"
