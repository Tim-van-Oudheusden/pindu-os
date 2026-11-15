# Shared QEMU plumbing for the VM tests (boot.sh, update.sh, install.sh) and run.sh.
#
# A test runs an unmodified disk image. Its assertions travel into the guest as systemd
# credentials on QEMU's SMBIOS table: a unit (systemd.extra-unit.*), a drop-in that makes
# multi-user.target want it (systemd.unit-dropin.*) and the script the unit runs. The script
# writes to the second serial port, which QEMU saves as test.log; the host side waits for
# lines in that file. So the production image needs no SSH server and no test hooks. The
# first serial port is the guest's console where it has one (console.log).
#
# Needs qemu-system-x86_64 with KVM and UEFI firmware (edk2-ovmf / ovmf).
# shellcheck shell=bash

VM_MEMORY=${VM_MEMORY:-4096}
VM_CPUS=${VM_CPUS:-2}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

# vm_init OUTDIR: prepare the output directory and the base QEMU command line in QEMU_ARGS.
vm_init() {
    VM_OUT=$1
    mkdir -p "${VM_OUT}"
    VM_OUT=$(realpath "${VM_OUT}")
    rm -f "${VM_OUT}"/console.log "${VM_OUT}"/test.log "${VM_OUT}"/monitor.log "${VM_OUT}"/screenshot.*

    command -v qemu-system-x86_64 >/dev/null || die "qemu-system-x86_64 is not installed"
    [[ -w /dev/kvm ]] || die "/dev/kvm is not usable; the VM tests need KVM"

    local code vars pair
    code=${OVMF_CODE:-}
    vars=${OVMF_VARS:-}
    if [[ -z ${code} ]]; then
        for pair in \
            /usr/share/edk2/ovmf/OVMF_CODE.fd:/usr/share/edk2/ovmf/OVMF_VARS.fd \
            /usr/share/OVMF/OVMF_CODE_4M.fd:/usr/share/OVMF/OVMF_VARS_4M.fd \
            /usr/share/OVMF/OVMF_CODE.fd:/usr/share/OVMF/OVMF_VARS.fd \
            /usr/share/edk2/x64/OVMF_CODE.4m.fd:/usr/share/edk2/x64/OVMF_VARS.4m.fd; do
            if [[ -r ${pair%%:*} && -r ${pair##*:} ]]; then
                code=${pair%%:*}
                vars=${pair##*:}
                break
            fi
        done
    fi
    [[ -r ${code} && -r ${vars} ]] || die "no UEFI firmware found; install edk2-ovmf or set OVMF_CODE and OVMF_VARS"
    cp "${vars}" "${VM_OUT}/ovmf-vars.fd"
    chmod u+w "${VM_OUT}/ovmf-vars.fd"

    QEMU_ARGS=(
        -machine "q35,accel=kvm"
        -cpu host
        -smp "${VM_CPUS}"
        -m "${VM_MEMORY}"
        -drive "if=pflash,format=raw,readonly=on,file=${code}"
        -drive "if=pflash,format=raw,file=${VM_OUT}/ovmf-vars.fd"
        -device virtio-rng-pci
        -vga none
        -device virtio-vga
        -serial "file:${VM_OUT}/console.log"
        -serial "file:${VM_OUT}/test.log"
    )
}

# vm_disk FILE [snapshot]: attach a disk image. With "snapshot", writes go to a temporary
# file and the image stays as it is.
vm_disk() {
    local file format
    file=$(realpath "$1")
    [[ -r ${file} ]] || die "disk image $1 not found"
    format=raw
    [[ ${file} == *.qcow2 ]] && format=qcow2
    QEMU_ARGS+=(-drive "if=virtio,format=${format},file=${file}${2:+,snapshot=on}")
}

# vm_network: user-mode network. The guest reaches the host as 10.0.2.2.
vm_network() {
    QEMU_ARGS+=(-nic "user,model=virtio-net-pci")
}

# vm_network_forward HOST_PORT GUEST_PORT: the same, with a TCP port of the guest on 127.0.0.1.
vm_network_forward() {
    QEMU_ARGS+=(-nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:$1-:$2")
}

# vm_credential NAME FILE: pass FILE to the guest as the systemd credential NAME.
vm_credential() {
    QEMU_ARGS+=(-smbios "type=11,value=io.systemd.credential.binary:$1=$(base64 --wrap=0 "$2")")
}

# vm_guest_script SCRIPT [VAR=VALUE...]: run SCRIPT as root in the guest on every boot, with
# the given variables set. The script sources tests/vm/guest/lib.sh, which arrives as a
# credential next to it, and reports on /dev/ttyS1 (test.log).
vm_guest_script() {
    local script=$1 assignment lib
    lib=$(dirname "${BASH_SOURCE[0]}")/guest/lib.sh
    shift
    {
        echo '#!/usr/bin/bash'
        for assignment in "$@"; do
            printf 'export %q\n' "${assignment}"
        done
        cat "${script}"
    } >"${VM_OUT}/guest-script.sh"

    cat >"${VM_OUT}/guest.service" <<'EOF'
[Unit]
Description=Pindu OS VM test

[Service]
Type=exec
ImportCredential=pindu.test.*
ExecStart=/usr/bin/bash ${CREDENTIALS_DIRECTORY}/pindu.test.script
EOF
    printf '[Unit]\nWants=pindu-test.service\n' >"${VM_OUT}/guest.dropin"

    vm_credential systemd.extra-unit.pindu-test.service "${VM_OUT}/guest.service"
    vm_credential systemd.unit-dropin.multi-user.target "${VM_OUT}/guest.dropin"
    vm_credential pindu.test.script "${VM_OUT}/guest-script.sh"
    vm_credential pindu.test.lib "${lib}"
}

# vm_start: start QEMU headless in the background. Its monitor reads commands from a FIFO.
# The caller stops it with vm_stop, normally from an EXIT trap.
vm_start() {
    rm -f "${VM_OUT}/monitor.fifo"
    mkfifo "${VM_OUT}/monitor.fifo"
    qemu-system-x86_64 "${QEMU_ARGS[@]}" -display none -monitor stdio \
        <"${VM_OUT}/monitor.fifo" >"${VM_OUT}/monitor.log" 2>&1 &
    VM_PID=$!
    exec {VM_MONITOR}>"${VM_OUT}/monitor.fifo"
}

# vm_monitor COMMAND: send a command to the QEMU monitor.
vm_monitor() {
    vm_running || die "QEMU is not running: $(tail --lines=5 "${VM_OUT}/monitor.log")"
    echo "$1" >&"${VM_MONITOR}"
}

vm_running() {
    kill -0 "${VM_PID}" 2>/dev/null
}

# vm_wait_for PATTERN TIMEOUT: wait until a line of test.log matches the extended regular
# expression. Fails after TIMEOUT seconds or when QEMU exits.
vm_wait_for() {
    local pattern=$1 deadline=$((SECONDS + $2))
    while ((SECONDS < deadline)); do
        if grep --quiet --extended-regexp --text "${pattern}" "${VM_OUT}/test.log" 2>/dev/null; then
            return 0
        fi
        vm_running || return 1
        sleep 1
    done
    return 1
}

# vm_screenshot: save the guest's screen as screenshot.png (screenshot.ppm if this QEMU
# cannot write PNG) and print how many different colours it shows.
vm_screenshot() {
    local ppm=${VM_OUT}/screenshot.ppm
    rm -f "${ppm}" "${VM_OUT}/screenshot.png"
    vm_monitor "screendump ${ppm}"
    vm_monitor "screendump ${VM_OUT}/screenshot.png -f png"
    local waited=0
    until [[ -s ${ppm} ]] || ((waited++ >= 10)); do sleep 1; done
    sleep 1
    [[ -s ${ppm} ]] || die "QEMU wrote no screenshot"
    # A binary PPM is three text lines (P6, size, maximum) followed by RGB bytes.
    tail --lines=+4 "${ppm}" | od --address-radix=n --output-duplicates --format=x1 --width=3 | sort --unique | wc --lines
    if [[ -s ${VM_OUT}/screenshot.png ]]; then
        rm -f "${ppm}"
    else
        rm -f "${VM_OUT}/screenshot.png"
    fi
}

# vm_stop: quit QEMU. Safe to call twice.
vm_stop() {
    if [[ -n ${VM_PID:-} ]] && vm_running; then
        { echo quit >&"${VM_MONITOR}"; } 2>/dev/null || true
        local waited=0
        while vm_running && ((waited++ < 10)); do sleep 1; done
        kill "${VM_PID}" 2>/dev/null || true
    fi
    if [[ -n ${VM_MONITOR:-} ]]; then
        exec {VM_MONITOR}>&-
        VM_MONITOR=
    fi
    rm -f "${VM_OUT}/monitor.fifo"
}

# vm_report: print the guest's report from test.log, without the firmware and boot loader
# output that shares the serial port.
vm_report() {
    tr -d '\r' <"${VM_OUT}/test.log" 2>/dev/null | grep --text '^PINDU-TEST' || true
}
