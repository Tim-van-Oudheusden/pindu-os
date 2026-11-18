# Decision records

This directory holds one record per design decision of Pindu OS, taken from the spec and corrected where the
repository settled a question differently. Each record gives the context, the decision, the rejected alternatives and
the cost; when a decision changes, add a new record rather than rewriting an accepted one.

| Number | Title | Decision |
| --- | --- | --- |
| 0001 | [Base image](0001-base-image.md) | Fedora's `fedora-bootc:45`, pinned by digest in `image.env`. |
| 0002 | [Kernel](0002-kernel.md) | Stock Fedora kernel; `KERNEL_FLAVOR=ogc` swaps in the prebuilt OGC kernel. |
| 0003 | [Session](0003-session.md) | gamescope on DRM, cage as fallback, run by our own `pindu-session`. |
| 0004 | [Login](0004-login.md) | greetd autologin; a session that ends comes back through a restart of greetd. |
| 0005 | [Launcher delivery](0005-launcher-delivery.md) | The launcher's release RPM, pinned by version and SHA-256. |
| 0006 | [Updates](0006-updates.md) | `bootc upgrade` staged for the next boot; `:testing`, `:stable`, dated tags. |
| 0007 | [Trust](0007-trust.md) | cosign key signature enforced by `policy.json`; provenance and an SBOM. |
| 0008 | [Repositories](0008-repositories.md) | One `pindu-os` repository; further splits only on a trigger. |
| 0009 | [Runners](0009-runners.md) | GitHub-hosted only; pull request code never meets a secret or write token. |
| 0010 | [Keyring](0010-keyring.md) | The Secret Service keyring has no password. |
| 0011 | [Users and access](0011-users-and-access.md) | One locked `pindu` user; sshd and sudo only in the dev image. |
| 0012 | [Launcher releases](0012-launcher-releases.md) | Final launcher releases only; a new launcher reaches `:stable` after its hardware check. |
| 0013 | [Game sources](0013-game-sources.md) | Stores as Flatpaks from Flathub in the system installation; MangoHud and GameMode as RPMs. |
| 0014 | [Base image registry](0014-base-image-registry.md) | `registry.fedoraproject.org`, which keeps superseded digests; quay.io expires them daily. |
