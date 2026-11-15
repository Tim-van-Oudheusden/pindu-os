#!/usr/bin/env bash
# Package repositories that are enabled for the build only.
#
# v0 needs none: Fedora 45 itself packages gamescope, cage and greetd, so the Terra fallback the
# spec kept in reserve is not used. A repository added here must be written as
# /etc/yum.repos.d/pindu-build-<id>.repo with gpgcheck=1; 90-cleanup.sh deletes those files and
# fails the build if anything but the base image's repositories is left enabled.
set -euo pipefail

# The base image's repositories, recorded so 90-cleanup.sh can prove none was added.
mkdir -p /tmp/pindu-build
dnf --quiet repolist --enabled | awk 'NR > 1 { print $1 }' | sort >/tmp/pindu-build/base-repos
cat /tmp/pindu-build/base-repos
