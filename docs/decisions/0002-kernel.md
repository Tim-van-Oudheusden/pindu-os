# 0002: Kernel

Status: accepted (2026-11-15)

## Context

The base image ships Fedora's stock kernel, signed with Fedora's key, so it boots with Secure Boot on. Gaming
distributions such as Bazzite use the Open Gaming Collective (OGC) kernel, which carries handheld and gaming patches.
Building a kernel ourselves is the job most likely to exceed a hosted runner's 6-hour limit.

## Decision

Keep Fedora's stock kernel by default (`KERNEL_FLAVOR=fedora` in `image.env`). A build with `KERNEL_FLAVOR=ogc` swaps in
the prebuilt OGC kernel from `ghcr.io/ublue-os/akmods:ogc-45`, pinned by digest as `AKMODS_IMAGE`.

- The `Containerfile` has two kernel stages, `kernel-fedora` (empty) and `kernel-ogc` (the akmods image), and selects
  one as `kernel`. The stage that is not selected is never pulled.
- `build_files/20-kernel.sh` does nothing for `fedora`. For `ogc` it removes the Fedora kernel packages and installs the
  RPMs from `/kernel-rpms` of the akmods image, following Bazzite's recipe. It also installs Universal Blue's
  certificate, `/etc/pki/akmods/certs/akmods-ublue.der`, for the MOK enrolment. Any other value fails the build.
- `build_files/70-os-release.sh` rebuilds the initramfs for whichever kernel is installed, and
  `build_files/90-cleanup.sh` fails the build unless exactly one kernel with its initramfs is present.
- `just verify-inputs` checks the akmods image's signature against Universal Blue's key in
  `build_files/ublue-os-akmods.pub`.

## Alternatives considered

- OGC kernel by default from v0: it is signed with Universal Blue's key, so every Secure Boot user would need a MOK
  enrolment before the first boot, and it adds a third-party input before anything needs it.
- Building our own kernel: the most expensive build there is, likely to hit the hosted runner time limit, for patches
  OGC already carries.

## Consequences

- With the stock kernel, Secure Boot works without user action. An OGC image needs a one-time MOK enrolment of
  Universal Blue's key on each Secure Boot machine, as on Bazzite.
- The OGC images have no service promise to us. The digest pin means a bad upstream build reaches no device without a
  pull request, and `KERNEL_FLAVOR=fedora` stays a working fallback.
- A Fedora release bump moves the akmods tag (`ogc-45`) together with `FEDORA_VERSION`; Renovate follows only its
  digest.
- Revisit when hardware testing shows a device that needs OGC patches (spec OS-16, OS-21), at which point `ogc` may
  become the default for that variant, or when we need a kernel patch OGC does not carry.
