# packages/

Empty in v0: the image is built only from prebuilt, pinned inputs (`image.env`).

This directory is reserved for the first package that has to be forked or patched (gamescope, Mesa, a kernel, or the
launcher built from a pinned commit for a testing stream). Each fork then gets one directory with a `BASE.env` (the
pinned upstream source), `patches/` and a `build.sh`, is built once into an image tagged by a hash of those sources
(`ghcr.io/tim-van-oudheusden/pindu-os/pkg/<name>:<hash>`), and the `Containerfile` mounts its RPMs like it mounts the
launcher's. `docs/decisions/0008-repositories.md` says when this moves to its own repository.
