#!/usr/bin/env bash
# Boots a disk image in a QEMU window for a look at the session (`just run-vm`). Changes to
# the disk are thrown away when the window closes. In a VM the session normally runs in
# cage, because gamescope needs a GPU with Vulkan.
#
#   tests/vm/run.sh DISK
set -euo pipefail

here=$(dirname "$(realpath "$0")")
# shellcheck source=tests/vm/lib.sh
source "${here}/lib.sh"

[[ $# -eq 1 ]] || die "usage: $0 DISK"

vm_init "$(mktemp -d)"
trap 'rm -rf "${VM_OUT}"' EXIT
vm_disk "$1" snapshot
vm_network
QEMU_ARGS+=(-device qemu-xhci -device usb-tablet -device usb-kbd -device intel-hda -device hda-duplex)

qemu-system-x86_64 "${QEMU_ARGS[@]}" -display gtk
