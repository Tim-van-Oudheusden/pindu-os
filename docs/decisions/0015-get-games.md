# 0015: Get Games

Status: accepted (2026-11-24), settles spec OS-22 (issue #66); amends the polkit paragraph of
[0013](0013-game-sources.md)

## Context

A console installs three game stores through the launcher's Add a Store, and nothing else. Pindu launcher is getting
Get Games: a small catalogue of Flathub's games, plus a short list of extras such as a browser or a media player, that
the owner browses, installs and removes with a controller (the launcher's work packages GG-1 to GG-6). It reuses what
Add a Store already does on this image: the host's `flatpak`, the system installation, Flathub as its only remote
([0013](0013-game-sources.md)). The launcher does the work; the image has to allow and provide what it needs.

- Removing an app did not work. `50-pindu-os.rules` let `pindu` install and update from Flathub; uninstalling still
  needed an administrator, which the console does not have, and the gamescope session has no polkit agent to ask.
- Get Games reads Flathub's AppStream catalogue from `/var/lib/flatpak/appstream/flathub/x86_64/active/`. On a new
  console that folder does not exist until something asks flatpak for it; the launcher runs
  `flatpak update --appstream --system` when it finds the catalogue missing or stale.
- Every removed game can leave a runtime behind that nothing uses.
- The launcher ships default lists (which categories count as games, a blocklist, extras, picks shown first), and a
  distributor may replace them with a file under `/usr/share`.

## Decision

The image gains no package and no pin. It allows uninstalling, cleans up runtimes as root, and ships the console's
lists.

- `system_files/usr/share/polkit-1/rules.d/50-pindu-os.rules` lets `pindu`, in an active local session, uninstall apps
  and runtimes from the system installation (`org.freedesktop.Flatpak.app-uninstall`, `runtime-uninstall`). flatpak's
  system helper passes only the ref with these actions (for an app, its name when it has one), not the remote, so the
  rule cannot and does not check the origin; Flathub is the installation's only remote. Installing from another
  remote, installing bundles, and adding, changing or removing remotes (`configure-remote`, `configure`) still need an
  administrator.
- The catalogue needs no new right. flatpak's system helper deploys a downloaded catalogue under
  `org.freedesktop.Flatpak.appstream-update`, which flatpak's own policy allows the active session (`allow_active`
  `yes`). `tests/vm/guest/boot.sh` runs `flatpak update --appstream --system` as `pindu`, from the user manager the
  launcher runs in and with no polkit agent, and checks that the catalogue's folder exists afterwards.
- `pindu-os-flatpak-update.service` runs `flatpak uninstall --system --unused --noninteractive` after its update, as
  root, after boot and twice a day. The update comes first because it can leave an older runtime branch unused. The
  launcher needs no right for that, and the clean-up never removes a runtime an installed app still uses.
- `system_files/usr/share/pindu-launcher/distributor/get-games.yaml` holds the console's lists, each entry with a
  comment that says why it is there. The launcher's work package GG-2 fixes the path and the format; the file is Pindu
  OS's proposal for both, `version: 1` with four lists (`categories`, `blocklist`, `extras`, `picks`). It starts with
  `Game` as the only category, a blocklist of two apps with a game category that cannot work with a controller alone,
  Kodi and Firefox as extras, and four free games that play with a controller as picks. An image update changes them,
  not a launcher release.
- Updates stay with the timer ([0013](0013-game-sources.md)); Get Games has no update screen.

## Alternatives considered

- A fork of [Bazaar](https://gitlab.gnome.org/World/bazaar), the GNOME Flathub client, with controller support:
  GPL-3.0-or-later, so allowed, but a second program to keep merged with upstream for good, WebKitGTK in the image, and
  a second app reading the controller next to the launcher.
- GNOME Software (GPL-2.0-or-later): built around package back ends a bootc image does not use, and made for a mouse.
- Letting the launcher remove unused runtimes itself: needs the same uninstall right for refs the owner never chose,
  and a removal that waits for the launcher to be open. Root's timer already runs twice a day.
- Checking the remote in the uninstall rule, as the install rule does: the helper does not pass it.
- A first-boot unit that downloads the catalogue: every console would download it whether Get Games is used or not,
  and it goes stale anyway; the launcher refreshes it when it needs it.
- Lists in `/etc`: configuration goes in `/usr` (AGENTS.md), and nothing on a console edits them.

## Consequences

- `pindu` can remove any app or runtime in the system installation without a password, Steam, Heroic and Lutris
  included. That is what Remove is for; there is nothing on the console a removal could take away that an install
  cannot bring back.
- A runtime stays on disk until the next run of the update service, up to 12 hours after a removal.
- `flatpak uninstall --unused`, run as root, does not see apps in `pindu`'s per-user installation. The launcher
  installs into the system installation whenever it lists `flathub`, which it always does here, so there are none.
- The update service fails, and skips the clean-up, when the update fails (no network, for example); the next run
  catches up.
- Until GG-2 settles the format, the lists file is a proposal the launcher does not read. If GG-2 picks another path or
  format, the file moves or changes with it.
- `tests/container/flatpak.sh` installs two apps with their own runtimes from a local repository, removes one, runs the
  service's commands and checks that only the unused runtime is gone; it also checks that the lists file parses and
  holds the four lists. `tests/vm/guest/boot.sh` asks polkit about uninstalling from the launcher's process, downloads
  the catalogue as `pindu`, and checks that `pindu` cannot add a remote.
- A person confirms on a device, with a launcher that has Get Games, that a game installs, plays and is removed with a
  controller alone.
- Revisit when GG-2 fixes the lists' path and format, or when a remote other than Flathub joins the installation:
  the uninstall rule would then need a way to tell remotes apart.
