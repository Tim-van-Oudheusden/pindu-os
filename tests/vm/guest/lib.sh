# Helpers for the scripts that run inside the VM. Each guest script sources this file, which
# the host passes as a credential next to it (tests/vm/lib.sh, vm_guest_script). Everything
# is reported on the second serial port, which the host reads as test.log. The first one may
# be the console, and its getty hangs up whoever else has it open.
# shellcheck shell=bash

exec >/dev/ttyS1 2>&1

failures=0

say() {
    echo "PINDU-TEST: $*"
}

# check DESCRIPTION COMMAND...
check() {
    local description=$1
    shift
    if "$@" >/dev/null 2>&1; then
        say "ok    ${description}"
    else
        say "FAIL  ${description}"
        failures=$((failures + 1))
    fi
}

# wait_for SECONDS COMMAND...: retry the command once a second until it succeeds.
wait_for() {
    local deadline=$((SECONDS + $1))
    shift
    until "$@" >/dev/null 2>&1; do
        ((SECONDS < deadline)) || return 1
        sleep 1
    done
}

# as_pindu COMMAND...: run a command as the pindu user, on its session bus.
as_pindu() {
    runuser -u pindu -- env XDG_RUNTIME_DIR=/run/user/1000 \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus "$@"
}

# result: print the verdict the host waits for, with logs when something failed.
result() {
    if ((failures)); then
        # Every line starts with PINDU-TEST, which is how the host tells the report from the
        # firmware's output on the same port.
        say "---- journal of the pindu user"
        journalctl --boot --no-pager _UID=1000 | tail --lines=120 | sed 's/^/PINDU-TEST:   /'
        say "---- greetd"
        journalctl --boot --no-pager --unit greetd.service | tail --lines=40 | sed 's/^/PINDU-TEST:   /'
        echo "PINDU-TEST-RESULT: FAIL (${failures} failed)"
    else
        echo "PINDU-TEST-RESULT: PASS"
    fi
}
