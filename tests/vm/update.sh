#!/usr/bin/env bash
# OS-12: serves an update from a local registry and checks, inside the guest
# (tests/vm/guest/update.sh), that the update service stages it without rebooting, that the
# next boot runs it and that `bootc rollback` returns to the previous image.
#
#   tests/vm/update.sh IMAGE DISK OUTDIR
#
# IMAGE is the container image DISK was built from (image N). The test pushes it to a
# throwaway registry, builds N+1 (N plus one marker file) and pushes that to the same tag once
# the guest runs N from the registry. DISK is not modified. Needs podman next to QEMU.
set -euo pipefail

here=$(dirname "$(realpath "$0")")
# shellcheck source=tests/vm/lib.sh
source "${here}/lib.sh"
# shellcheck source=image.env
source "${here}/../../image.env"

[[ $# -eq 3 ]] || die "usage: $0 IMAGE DISK OUTDIR"
image=$1

vm_init "$3"
vm_disk "$2" snapshot
vm_network

port=$((20000 + RANDOM))
container=pindu-update-test-${port}
host_ref=localhost:${port}/pindu-os-update-test:latest
# 10.0.2.2 is the host as QEMU's user-mode network shows it to the guest.
guest_ref=10.0.2.2:${port}/pindu-os-update-test:latest
next=localhost/pindu-os-update-test:next-${port}

# shellcheck disable=SC2329  # the EXIT trap calls it
cleanup() {
    vm_stop
    podman rm --force "${container}" >/dev/null 2>&1 || true
    podman rmi "${next}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Starting a registry on 127.0.0.1:${port}"
podman run --detach --rm --name "${container}" --publish "127.0.0.1:${port}:5000" "${REGISTRY_IMAGE}" >/dev/null

echo "Pushing ${image} as image N"
podman push --quiet --tls-verify=false --compression-format zstd "${image}" "docker://${host_ref}"

echo "Building image N+1"
podman build --quiet --tag "${next}" --file - "${VM_OUT}" >/dev/null <<EOF
FROM ${image}
RUN echo "image N+1 of tests/vm/update.sh" >/usr/share/pindu-os/update-test-marker
EOF

vm_guest_script "${here}/guest/update.sh" "PINDU_TEST_IMAGE=${guest_ref}"
vm_start

status=0
if vm_wait_for 'PINDU-TEST: waiting-for-update' "${PINDU_TEST_TIMEOUT:-1200}"; then
    echo "The guest runs image N from the registry; pushing N+1"
    podman push --quiet --tls-verify=false --compression-format zstd "${next}" "docker://${host_ref}"
    vm_wait_for '^PINDU-TEST-RESULT' "${PINDU_TEST_TIMEOUT:-1200}" || status=1
else
    status=1
fi
vm_report
grep --quiet --text '^PINDU-TEST-RESULT: PASS' "${VM_OUT}/test.log" || status=1

if ((status)); then
    vm_running && vm_screenshot >/dev/null
    echo "VM update test FAILED; see ${VM_OUT}/test.log"
else
    echo "VM update test passed"
fi
exit "${status}"
