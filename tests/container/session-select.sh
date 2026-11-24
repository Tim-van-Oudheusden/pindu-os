#!/usr/bin/env bash
# Issue #69: Steam's Switch to Desktop runs steamos-session-select inside its Flatpak sandbox.
# Pindu OS's copy must be where Steam's override points the sandbox after boot, and it must
# bring the launcher back when the launcher answers on the session bus, and close Steam when it
# does not. gdbus and steam are stubs on PATH that record how they were called.
set -euo pipefail
# shellcheck source=tests/container/lib.sh
source /tests/lib.sh

# A device starts with an empty /var, which systemd-tmpfiles fills on every boot.
rm -rf /var/lib/flatpak /var/lib/pindu-os
systemd-tmpfiles --create --remove --boot --prefix=/var/lib/flatpak --prefix=/var/lib/pindu-os >/dev/null 2>&1 || true

script=/var/lib/pindu-os/steam/steamos-session-select
check "the boot puts steamos-session-select where Steam's sandbox is given it" test -x "${script}"
check "it is the image's copy" cmp "${script}" /usr/libexec/pindu-os/steam/steamos-session-select
check "the sandbox's folder belongs to root, so Steam cannot change the script" \
    test "$(stat -c %U "$(dirname "${script}")")" = root

# What `flatpak run` applies to Steam: the folder read-only, first in PATH, and the launcher's
# name on the session bus.
override=$(flatpak override --system --show com.valvesoftware.Steam 2>/dev/null || true)
check "Steam's sandbox gets the folder read-only" grep -qx 'filesystems=/var/lib/pindu-os/steam:ro;' <<<"${override}"
check "Steam may call the launcher on the session bus" \
    grep -qx 'io.github.tim_van_oudheusden.pindu-launcher=talk' <<<"${override}"
sandbox_path=$(sed -n 's/^PATH=//p' <<<"${override}")
check_eq "with the PATH the override sets, Steam finds Pindu OS's steamos-session-select" \
    "${script}" "$(PATH=${sandbox_path} command -v steamos-session-select)"
check "and still finds its own programs after it" grep -q ':/app/bin:/app/utils/bin:/usr/bin$' <<<"${sandbox_path}"

work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT
mkdir "${work}/bin"

# gdbus stub: records each call. NameHasOwner answers as ${work}/owner says ("true" or
# "false"); ActivateAction succeeds unless ${work}/action says "fail", as a launcher without
# the action does.
cat >"${work}/bin/gdbus" <<EOF
#!/usr/bin/bash
echo "\$*" >>"${work}/gdbus.calls"
case "\$*" in
*org.freedesktop.DBus.NameHasOwner*) echo "(\$(cat "${work}/owner"),)" ;;
*org.freedesktop.Application.ActivateAction*)
    [[ \$(cat "${work}/action") == fail ]] && { echo "Error: Unknown action" >&2; exit 1; }
    echo "()" ;;
*) exit 1 ;;
esac
EOF
# steam stub: records its arguments and exits as ${work}/steam says.
cat >"${work}/bin/steam" <<EOF
#!/usr/bin/bash
echo "\$*" >>"${work}/steam.calls"
exit "\$(cat "${work}/steam")"
EOF
chmod +x "${work}/bin/gdbus" "${work}/bin/steam"

# select OWNER ACTION STEAM_STATUS ARGS...: run the script as Steam does, with the stubs.
select_session() {
    echo "$1" >"${work}/owner"
    echo "$2" >"${work}/action"
    echo "$3" >"${work}/steam"
    shift 3
    rm -f "${work}/gdbus.calls" "${work}/steam.calls"
    touch "${work}/gdbus.calls" "${work}/steam.calls"
    status=0
    PATH="${work}/bin:${sandbox_path}" timeout 10 steamos-session-select "$@" >/dev/null 2>&1 || status=$?
}

for argument in desktop plasma ""; do
    select_session true ok 0 ${argument:+"${argument}"}
    check_eq "with the launcher on the bus (argument '${argument}'), it asks the launcher to come back" \
        "call --session --timeout 5 --dest io.github.tim_van_oudheusden.pindu-launcher --object-path /io/github/tim_van_oudheusden/pindu_launcher --method org.freedesktop.Application.ActivateAction leave-big-picture [] {}" \
        "$(grep ActivateAction "${work}/gdbus.calls")"
    check_eq "and leaves Steam running (argument '${argument}')" "" "$(cat "${work}/steam.calls")"
    check_eq "and succeeds (argument '${argument}')" 0 "${status}"
done

select_session false ok 0 desktop
check_eq "with no launcher on the bus, it does not call one, which would start a new launcher" \
    "" "$(grep ActivateAction "${work}/gdbus.calls" || true)"
check_eq "and closes Steam instead" -shutdown "$(cat "${work}/steam.calls")"
check_eq "and succeeds" 0 "${status}"

select_session true fail 0 desktop
check_eq "with a launcher that does not have the action, it closes Steam" -shutdown "$(cat "${work}/steam.calls")"
check_eq "and succeeds" 0 "${status}"

select_session false ok 1 desktop
check_eq "when closing Steam fails too, it still succeeds" 0 "${status}"

finish
