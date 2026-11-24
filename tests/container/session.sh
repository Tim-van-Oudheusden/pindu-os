#!/usr/bin/env bash
# OS-06: `pindu-session compositor` starts the launcher in gamescope and falls back to cage
# only when gamescope fails to stay up twice in a row. gamescope and cage are stubs on PATH
# that record how they were called; the "few seconds" threshold is shortened to 2. Issue #67:
# gamescope runs in Steam mode, so the launcher decides which window is in front.
set -euo pipefail
# shellcheck source=tests/container/lib.sh
source /tests/lib.sh

work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT
mkdir "${work}/bin"

# cage stub: record the arguments and exit.
cat >"${work}/bin/cage" <<EOF
#!/usr/bin/bash
echo "\$*" >>"${work}/cage.calls"
EOF

# gamescope stub: record the arguments, then behave as ${work}/gamescope.plan says for this
# call (one word per call: "fail" exits 1 at once, "stay" keeps running).
cat >"${work}/bin/gamescope" <<EOF
#!/usr/bin/bash
echo "\$*" >>"${work}/gamescope.calls"
call=\$(wc -l <"${work}/gamescope.calls")
action=\$(sed -n "\${call}p" "${work}/gamescope.plan")
[[ \${action} == stay ]] && exec sleep 30
exit 1
EOF
chmod +x "${work}/bin/cage" "${work}/bin/gamescope"

# An empty DRM tree: no display, so no size arguments unless a test adds one.
mkdir "${work}/drm"

# run_compositor PLAN...: run `pindu-session compositor` against the stubs for at most 6
# seconds, which is three times the shortened threshold.
run_compositor() {
    rm -f "${work}/gamescope.calls" "${work}/cage.calls"
    touch "${work}/gamescope.calls" "${work}/cage.calls"
    printf '%s\n' "$@" >"${work}/gamescope.plan"
    PATH="${work}/bin:${PATH}" PINDU_SESSION_MIN_UPTIME=2 PINDU_SESSION_DRM_ROOT="${work}/drm" \
        timeout 6 /usr/bin/pindu-session compositor >/dev/null 2>&1 || true
}

calls() {
    wc -l <"${work}/$1.calls"
}

run_compositor fail fail
check_eq "gamescope exiting at once is tried twice" 2 "$(calls gamescope)"
check_eq "then cage is started once" 1 "$(calls cage)"
check_eq "cage runs the session client" "-- /usr/bin/pindu-session client" "$(cat "${work}/cage.calls")"
check_eq "gamescope ran the session client in Steam mode on the DRM backend" \
    "--backend drm --steam -- /usr/bin/pindu-session client" "$(head -n 1 "${work}/gamescope.calls")"
check_eq "the retry starts gamescope the same way" \
    "$(sed -n 1p "${work}/gamescope.calls")" "$(sed -n 2p "${work}/gamescope.calls")"

run_compositor stay
check_eq "gamescope that stays up is started once" 1 "$(calls gamescope)"
check_eq "and cage is not started" 0 "$(calls cage)"

run_compositor fail stay
check_eq "one failed start is retried" 2 "$(calls gamescope)"
check_eq "and a second start that stays up means no fallback" 0 "$(calls cage)"

# A 4K display: gamescope renders the launcher at 1080 lines and upscales.
mkdir "${work}/drm/card1-HDMI-A-1"
echo connected >"${work}/drm/card1-HDMI-A-1/status"
printf '3840x2160\n1920x1080\n' >"${work}/drm/card1-HDMI-A-1/modes"
run_compositor stay
check_eq "a 4K display gets a 1080-line render size" \
    "--backend drm --steam -w 1920 -h 1080 -- /usr/bin/pindu-session client" "$(cat "${work}/gamescope.calls")"

printf '1920x1080\n' >"${work}/drm/card1-HDMI-A-1/modes"
run_compositor stay
check_eq "a 1080p display gets no size arguments" \
    "--backend drm --steam -- /usr/bin/pindu-session client" "$(cat "${work}/gamescope.calls")"

# The files the session is made of.
check "the user unit runs pindu-session compositor" \
    grep -qx 'ExecStart=/usr/bin/pindu-session compositor' /usr/lib/systemd/user/pindu-session.service
check "the user unit passes systemd's checks" \
    env XDG_RUNTIME_DIR="${work}" systemd-analyze verify --user /usr/lib/systemd/user/pindu-session.service
check "the session desktop file starts pindu-session" \
    grep -qx 'Exec=pindu-session' /usr/share/wayland-sessions/pindu.desktop
for backend in gtk gnome-keyring; do
    check "the ${backend} portal backend named in gamescope-portals.conf is installed" \
        test -f "/usr/share/xdg-desktop-portal/portals/${backend}.portal"
done

finish
