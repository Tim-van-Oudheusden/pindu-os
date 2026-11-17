# 0012: Launcher releases reach stable after a hardware check

Status: accepted (2026-11-17)

## Context

Renovate bumps `LAUNCHER_VERSION` in `image.env` on each launcher release, every merge publishes `:testing`, and
`promote.yml` retags `:testing` as `:stable`. The VM tests cannot show gamescope, controllers, Bluetooth, suspend or a
Proton game, so a launcher bump could reach `:stable` without anyone running it on a real PC. pindu-launcher now runs a
hardware checklist per release and records the result on its `Release X.Y.Z` issue (pindu-launcher#381), and it
publishes pre-releases `vX.Y.Z-rc.N` to soak before the final tag (pindu-launcher#379).

## Decision

- `promote.yml` runs `.github/scripts/launcher-gate.sh` on the digest it promotes. The launcher version of an image is
  `LAUNCHER_VERSION` in `image.env` at the commit in the image's `org.opencontainers.image.revision` label. When the
  version differs from the one in the current `:stable` (or there is no `:stable`), the promotion is refused unless
  the pindu-launcher issue titled exactly `Release X.Y.Z` carries the label `hardware-check:passed`, open or closed.
- Renovate ignores launcher pre-releases: `image.env` only follows final releases (`renovate.json5`). The soak of an
  rc happens in the launcher repository, where its hardware checklist runs on the rc before the final is tagged.

## Alternatives considered

- Following pre-releases into `:testing`: `:testing` is built from `main`, so an rc on `main` would hold every other
  change (Fedora updates, fixes) out of `:stable` until the final lands, since the gate never passes an rc. The rc's
  RPM file is named after the tag (`0.5.0-rc.1`) but its package version is `0.5.0~rc1`, which the version check in
  `build_files/50-launcher.sh` would have to map, and each launcher release would open two or more bump pull requests.
- A `hardware-check` issue in this repository: a second record of the same check, and the job would need
  `issues: read`. The launcher's release issue is public and already carries the checklist.
- A label with the launcher version on the image: images built before it would have none, so the gate would still
  need the source commit. One way of finding the version is enough.

## Consequences

- The promote job needs the full history (`fetch-depth: 0`) and reads the launcher's public issues with its own
  `GITHUB_TOKEN`; no permission was added.
- A promotion that only changes the base image, the kernel or the scripts needs no hardware check; one that changes the
  launcher waits for the label. Only someone with triage access to pindu-launcher can add it.
- Revisit if the OS needs launcher builds that are not releases (decision 0005), or if hardware checks move to a
  system that GitHub labels cannot express.
