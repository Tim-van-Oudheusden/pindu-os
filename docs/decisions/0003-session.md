# 0003: Session

Status: accepted (2026-11-15); amended 2026-11-24: gamescope runs in Steam mode
([amendment](#amendment-2026-11-24-steam-mode), issue #67)

## Context

The launcher must fill the screen with nothing else around it, and games it starts must take over the display.
gamescope is the compositor the launcher's README documents. gamescope-session-plus, the usual wrapper around it, always
starts gamescope with `--steam`, and in that mode gamescope shows only windows that carry the `STEAM_GAME` X property.
pindu-launcher does not set that property yet. A VM's virtual GPU has no Vulkan, so gamescope does not start there.

## Decision

Run gamescope on the DRM backend, with cage as fallback, from our own script `system_files/usr/bin/pindu-session` and
user unit `system_files/usr/lib/systemd/user/pindu-session.service`.

- The login entry point (`pindu-session` without arguments) sets `XDG_CURRENT_DESKTOP=gamescope`, exports the session
  environment and runs `systemctl --user start --wait pindu-session.service`.
- The unit is `Type=notify`, binds `graphical-session.target` and runs `pindu-session compositor`, which starts
  `gamescope --backend drm -- pindu-session client` (`--steam` since the [amendment](#amendment-2026-11-24-steam-mode)).
- A gamescope run shorter than 10 seconds counts as a failed start. After two in a row the script execs
  `cage -- pindu-session client`.
- `client` publishes the display to the user manager and D-Bus, sends readiness and execs `pindu-launcher --fullscreen`.
  Under gamescope it sets `GDK_BACKEND=x11`, so the launcher is an X11 client on gamescope's Xwayland.
- On a display taller than 1080 lines gamescope renders at 1080 lines and upscales (`-w ... -h 1080`), because the
  launcher draws at scale 1 under Xwayland.
- `system_files/usr/share/xdg-desktop-portal/gamescope-portals.conf` selects the GTK portal backend for this desktop
  name under both compositors.

## Alternatives considered

- gamescope-session-plus: it always passes `--steam`, and gamescope would then show no launcher window. It becomes the
  right choice once the launcher speaks gamescope's window-property protocol (spec L-02, OS-18).
- gamescope alone, without a fallback: VMs and GPUs without usable Vulkan would show a black screen, and the VM tests
  could not see the launcher.
- A desktop compositor (GNOME Shell, KWin): pulls in a desktop environment the console never shows.

## Consequences

- No Quick Access overlay over a running game, no MangoApp and none of gamescope-session-plus's per-device quirks until
  the move to `--steam` mode. Focus handover to games relies on plain gamescope.
- Fedora 45 packages gamescope 3.16, cage and greetd, so no third-party repository is enabled
  (`build_files/40-session-packages.sh`, `build_files/10-repos.sh`).
- In a QEMU VM gamescope does not start and the cage fallback shows the launcher; `tests/vm/boot.sh` observed this.
  gamescope itself is proven only on hardware (spec gate H-02).
- Revisit when the launcher sets `STEAM_GAME` and handles gamescope's window protocol, or when it renders at the
  display's scale under Xwayland and the 1080-line cap can go.

## Amendment 2026-11-24: Steam mode

### Context

The device test of the ISO with launcher 0.7.0-rc.3 (issue #51's laptop) found no way back from Steam once it was open,
a Play on a Steam game that brought Steam's console interface to the front instead of the game, and a first Steam start
whose windows came and went full-screen with nothing in between. In plain gamescope the newest window covers the
launcher, and the launcher has no say over what is in front. Everything the launcher does to keep Steam in its place
works only in gamescope's Steam mode, which it detects by itself: it starts Steam hidden with `-silent`, brings the game
to the front and itself back when the game ends, opens its menu over a running game on Guide, shows Steam's prompts
when a launch needs an answer, and gives Big Picture its "Opening…" state. In plain gamescope it writes nothing. The
launcher has spoken that protocol since 0.5.0 (spec L-02, pindu-launcher#390), which is what this decision said to wait
for.

### Decision

`pindu-session compositor` starts `gamescope --backend drm --steam -- pindu-session client`. Everything else above
stands: the 1080-line render size, `PINDU_GAMESCOPE_ARGS` for hardware testing, and the cage fallback.

- No `--xwayland-count 2`. The launcher, Steam and every game run on the one Xwayland the launcher is a client of,
  and the launcher reads and writes the focus properties there. A second Xwayland would run with nothing on it.
- No `--mangoapp`. Games already get MangoHud through the launcher's Performance Overlay. Driving gamescope's
  MangoApp instead needs a `MANGOHUD_CONFIGFILE` the launcher can write before gamescope starts, and a device test of
  its own; `PINDU_GAMESCOPE_ARGS=--mangoapp` tries it without an image change.
- Not gamescope-session-plus. Moving to it, with its per-device quirks, is the rest of spec OS-18.

### Alternatives considered

- Staying in plain gamescope and giving Steam a way back by itself (Switch to Desktop, issue #69): leaves a game
  started by Steam, Steam's first start and Steam's prompts in front with no way for the launcher to take the screen
  back.
- Steam's full SteamOS mode (`-steamos3`, with helper scripts on the host): needs the native Steam package that
  [0013](0013-game-sources.md) turned down.

### Consequences

- In Steam mode gamescope shows only windows with an app ID that the focus list on the root window names. A launcher
  that never tags its window (one older than 0.5.0, or one that fails to detect the mode) leaves gamescope running with
  nothing on screen. The cage fallback does not help there: it reacts only to a gamescope that exits within
  10 seconds. The launcher crashing still ends gamescope and the session, and greetd starts a new one
  ([0004](0004-login.md)). A console stuck on a black screen goes back to the previous image from the boot menu.
- The launcher's Steam mode was tested with gamescope 3.17.0, headless and nested; the image ships Fedora's 3.16.31,
  and gamescope's `--steam` protocol is undocumented. It is proven only on a device, by a person (issue #67): the
  launcher fullscreen with a controller, a Steam game and a game through umu, Heroic or Lutris that start and return,
  Guide over a game, and Big Picture's Opening… state.
- Steam Input and the launcher both read Guide while a Steam game runs. What each does there is checked on the same
  device test.
- gamescope tells every program that the desktop is `gamescope` in either mode, so Steam keeps running as its console
  interface, with Switch to Desktop in place of Exit Big Picture; issue #69 gives that entry its meaning.
- The VM tests run in cage and cannot show any of this. `tests/container/session.sh` checks that gamescope is started
  with `--steam`, the first time and on the retry.
