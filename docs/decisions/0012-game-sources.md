# 0012: Game sources

Status: accepted (2026-11-17), settles spec OS-17 (issue #29)

## Context

A new console boots into an empty library: the image has no store, and the launcher has no way to add one. Spec OS-17
left open whether Steam, umu-launcher, MangoHud and GameMode go into the image as RPMs or arrive as Flatpaks after
first boot. pindu-launcher's "add a store" flow (pindu-launcher#378) installs Steam, Heroic or Lutris from Flathub with
the `flatpak` CLI: into the system installation when `flatpak remotes --system` lists `flathub`, otherwise into the
user's. The production image has no password and no polkit agent, so anything that asks for authentication fails.

## Decision

Stores are Flatpaks from Flathub, installed on request into the system installation. The game helpers stay RPMs.

- `flatpak` is in the image (`build_files/40-session-packages.sh`). No store is preinstalled; the launcher asks which
  one.
- Flathub is the system installation's only remote, declared in
  `system_files/usr/share/flatpak/remotes.d/flathub.flatpakrepo`, an unchanged copy of Flathub's own file with its
  signing key. flatpak applies the file the first time it opens `/var/lib/flatpak`, which `tmpfiles.d/pindu.conf`
  creates on first boot, and records it as applied.
- Fedora's remote stays out. The flatpak package enables `flatpak-add-fedora-repos.service`, which adds it at boot;
  `build_files/60-system-files.sh` disables the unit, and
  `system_files/usr/lib/systemd/system-preset/40-pindu-os.preset` keeps it disabled when systemd applies the presets
  on first boot.
- `system_files/usr/share/polkit-1/rules.d/50-pindu-os.rules` lets `pindu`, in an active local session, install and
  update apps and runtimes whose origin is `flathub` (`org.freedesktop.Flatpak.app-install`, `runtime-install`,
  `app-update`, `runtime-update`). Fedora's defaults already allow the active session to update, refresh remotes and
  maintain the repository. Installing from any other remote, uninstalling, installing bundles and adding or changing
  remotes still need an administrator, which the console does not have.
- `pindu-os-flatpak-update.timer` runs `flatpak update --system --noninteractive` 30 minutes after boot and every
  12 hours, at idle CPU and I/O priority, once the installation exists. A running app keeps its version until it
  starts again.
- Controllers: `steam-devices`, from Fedora's own repositories, was already in the image. Its udev rules give the
  logged-in user Valve's and other controllers' HID nodes and `uinput`, which Flatpak Steam needs from the host.
- MangoHud and GameMode stay RPMs (`40-session-packages.sh`): games outside Flatpak use them directly, and Flatpak
  games reach GameMode through `xdg-desktop-portal`. umu-launcher is not in the image; Heroic and Lutris bring their
  own.

## Alternatives considered

- Steam as an RPM in the image: it lives in RPM Fusion, a new package repository, and pulls in a 32-bit library stack
  that every image update would then carry. Heroic and Lutris would still need another route.
- A store preinstalled in the image or on first boot: the user's choice of store is the launcher's flow, the issue puts
  it out of scope, and every console would download one whether it is wanted or not.
- A first-boot oneshot running `flatpak remote-add --system --if-not-exists flathub`: works, but is one more unit
  whose state lives in `/var`. `remotes.d` is the declarative form flatpak reads by itself.
- The file in `/etc/flatpak/remotes.d`: flatpak reads `/usr/share/flatpak/remotes.d` as well, and configuration goes
  in `/usr` (AGENTS.md).
- Per-user installations only: needs no polkit rule, but the OS cannot update the apps without a user session and
  every user would download their own copy. The launcher still falls back to it where there is no system remote.
- No update timer, leaving updates to the stores or the launcher: Flatpak apps would never update on a console without
  a settings UI, and the runtimes carry security fixes.

## Consequences

- flatpak's hard dependencies bring `appstream`, `python3` and, through its parental controls library,
  `accountsservice`, whose D-Bus-activated daemon creates its state directory when it starts; `90-cleanup.sh` drops
  the copy in `/var`.
- The console needs network on first use of a store; installing Steam downloads its runtime and the 32-bit GL
  extensions, a few gigabytes.
- `pindu` can fill the disk with Flathub apps without a password. It cannot remove them without an administrator; the
  launcher needs `app-uninstall` granted the same way when it offers that.
- flatpak applies `remotes.d` once per installation: a later image with a changed `flathub.flatpakrepo` does not
  change the remote on devices that already have it, and a remote the user removed is not added back.
- MangoHud inside Flatpak games needs Flathub's `org.freedesktop.Platform.VulkanLayer.MangoHud` extension; the host
  RPM does not reach the sandbox.
- `tests/container/flatpak.sh` checks the remote, the key, the disabled Fedora unit across the first-boot presets,
  the controller rules and the update units. `tests/vm/guest/boot.sh` checks that `pindu` sees `flathub` and asks
  polkit about each Flatpak action from the launcher's process.
- Revisit when the launcher offers uninstalling, when a store needs a remote other than Flathub, or when a variant
  (handheld, spec OS-21) ships a store preinstalled.
