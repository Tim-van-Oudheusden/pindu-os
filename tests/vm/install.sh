#!/usr/bin/env bash
# OS-13: boots the installer ISO in QEMU with one empty disk, lets it install unattended,
# then boots the installed disk and runs the boot assertions (tests/vm/boot.sh) on it.
#
#   tests/vm/install.sh ISO OUTDIR EXPECTED_IMAGE
#
# EXPECTED_IMAGE is the registry reference the installed system must update from, with
# signature enforcement (disk_config/iso.toml sets it in %post).
set -euo pipefail

here=$(dirname "$(realpath "$0")")
# shellcheck source=tests/vm/lib.sh
source "${here}/lib.sh"

[[ $# -eq 3 ]] || die "usage: $0 ISO OUTDIR EXPECTED_IMAGE"
iso=$(realpath "$1")
[[ -r ${iso} ]] || die "ISO $1 not found"

vm_init "$2"
out=${VM_OUT}
rm -f "${out}/installed.qcow2"
qemu-img create -q -f qcow2 "${out}/installed.qcow2" 40G
vm_disk "${out}/installed.qcow2"
vm_network
# The installer reboots when it is done; -no-reboot turns that into QEMU exiting.
QEMU_ARGS+=(-cdrom "${iso}" -no-reboot)

vm_start
trap vm_stop EXIT
echo "Installing from ${iso}"
deadline=$((SECONDS + ${PINDU_TEST_TIMEOUT:-2400}))
while vm_running; do
    if ((SECONDS >= deadline)); then
        vm_screenshot >/dev/null
        die "the installer did not finish in time; ${out}/screenshot.* shows where it stopped"
    fi
    sleep 5
done
vm_stop
trap - EXIT
echo "The installer finished after ${SECONDS} s"

PINDU_TEST_EXPECT_IMAGE=$3 exec "${here}/boot.sh" "${out}/installed.qcow2" "${out}/boot"
