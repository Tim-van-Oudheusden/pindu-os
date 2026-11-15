# pindu-os: one bootc image from three stages. Every version arrives as a build argument from
# image.env (`just build` passes them), so nothing is pinned in this file.

ARG BASE_IMAGE
ARG AKMODS_IMAGE
ARG KERNEL_FLAVOR=fedora

# Build scripts and system files. The image stage bind-mounts them, so they never become a layer.
FROM scratch AS ctx
COPY build_files /build_files
COPY system_files /system_files

# The launcher's release RPM. The stage fails unless the download matches the pinned SHA-256.
FROM ${BASE_IMAGE} AS launcher
ARG FEDORA_VERSION
ARG LAUNCHER_VERSION
ARG LAUNCHER_SHA256
WORKDIR /rpms
RUN rpm="pindu-launcher-${LAUNCHER_VERSION}-1.fc${FEDORA_VERSION}.x86_64.rpm" \
    && curl --fail --silent --show-error --location --retry 3 --remote-name \
        "https://github.com/Tim-van-Oudheusden/pindu-launcher/releases/download/v${LAUNCHER_VERSION}/${rpm}" \
    && echo "${LAUNCHER_SHA256}  ${rpm}" >SHA256SUMS \
    && sha256sum --check --strict SHA256SUMS \
    && rm SHA256SUMS

# Kernel packages for 20-kernel.sh: nothing for the stock Fedora kernel, the akmods image
# (with /kernel-rpms) for OGC. The stage that is not selected is never pulled.
FROM scratch AS kernel-fedora
FROM ${AKMODS_IMAGE} AS kernel-ogc
FROM kernel-${KERNEL_FLAVOR} AS kernel

FROM ${BASE_IMAGE} AS image
ARG FEDORA_VERSION
ARG LAUNCHER_VERSION
ARG KERNEL_FLAVOR
ARG VARIANT=prod
ARG IMAGE_VERSION

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=tmpfs,dst=/run \
    --mount=type=bind,from=launcher,source=/rpms,target=/tmp/launcher \
    --mount=type=bind,from=kernel,source=/,target=/tmp/kernel \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    /ctx/build_files/build.sh

# Warnings are fatal, so content that would be lost or stale on an installed system (files in
# /run, state in /var without a tmpfiles.d entry) is dealt with when it first appears.
RUN --mount=type=tmpfs,dst=/run bootc container lint --fatal-warnings

LABEL org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.licenses="GPL-3.0-or-later" \
      org.opencontainers.image.source="https://github.com/Tim-van-Oudheusden/pindu-os"
