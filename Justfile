# pindu-os: build, check and boot the image. Every pinned input comes from image.env.

set dotenv-filename := "image.env"
set dotenv-load
set dotenv-required

# Registry namespace the image is published to and devices update from. policy.json,
# registries.d/pindu-os.yaml and disk_config/iso.toml name the same repository; `just lint`
# checks that they agree.

registry := env("IMAGE_REGISTRY", "ghcr.io/tim-van-oudheusden")

# Tag of locally built images.

tag := env("IMAGE_TAG", "local")

# Version of a build, as 45.YYYYMMDD.N. CI sets N; a local build is always .0.

image_version := env("IMAGE_VERSION", env("FEDORA_VERSION") + "." + `date -u +%Y%m%d` + ".0")

[private]
default:
    @just --list

# Print the image name of a variant: pindu-os for prod, pindu-os-<variant> otherwise
[group('build')]
image-name variant="prod":
    @echo "{{ if variant == "prod" { "pindu-os" } else { "pindu-os-" + variant } }}"

# Build the image of a variant (prod or dev) as localhost/pindu-os[-dev]:local
[group('build')]
build variant="prod" kernel=env("KERNEL_FLAVOR"):
    #!/usr/bin/env bash
    set -euo pipefail
    name=$(just image-name {{ variant }})
    podman build \
        --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
        --build-arg "AKMODS_IMAGE=${AKMODS_IMAGE}" \
        --build-arg "FEDORA_VERSION=${FEDORA_VERSION}" \
        --build-arg "LAUNCHER_VERSION=${LAUNCHER_VERSION}" \
        --build-arg "LAUNCHER_SHA256=${LAUNCHER_SHA256}" \
        --build-arg "UMU_VERSION=${UMU_VERSION}" \
        --build-arg "UMU_SHA256=${UMU_SHA256}" \
        --build-arg "KERNEL_FLAVOR={{ kernel }}" \
        --build-arg "VARIANT={{ variant }}" \
        --build-arg "IMAGE_VERSION={{ image_version }}" \
        --label "org.opencontainers.image.title=${name}" \
        --label "org.opencontainers.image.revision=$(git rev-parse HEAD 2>/dev/null || echo unknown)" \
        --tag "localhost/${name}:{{ tag }}" \
        --file Containerfile \
        .
    echo "Built localhost/${name}:{{ tag }} ({{ image_version }})"

# Check that every pin in image.env resolves: image digests, the launcher RPM, umu's zipapp, the akmods signature
[group('check')]
verify-inputs:
    #!/usr/bin/env bash
    set -euo pipefail
    status=0

    # Images: the pinned digest must exist and have an x86_64 build.
    while IFS='=' read -r key value; do
        [[ ${key} == *_IMAGE ]] || continue
        ref="${value%%:*}@${value##*@}"
        if arch=$(skopeo inspect --no-tags --override-os linux --override-arch amd64 \
            --format '{{{{ .Architecture }}' "docker://${ref}" 2>/dev/null) && [[ ${arch} == amd64 ]]; then
            echo "ok    ${key}  ${value}"
        else
            echo "FAIL  ${key}  ${value}: the digest does not resolve to an amd64 image"
            status=1
        fi
    done <image.env

    # The base image must be a Fedora ${FEDORA_VERSION} bootc image.
    base="${BASE_IMAGE%%:*}@${BASE_IMAGE##*@}"
    labels=$(skopeo inspect --no-tags --override-os linux --override-arch amd64 "docker://${base}" | jq -c .Labels)
    if jq -e --arg v "${FEDORA_VERSION}" \
        '."containers.bootc" == "1" and (."org.opencontainers.image.version" | startswith($v + "."))' \
        <<<"${labels}" >/dev/null; then
        echo "ok    BASE_IMAGE is a Fedora ${FEDORA_VERSION} bootc image"
    else
        echo "FAIL  BASE_IMAGE is not a Fedora ${FEDORA_VERSION} bootc image: ${labels}"
        status=1
    fi

    # The akmods image is signed by Universal Blue; build_files/ublue-os-akmods.pub is their
    # key. The signature is in cosign's classic format, like ours.
    akmods="${AKMODS_IMAGE%%:*}@${AKMODS_IMAGE##*@}"
    if cosign verify --new-bundle-format=false --key build_files/ublue-os-akmods.pub "${akmods}" >/dev/null 2>&1; then
        echo "ok    AKMODS_IMAGE is signed by Universal Blue"
    else
        echo "FAIL  AKMODS_IMAGE has no valid Universal Blue signature"
        status=1
    fi

    # The launcher RPM must exist and match its SHA-256.
    rpm="pindu-launcher-${LAUNCHER_VERSION}-1.fc${FEDORA_VERSION}.x86_64.rpm"
    url="https://github.com/Tim-van-Oudheusden/pindu-launcher/releases/download/v${LAUNCHER_VERSION}/${rpm}"
    if sum=$(curl --fail --silent --show-error --location --retry 3 "${url}" | sha256sum | cut -d ' ' -f 1) &&
        [[ ${sum} == "${LAUNCHER_SHA256}" ]]; then
        echo "ok    LAUNCHER_VERSION ${LAUNCHER_VERSION} matches LAUNCHER_SHA256"
    else
        echo "FAIL  ${url} does not match LAUNCHER_SHA256"
        status=1
    fi

    # umu-launcher's zipapp must exist and match its SHA-256.
    url="https://github.com/Open-Wine-Components/umu-launcher/releases/download/${UMU_VERSION}/umu-launcher-${UMU_VERSION}-zipapp.tar"
    if sum=$(curl --fail --silent --show-error --location --retry 3 "${url}" | sha256sum | cut -d ' ' -f 1) &&
        [[ ${sum} == "${UMU_SHA256}" ]]; then
        echo "ok    UMU_VERSION ${UMU_VERSION} matches UMU_SHA256"
    else
        echo "FAIL  ${url} does not match UMU_SHA256"
        status=1
    fi

    exit "${status}"

# Lint shell scripts, the Containerfile, the Justfile and the workflows
[group('check')]
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    run() { podman run --rm --security-opt label=disable --volume "${PWD}:/repo:ro" --workdir /repo "$@"; }

    echo "== shellcheck"
    mapfile -t scripts < <(git ls-files --cached --others --exclude-standard -- '*.sh' system_files/usr/bin)
    run "${SHELLCHECK_IMAGE}" --external-sources "${scripts[@]}"

    for section in %pre %post; do
        echo "== shellcheck: the bash ${section} script of disk_config/iso.toml"
        awk -v section="${section}" '/^%end/ { on = 0 } on; $1 == section && /--interpreter=\/usr\/bin\/bash/ { on = 1 }' \
            disk_config/iso.toml | run --interactive "${SHELLCHECK_IMAGE}" --shell=bash -
    done

    echo "== hadolint"
    run "${HADOLINT_IMAGE}" hadolint Containerfile

    echo "== just --fmt"
    just --unstable --fmt --check

    echo "== actionlint"
    run "${ACTIONLINT_IMAGE}" -color

    echo "== zizmor"
    run "${ZIZMOR_IMAGE}" --offline --pedantic .github/workflows

    echo "== repository names"
    for file in system_files/etc/containers/policy.json system_files/etc/containers/registries.d/pindu-os.yaml disk_config/iso.toml; do
        grep --quiet --fixed-strings "{{ registry }}/" "${file}" ||
            { echo "${file} does not name {{ registry }}"; exit 1; }
    done

    echo "== signing key"
    if [[ -e cosign.pub || -e system_files/etc/pki/containers/pindu-os.pub ]]; then
        cmp cosign.pub system_files/etc/pki/containers/pindu-os.pub
    else
        echo "no cosign.pub yet (docs/runbook.md, Signing key)"
    fi

# Test the scripts the workflows run (tests/ci/*.sh) against stubbed registry and GitHub lookups
[group('check')]
test-ci:
    #!/usr/bin/env bash
    set -euo pipefail
    for test in tests/ci/*.sh; do
        echo "== ${test}"
        bash "${test}"
    done

# Run the container tests (tests/container/*.sh) inside the built image of a variant
[group('check')]
test variant="prod":
    #!/usr/bin/env bash
    set -euo pipefail
    image="localhost/$(just image-name {{ variant }}):{{ tag }}"
    failed=()
    for test in tests/container/*.sh; do
        [[ ${test} == */lib.sh ]] && continue
        echo "== ${test}"
        podman run --rm --security-opt label=disable \
            --volume "${PWD}/tests/container:/tests:ro" \
            --volume "${PWD}/build_files:/build_files:ro" \
            --env-file image.env \
            --env "VARIANT={{ variant }}" \
            "${image}" bash "/tests/${test##*/}" || failed+=("${test}")
    done
    if ((${#failed[@]})); then
        echo "FAILED: ${failed[*]}"
        exit 1
    fi
    echo "All container tests passed for {{ variant }}"

# bootc-image-builder needs root: copy the image into root's storage, then build under sudo
[private]
_bib variant type config:
    #!/usr/bin/env bash
    set -euo pipefail
    image="localhost/$(just image-name {{ variant }}):{{ tag }}"
    sudo=()
    if ((EUID != 0)); then
        sudo=(sudo)
        if [[ $(podman image inspect --format '{{{{ .Id }}' "${image}") != \
            $(sudo podman image inspect --format '{{{{ .Id }}' "${image}" 2>/dev/null) ]]; then
            echo "Copying ${image} into root's container storage"
            podman save "${image}" | sudo podman load
        fi
    fi
    mkdir -p "output/{{ variant }}"
    "${sudo[@]}" podman run --rm --privileged \
        --security-opt label=type:unconfined_t \
        --volume "${PWD}/{{ config }}:/config.toml:ro" \
        --volume "${PWD}/output/{{ variant }}:/output" \
        --volume /var/lib/containers/storage:/var/lib/containers/storage \
        "${BIB_IMAGE}" \
        --type "{{ type }}" \
        --use-librepo=True \
        "${image}"
    "${sudo[@]}" chown -R "$(id -u):$(id -g)" "output/{{ variant }}"

# Build a qcow2 disk image of a built variant into output/<variant>/qcow2/disk.qcow2
[group('disk')]
build-qcow2 variant="prod": (_bib variant "qcow2" "disk_config/disk.toml")

# Build a raw disk image of a built variant into output/<variant>/image/disk.raw
[group('disk')]
build-raw variant="prod": (_bib variant "raw" "disk_config/disk.toml")

# Build the installer ISO of a built variant into output/<variant>/bootiso/install.iso
[group('disk')]
build-iso variant="prod": (_bib variant "anaconda-iso" "disk_config/iso.toml")

# Boot the qcow2 of a variant in a QEMU window (changes are thrown away when it closes)
[group('vm')]
run-vm variant="prod":
    tests/vm/run.sh "output/{{ variant }}/qcow2/disk.qcow2"

# VM test: boot the qcow2 of a variant headless and assert on the session (dev also checks SSH)
[group('vm')]
test-vm variant="prod":
    tests/vm/boot.sh {{ if variant == "dev" { "--ssh" } else { "" } }} \
        "output/{{ variant }}/qcow2/disk.qcow2" "output/{{ variant }}/test-boot"

# VM test: stage an update from a local registry, boot into it, roll back
[group('vm')]
test-update variant="prod":
    tests/vm/update.sh "localhost/$(just image-name {{ variant }}):{{ tag }}" \
        "output/{{ variant }}/qcow2/disk.qcow2" "output/{{ variant }}/test-update"

# VM test: the ISO refuses two disks and an unconfirmed one, installs a confirmed one, which then passes the boot assertions
[group('vm')]
test-install variant="prod":
    tests/vm/install.sh "output/{{ variant }}/bootiso/install.iso" "output/{{ variant }}/test-install" \
        "{{ registry }}/$(just image-name {{ variant }}):stable"

# Remove build outputs
[group('build')]
clean:
    rm -rf output
