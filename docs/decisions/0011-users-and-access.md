# 0011: Users and access

Status: accepted (2026-11-15)

## Context

A console has one person in front of it and no administrator. Every way into the system (a password, an SSH server,
sudo) is something an attacker on the network or a game could use. Testers on real hardware, however, need a shell to
join Wi-Fi, read logs and diagnose gamescope, because v0 has no settings UI.

## Decision

One user, two images from the same `Containerfile`.

- `system_files/usr/lib/sysusers.d/pindu.conf` creates `pindu` with UID and GID 1000 and home `/var/home/pindu`;
  `system_files/usr/lib/tmpfiles.d/pindu.conf` creates the home on first boot. The password is locked, and
  `build_files/60-system-files.sh` fails the build if it is not. The only way in is greetd's autologin (decision 0004).
- The production image (`VARIANT=prod`) has no SSH server and no sudo. Both are in the Fedora base image;
  `build_files/30-base-packages.sh` removes `openssh-server` and `sudo`.
- `VARIANT=dev` builds `pindu-os-dev` through `build_files/80-variant-dev.sh`: it installs `openssh-server` and `sudo`
  again, enables sshd with key authentication only, gives the `wheel` group passwordless sudo, adds `pindu` to it,
  starts an autologin shell on VT 2 (Ctrl+Alt+F2), and adds `nmtui`, `vulkaninfo`, `evtest`, `secret-tool`, `gdb`,
  `strace` and similar tools.

In VMs the tests inject an SSH key for root as the systemd credential `ssh.authorized_keys.root`. On hardware a tester
adds a key from the VT 2 shell.

## Alternatives considered

- One image with access switched on by a setting or kernel argument: the production image would carry sshd and sudo,
  and the switch itself would become a way in.
- A password for `pindu`: there is no keyboard to type it on, and it would be the same on every device.
- sshd disabled but installed in production: one `systemctl enable` from being open, and more to patch.

## Consequences

- A production device cannot be administered on the device. Fixes reach it only as an update, and a tester installs
  the dev image instead.
- The dev image is open by design: anyone at the machine gets a root shell on VT 2. `SECURITY.md` marks it as meant for
  test machines only.
- `build_files/build.sh` rejects any `VARIANT` other than `prod` and `dev`, and `tests/container/variant.sh` checks
  each image's access.
- Revisit when the launcher has system panels (spec L-03) that need privileged actions, which will come as narrow
  polkit rules rather than sudo, or when a second user is needed.
