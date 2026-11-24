#!/usr/bin/env bash
# Installs umu-run from umu-launcher's release zipapp, which the Containerfile's umu stage
# downloaded and checked against UMU_SHA256. pindu-launcher starts the Windows games added
# with Add Game through umu-run on PATH (docs/decisions/0013-game-sources.md). The zipapp
# carries its Python libraries and runs on the image's python3 (40-session-packages.sh).
set -euo pipefail

install -D --mode=0755 /tmp/umu/umu-run /usr/bin/umu-run

# `umu-run --version` prints "umu-launcher version <version> (<Python version>)", and only
# gets that far when the zipapp runs on this Python.
reported=$(umu-run --version)
if [[ ${reported} != "umu-launcher version ${UMU_VERSION} "* ]]; then
    echo "ERROR: umu-run reports '${reported}', UMU_VERSION is ${UMU_VERSION}" >&2
    exit 1
fi
