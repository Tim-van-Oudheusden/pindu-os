# 0007: Trust

Status: accepted (2026-11-15)

## Context

Devices update themselves from a public registry. Anyone who can push to the repository, or tamper with an image in
transit, must not be able to get an image onto a device. Users and auditors also need to tie an image to the commit it
was built from.

## Decision

Sign every pushed digest with a cosign key and enforce the signature on the device; attach GitHub build provenance and
an SBOM as well.

- `.github/workflows/build.yml` signs with
  `cosign sign --new-bundle-format=false --use-signing-config=false --key ...` on the pushed digest, following
  ublue-os/image-template, because the container tools on the device read the classic signature format, not cosign 3's
  bundle format. The private key sits in the `signing` environment, which only `main` can use.
- `system_files/etc/containers/policy.json` requires `sigstoreSigned` with `/etc/pki/containers/pindu-os.pub` and
  `signedIdentity: matchRepository` for `ghcr.io/tim-van-oudheusden/pindu-os` and `pindu-os-dev`, and keeps the base
  image's entries for everything else. `system_files/etc/containers/registries.d/pindu-os.yaml` turns on
  `use-sigstore-attachments`, so the tools find the signature next to the image.
- `matchRepository` accepts the signature under any tag of the repository, so `.github/workflows/promote.yml` can
  retag the same digest as `:stable` without re-signing.
- `build.yml` also attaches a build provenance attestation and an SPDX SBOM made with syft, then verifies both with
  `gh attestation verify`. They need no key.

This was verified against a local registry: a signed image is accepted by tag and after a retag, and an unsigned one is
rejected with "A signature was required, but no signature exists".

## Alternatives considered

- Keyless cosign signing with GitHub OIDC: every device would have to trust Fulcio's and Rekor's keys and match the
  workflow identity; a key is the image-template method and verifies offline.
- Provenance only: nothing on the device checks it, so it cannot stop an unsigned pull.
- `signedIdentity: matchExact` or the default `matchRepoDigestOrExact`: the signature is made on the digest and names
  the repository, not a tag, so a pull by `:testing` or `:stable` would not match without signing each tag again.

## Consequences

- The key pair is a human task (spec H-03). Until `cosign.pub` is committed at the repository root and as
  `system_files/etc/pki/containers/pindu-os.pub` (`just lint` keeps them identical), `build_files/60-system-files.sh`
  leaves the policy out with a build warning, and `build.yml` refuses to publish.
- Losing the private key means devices accept no new image until they get a new public key by other means; leaking it
  lets an attacker sign images devices accept.
- Renovate asks for approval before a cosign major bump (`renovate.json5`), since it may change the signature format.
- Revisit if the container tools on the device read cosign's bundle format, or if keyless verification becomes simple
  to configure on the device.
