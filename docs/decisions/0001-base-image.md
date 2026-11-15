# 0001: Base image

Status: accepted (2026-11-15)

## Context

pindu-launcher needs GTK 4.24 and libadwaita 1.10, and its release workflow builds an `fc45` RPM, so Fedora 45 is the
floor. The image has to be a bootc image so devices update with `bootc upgrade`. Every package between Fedora and the
device is something we either own or depend on someone else to maintain.

## Decision

Build on Fedora's upstream bootc image, `quay.io/fedora/fedora-bootc:45`, passed to the `Containerfile` as
`BASE_IMAGE` and pinned by digest in `image.env`. We own the package list on top of it: hardware and system packages in
`build_files/30-base-packages.sh`, session packages in `build_files/40-session-packages.sh`.

The spec could not confirm that `fedora-bootc:45` exists and named `quay.io/fedora-ostree-desktops/base-atomic:45` as
the fallback. The image exists, so the fallback was not needed. `just verify-inputs` checks that the pinned digest
resolves and carries the `containers.bootc` label and a Fedora 45 version.

The image identifies itself as Pindu OS: `build_files/70-os-release.sh` writes `ID=pindu-os`, `ID_LIKE=fedora` and
keeps `VERSION_ID=45`, so tools keyed on the Fedora release, bootc-image-builder among them, keep working.

## Alternatives considered

- `ghcr.io/ublue-os/base-main:45`: ublue would add codecs, udev rules and tools for us. ublue's README says it is
  trimming intermediate images its own final images do not use, and neither Bazzite nor Bluefin builds on `base-main`,
  so it is a weak foundation to depend on.
- `ghcr.io/ublue-os/bazzite-deck:stable`: kernel, gamescope and Steam arrive ready. It is a multi-gigabyte KDE and
  Steam image that we would have to subtract from, and it would make Pindu OS a Bazzite remix.
- `quay.io/fedora-ostree-desktops/base-atomic:45`: the spec's fallback, which ublue pins today. Not needed once
  `fedora-bootc:45` was confirmed, and larger than the plain bootc base.

## Consequences

- We maintain the package list ourselves, one commented group per reason. `build_files/90-cleanup.sh` fails the build
  if a dependency pulls in `gnome-shell` or `plasma-workspace`.
- No third party sits between us and Fedora. Renovate (`renovate.json5`) bumps the base digest once a week; the daily
  build in `.github/workflows/build.yml` picks up Fedora package updates in between.
- The OS and the launcher move together: when the launcher raises its minimum GNOME version, the OS must already be on
  the matching Fedora release. A release bump is manual and changes `FEDORA_VERSION`, the base tag, the akmods tag and
  the launcher's dist tag in `image.env` together.
- Revisit if the upstream bootc image stops being published for a Fedora release we need, or if a second image family
  makes a shared base layer worth maintaining.
