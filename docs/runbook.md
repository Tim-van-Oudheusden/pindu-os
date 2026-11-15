# Runbook

How to set the project up once, publish and promote builds, test on hardware, and deal with the things that break.
Steps marked **(person)** need account settings, secrets or a physical machine; the spec lists them as `H-nn` and
agents do not do them.

## One-time setup

### Repository settings (person)

These are set through the GitHub API or in the repository's **Settings**. All but the last one were applied when the
repository was first pushed; the commands are here to check or redo them.

1. **Ruleset for `main`:** [`.github/rulesets/main.json`](../.github/rulesets/main.json) requires a pull request and the
   checks `Lint`, `Build and test (prod)` and `Build and test (dev)` from `pr.yml`, and blocks force pushes and
   deletion; repository admins may bypass it. Change the file through a pull request, then apply it. Renaming a job in
   `pr.yml` means updating the required checks in the same pull request.

   ```sh
   gh api repos/Tim-van-Oudheusden/pindu-os/rulesets --jq '.[] | "\(.id) \(.name)"'    # find the ruleset's id
   gh api -X PUT repos/Tim-van-Oudheusden/pindu-os/rulesets/<id> --input .github/rulesets/main.json
   ```

2. **Actions → General:** workflow permissions are "Read repository contents and packages permissions", and workflow
   runs of outside contributors need approval.
3. **Environments:**
   - `signing`: only `main` may deploy to it. It holds the secret `SIGNING_SECRET`.
   - `promote`: the maintainer is a required reviewer.
4. **Code security:** private vulnerability reporting is on (`SECURITY.md` points people to it).
5. Install the [Renovate app](https://github.com/apps/renovate) on the repository. Its rules are in
   `renovate.json5`. This needs a browser.

After the first successful `build.yml` run, open each package (`pindu-os`, `pindu-os-dev`) under your profile's
**Packages**, make it public and link it to this repository. Devices pull without a login.

### Signing key (person)

Devices refuse images that are not signed with this key, so it is made once and kept safe.

```sh
cosign generate-key-pair            # leave the password empty: the workflow passes none
cp cosign.pub system_files/etc/pki/containers/pindu-os.pub
gh secret set SIGNING_SECRET --env signing < cosign.key
```

Then:

1. Store `cosign.key` offline (a password manager or an encrypted disk) and delete it from the working tree. It is
   never committed.
2. Commit `cosign.pub` and `system_files/etc/pki/containers/pindu-os.pub` through a pull request. `just lint` fails if
   the two differ.

From that commit on, every build carries the key and the signature policy, and `build.yml` can publish. Before it,
builds leave the policy out with a warning and `build.yml` stops at "Refuse to publish an image that cannot be
verified".

**If the key leaks or is lost:** devices trust exactly the key in their current image. Generate a new pair, add the
new public key next to the old one (`keyPaths` in `policy.json`), and publish that image signed with the **old** key
so devices pick it up. Only then start signing with the new key and, a release later, drop the old one. If the old
private key is gone, devices in the field cannot be moved over; they have to be reinstalled.

## Everyday work

### Local checks

```sh
just lint                          # shellcheck, hadolint, just --fmt, actionlint, zizmor
just verify-inputs                 # every pin in image.env resolves (needs skopeo, cosign, curl)
just build && just test            # production image and its container tests
just build dev && just test dev
```

The disk recipes call `sudo` for bootc-image-builder. The VM tests need `qemu-system-x86_64` with KVM and UEFI
firmware (`edk2-ovmf` on Fedora, `ovmf` on Debian and Ubuntu); on an image-based host, run them from a toolbox or
distrobox that has QEMU.

```sh
just build-qcow2 && just test-vm   # boot, session and screenshot; report in output/prod/test-boot/
just test-update                   # staged update and rollback, from a local registry
just build-iso && just test-install
just run-vm                        # look at the image in a QEMU window
```

`just test-vm dev` also logs in over SSH with an injected key.

### What a build publishes

`build.yml` runs on every push to `main` (except changes to documentation only), once a day, and on demand. For each
variant it pushes `:testing` and an immutable `45.YYYYMMDD.N`, signs the digest, attaches provenance and an SBOM, and
boots the published digest in a VM. The run's summary shows the version and digest.

A failed daily build usually means Fedora changed under us. Common causes:

| Failure | Meaning | Fix |
| --- | --- | --- |
| `dnf` cannot find a package | Fedora renamed or dropped it | Update the list in `build_files/30-base-packages.sh` or `40-session-packages.sh` |
| `bootc container lint` warning | A package put files in `/run` or state in `/var` | Remove it in `build_files/90-cleanup.sh`, with the reason |
| "the enabled repositories differ" | A package installed a `.repo` file | Find it with `dnf repolist`, remove the file or the package |
| `verify-inputs` fails | A pinned digest was deleted upstream | Merge or trigger the Renovate bump for it |
| VM boot test fails | See `test.log` and the screenshot in the run's artifacts | Reproduce with `just test-vm` |

### Promoting to stable

`:stable` is a `:testing` build that has been looked at.

1. Check the build you want: its VM test passed, and it runs on the test machine (see below).
2. Run the **Promote** workflow. `source` is `testing`, or a version tag such as `45.20261115.0` to promote an older
   build.
3. Approve the run (the `promote` environment asks for a reviewer).

The workflow verifies the signature of both variants, retags the same digests as `:stable` and then builds the disk
images. Nothing is rebuilt. Devices pick the new `:stable` up within four hours of use and run it after their next
start. To take a bad release back, promote the previous version tag.

### Disk images

The **Disk images** workflow turns a signed tag or digest into `pindu-os.qcow2.zst`, `pindu-os.raw.zst` and
`pindu-os.iso`, tests the qcow2 and the ISO in QEMU and stores all three as artifacts for 30 days. It runs after each
promotion; run it by hand for the dev variant or another tag. `docs/install.md` tells users where to find them.

### Pins

Renovate opens the pull requests that change `image.env` and the action SHAs, and each one has to pass `pr.yml`:

- base image, akmods and bootc-image-builder digests: one grouped pull request a week
- the launcher: on each launcher release, version and SHA-256 together
- tools and GitHub Actions: as they are released

To bump the launcher by hand, set `LAUNCHER_VERSION` and `LAUNCHER_SHA256` (the `sha256` of
`pindu-launcher-<version>-1.fc45.x86_64.rpm`, shown on the release page) and run `just verify-inputs`.

### Moving to a new Fedora release

This is manual, because four things move together. The launcher must already build an RPM for the new release.

1. In `image.env`: `FEDORA_VERSION`, the tag and digest of `BASE_IMAGE`, the tag and digest of `AKMODS_IMAGE`.
2. `just verify-inputs`, then build and run every test, including `just test-update` and `just test-install`.
3. Test on hardware before promoting.

## Testing on hardware

The VM tests cannot prove gamescope: a virtual GPU has no Vulkan, so the session falls back to cage there. Each gate
below is a person at a real PC.

### Getting the dev image onto a PC (person)

Before the first promotion there is no ISO to download. Build one locally and write it to a USB stick as in
`docs/install.md`:

```sh
just build dev && just build-iso dev          # output/dev/bootiso/install.iso
```

The installer erases the PC's disks.

### Gate v0: the dev image on a PC with an AMD or Intel GPU (person)

- [ ] The launcher is fullscreen a few seconds after power-on, with no login.
- [ ] It runs under gamescope, not the fallback: in the shell on VT 2, `pgrep -a gamescope` prints a process and
      `journalctl --user -u pindu-session` has no "falling back to cage" line.
- [ ] A controller moves the focus.
- [ ] Navigation sounds play.
- [ ] On a 4K television the interface is sharp enough and not tiny (gamescope renders at 1080 lines and upscales).
- [ ] A game that opens its own launcher window first (a Steam title) gets the focus and gives it back.

If gamescope does not start, `vulkaninfo --summary` shows whether the GPU has a Vulkan driver, and
`journalctl --user -u pindu-session` has gamescope's own messages. Extra gamescope arguments can be tried without a
rebuild:

```sh
systemctl --user edit pindu-session.service
#   [Service]
#   Environment=PINDU_GAMESCOPE_ARGS=--prefer-output HDMI-A-1
# then end the session; greetd starts a new one:
systemctl --user stop pindu-session.service
```

### Gate v1: install, update, roll back (person)

- [ ] The ISO from the Disk images workflow installs without a keyboard and the PC boots into the launcher.
- [ ] After a new `:stable` is promoted, the console stages it by itself (leave it on for 15 minutes) and runs it
      after the next power cycle. `cat /usr/share/pindu-os/image-info.json` on the dev image shows the version.
- [ ] Rollback works: the previous entry in the boot menu, or `sudo bootc rollback` on the dev image.

Rolling back on the production image needs a keyboard for the boot menu until the launcher has a system panel.

## OGC kernel

`KERNEL_FLAVOR=ogc` swaps Fedora's kernel for the Open Gaming Collective kernel, prebuilt in
`ghcr.io/ublue-os/akmods:ogc-45`:

```sh
just build prod ogc                # or set KERNEL_FLAVOR=ogc in image.env to make it the default
```

That kernel is signed with Universal Blue's key, not Fedora's. With Secure Boot on, the firmware refuses it until the
owner of the machine enrols Universal Blue's certificate once. The image carries it:

```sh
sudo mokutil --import /etc/pki/akmods/certs/akmods-ublue.der     # asks for a one-time password
sudo systemctl reboot                                            # the blue MOK screen asks for that password
```

This needs root, so it is done on the dev image, or with a keyboard before the switch to the OGC kernel. The
alternative is to turn Secure Boot off in the firmware. `KERNEL_FLAVOR=fedora` stays the default and the fallback.

## If we ever add self-hosted runners

Everything runs on GitHub-hosted runners. A self-hosted runner executes whatever a workflow tells it to, and a pull
request can change the workflow, so these rules apply together (spec, "If we ever add self-hosted runners"):

1. No pull-request triggers on self-hosted jobs: only `push` to protected branches, `schedule`, `workflow_dispatch`
   and `merge_group`.
2. A maintainer starts heavy builds for outside changes, on an exact commit SHA, after reading the diff.
3. Ephemeral VMs: a fresh VM per job, registered with `--ephemeral`, destroyed afterwards.
4. Runner groups limited to this repository and to named workflow files. This needs a GitHub organisation; the
   repository lives under a user account today.
5. No secrets on the builder: it gets `contents: read` and hands an unsigned artifact with its hash to a hosted job
   that checks, pushes and signs.
6. Network isolation: outbound only, no route to a home or office network.
7. Never `pull_request_target` with a checkout of pull request code, on any runner.
