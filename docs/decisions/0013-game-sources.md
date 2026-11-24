# 0013: Game sources

Status: accepted (2026-11-17), settles spec OS-17 (issue #29); amended 2026-11-23 for umu-launcher (issue #59);
amended 2026-11-24 for Steam's network state and power entries (issue #68)

## Context

A new console boots into an empty library: the image has no store, and the launcher has no way to add one. Spec OS-17
left open whether Steam, umu-launcher, MangoHud and GameMode go into the image as RPMs or arrive as Flatpaks after
first boot. pindu-launcher's "add a store" flow (pindu-launcher#378) installs Steam, Heroic or Lutris from Flathub with
the `flatpak` CLI: into the system installation when `flatpak remotes --system` lists `flathub`, otherwise into the
user's. The production image has no password and no polkit agent, so anything that asks for authentication fails.

The launcher also runs Windows games itself: a game or its installer added with Add Game starts through `umu-run`,
which the launcher looks for on `PATH`. The image had none, so the launcher's Library Health reported umu-launcher
missing on the device test of 0.7.0-rc.2, with no way to install it on a read-only console (issue #59).

## Decision

Stores are Flatpaks from Flathub, installed on request into the system installation. The game helpers stay RPMs, and
umu-launcher comes from its own release, pinned like the launcher.

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
- Store links (issue #60): Play hands a store game to its store as a link (`steam://rungameid/…`,
  `heroic://launch?…`, `lutris:rungameid/…`), and Open Steam sends `steam://open/bigpicture`. GLib finds the app for
  a link scheme through `mimeinfo.cache` in `/var/lib/flatpak/exports/share/applications`. flatpak's
  `desktop-database` trigger writes that file after each app install, update or removal, by running the host's
  `update-desktop-database`, so `desktop-file-utils` is in the image (`40-session-packages.sh`). flatpak's user
  environment generator already puts the exports in the session's `XDG_DATA_DIRS`.
- Controllers: `steam-devices`, from Fedora's own repositories, was already in the image. Its udev rules give the
  logged-in user Valve's and other controllers' HID nodes and `uinput`, which Flatpak Steam needs from the host.
- Steam's Flatpak gets a system-wide override (issue #68). Its manifest lets it reach UDisks2 and UPower on the system
  bus, but not NetworkManager, which Steam's console interface reads the connection from, nor the login service
  (`org.freedesktop.login1`), which restarts and powers off. The device test of 0.7.0-rc.3 found Steam signed in and
  downloading while it showed no network connection, and its Restart and Shut Down entries doing nothing.
  `system_files/usr/share/pindu-os/flatpak/overrides/com.valvesoftware.Steam` grants `talk` to both names. flatpak
  reads system overrides only from `/var/lib/flatpak/overrides`, so `tmpfiles.d/pindu.conf` links the file there on
  every boot: an image update changes it, it is there before Steam is installed, and a file root puts there instead is
  left alone.
  - NetworkManager: Steam shows the connection it uses. Its network settings can then also change connections, as far
    as polkit lets `pindu`'s active session: connect and disconnect, scan for Wi-Fi and save system-wide connections
    (Fedora's defaults and `50-pindu-os.rules`), which the launcher's Quick Access already does.
  - Power: granted. Steam's Restart and Shut Down then ask the login service, which polkit already lets the active
    session use to power off, reboot and suspend without a password. A dead Shut Down button on a console is worse than
    a second way to do what the launcher's power dock does, and the grant adds no power the session does not already
    have.
- MangoHud and GameMode stay RPMs (`40-session-packages.sh`): games outside Flatpak use them directly, and Flatpak
  games reach GameMode through `xdg-desktop-portal`.
- umu-launcher is `/usr/bin/umu-run`, the zipapp from its GitHub release. `image.env` pins `UMU_VERSION` and
  `UMU_SHA256`; the `umu` stage of the `Containerfile` downloads the file and fails unless it matches, and
  `build_files/55-umu.sh` installs it and checks that it runs and reports the pinned version. The zipapp carries its
  Python libraries (python-xlib, urllib3, truststore) and runs on Fedora's `python3`, which `40-session-packages.sh`
  lists for it. Renovate follows its releases the way it follows the launcher's. Heroic and Lutris keep bringing
  their own.
- No 32-bit graphics drivers. umu starts a game in the Steam Linux Runtime container, which takes its graphics drivers
  from the host, and the image has only 64-bit Mesa. Proton runs a 32-bit Windows game as a 32-bit Linux process
  unless its WoW64 mode is switched on (`PROTON_USE_WOW64=1`, still opt-in and experimental), so a 32-bit Windows game
  added with Add Game gets no GL or Vulkan driver and is expected not to start. Games from Steam, Heroic and Lutris are
  not affected: their Flatpak runtimes bring 32-bit drivers of their own.

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
- umu-launcher from Fedora: there is no package; its review was closed as WONTFIX
  ([Red Hat Bugzilla 2318468](https://bugzilla.redhat.com/show_bug.cgi?id=2318468)).
- umu-launcher's release RPM: upstream builds it for particular Fedora releases (fc43 and fc44 for 1.4.4), and the fc44
  one requires `python(abi) = 3.14` and installs into `python3.14/site-packages`. Fedora 45 has Python 3.15, so it
  does not install. The zipapp has no such tie.
- umu-launcher from Terra or a COPR: a new package repository for one program.
- Packaging umu-launcher under `packages/` (decision 0008): a build in this repository for a file upstream already
  ships.
- 32-bit Mesa (`mesa-dri-drivers`, `mesa-vulkan-drivers`, `vulkan-loader`, the GL and EGL libraries, all `i686`):
  38 packages, 417 MiB installed (89 MiB to download), `llvm-libs` alone 150 MiB, which every image update carries.
  The Steam RPM was turned down above for the same stack.
- Leaving Steam's power entries dead and pointing to the launcher's power dock: one permission fixes them, and a
  console entry that does nothing reads as a fault.
- The override in Steam's own data folder or the user's installation (`flatpak override --user`): `pindu` could
  change it, and it would not follow image updates.
- Copying the override into `/var` instead of linking it: a later image could not change it on devices that already
  have it.

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
- The first Windows game that umu starts downloads the Steam Linux Runtime and a Proton build into `pindu`'s home, so
  that start needs a network and takes a while; the launcher follows the download. umu's optional modules for delta
  updates (`cbor2`, `xxhash`, `pyzstd`) are not in the image, so a new Proton build downloads whole.
- A 32-bit Windows game added with Add Game is expected not to start until Proton runs 32-bit games through WoW64 by
  default or the image ships 32-bit Mesa; revisit then, or when a device test shows otherwise.
- MangoHud inside Flatpak games needs Flathub's `org.freedesktop.Platform.VulkanLayer.MangoHud` extension; the host
  RPM does not reach the sandbox.
- A console that installed a store before `desktop-file-utils` was in the image has no `mimeinfo.cache` until flatpak
  next installs, updates or removes an app there; its store links fail until then.
- `tests/container/flatpak.sh` checks the remote, the key, the disabled Fedora unit across the first-boot presets,
  Steam's override after the first-boot tmpfiles run, the controller rules, the update units, and that a `steam://`
  link opens the app an install exports for it. `tests/vm/guest/boot.sh` checks that `pindu` sees `flathub` and
  Steam's override, asks polkit about each Flatpak action from the launcher's process, and opens a `steam://` link with
  the launcher's environment.
- Whether Steam's Restart and Shut Down use the login service outside SteamOS is not documented
  ([flathub/com.valvesoftware.Steam#1411](https://github.com/flathub/com.valvesoftware.Steam/issues/1411) reports the
  same dead entry). A person checks on a device that Steam shows its connection and that both entries work; if they
  still do nothing, this grant comes out again.
- Revisit when the launcher offers uninstalling, when a store needs a remote other than Flathub, or when a variant
  (handheld, spec OS-21) ships a store preinstalled.
