# 0006: Updates

Status: accepted (2026-11-15)

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

Images are published in three kinds of tags:

- `:testing`: `.github/workflows/build.yml` builds on every push to `main` (except changes to docs only), once a day to
  pick up Fedora updates, and on demand, then signs and boot-tests the pushed digest.
- `45.YYYYMMDD.N`: an immutable tag on the same digest, for every build.
- `:stable`: `.github/workflows/promote.yml`, behind an environment with a required reviewer, verifies the signature of
  a `:testing` or version-tagged digest and retags it for both variants. Nothing is rebuilt.

The installer ISO from `disk_config/iso.toml` is unattended and erases every disk of the machine it boots on, as
bootc-image-builder's default installer does. Its `%post` runs `bootc switch --enforce-container-sigpolicy` to point the
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
- `just test-update` (`tests/vm/update.sh`) stages an update from a local registry, boots it and rolls back.
- Revisit when the launcher gets an update control (L-03), or if a 4-hour check proves too frequent for GHCR.
