# OS-07 and OS-08, inside the VM: the machine logs pindu in by itself and ends up showing the
# launcher. Runs as root from the injected pindu-test.service (tests/vm/lib.sh).
# shellcheck shell=bash
# shellcheck source=tests/vm/guest/lib.sh
source "${CREDENTIALS_DIRECTORY}/pindu.test.lib"

login_deadline=${PINDU_TEST_LOGIN_DEADLINE:-60}

# The ID of pindu's logind session on seat0. Its class must be "user": greetd runs a greeter's
# command as class "greeter", in an SELinux domain that may not start the session (issue #18).
pindu_session() {
    loginctl list-sessions --json=short |
        jq -r 'first(.[] | select(.user == "pindu" and .seat == "seat0" and .class == "user") | .session) // empty'
}

# shellcheck disable=SC2329  # called through wait_for
pindu_on_seat0() {
    [[ -n $(pindu_session) ]]
}

# The 60 seconds count from the start of the kernel, which is what /proc/uptime measures.
if wait_for 300 pindu_on_seat0; then
    uptime=$(cut -d . -f 1 /proc/uptime)
    check "pindu has a session on seat0 within ${login_deadline} s of boot (took ${uptime} s)" \
        test "${uptime}" -le "${login_deadline}"
else
    check "pindu has a session on seat0" false
fi

check "the pindu password is locked" test "$(passwd --status pindu | cut -d ' ' -f 2)" = L

# shellcheck disable=SC2329  # called through check and wait_for
unit_active() {
    as_pindu systemctl --user is-active "$1"
}

# pindu-session.service becomes active when the launcher is about to start, after at most
# two gamescope attempts and the switch to cage.
wait_for 120 unit_active pindu-session.service
check "pindu-session.service is active" unit_active pindu-session.service
wait_for 30 pgrep --uid pindu --exact pindu-launcher
check "a pindu-launcher process exists" pgrep --uid pindu --exact pindu-launcher

if pgrep --uid pindu --exact cage >/dev/null; then
    say "note  compositor: cage (gamescope did not start on this GPU)"
elif pgrep --uid pindu gamescope >/dev/null; then
    say "note  compositor: gamescope"
else
    check "a compositor is running" false
fi

# What the session needs around the launcher: sound, portals, and a keyring that is open
# without a password prompt.
# The sound units start with the user manager, at the same moment as the session.
wait_for 30 unit_active wireplumber.service
check "PipeWire's socket is listening" unit_active pipewire.socket
check "WirePlumber is running" unit_active wireplumber.service
check "the settings portal answers" as_pindu busctl --user call --timeout=30 \
    org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
    org.freedesktop.DBus.Properties Get ss org.freedesktop.portal.Settings version
# A client unlocks the default keyring before it stores a secret. The reply names a prompt
# object when the user has to type a password; "/" means none was needed.
keyring=/org/freedesktop/secrets/collection/Default_5fkeyring
# shellcheck disable=SC2329  # called through check
keyring_opens_without_prompt() {
    [[ $(as_pindu busctl --user call --timeout=30 org.freedesktop.secrets /org/freedesktop/secrets \
        org.freedesktop.Secret.Service Unlock ao 1 "${keyring}") == "aoo 1 \"${keyring}\" \"/\"" ]] &&
        [[ $(as_pindu busctl --user get-property org.freedesktop.secrets "${keyring}" \
            org.freedesktop.Secret.Collection Locked) == "b false" ]]
}
check "the default keyring opens without a password prompt" keyring_opens_without_prompt
check "one gnome-keyring-daemon is running" test "$(pgrep --uid pindu --count --exact gnome-keyring-d)" = 1

# The launcher's system panel (issue #17): the update status it reads, and what polkit lets
# it do without a password. The session has no polkit agent, so anything but a plain yes
# fails there. The launcher runs in pindu's user manager, so its process is the subject.
wait_for 60 update_status '.status.booted.image.imageDigest'
check "the update status names the booted image, readable by pindu" \
    update_status '.status.booted.image.imageDigest | startswith("sha256:")'
check "the update status file has mode 0644" test "$(stat -c %a /run/pindu-os/update-status.json)" = 644
launcher=$(pgrep --uid pindu --exact --newest pindu-launcher)
for action in org.freedesktop.login1.power-off org.freedesktop.login1.reboot org.freedesktop.login1.suspend \
    org.freedesktop.NetworkManager.network-control org.freedesktop.NetworkManager.wifi.scan \
    org.freedesktop.NetworkManager.settings.modify.system; do
    check "polkit allows the launcher ${action}" pkcheck --action-id "${action}" --process "${launcher}"
done
check "polkit allows the launcher to start pindu-os-rollback.service" \
    pkcheck --action-id org.freedesktop.systemd1.manage-units --process "${launcher}" \
    --detail unit pindu-os-rollback.service --detail verb start
check_not "polkit refuses the launcher any other verb on pindu-os-rollback.service" \
    pkcheck --action-id org.freedesktop.systemd1.manage-units --process "${launcher}" \
    --detail unit pindu-os-rollback.service --detail verb stop
check_not "polkit refuses the launcher to start another unit" \
    pkcheck --action-id org.freedesktop.systemd1.manage-units --process "${launcher}" \
    --detail unit bootc-fetch-apply-updates.service --detail verb start
check_not "systemd refuses pindu to start another system unit" \
    start_unit_as_pindu pindu-os-update-status.service

# The launcher's "add a store" flow (issue #29, pindu-launcher#378): from its process in
# pindu's user manager it lists the system installation's remotes, then installs from flathub
# without a password. pkcheck asks polkit what flatpak's system helper asks on Deploy.
check "pindu sees flathub in the system installation" \
    test "$(as_pindu systemd-run --user --quiet --wait --pipe -- flatpak remotes --system --columns=name)" = flathub
steam=app/com.valvesoftware.Steam/x86_64/stable
for action in app-install runtime-install app-update runtime-update; do
    check "polkit allows the launcher ${action} from flathub" \
        pkcheck --action-id "org.freedesktop.Flatpak.${action}" --process "${launcher}" \
        --detail origin flathub --detail ref "${steam}"
done
check_not "polkit refuses the launcher app-install from another remote" \
    pkcheck --action-id org.freedesktop.Flatpak.app-install --process "${launcher}" \
    --detail origin fedora --detail ref "${steam}"
for action in app-uninstall runtime-uninstall install-bundle configure-remote configure; do
    check_not "polkit refuses the launcher org.freedesktop.Flatpak.${action}" \
        pkcheck --action-id "org.freedesktop.Flatpak.${action}" --process "${launcher}" \
        --detail origin flathub --detail remote flathub --detail ref "${steam}"
done

# An installed system (tests/vm/install.sh) must update from the registry, signatures enforced.
if [[ -n ${PINDU_TEST_EXPECT_IMAGE:-} ]]; then
    check "updates come from ${PINDU_TEST_EXPECT_IMAGE}" \
        test "$(bootc status --json | jq -r '.spec.image.image')" = "${PINDU_TEST_EXPECT_IMAGE}"
    check "updates must pass the signature policy" \
        test "$(bootc status --json | jq -r '.spec.image.signature')" = containerPolicy
fi

# A session that ends comes back by itself (decision 0004). Kill the launcher, as a crash
# would: the compositor exits, the unit fails, and greetd must log pindu in again in a new
# session of class "user" that starts the unit and the launcher once more.
first_session=$(pindu_session)
first_launcher=$(pgrep --uid pindu --exact --newest pindu-launcher || true)
pkill --signal KILL --uid pindu --exact pindu-launcher
# shellcheck disable=SC2329  # called through check and wait_for
session_came_back() {
    local session launcher
    session=$(pindu_session)
    launcher=$(pgrep --uid pindu --exact --newest pindu-launcher) &&
        [[ -n ${session} && ${session} != "${first_session}" && ${launcher} != "${first_launcher}" ]] &&
        unit_active pindu-session.service
}
wait_for 120 session_came_back
check "after the launcher is killed, pindu gets a new session with the unit and the launcher" session_came_back

result
