#!/usr/bin/env bash
# Issue #29 (spec OS-17): Flatpak with Flathub as the system installation's only remote,
# Fedora's remote kept out also after first boot, controller udev rules for Flatpak Steam,
# and the timer that updates Flatpak apps. The polkit rule needs a logind session to be
# evaluated; tests/vm/guest/boot.sh checks it from the launcher's process.
set -euo pipefail
# shellcheck source=tests/container/lib.sh
source /tests/lib.sh

# A device starts with an empty /var: the system installation does not exist until flatpak
# first opens it, which is when it applies /usr/share/flatpak/remotes.d.
rm -rf /var/lib/flatpak
mkdir /var/lib/flatpak

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
check_eq "the update service updates the system installation without asking" \
    "ExecStart=/usr/bin/flatpak update --system --noninteractive" \
    "$(systemctl cat "${service}" | grep '^ExecStart=')"
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

finish
