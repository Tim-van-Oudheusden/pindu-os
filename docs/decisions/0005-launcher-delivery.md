# 0005: Launcher delivery

Status: accepted (2026-11-15)

## Context

pindu-launcher lives in its own repository, whose release workflow publishes an RPM
(`pindu-launcher-<version>-1.fc45.x86_64.rpm`), a Flatpak and a tarball. The OS image must contain exactly the launcher
release we tested, build in a few minutes and start host programs (games, Steam) directly.

## Decision

Install the release RPM, pinned by version and SHA-256.

- `image.env` records `LAUNCHER_VERSION` and `LAUNCHER_SHA256`.
- The `launcher` stage of the `Containerfile` downloads the RPM from the launcher's GitHub Releases and fails unless the
  file matches the pinned SHA-256 (`sha256sum --check --strict`).
- `build_files/50-launcher.sh` installs it with `dnf`, which resolves `glycin-loaders`, `bubblewrap`, `libmanette`,
  GTK 4 and libadwaita from Fedora. It fails if the installed version differs from `LAUNCHER_VERSION` or if `ldd`
  reports a missing library.
- `just verify-inputs` downloads the RPM again and checks the hash; Renovate (`renovate.json5`) opens a pull request
  that bumps version and hash together on each launcher release.

## Alternatives considered

- Flatpak: needs a GNOME runtime in the image or a first-boot download, and the sandbox would have to be opened with
  `org.freedesktop.Flatpak` to start host programs.
- Building the launcher from source in the image build: adds a compiler toolchain and many minutes to every OS
  build for a binary the launcher repo already produces.
- Downloading the latest release at build time: the image would change without a diff in this repository.

## Consequences

- The OS build compiles nothing for the launcher, and a diff of `image.env` explains every launcher change.
- The launcher's Fedora release must match the image's: the dist tag `fc45` moves with `FEDORA_VERSION`.
- The SHA-256 proves the file is the one we pinned, not who built it. Verifying the launcher's build provenance during
  the build waits for the launcher release workflow to attach it (spec L-01).
- Revisit when we need launcher builds between releases: a `testing` stream that builds from a pinned commit would be
  the first entry in `packages/` (decision 0008).
