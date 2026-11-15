# Pindu OS

Pindu OS turns a PC into a game console: it boots, logs in by itself and shows
[pindu-launcher](https://github.com/Tim-van-Oudheusden/pindu-launcher) fullscreen inside
[gamescope](https://github.com/ValveSoftware/gamescope). It is one x86_64
[bootc](https://bootc-dev.github.io/bootc/) image on Fedora 45, updated as a whole from a container registry and rolled
back the same way.

| Image | For | Has |
| --- | --- | --- |
| `ghcr.io/tim-van-oudheusden/pindu-os` | Consoles | No SSH server, no sudo, no password |
| `ghcr.io/tim-van-oudheusden/pindu-os-dev` | Test machines | SSH with keys, passwordless sudo, a shell on VT 2, debugging tools |

Both come in two channels: `:testing` is built from every change and once a day, `:stable` is a tested `:testing`
build. Every published image is signed, and devices refuse an update that is not.

## Documentation

- [Install guide](docs/install.md): install on a PC from the ISO, or try it in a virtual machine; updates and rollback
- [Runbook](docs/runbook.md): one-time setup, releasing, the signing key, testing on hardware, what to do when a build
  or a device breaks
- [Architecture](docs/architecture.md): what is in the image and how it is built, tested and published
- [Decisions](docs/decisions/README.md): one record per design decision
- [Spec and implementation plan](pindu-os%20bootc%20OS%20spec%20and%20implementation%20plan.md)

## Building

The build needs `podman`, [`just`](https://just.systems) and `git`. Every pinned input is in [`image.env`](image.env).

```sh
just build            # the production image, as localhost/pindu-os:local
just test             # checks inside the image
just lint             # shellcheck, hadolint, actionlint, zizmor
just build dev && just test dev
```

Disk images need root for [bootc-image-builder](https://github.com/osbuild/bootc-image-builder) (the recipes call
`sudo`), and the VM tests need QEMU with KVM and UEFI firmware (`qemu-system-x86`, `edk2-ovmf`):

```sh
just build-qcow2      # output/prod/qcow2/disk.qcow2
just run-vm           # look at it in a QEMU window
just test-vm          # boot it headless, assert on the session, save a screenshot
just test-update      # stage an update from a local registry, boot it, roll back
just build-iso && just test-install
```

`just --list` shows every recipe. Contributions follow [`AGENTS.md`](AGENTS.md); security reports follow
[`SECURITY.md`](SECURITY.md).

## Licence

GPL-3.0-or-later, see [`LICENSE`](LICENSE). Parts of the repository layout and the build recipes are adapted from
[ublue-os/image-template](https://github.com/ublue-os/image-template) (Apache-2.0) and
[armada-os/armada](https://github.com/armada-os/armada) (GPL-2.0-or-later).
