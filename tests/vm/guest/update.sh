# OS-12, inside the VM: an update is staged without a reboot, the next boot runs it, and
# `bootc rollback` returns to the previous image. Runs as root from the injected
# pindu-test.service on every boot (tests/vm/lib.sh).
#
# The test spans four boots. /var/lib/pindu-test/stage says which one this is:
#   0  booted from the disk image: switch to the same image (N) as served by the registry
#   1  running N from the registry: wait for the host to push N+1, run the update service,
#      check that N+1 is staged and that nothing rebooted
#   2  running N+1: roll back
#   3  running N again: verdict
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
    reboot_into 2
    ;;
rebooted-while-staging)
    check "the update service does not reboot the machine" false
    result
    ;;
2)
    check "the next boot runs the new image" test "$(booted_digest)" = "$(<"${state}/digest-new")"
    check "the new image's marker file is there" test -e "${marker}"
    check "bootc rollback" bootc rollback
    reboot_into 3
    ;;
3)
    check "after the rollback the old image runs again" test "$(booted_digest)" = "$(<"${state}/digest-old")"
    check "the new image's marker file is gone" test ! -e "${marker}"
    result
    ;;
*)
    check "known test stage (${stage})" false
    result
    ;;
esac
