# Security Policy

Pindu OS is an operating system image: it boots a PC, logs a user in without a password, starts games, and updates
itself from a container registry. A flaw in it could let an unsigned image onto devices, open a way into the
production image (which has no SSH server, no sudo and no password), or leak the signing key or a registry token from
the build pipeline, so reports are welcome.

## Supported versions

Fixes go into the next build; older builds are not patched.

| Version | Supported |
| --- | --- |
| `:stable` and `:testing` on `ghcr.io/tim-van-oudheusden/pindu-os` and `pindu-os-dev` | Yes |
| Older version tags (`45.YYYYMMDD.N`) and disk images made from them | No; update with `bootc upgrade` |

## Reporting a vulnerability

**Do not open a public issue, pull request or discussion for a vulnerability.**

Report it privately through GitHub's private vulnerability reporting: the repository's **Security** tab → **Report a
vulnerability** ([direct link](https://github.com/Tim-van-Oudheusden/pindu-os/security/advisories/new)). Only the
maintainer ([@Tim-van-Oudheusden](https://github.com/Tim-van-Oudheusden)) sees the report. If the form is not
available, contact the maintainer through [GitHub](https://github.com/Tim-van-Oudheusden) without any details and ask
for a private channel.

Include what you can of:

- the image and its version (`cat /usr/share/pindu-os/image-info.json`, or the tag or digest you pulled)
- what an attacker can do, and what they need first (network access, a USB device, a crafted game library, a pull
  request, ...)
- steps or a proof of concept that reproduce it
- for a leaked secret: where you found it

## What to expect

This is a one-person project, so these are aims, not guarantees:

- an acknowledgement within 7 days
- a first assessment (accepted or not, and the severity) within 14 days
- a fix in a published build as soon as practical, coordinated with you, then a GitHub security advisory that credits
  you unless you prefer otherwise

Please keep the details private until the fix is published or 90 days have passed, whichever comes first.

## Scope

In scope:

- what this repository adds to Fedora: the session (`system_files/usr/bin/pindu-session`), the autologin, the update
  and signature configuration, the build scripts and the disk and installer configuration
- the build and release pipeline (`.github/workflows/`, `Justfile`, `image.env`), including leaked secrets, a way for a
  pull request to reach a secret or a write token, and a way to publish or promote an image without a valid signature
- the published images and disk images

Out of scope:

- flaws in Fedora packages, the kernel, gamescope or other upstream software that the image ships unchanged: report
  them upstream; tell us if the image needs a faster update than the daily build gives
- flaws in pindu-launcher itself: report them to
  [pindu-launcher](https://github.com/Tim-van-Oudheusden/pindu-launcher/security/policy)
- the dev image (`pindu-os-dev`) being open by design: it has SSH, passwordless sudo and a logged-in shell on VT 2, and
  is meant for test machines
- attacks that need physical access to an unlocked machine: the console logs in without a password and its disk is not
  encrypted

## How images are verified

Every published image is signed with the project's cosign key, and devices refuse an update that is not
(`/etc/containers/policy.json`). Each image also has a GitHub build provenance attestation and an SBOM. To check an
image yourself:

```sh
cosign verify --new-bundle-format=false \
    --key https://raw.githubusercontent.com/Tim-van-Oudheusden/pindu-os/main/cosign.pub \
    ghcr.io/tim-van-oudheusden/pindu-os:stable
gh attestation verify oci://ghcr.io/tim-van-oudheusden/pindu-os:stable --repo Tim-van-Oudheusden/pindu-os
```

`--new-bundle-format=false` makes cosign 3 read the signature in the classic format, which is the one the devices
check. Without it, cosign looks only at the attestations and reports "expected key signature, not certificate".
