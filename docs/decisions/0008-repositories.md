# 0008: Repositories

Status: accepted (2026-11-15)

## Context

Pindu OS is two products: the launcher, which already has its own repository, and the image that ships it. Projects
such as Armada keep forked packages in the image repository and build each once into a content-hashed image; Bluefin
keeps shared config in a separate `common` repository. Every extra repository costs CI, permissions and release
coordination.

## Decision

Keep the OS in one repository, `Tim-van-Oudheusden/pindu-os`, next to the existing `pindu-launcher`. It holds the
`Containerfile`, `build_files/`, `system_files/`, `disk_config/`, `tests/`, `docs/` and `.github/workflows/`, and
publishes `ghcr.io/tim-van-oudheusden/pindu-os` and `pindu-os-dev`.

A `packages/` directory is reserved for later forks: one directory per package with its base, patches and build script,
built once per source hash as in Armada. v0 forks nothing, so the directory holds only `packages/README.md`.

Split further only when a trigger fires:

- `pindu-os-packages`, when more than about five packages live in `packages/`, or a second image needs them.
- `pindu-os-common`, when a second image family exists, for example a desktop variant, and they share config files as
  one OCI layer.

The repository lives under the maintainer's user account, not an organisation as the spec assumed.

## Alternatives considered

- Separate packages and common repositories from the start: both are empty in v0 and would only add CI and pins to
  keep in step.
- One repository for the launcher and the OS: the launcher also ships as a Flatpak and tarball for other systems, and
  its release cadence is its own.
- An organisation as owner: gives runner groups and GHCR names that survive a change of maintainer, which a one-person
  project does not need yet.

## Consequences

- Every pin, script and workflow is reviewed in one place; `.github/CODEOWNERS` covers the trust-relevant paths.
- Images are named after the user account. Moving to an organisation later changes every GHCR path, which devices have
  in their bootc origin and in `policy.json`; it would need an image that trusts both names before the move.
- Runner groups exist only for organisations, so self-hosted runners are not an option under this owner
  (decision 0009).
- Revisit when a split trigger above fires, or when a second maintainer joins and an organisation pays off.
