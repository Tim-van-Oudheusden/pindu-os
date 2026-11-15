#!/usr/bin/env bash
# Entry point of the image build: runs the numbered scripts next to it in order, one log group
# each (GitHub folds `::group::` blocks). 80-variant-<name>.sh runs only for that variant.
#
# Inputs are the Containerfile's build arguments, which reach the scripts as environment
# variables: FEDORA_VERSION, LAUNCHER_VERSION, KERNEL_FLAVOR, VARIANT, IMAGE_VERSION.
set -euo pipefail

: "${FEDORA_VERSION:?}" "${LAUNCHER_VERSION:?}" "${KERNEL_FLAVOR:?}" "${VARIANT:?}" "${IMAGE_VERSION:?}"

case "${VARIANT}" in
prod | dev) ;;
*)
    echo "ERROR: unknown VARIANT '${VARIANT}' (expected prod or dev)" >&2
    exit 1
    ;;
esac

cd "$(dirname "$0")"

for script in [0-9][0-9]-*.sh; do
    if [[ ${script} == 80-variant-* && ${script} != "80-variant-${VARIANT}.sh" ]]; then
        continue
    fi
    echo "::group::${script}"
    start=${SECONDS}
    bash "./${script}"
    echo "${script} finished in $((SECONDS - start)) s"
    echo "::endgroup::"
done
