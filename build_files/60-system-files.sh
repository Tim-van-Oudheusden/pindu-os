#!/usr/bin/env bash
# Copies system_files/ into the image, creates the pindu user and enables the units that turn
# a Fedora bootc system into the console: greetd on VT 1, the graphical target, staged updates.
set -euo pipefail

cp --archive --no-preserve=ownership /ctx/system_files/. /

# Signature enforcement. policy.json makes the device refuse images from our repositories
# unless they are signed with /etc/pki/containers/pindu-os.pub. That key is the public half
# of the cosign key pair a maintainer creates once (docs/runbook.md, "Signing key"). Until it
# is committed, an image that carried the policy could never update, so the policy is left
# out and the build says so; build.yml refuses to publish such an image.
key=/etc/pki/containers/pindu-os.pub
if [[ ! -s ${key} ]]; then
    echo "::warning::${key} is missing: this image does not enforce signatures on updates"
    rm -f /etc/containers/policy.json /etc/containers/registries.d/pindu-os.yaml
fi

# Fedora 45 keeps its repository files in /usr/share/dnf5/repos.d. bootc-image-builder reads
# only /etc/yum.repos.d when it looks up the installer's packages for the ISO, and finds no
# repository. Link the files there; dnf treats a file of the same name as the same repository.
ln --symbolic --relative /usr/share/dnf5/repos.d/*.repo /etc/yum.repos.d/

# Create the user now, so the image's /etc/passwd has it; systemd-sysusers runs again on
# every boot and finds nothing to do.
systemd-sysusers
if [[ $(passwd --status pindu | cut -d ' ' -f 2) != L ]]; then
    echo "ERROR: the pindu account must have a locked password" >&2
    exit 1
fi

systemctl enable greetd.service
systemctl set-default graphical.target
systemctl enable bootc-fetch-apply-updates.timer
