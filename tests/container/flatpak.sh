#!/usr/bin/env bash
# Issue #29 (spec OS-17): Flatpak with Flathub as the system installation's only remote,
# Fedora's remote kept out also after first boot, controller udev rules for Flatpak Steam,
# and the timer that updates Flatpak apps. Issue #66 (spec OS-22): the update service removes
# unused runtimes, and the image carries the console's lists for the launcher's Get Games.
# Issue #68: Steam's system-wide override, there from first boot. The polkit rule needs a
# logind session to be evaluated; tests/vm/guest/boot.sh checks it from the launcher's process.
set -euo pipefail
# shellcheck source=tests/container/lib.sh
source /tests/lib.sh

# A device starts with an empty /var, which systemd-tmpfiles fills on first boot. The system
# installation does not exist until flatpak first opens it, which is when it applies
# /usr/share/flatpak/remotes.d.
rm -rf /var/lib/flatpak
systemd-tmpfiles --create --prefix=/var/lib/flatpak >/dev/null 2>&1 || true

# Steam's override (issue #68) is in place before Steam is installed, and reads back as the
# permissions the image grants: NetworkManager for the connection Steam shows, the login
# service for its Restart and Shut Down entries.
steam_override=$(flatpak override --system --show com.valvesoftware.Steam 2>/dev/null || true)
check "Steam's override lets it talk to NetworkManager on the system bus" \
    grep -qx 'org.freedesktop.NetworkManager=talk' <<<"${steam_override}"
check "Steam's override lets it talk to the login service on the system bus" \
    grep -qx 'org.freedesktop.login1=talk' <<<"${steam_override}"
check_eq "Steam's override is the image's copy, so an image update changes it" \
    /usr/share/pindu-os/flatpak/overrides/com.valvesoftware.Steam \
    "$(readlink /var/lib/flatpak/overrides/com.valvesoftware.Steam)"

check_eq "the system installation's remotes are flathub alone, disabled ones included" \
    flathub "$(flatpak remotes --system --show-disabled --columns=name)"
check_eq "flathub points at Flathub's repository" \
    https://dl.flathub.org/repo/ "$(flatpak remotes --system --columns=url)"
config=/var/lib/flatpak/repo/config
check "flathub verifies signatures" \
    grep -qx 'gpg-verify=true' <(sed -n '/^\[remote "flathub"\]$/,/^\[/p' "${config}")
check "Flathub's signing key is imported" test -s /var/lib/flatpak/repo/flathub.trustedkeys.gpg
check "tmpfiles.d creates the installation's directory on first boot" \
    grep -qx 'd /var/lib/flatpak 0755 root root -' <(cat /usr/lib/tmpfiles.d/*.conf)

# Fedora's flatpak package enables a unit that adds its own remote at boot. systemd applies
# the presets again on a device's first boot, which must leave it off.
fedora_unit=flatpak-add-fedora-repos.service
check_eq "${fedora_unit} is disabled" disabled "$(systemctl is-enabled "${fedora_unit}")"
systemctl preset-all --preset-mode=enable-only >/dev/null 2>&1
check_eq "${fedora_unit} stays disabled after the first-boot presets" \
    disabled "$(systemctl is-enabled "${fedora_unit}")"

# Steam Input reads the controllers' raw HID nodes and creates virtual pads through uinput;
# inside the Flatpak sandbox it can only use what the host's udev rules hand the user.
rules=/usr/lib/udev/rules.d/60-steam-input.rules
check "the Steam controller rules pass udev's checks" udevadm verify --resolve-names=never "${rules}"
check "Valve's controllers are the logged-in user's" grep -qE '28de.*TAG\+="uaccess"' "${rules}"
check "uinput is the logged-in user's" grep -qE 'KERNEL=="uinput".*TAG\+="uaccess"' "${rules}"

# Flatpak apps update on their own, at low priority, without reboots.
service=pindu-os-flatpak-update.service
check_eq "the Flatpak update timer is enabled" enabled "$(systemctl is-enabled pindu-os-flatpak-update.timer)"
check_eq "the update service first updates the system installation without asking" \
    "ExecStart=/usr/bin/flatpak update --system --noninteractive" \
    "$(systemctl cat "${service}" | grep '^ExecStart=' | head -n 1)"
check "the units pass systemd's checks" systemd-analyze verify "${service}" pindu-os-flatpak-update.timer

# Store links (issue #60). Play and Open Steam hand steam://, heroic:// and lutris: links to
# GLib, which finds their handler through mimeinfo.cache in the installation's exports.
# flatpak writes that file after every app install with its desktop-database trigger, which
# does nothing without the host's update-desktop-database. Stand in for an installed Steam
# with an exported entry that records the link it gets, run the trigger as flatpak does, and
# open a link with the data folders the user manager gives the session (flatpak's environment
# generator; tests/vm/guest/boot.sh checks the launcher's own environment).
work=$(mktemp -d)
cat >"${work}/handler" <<EOF
#!/usr/bin/sh
echo "\$1" >${work}/opened
EOF
chmod +x "${work}/handler"
applications=/var/lib/flatpak/exports/share/applications
mkdir -p "${applications}"
cat >"${applications}/com.valvesoftware.Steam.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Steam
Exec=${work}/handler %u
MimeType=x-scheme-handler/steam;
EOF
/usr/share/flatpak/triggers/desktop-database.trigger /var/lib/flatpak
data_dirs=$(/usr/lib/systemd/user-environment-generators/60-flatpak | sed -n 's/^XDG_DATA_DIRS=//p')
XDG_DATA_DIRS=${data_dirs} gio open steam://open/bigpicture >/dev/null 2>&1 || true
for _ in {1..50}; do
    [[ -s ${work}/opened ]] && break
    sleep 0.1
done
check_eq "a steam:// link opens the app that the system installation exports for it" \
    steam://open/bigpicture "$(cat "${work}/opened" 2>/dev/null)"
rm -rf "${work}"

# Unused runtimes (issue #66). Get Games' Remove uninstalls an app as pindu, which may leave
# its runtime behind; the update service removes it as root. Build two runtimes and two apps
# into a local repository, install both apps, remove one, then run the service's commands in
# their order: the runtime the removed app used must go, the other app's must stay.
work=$(mktemp -d)
# build_ref DIR METADATA_GROUP ID RUNTIME: a build directory flatpak build-export accepts,
# with nothing in it but the metadata.
build_ref() {
    mkdir -p "${work}/$1/files" "${work}/$1/usr" "${work}/$1/export"
    printf '[%s]\nname=%s\nruntime=%s/x86_64/1\nsdk=%s/x86_64/1\n' "$2" "$3" "$4" "$4" >"${work}/$1/metadata"
}
for name in Unused Kept; do
    build_ref "runtime-${name}" Runtime "org.pindu.Test.${name}" "org.pindu.Test.${name}"
    flatpak build-export --runtime --no-update-summary "${work}/repo" "${work}/runtime-${name}" 1 >/dev/null
done
build_ref app-removed Application org.pindu.Test.Removed org.pindu.Test.Unused
build_ref app-stays Application org.pindu.Test.Stays org.pindu.Test.Kept
for app in app-removed app-stays; do
    flatpak build-export --no-update-summary "${work}/repo" "${work}/${app}" stable >/dev/null
done
flatpak build-update-repo "${work}/repo" >/dev/null
flatpak remote-add --system --no-gpg-verify pindu-test "file://${work}/repo"
# The triggers run in bwrap, which a container cannot start; they do not matter here.
flatpak install --system --noninteractive pindu-test org.pindu.Test.Removed org.pindu.Test.Stays >/dev/null 2>&1
flatpak uninstall --system --noninteractive org.pindu.Test.Removed >/dev/null 2>&1
check "a removed app's runtime is still installed before the service runs" \
    flatpak info --system org.pindu.Test.Unused//1
# systemd runs a oneshot's ExecStart= lines in order and stops at the first that fails.
while read -r -a command; do
    "${command[@]}" >/dev/null 2>&1 || break
done < <(systemctl cat "${service}" | sed -n 's/^ExecStart=//p')
check_not "after the update service, the runtime no app uses is gone" \
    flatpak info --system org.pindu.Test.Unused//1
check "the runtime an installed app uses stays" flatpak info --system org.pindu.Test.Kept//1
check "the installed app stays" flatpak info --system org.pindu.Test.Stays
flatpak remote-delete --system --force pindu-test >/dev/null 2>&1
rm -rf "${work}"

# Get Games' lists (issue #66): the launcher reads a distributor's file in place of its
# defaults. It must be where the launcher looks, parse as YAML, and hold four lists of app IDs
# (categories for `categories`), with no app both blocked and offered.
lists=/usr/share/pindu-launcher/distributor/get-games.yaml
check "the Get Games lists are at ${lists}" test -s "${lists}"
check "the Get Games lists parse and hold what the launcher reads" python3 - "${lists}" <<'EOF'
import re, sys, yaml

with open(sys.argv[1]) as f:
    lists = yaml.safe_load(f)
assert lists["version"] == 1
app_id = re.compile(r"^[A-Za-z_][\w-]*(\.[A-Za-z_][\w-]*){2,}$")
for key in ("categories", "blocklist", "extras", "picks"):
    assert isinstance(lists[key], list) and lists[key], key
    assert all(isinstance(entry, str) for entry in lists[key]), key
for key in ("blocklist", "extras", "picks"):
    assert all(app_id.match(entry) for entry in lists[key]), key
offered = set(lists["extras"]) | set(lists["picks"])
assert not offered & set(lists["blocklist"]), offered & set(lists["blocklist"])
EOF

finish
