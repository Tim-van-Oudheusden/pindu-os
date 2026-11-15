# Shared helpers for the container tests. Each test runs inside the built image (`just test`)
# with tests/container at /tests, build_files at /build_files, image.env in the environment
# and VARIANT set to the image's variant.
# shellcheck shell=bash

failures=0

# check DESCRIPTION COMMAND...: run the command, record a failure if it does not succeed.
check() {
    local description=$1
    shift
    if "$@" >/dev/null 2>&1; then
        echo "ok    ${description}"
    else
        echo "FAIL  ${description}"
        failures=$((failures + 1))
    fi
}

# check_not DESCRIPTION COMMAND...: the command must fail.
check_not() {
    local description=$1
    shift
    if "$@" >/dev/null 2>&1; then
        echo "FAIL  ${description}"
        failures=$((failures + 1))
    else
        echo "ok    ${description}"
    fi
}

# check_eq DESCRIPTION EXPECTED ACTUAL
check_eq() {
    if [[ $2 == "$3" ]]; then
        echo "ok    $1"
    else
        echo "FAIL  $1: expected '$2', got '$3'"
        failures=$((failures + 1))
    fi
}

finish() {
    if ((failures)); then
        echo "${failures} check(s) failed"
        exit 1
    fi
}
