# 0004: Login

Status: accepted (2026-11-15), amended 2026-11-16 (issue #18: how the session comes back)

## Context

The console has one user, no password and often no keyboard. After boot it must go straight to the session, and if the
session ends or crashes it must come back without anyone logging in. Something still has to open a logind session on
seat0 for the `pindu` user, so the compositor gets access to the GPU and input devices.

## Decision

Use greetd with no greeter, and get every session from `initial_session`. A greeter would be useless, because the
account has no password.

- `initial_session` in `system_files/etc/greetd/config.toml` runs `pindu-session` as `pindu` on VT 1: the autologin.
- `default_session`, which greetd runs whenever no session is running, is `/usr/bin/true` as the `greetd` user. It
  exits at once, and greetd exits because its greeter ended without creating a session.
- systemd restarts `greetd.service` (`Restart=always`, Fedora's unit). The drop-in
  `system_files/usr/lib/systemd/system/greetd.service.d/10-pindu.conf` deletes greetd's runfile before every start,
  so greetd treats each start as the first since boot and runs `initial_session` again.

`default_session` cannot be the session itself (issue #18). greetd runs it through the `greetd-greeter` PAM service, as
a logind session of class `greeter`, and `greetd-selinux` runs greeters in `xdm_t`, which may not start
`pindu-session.service`: `systemctl --user start` fails with "Access denied" and the session never comes back. The
first version of this decision did that; the VM boot test did not end a session, so only a crashed launcher showed it.

`build_files/60-system-files.sh` enables `greetd.service` and sets `graphical.target` as the default target. No display
manager and no desktop environment is installed; `build_files/90-cleanup.sh` fails the build if `gnome-shell` or
`plasma-workspace` arrives through a dependency.

`pindu-session` itself has no restart loop: the user unit has no `Restart=`, and when it ends the login script returns
and greetd restarts. If a session lasted less than 10 seconds, the login script sleeps 10 seconds before it returns, so
a session that cannot start does not spin the machine and stays within `greetd.service`'s start limit (5 starts in 30
seconds). `tests/vm/boot.sh` kills the launcher and checks that a new session of class `user` starts it again.

## Alternatives considered

- GDM or SDDM with autologin: a display-manager stack, its greeter and usually a desktop session come along for one
  autologin line.
- A getty autologin on VT 1 that starts the session from the shell profile: no logind session class for a graphical
  seat, and restarting after a crash would be our own code.
- A system unit that starts the compositor directly as `pindu`: bypasses PAM and logind, so device access and the user
  manager would have to be arranged by hand.
- The login script restarts the unit in a loop and never returns, so greetd's session never ends: a restarted greetd
  (by hand, or after it crashed) would still run `default_session` and need the runfile drop-in anyway, so the loop
  would be a second mechanism for the same job.
- A small greeter that logs `pindu` in through greetd's IPC: that goes through PAM authentication, which a locked
  password fails.

## Consequences

- greetd and `greetd-selinux` are the only login packages (`build_files/40-session-packages.sh`).
- There is no way to log in as anyone else on VT 1, and no lock screen. Anyone at the machine has the session, which
  `SECURITY.md` lists as out of scope.
- The dev image adds a second way in, an autologin shell on VT 2 (decision 0011).
- Each time the session ends greetd logs "greeter exited without creating a session" and exits; that is the restart
  working, not a fault.
- Revisit if the console needs several user profiles or a lock, which would need a greeter that works with a
  controller.
