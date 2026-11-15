#!/usr/bin/env bash
# OS-08: boots a disk image under QEMU with KVM, asserts on the session from inside the guest
# (tests/vm/guest/boot.sh) and saves a screenshot.
#
#   tests/vm/boot.sh [--ssh] DISK OUTDIR
#
# DISK is a qcow2 or raw image and is not modified. OUTDIR receives test.log (the guest's
# report), console.log, screenshot.png and monitor.log. With --ssh (OS-09, the dev image) the test also
# logs in over SSH with a key injected as the systemd credential ssh.authorized_keys.root.
# With PINDU_TEST_EXPECT_IMAGE set, the guest must be set to update from that image reference
# with signature enforcement (tests/vm/install.sh uses this).
set -euo pipefail

here=$(dirname "$(realpath "$0")")
# shellcheck source=tests/vm/lib.sh
source "${here}/lib.sh"

ssh_check=0
if [[ ${1:-} == --ssh ]]; then
    ssh_check=1
    shift
fi
[[ $# -eq 2 ]] || die "usage: $0 [--ssh] DISK OUTDIR"

vm_init "$2"
vm_disk "$1" snapshot

if ((ssh_check)); then
    rm -f "${VM_OUT}"/ssh-key "${VM_OUT}"/ssh-key.pub
    ssh-keygen -q -t ed25519 -N '' -C pindu-os-test -f "${VM_OUT}/ssh-key"
    vm_credential ssh.authorized_keys.root "${VM_OUT}/ssh-key.pub"
    ssh_port=$((20000 + RANDOM))
    vm_network_forward "${ssh_port}" 22
else
    vm_network
fi

vm_guest_script "${here}/guest/boot.sh" \
    "PINDU_TEST_LOGIN_DEADLINE=${PINDU_TEST_LOGIN_DEADLINE:-60}" \
    "PINDU_TEST_EXPECT_IMAGE=${PINDU_TEST_EXPECT_IMAGE:-}"

vm_start
trap vm_stop EXIT
status=0
if ! vm_wait_for '^PINDU-TEST-RESULT' "${PINDU_TEST_TIMEOUT:-600}"; then
    echo "The guest did not report a result; the screenshot shows where it stopped."
    status=1
fi
vm_report

# Give the launcher a moment to draw its first frame.
sleep 5
colours=$(vm_screenshot)
echo "Screenshot: $(ls "${VM_OUT}"/screenshot.*) (${colours} colours)"
if ((colours < 16)); then
    echo "FAIL  the screen shows fewer than 16 colours; the launcher is not drawing"
    status=1
fi

if ((ssh_check)) && ((status == 0)); then
    # Root logs in with the injected key; pindu has passwordless sudo.
    if ssh_out=$(ssh -i "${VM_OUT}/ssh-key" -p "${ssh_port}" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        -o BatchMode=yes -o ConnectTimeout=10 root@127.0.0.1 \
        'runuser -u pindu -- sudo --non-interactive id --user') && [[ ${ssh_out} == 0 ]]; then
        echo "ok    SSH with the injected key works and pindu has passwordless sudo"
    else
        echo "FAIL  SSH with the injected key, then sudo as pindu (got: ${ssh_out:-nothing})"
        status=1
    fi
fi

grep --quiet --text '^PINDU-TEST-RESULT: PASS' "${VM_OUT}/test.log" || status=1
vm_stop
if ((status)); then
    echo "VM boot test FAILED; see ${VM_OUT}/test.log"
else
    echo "VM boot test passed"
fi
exit "${status}"
