# 0009: Runners

Status: accepted (2026-11-15)

## Context

The repository is public, so anyone can open a pull request, and a pull request can change the workflows it runs. The
build compiles nothing: it installs prebuilt packages on a prebuilt base, which fits a standard runner. Disk images need
more free disk than a standard runner has, and the VM tests need KVM.

## Decision

Use GitHub-hosted runners only (`ubuntu-26.04`). Jobs that build images first free space with
`ublue-os/remove-unwanted-software`, and KVM is opened to the runner user for the VM tests.

Code from a pull request never runs in a job that holds a secret or a write token:

- `.github/workflows/pr.yml` runs on `pull_request` with `contents: read`, no secrets and no registry login. It lints,
  builds both variants and boot-tests them.
- `.github/workflows/build.yml`, `disk.yml` and `promote.yml` run only on `main`, a schedule or a manual dispatch. The
  cosign key sits in the `signing` environment restricted to `main`; promotion sits behind the `promote` environment
  with a required reviewer.
- Every workflow sets read-only default permissions, actions are pinned by commit SHA, and `just lint` runs actionlint
  and zizmor. `.github/CODEOWNERS` requires the maintainer's review on `.github/` and `image.env`.

If self-hosted runners are ever added, these seven rules apply together:

1. No pull-request triggers: only `push` to protected branches, `schedule`, `workflow_dispatch` and `merge_group`.
2. A maintainer starts heavy builds for outside changes by dispatching on the exact commit SHA after reading the diff.
3. Ephemeral virtual machines: a fresh VM per job, registered with `--ephemeral` and destroyed afterwards.
4. Runner groups limited to `pindu-os` and to named workflow files.
5. No secrets on the builder: it has `contents: read` and outputs an unsigned artifact with its hash; a hosted job
   checks the hash, pushes and signs.
6. Network isolation: its own segment, outbound only, no route to a home or office LAN.
7. Never `pull_request_target` with a checkout of pull request code, on any runner.

## Alternatives considered

- Self-hosted runners now: nothing needs them, and every rule above is work and risk for no gain.
- Larger hosted runners: paid, and the build fits a standard runner.

## Consequences

- Build time and disk are bounded by a standard runner: a 6-hour job limit and about 14 GB free before cleanup, both
  figures from the spec and still to be rechecked against GitHub's documentation.
- Rule 4 needs runner groups, which exist only for organisations. The repository is under a user account
  (decision 0008), so self-hosted runners would first need a move to an organisation.
- Revisit when a package in `packages/` cannot build within the hosted limits, the first likely case being a full
  kernel build, which the prebuilt OGC kernel avoids (decision 0002).
