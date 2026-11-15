# 0004: Login

Status: accepted (2026-11-15)

## Context

The console has one user, no password and often no keyboard. After boot it must go straight to the session, and if the
session ends or crashes it must come back without anyone logging in. Something still has to open a logind session on
seat0 for the `pindu` user, so the compositor gets access to the GPU and input devices.

## Decision

Use greetd with no greeter. `system_files/etc/greetd/config.toml` runs on VT 1 and sets both sections to the same
session:

- `initial_session` runs `pindu-session` as `pindu` once after boot: the autologin.
- `default_session` is what greetd runs whenever no session is running. It is the same command and user, so when the
  session ends greetd starts it again. A greeter would be useless, because the account has no password.

`build_files/60-system-files.sh` enables `greetd.service` and sets `graphical.target` as the default target. No display
manager and no desktop environment is installed; `build_files/90-cleanup.sh` fails the build if `gnome-shell` or
`plasma-workspace` arrives through a dependency.

`pindu-session` itself has no restart loop: the user unit has no `Restart=`, and when it ends the login script returns
and greetd starts a new session. If a session lasted less than 10 seconds, the login script sleeps 10 seconds before it
returns, so a session that cannot start does not spin the machine.

## Alternatives considered

- GDM or SDDM with autologin: a display-manager stack, its greeter and usually a desktop session come along for one
  autologin line.
- A getty autologin on VT 1 that starts the session from the shell profile: no logind session class for a graphical
  seat, and restarting after a crash would be our own code.
- A system unit that starts the compositor directly as `pindu`: bypasses PAM and logind, so device access and the user
  manager would have to be arranged by hand.

## Consequences

- greetd and `greetd-selinux` are the only login packages (`build_files/40-session-packages.sh`).
- There is no way to log in as anyone else on VT 1, and no lock screen. Anyone at the machine has the session, which
  `SECURITY.md` lists as out of scope.
- The dev image adds a second way in, an autologin shell on VT 2 (decision 0011).
- Revisit if the console needs several user profiles or a lock, which would need a greeter that works with a
  controller.
