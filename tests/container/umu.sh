#!/usr/bin/env bash
# Issue #59: the launcher runs the Windows games added with Add Game through umu-run, which
# it looks for on PATH. umu-run is the pinned release and runs on the image's Python, as the
# pindu user that the session runs as.
set -euo pipefail
# shellcheck source=tests/container/lib.sh
source /tests/lib.sh

check "umu-run is on PATH" command -v umu-run
check_eq "umu-run answers as umu-launcher ${UMU_VERSION}, as pindu" \
    "umu-launcher version ${UMU_VERSION}" \
    "$(runuser -u pindu -- env HOME=/tmp umu-run --version 2>&1 | cut -d ' ' -f 1-3)"

finish
