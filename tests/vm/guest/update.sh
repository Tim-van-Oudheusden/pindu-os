# OS-12, inside the VM: an update is staged without a reboot, the next boot runs it, and a
# rollback returns to the previous image. The rollback goes the way the launcher's system
# panel does it (issue #17): pindu starts pindu-os-rollback.service, and every step shows in
# /run/pindu-os/update-status.json. Runs as root from the injected pindu-test.service on
# every boot (tests/vm/lib.sh).
#
# The test spans four boots. /var/lib/pindu-test/stage says which one this is:
#   0  booted from the disk image: switch to the same image (N) as served by the registry
#   1  running N from the registry: wait for the host to push N+1, run the update service,
#      check that N+1 is staged and that nothing rebooted; roll back and revert that while
#      N+1 is staged, then stage it again
#   2  running N+1: roll back
#   3  running N again: the update service stages N+1 again; verdict
#
# PINDU_TEST_IMAGE is the image reference in the host's registry.
# shellcheck shell=bash
# shellcheck source=tests/vm/guest/lib.sh
source "${CREDENTIALS_DIRECTORY}/pindu.test.lib"

image=${PINDU_TEST_IMAGE:?}
registry=${image%%/*}
state=/var/lib/pindu-test
marker=/usr/share/pindu-os/update-test-marker
mkdir -p "${state}"
stage=$(cat "${state}/stage" 2>/dev/null || echo 0)

# shellcheck disable=SC2329  # the helpers below are called through check and wait_for
booted_digest() {
    bootc status --json | jq -r '.status.booted.image.imageDigest'
}

staged_digest() {
    bootc status --json | jq -r '.status.staged.image.imageDigest // "none"'
}

# shellcheck disable=SC2329
registry_digest() {
    skopeo inspect --no-tags --format '{{.Digest}}' "docker://${image}"
}

# reboot_into STAGE: record the next stage and reboot. A failed check ends the test instead.
reboot_into() {
    if ((failures)); then
        result
        exit 0
    fi
    echo "$1" >"${state}/stage"
    sync
    say "stage ${stage} done, rebooting into stage $1"
    systemctl reboot
    exit 0
}

say "stage ${stage}, running $(booted_digest)"

case "${stage}" in
0)
    # The test registry speaks plain HTTP.
    cat >/etc/containers/registries.conf.d/99-pindu-test.conf <<EOF
[[registry]]
location = "${registry}"
insecure = true
EOF
    wait_for 120 registry_digest
    check "bootc switch to the image in the registry" bootc switch --quiet "${image}"
    reboot_into 1
    ;;
1)
    check "the system runs the image from the registry" \
        test "$(bootc status --json | jq -r '.status.booted.image.image.image')" = "${image}"
    booted_digest >"${state}/digest-old"

    # The host pushes N+1 to the same tag when it reads this line.
    say "waiting-for-update"
    # shellcheck disable=SC2329
    update_published() {
        [[ $(registry_digest) != "$(<"${state}/digest-old")" ]]
    }
    wait_for 900 update_published
    check "the registry serves a new image" update_published
    registry_digest >"${state}/digest-new"

    # If the update service reboots (the stock `bootc upgrade --apply` would), the next boot
    # finds this stage and fails the test.
    echo rebooted-while-staging >"${state}/stage"
    sync
    check "the update timer is active" systemctl is-active bootc-fetch-apply-updates.timer
    check "the timer's service, bootc-fetch-apply-updates.service, succeeds" \
        systemctl start bootc-fetch-apply-updates.service
    check "the new image is staged" test "$(staged_digest)" = "$(<"${state}/digest-new")"
    check "the running system is still the old image" test "$(booted_digest)" = "$(<"${state}/digest-old")"
    # shellcheck disable=SC2329
    no_reboot_pending() {
        [[ ! -e /run/systemd/shutdown/scheduled ]] && ! systemctl list-jobs --no-legend | grep -q -E 'reboot|shutdown|poweroff'
    }
    sleep 20
    check "no reboot is scheduled or under way 20 s later" no_reboot_pending

    # The launcher's system panel (issue #17) sees the staged update in the status file that
    # the update service refreshes.
    check "the update status shows pindu the staged image" \
        update_status ".status.staged.image.imageDigest == \"$(<"${state}/digest-new")\""
    # A rollback, started as the panel starts it, while an update is staged: it is queued,
    # and the staged update is discarded. Starting it again reverts it.
    check "pindu may start pindu-os-rollback.service" start_unit_as_pindu pindu-os-rollback.service
    wait_for 60 update_status '.status.rollbackQueued'
    check "the update status shows the rollback queued" update_status '.status.rollbackQueued'
    check "the rollback discarded the staged update" update_status '.status.staged == null'
    check "pindu-os-rollback.service again" start_unit_as_pindu pindu-os-rollback.service
    wait_for 60 update_status '.status.rollbackQueued == false'
    check "starting it again reverts the rollback" update_status '.status.rollbackQueued == false'
    check "the reverted rollback does not bring the staged update back" update_status '.status.staged == null'
    # Stage N+1 again for the next boot.
    check "the update service stages the new image again" systemctl start bootc-fetch-apply-updates.service
    check "the update status shows the new image staged again" \
        update_status ".status.staged.image.imageDigest == \"$(<"${state}/digest-new")\""
    reboot_into 2
    ;;
rebooted-while-staging)
    check "the update service does not reboot the machine" false
    result
    ;;
2)
    check "the next boot runs the new image" test "$(booted_digest)" = "$(<"${state}/digest-new")"
    check "the new image's marker file is there" test -e "${marker}"
    wait_for 60 update_status '.status.booted.image.imageDigest'
    check "the update status at boot shows the new image booted and the old one as rollback" \
        update_status ".status.booted.image.imageDigest == \"$(<"${state}/digest-new")\" and
            .status.rollback.image.imageDigest == \"$(<"${state}/digest-old")\""
    # The rollback, as the launcher's system panel starts it, once the launcher runs: before
    # that, pindu has no active session in which polkit would allow it.
    wait_for 120 pgrep --uid pindu --exact pindu-launcher
    check "pindu starts pindu-os-rollback.service" start_unit_as_pindu pindu-os-rollback.service
    wait_for 60 update_status '.status.rollbackQueued'
    check "the update status shows the rollback queued" update_status '.status.rollbackQueued'
    reboot_into 3
    ;;
3)
    check "after the rollback the old image runs again" test "$(booted_digest)" = "$(<"${state}/digest-old")"
    check "the new image's marker file is gone" test ! -e "${marker}"
    wait_for 60 update_status '.status.booted.image.imageDigest'
    check "the update status at boot shows the old image booted" \
        update_status ".status.booted.image.imageDigest == \"$(<"${state}/digest-old")\""
    # The update service is still in control: it stages the newer image again.
    check "the update service stages the new image again after the rollback" \
        systemctl start bootc-fetch-apply-updates.service
    check "the update status shows the new image staged" \
        update_status ".status.staged.image.imageDigest == \"$(<"${state}/digest-new")\""
    result
    ;;
*)
    check "known test stage (${stage})" false
    result
    ;;
esac
