#!/usr/bin/env bash
# OS-07, the part visible without booting: the pindu account, greetd's autologin and the
# default target. tests/vm/boot.sh checks the login itself.
set -euo pipefail
# shellcheck source=tests/container/lib.sh
source /tests/lib.sh

check_eq "pindu has UID and GID 1000, its home under /var/home and bash as shell" \
    "pindu:x:1000:1000:Pindu:/var/home/pindu:/usr/bin/bash" "$(getent passwd pindu)"
check_eq "the pindu password is locked" L "$(passwd --status pindu | cut -d ' ' -f 2)"
check "tmpfiles.d creates the home directory" \
    grep -qx 'd /var/home/pindu 0700 pindu pindu -' /usr/lib/tmpfiles.d/pindu.conf

check_eq "greetd is the display manager" enabled "$(systemctl is-enabled greetd.service)"
check_eq "the default target is graphical.target" graphical.target "$(systemctl get-default)"

# greetd's autologin: both sessions run pindu-session as pindu on VT 1.
config=$(grep -v '^#' /etc/greetd/config.toml | tr -d ' \n')
check "greetd uses VT 1" grep -q '\[terminal\]vt=1' <<<"${config}"
check "greetd logs pindu in at boot" \
    grep -q '\[initial_session\]command="pindu-session"user="pindu"' <<<"${config}"

# The session comes back through a restart of greetd, which runs initial_session again only
# when its runfile is gone (issue #18); tests/vm/boot.sh ends a session and watches it return.
runfile=$(sed -n 's/^runfile = "\(.*\)"$/\1/p' /etc/greetd/config.toml)
check "greetd names its runfile" test -n "${runfile}"
check "every start of greetd deletes the runfile" \
    grep -qx "ExecStartPre=/usr/bin/rm -f ${runfile}" <(systemctl cat greetd.service)
check "greetd restarts when it exits" grep -qx 'Restart=always' <(systemctl cat greetd.service)
check "default_session ends greetd instead of running the session as a greeter" \
    grep -q '\[default_session\]command="/usr/bin/true"user="greetd"' <<<"${config}"

finish
