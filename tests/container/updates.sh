#!/usr/bin/env bash
# OS-12, the part visible without booting: the update service downloads and stages but never
# applies (applying reboots), and its timer is on. tests/vm/update.sh runs a real update.
set -euo pipefail
# shellcheck source=tests/container/lib.sh
source /tests/lib.sh

# The last ExecStart of the merged unit is the one that runs; an empty one resets the list.
exec_start=$(systemctl cat bootc-fetch-apply-updates.service | grep '^ExecStart=' | tail -n 1)
check_eq "the update service stages without applying" \
    "ExecStart=/usr/bin/bootc upgrade --quiet" "${exec_start}"
check_eq "exactly one command is left after the reset" 1 \
    "$(systemctl cat bootc-fetch-apply-updates.service | sed -n '/^ExecStart=$/,$p' | grep -c '^ExecStart=.')"
check_eq "the update timer is enabled" enabled "$(systemctl is-enabled bootc-fetch-apply-updates.timer)"
check "the units pass systemd's checks" \
    systemd-analyze verify bootc-fetch-apply-updates.service bootc-fetch-apply-updates.timer \
    pindu-os-update-status.service pindu-os-rollback.service

# The launcher's system panel (issue #17); tests/vm/ checks the status file and polkit.
check_eq "the update status is published at boot" enabled "$(systemctl is-enabled pindu-os-update-status.service)"
check_eq "the rollback unit only runs on demand" static "$(systemctl is-enabled pindu-os-rollback.service)"
check "the update service publishes the status after it stages an update" \
    grep -qx 'ExecStartPost=/usr/bin/systemctl start pindu-os-update-status.service' \
    <(systemctl cat bootc-fetch-apply-updates.service)
check "the rollback unit publishes the status after it rolls back" \
    grep -qx 'ExecStartPost=/usr/bin/systemctl start pindu-os-update-status.service' \
    <(systemctl cat pindu-os-rollback.service)

finish
