#!/usr/bin/env bash
# OS-13, #28, #52: boots the installer ISO in QEMU four times.
#
# 1. Two empty disks: the installer must refuse, and power off when Enter is pressed,
#    without writing to either disk.
# 2. One empty disk, answered "no": it must power off without writing to the disk.
# 3. One empty disk, answered "erase": it installs, then says so and waits for Enter before
#    it restarts, so the user can remove the USB stick first.
# 4. One empty disk, confirmed by the systemd credential pindu.install.confirm=vda: it
#    installs unattended and restarts without a key press. The installed disk then has to
#    pass the boot assertions (tests/vm/boot.sh).
#
#   tests/vm/install.sh ISO OUTDIR EXPECTED_IMAGE
#
# EXPECTED_IMAGE is the registry reference the installed system must update from, with
# signature enforcement (disk_config/iso.toml sets it in %post). The installer reports its
# decision as "pindu-install: ..." lines on the first serial port (console.log); keys reach it
# through QEMU's monitor.
set -euo pipefail

here=$(dirname "$(realpath "$0")")
# shellcheck source=tests/vm/lib.sh
source "${here}/lib.sh"

[[ $# -eq 3 ]] || die "usage: $0 ISO OUTDIR EXPECTED_IMAGE"
iso=$(realpath "$1")
[[ -r ${iso} ]] || die "ISO $1 not found"
out=$2
timeout=${PINDU_TEST_TIMEOUT:-2400}

# installer_start OUTDIR CONFIRM DISK...: boot the ISO with fresh empty disks named DISK in
# OUTDIR. A non-empty CONFIRM is passed as the credential pindu.install.confirm.
installer_start() {
    local disk
    vm_init "$1"
    if [[ -n $2 ]]; then
        printf '%s' "$2" >"${VM_OUT}/confirm"
        vm_credential pindu.install.confirm "${VM_OUT}/confirm"
    fi
    shift 2
    for disk in "$@"; do
        rm -f "${VM_OUT}/${disk}"
        qemu-img create -q -f qcow2 "${VM_OUT}/${disk}" 40G
        vm_disk "${VM_OUT}/${disk}"
    done
    vm_network
    # The installer reboots when it is done; -no-reboot turns that into QEMU exiting.
    QEMU_ARGS+=(-cdrom "${iso}" -no-reboot)
    vm_start
    trap vm_stop EXIT
}

# installer_wait PATTERN: wait for the installer's report on the first serial port.
installer_wait() {
    if ! vm_wait_for "pindu-install: $1" "${timeout}" console.log; then
        vm_running && vm_screenshot >/dev/null
        die "the installer did not report \"$1\"; ${VM_OUT}/console.log and screenshot.* show where it stopped"
    fi
    echo "The installer reported: $(tr -d '\r' <"${VM_OUT}/console.log" | grep --text --only-matching "pindu-install: $1.*")"
}

# installer_type KEY...: press keys (QEMU key names) on the installer's keyboard.
installer_type() {
    local key
    for key in "$@"; do
        vm_monitor "sendkey ${key}"
        sleep 0.2
    done
}

# installer_exit SECONDS: wait for the installer to turn the VM off (or reboot it, which
# -no-reboot turns into the same).
installer_exit() {
    local deadline=$((SECONDS + $1))
    while vm_running; do
        if ((SECONDS >= deadline)); then
            vm_screenshot >/dev/null
            die "the installer did not finish in time; ${VM_OUT}/screenshot.* shows where it stopped"
        fi
        sleep 5
    done
    vm_stop
    trap - EXIT
}

# assert_unwritten DISK...: the guest wrote nothing to these qcow2 files; a fresh one has no
# allocated cluster until something is written, even zeros.
assert_unwritten() {
    local disk
    for disk in "$@"; do
        if qemu-img map --output=json "${VM_OUT}/${disk}" | grep --quiet --extended-regexp '"(present|data)": true'; then
            die "the installer wrote to ${disk}"
        fi
        echo "ok    ${disk} is unchanged"
    done
}

echo "== Two disks: the installer refuses"
installer_start "${out}/two-disks" "" first.qcow2 second.qcow2
installer_wait "refused: 2 disks"
vm_screenshot >/dev/null
installer_type ret
installer_exit 120
assert_unwritten first.qcow2 second.qcow2

echo "== One disk, not confirmed: the installer turns the PC off"
installer_start "${out}/declined" "" disk.qcow2
installer_wait "asking about vda"
vm_screenshot >/dev/null
installer_type n o ret
installer_wait "declined"
installer_exit 120
assert_unwritten disk.qcow2

echo "== One disk, erase typed: the installer installs and waits for Enter"
started=${SECONDS}
installer_start "${out}/attended" "" disk.qcow2
installer_wait "asking about vda"
installer_type e r a s e ret
installer_wait "confirmed vda"
installer_wait "installed"
echo "The installer finished after $((SECONDS - started)) s"
sleep 60
vm_running || die "the installer restarted the PC without waiting for Enter"
vm_screenshot >/dev/null
echo "ok    after 60 s the installer still waits for Enter (${VM_OUT}/screenshot.*)"
installer_type ret
installer_exit 120
rm -f "${VM_OUT}/disk.qcow2"

echo "== One disk, confirmed by the credential: the installer installs and restarts by itself"
started=${SECONDS}
installer_start "${out}/confirmed" vda installed.qcow2
installed=${VM_OUT}/installed.qcow2
installer_wait "confirmed vda"
installer_wait "installed"
installer_exit 120
echo "The installer finished after $((SECONDS - started)) s"

PINDU_TEST_EXPECT_IMAGE=$3 exec "${here}/boot.sh" "${installed}" "${out}/boot"
