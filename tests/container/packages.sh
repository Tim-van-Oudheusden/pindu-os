#!/usr/bin/env bash
# OS-04: every package the build scripts list is installed, the ones they remove are gone
# from the production image, and no desktop environment came in through a dependency.
set -euo pipefail
# shellcheck source=tests/container/lib.sh
source /tests/lib.sh

listed=$(bash /build_files/30-base-packages.sh --list && bash /build_files/40-session-packages.sh --list)
if [[ ${VARIANT} == dev ]]; then
    listed+=$'\n'$(bash /build_files/80-variant-dev.sh --list)
fi
for package in ${listed}; do
    check "${package} is installed" rpm -q "${package}"
done

if [[ ${VARIANT} == prod ]]; then
    for package in $(bash /build_files/30-base-packages.sh --removed); do
        check_not "${package} is not installed" rpm -q "${package}"
    done
fi

for package in gnome-shell plasma-workspace; do
    check_not "${package} is not installed" rpm -q "${package}"
done

finish
