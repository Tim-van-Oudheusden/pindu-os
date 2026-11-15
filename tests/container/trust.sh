#!/usr/bin/env bash
# OS-11: when the image carries the cosign public key, the signature policy requires a
# signature made with it for our repositories and still matches the base image's policy for
# everything else. Without the key (before docs/runbook.md "Signing key" is done), the image
# must not carry a policy that would block every update.
set -euo pipefail
# shellcheck source=tests/container/lib.sh
source /tests/lib.sh

key=/etc/pki/containers/pindu-os.pub
policy=/etc/containers/policy.json
lookaside=/etc/containers/registries.d/pindu-os.yaml
base_policy=/usr/share/containers/policy.json

if [[ ! -e ${key} ]]; then
    echo "note  no signing key in this image: signatures are not enforced"
    check_not "no policy.json overrides the base image's" test -e "${policy}"
    check_not "no registries.d entry for our repositories" test -e "${lookaside}"
    finish
    exit 0
fi

check "the public key is a PEM public key" grep -q 'BEGIN PUBLIC KEY' "${key}"

repos=$(jq -r '.transports.docker | to_entries[] | select(.value[0].keyPath == "'"${key}"'") | .key' "${policy}")
check_eq "the policy covers pindu-os and pindu-os-dev" 2 "$(grep -c '/pindu-os\(-dev\)\?$' <<<"${repos}")"
for repo in ${repos}; do
    requirement=$(jq -c --arg repo "${repo}" '.transports.docker[$repo]' "${policy}")
    check_eq "${repo} requires a signature with our key, valid for any tag" \
        '[{"type":"sigstoreSigned","keyPath":"'"${key}"'","signedIdentity":{"type":"matchRepository"}}]' \
        "${requirement}"
    check "${repo} signatures are read from the registry" \
        grep -q -A 1 "^  ${repo}:\$" "${lookaside}"
done

# Everything the base image's policy says must still hold.
check_eq "the default requirement is the base image's" \
    "$(jq -c .default "${base_policy}")" "$(jq -c .default "${policy}")"
for transport in $(jq -r '.transports | keys[]' "${base_policy}"); do
    for scope in $(jq -r --arg t "${transport}" '.transports[$t] | keys[] | select(. != "")' "${base_policy}"); do
        check_eq "${transport} ${scope} is as in the base image" \
            "$(jq -c --arg t "${transport}" --arg s "${scope}" '.transports[$t][$s]' "${base_policy}")" \
            "$(jq -c --arg t "${transport}" --arg s "${scope}" '.transports[$t][$s]' "${policy}")"
    done
done

finish
