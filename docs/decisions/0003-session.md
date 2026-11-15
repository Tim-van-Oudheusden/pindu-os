# 0003: Session

Status: accepted (2026-11-15)

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
  `gamescope --backend drm -- pindu-session client`.
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
