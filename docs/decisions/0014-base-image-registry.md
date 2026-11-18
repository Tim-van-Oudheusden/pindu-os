# 0014: Base image registry

Status: accepted (2026-11-19), changes the registry of [0001](0001-base-image.md) (issue #41)

## Context

Decision 0001 pinned `quay.io/fedora/fedora-bootc:45` by digest. Fedora pushes a new `:45` every day around 11:30 UTC,
and quay.io expires the manifest the tag leaves at that moment: in quay's tag history every superseded `45` manifest
has an `expiration` equal to the time the tag moved on. A digest in `image.env` stopped resolving within a day, while
Renovate bumps it once a week. Every scheduled build failed with `manifest unknown` (2026-11-16 to 2026-11-18), and so
did every pull request opened more than a day after the last bump, until someone bumped the digest by hand.

## Decision

Pull the base image from `registry.fedoraproject.org/fedora-bootc`, Fedora's own registry. It serves the same images
under the same digests, and keeps superseded ones: when this was decided it still served every `45` digest sampled
back to 2026-07-25, including the one quay.io had expired. Renovate keeps following the `:45` digest weekly.

## Alternatives considered

- Follow the digest every day: the pin still dies at 11:30 UTC each day, so pull requests and the scheduled build
  race Renovate, and a merged bump is a day's work at most.
- Pin the tag without a digest: the image would change without a change to `image.env`, which breaks the rule that a
  diff of that file explains any change in the image.
- Mirror the base into this project's GHCR: a new job with a write token and a second copy of Fedora's image to keep,
  for what Fedora's registry already does.

## Consequences

- `just verify-inputs`, the build and Renovate read the new name from `image.env`; no script changes.
- The other pins keep their digests: `ghcr.io/ublue-os/akmods` keeps old digests, and
  `quay.io/centos-bootc/bootc-image-builder` keeps each one alive through its `sha256-<digest>` signature tags.
- Revisit if Fedora's registry starts expiring superseded digests within Renovate's weekly window, or stops publishing
  `fedora-bootc`.
