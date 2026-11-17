# 0006: Updates

Status: accepted (2026-11-15), amended 2026-11-16 (issue #17: the launcher's update control)

## Context

A console must never reboot itself in the middle of a game. The stock `bootc-fetch-apply-updates.service` runs
`bootc upgrade --apply`, which reboots as soon as an update is downloaded, and its timer first fires one to three hours
after boot, longer than a console is often switched on. Testers need builds before users do, and a bad build must be
easy to leave.

## Decision

Devices update with `bootc upgrade` from GHCR, staged and applied on the next boot.

- `system_files/usr/lib/systemd/system/bootc-fetch-apply-updates.service.d/10-stage-only.conf` replaces the command with
  `bootc upgrade --quiet`: download and stage, no reboot.
- `system_files/usr/lib/systemd/system/bootc-fetch-apply-updates.timer.d/10-pindu.conf` checks 10 minutes after boot
  and every 4 hours after that, with up to 10 minutes of random delay.
- `bootc rollback` returns to the previous image.
- The launcher's system panel (spec L-03) reads `/run/pindu-os/update-status.json`, which the root oneshot
  `pindu-os-update-status.service` writes from `bootc status` at boot, after each successful update run and after a
  rollback. It rolls back by starting `pindu-os-rollback.service` (`bootc rollback`, then the status unit), which the
  polkit rule `system_files/usr/share/polkit-1/rules.d/50-pindu-os.rules` lets `pindu` start, and no other unit.
  Nothing on the root side takes input from the launcher.

Images are published in three kinds of tags:

- `:testing`: `.github/workflows/build.yml` builds on every push to `main` (except changes to docs only), once a day to
  pick up Fedora updates, and on demand, then signs and boot-tests the pushed digest.
- `45.YYYYMMDD.N`: an immutable tag on the same digest, for every build.
- `:stable`: `.github/workflows/promote.yml`, behind an environment with a required reviewer, verifies the signature of
  a `:testing` or version-tagged digest and retags it for both variants. Nothing is rebuilt.

The installer ISO from `disk_config/iso.toml` installs only on a machine with exactly one disk, and erases it only after
the user types `erase` or the credential `pindu.install.confirm` names it (issue #28; bootc-image-builder's default
installer erases every disk without asking). Its `%post` runs `bootc switch --enforce-container-sigpolicy` to point the
installed system at `:stable` of its own image.

## Alternatives considered

- The stock `--apply` behaviour: reboots a running console mid-game.
- Updates only on user request: v0 has no settings UI, so devices would never update. A launcher panel is spec L-03.
- Rebuilding for `:stable`: the stable image would differ from the tested one. A retag ships the tested bytes.
- Floating `:latest` only: no way for testers to run ahead of users, and no fixed name for a known-good build.

## Consequences

- An update takes effect only after a reboot, which the user decides when. A console that is never rebooted stays on
  its booted image, with the next one staged.
- The build writes the system in one large layer that changes with every build, so an update downloads most of it;
  smaller downloads wait for chunked layers (spec OS-19).
- Rollback keeps one previous image. `/var`, including the home directory, is not rolled back.
- `just test-update` (`tests/vm/update.sh`) stages an update from a local registry, boots it and rolls back the way the
  launcher does.
- A rollback discards an update that is staged at the time. After the reboot into the previous image, the update
  service stages the newer image again, so the reboot after that returns to it: a rollback is a way out of a bad build
  until a fixed one is published, not a pin.
- Revisit if a 4-hour check proves too frequent for GHCR.
