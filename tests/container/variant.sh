#!/usr/bin/env bash
# OS-09: the production image has no SSH server and no way to become root; the dev image has
# both, with key-only SSH.
set -euo pipefail
# shellcheck source=tests/container/lib.sh
source /tests/lib.sh

sudo_rules=$(grep -rhsE '^[^#]*(pindu|%wheel)' /etc/sudoers /etc/sudoers.d || true)

case "${VARIANT}" in
prod)
    check_not "sshd is not installed" test -e /usr/sbin/sshd
    check_not "sshd.service does not exist" test -e /usr/lib/systemd/system/sshd.service
    check_not "sudo is not installed" test -e /usr/bin/sudo
    check_eq "no sudo rule exists for pindu or wheel" "" "${sudo_rules}"
    check_eq "pindu is in no group but its own" "pindu" "$(id -nG pindu)"
    ;;
dev)
    check_eq "sshd.service is enabled" enabled "$(systemctl is-enabled sshd.service)"
    # sshd only prints its effective configuration when it has a host key; real ones are
    # generated on first boot.
    host_key=$(mktemp --dry-run)
    ssh-keygen -q -t ed25519 -N '' -f "${host_key}"
    check_eq "sshd refuses passwords" "passwordauthentication no" \
        "$(sshd -T -h "${host_key}" | grep -i '^passwordauthentication ' | tr '[:upper:]' '[:lower:]')"
    check "pindu is in the wheel group" grep -qw wheel <<<"$(id -nG pindu)"
    check_eq "wheel has passwordless sudo" "%wheel ALL=(ALL) NOPASSWD: ALL" \
        "$(grep -hv '^#' /etc/sudoers.d/10-pindu-dev)"
    check "the sudoers files are valid" visudo --check --quiet
    check "VT 2 logs pindu in" \
        grep -q -- '--autologin pindu' /usr/lib/systemd/system/getty@tty2.service.d/10-pindu-dev-autologin.conf
    ;;
*)
    echo "unknown VARIANT '${VARIANT}'"
    exit 1
    ;;
esac

finish
