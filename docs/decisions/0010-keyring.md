# 0010: Keyring

Status: accepted (2026-11-15)

## Context

pindu-launcher keeps its SteamGridDB API key in the Secret Service. A keyring is normally encrypted with the login
password and unlocked at login. The console logs in automatically and the account has no password, so nothing can
unlock an encrypted keyring. Without a usable default keyring, gnome-keyring asks the user to invent a password, on a
screen that often has no keyboard. The spec left the choice between an empty-password keyring and no SteamGridDB key in
v0.

## Decision

The Secret Service keyring has no password. gnome-keyring is the provider, and
`system_files/usr/lib/tmpfiles.d/pindu.conf` creates its default keyring once in `~/.local/share/keyrings`: the file
`default`, which names `Default_keyring`, and `Default_keyring.keyring`, a plain-text keyring with locking turned off.
Existing files are left alone.

`system_files/usr/lib/systemd/user/pindu-session.service` wants and orders itself after `gnome-keyring-daemon.service`,
so one daemon owns the Secret Service bus name before the launcher starts; otherwise D-Bus activation would start a
second daemon. `system_files/usr/share/xdg-desktop-portal/gamescope-portals.conf` routes the Secret portal to
gnome-keyring.

Tested: `gnome-keyring-daemon --unlock` with an empty password on stdin creates no keyring; the plain-text keyring file
stores and returns secrets without a prompt and survives a daemon restart; in the VM the Secret Service `Unlock` call
returns without a prompt.

## Alternatives considered

- No keyring in v0: the launcher loses its SteamGridDB key and with it artwork lookups.
- An encrypted keyring with an empty password: the disk is not encrypted, so it would protect nothing more, and
  `--unlock` with an empty password creates no keyring anyway.
- oo7-daemon: version 0.7 is a beta in Fedora 45, and it has the same unlock problem.
- A secret sealed to the TPM: the right answer once the disk is encrypted, and more work than v0 needs.

## Consequences

- Anyone who can read the `pindu` home directory, through physical access to the disk or root on the dev image, can
  read the stored secrets. `SECURITY.md` already lists physical access to the unencrypted machine as out of scope.
- Only low-value secrets such as an API key belong in this keyring; account passwords and tokens for stores do not.
- The dev image ships `secret-tool` (`build_files/80-variant-dev.sh`) to inspect it.
- Revisit when the disk is encrypted or the TPM is used, at which point the keyring should be sealed the same way, or
  when the launcher needs to store a credential that matters.
