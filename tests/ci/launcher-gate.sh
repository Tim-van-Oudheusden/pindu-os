#!/usr/bin/env bash
# Tests .github/scripts/launcher-gate.sh, the promote gate for launcher bumps. The registry
# (skopeo) and the launcher's issues (gh) are stubs fed from files; image.env comes from the
# commits of a scratch git repository, as in a clone of this one.
set -euo pipefail

gate=$(realpath "$(dirname "$0")/../../.github/scripts/launcher-gate.sh")
work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

# Stub skopeo: "<reference> <revision>" lines in images; an unknown reference does not exist.
mkdir "${work}/bin"
cat >"${work}/bin/skopeo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ref="${*: -1}"
ref="${ref#docker://}"
while read -r name revision; do
    [[ ${name} == "${ref}" ]] && { echo "${revision}"; exit 0; }
done <"${STUB_DIR}/images"
echo "manifest unknown: ${ref}" >&2
exit 1
EOF
# Stub gh issue list: the issues in issues.json, filtered by --state and --label like GitHub does.
cat >"${work}/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1 $2" == "issue list" ]] || { echo "unexpected gh $*" >&2; exit 1; }
state=open label=
while (($#)); do
    case $1 in
        --repo) [[ $2 == Tim-van-Oudheusden/pindu-launcher ]] || exit 1; shift ;;
        --state) state=$2; shift ;;
        --label) label=$2; shift ;;
    esac
    shift
done
jq --arg state "${state}" --arg label "${label}" \
    '[.[] | select($state == "all" or .state == $state)
          | select($label == "" or (.labels | index($label)))
          | {title, url}]' "${STUB_DIR}/issues.json"
EOF
chmod +x "${work}/bin/skopeo" "${work}/bin/gh"
export PATH="${work}/bin:${PATH}" STUB_DIR="${work}"

# One commit per launcher version.
repo="${work}/repo"
git init --quiet "${repo}"
declare -A rev
commit() {
    printf 'FEDORA_VERSION=45\nLAUNCHER_VERSION=%s\nBUILD=%s\n' "$2" "$1" >"${repo}/image.env"
    git -C "${repo}" add image.env
    git -C "${repo}" -c user.name=test -c user.email=test@example.invalid commit --quiet --message "$1"
    rev[$1]=$(git -C "${repo}" rev-parse HEAD)
}
commit old 0.4.0
commit same 0.4.0
commit new 0.5.0
commit rc 0.6.0~rc1

images() { printf '%s\n' "$@" >"${work}/images"; }
issues() { printf '%s\n' "$1" >"${work}/issues.json"; }
released_passed='{"title": "Release 0.5.0", "state": "closed", "labels": ["hardware-check:passed"], "url": "https://example.invalid/5"}'

failed=0
# expect <allow|refuse> <description>: runs the gate on testing against stable.
expect() {
    local output line status=0
    output=$(cd "${repo}" && "${gate}" "ghcr.io/x/pindu-os@sha256:testing" "ghcr.io/x/pindu-os:stable" 2>&1) || status=$?
    if { [[ $1 == allow ]] && ((status == 0)); } || { [[ $1 == refuse ]] && ((status == 1)); }; then
        echo "ok    $1: $2"
    else
        echo "FAIL  expected $1 (exit ${status}): $2"
        while IFS= read -r line; do echo "      ${line}"; done <<<"${output}"
        failed=1
    fi
}

images "ghcr.io/x/pindu-os@sha256:testing ${rev[same]}" "ghcr.io/x/pindu-os:stable ${rev[old]}"
issues '[]'
expect allow "same launcher as stable, no hardware check recorded"

images "ghcr.io/x/pindu-os@sha256:testing ${rev[new]}" "ghcr.io/x/pindu-os:stable ${rev[old]}"
issues '[]'
expect refuse "new launcher, no release issue"

issues '[{"title": "Release 0.5.0", "state": "open", "labels": [], "url": "https://example.invalid/5"}]'
expect refuse "new launcher, release issue without the passed label"

issues '[{"title": "Release 0.5.0 with packages", "state": "closed", "labels": ["hardware-check:passed"], "url": "u"},
         {"title": "Release 0.4.0", "state": "closed", "labels": ["hardware-check:passed"], "url": "u"}]'
expect refuse "new launcher, only other releases passed"

issues "[${released_passed}]"
expect allow "new launcher, closed release issue labelled hardware-check:passed"

issues '[{"title": "Release 0.5.0", "state": "open", "labels": ["hardware-check:passed"], "url": "u"}]'
expect allow "new launcher, open release issue labelled hardware-check:passed"

images "ghcr.io/x/pindu-os@sha256:testing ${rev[new]}"
issues '[]'
expect refuse "no stable image yet, no hardware check recorded"
issues "[${released_passed}]"
expect allow "no stable image yet, hardware check passed"

images "ghcr.io/x/pindu-os@sha256:testing ${rev[rc]}" "ghcr.io/x/pindu-os:stable ${rev[old]}"
issues '[{"title": "Release 0.6.0~rc1", "state": "open", "labels": ["hardware-check:passed"], "url": "u"},
         {"title": "Release 0.6.0", "state": "open", "labels": ["hardware-check:passed"], "url": "u"}]'
expect refuse "launcher pre-release"

images "ghcr.io/x/pindu-os@sha256:testing unknown" "ghcr.io/x/pindu-os:stable ${rev[old]}"
issues "[${released_passed}]"
expect refuse "image to promote has no source commit"

images "ghcr.io/x/pindu-os:stable ${rev[old]}"
expect refuse "image to promote does not exist"

exit "${failed}"
