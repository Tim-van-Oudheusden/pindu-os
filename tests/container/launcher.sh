#!/usr/bin/env bash
# OS-05: the installed launcher is the pinned release and all its libraries resolve.
set -euo pipefail
# shellcheck source=tests/container/lib.sh
source /tests/lib.sh

check_eq "pindu-launcher is version ${LAUNCHER_VERSION}" \
    "${LAUNCHER_VERSION}" "$(rpm -q --qf '%{VERSION}' pindu-launcher)"

unresolved=$(ldd /usr/bin/pindu-launcher | grep 'not found' || true)
check_eq "ldd reports no missing library" "" "${unresolved}"

# The launcher's settings schema must be compiled in, or it aborts at startup.
check "the launcher's GSettings schema is compiled" \
    gsettings list-keys io.github.tim_van_oudheusden.pindu-launcher

finish
