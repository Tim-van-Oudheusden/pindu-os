# Install guide

This guide takes a PC from nothing to Pindu OS showing the launcher, and covers updates and rollback. You do not need
to have seen any other document.

## What you need

- A 64-bit Intel or AMD PC with UEFI firmware. Secure Boot can stay on.
- An AMD or Intel GPU. gamescope needs Vulkan; NVIDIA cards are not supported yet.
- A wired network connection. Wi-Fi has no setup screen yet (see [Wi-Fi](#wi-fi)).
- A USB stick of 8 GB or more, and a controller.
- Nothing on the PC that you want to keep.

> **The installer erases the PC.** It is unattended: once it boots, it wipes every disk in the machine and installs
> without asking a single question. Unplug any disk you want to keep before you start, and do not leave the USB stick
> in a PC you did not mean to install.

## 1. Download the installer

Disk images are built by the repository's **Disk images** workflow and kept as workflow artifacts (they are too large
for a GitHub release).

1. Open [Actions → Disk images](https://github.com/Tim-van-Oudheusden/pindu-os/actions/workflows/disk.yml) and pick the
   latest successful run. A run starts after every promotion to `:stable`.
2. Download the `pindu-os-iso` artifact and unpack it. It holds `pindu-os.iso` and `SHA256SUMS`.
3. Check the download:

   ```sh
   sha256sum --check SHA256SUMS
   ```

With the [GitHub CLI](https://cli.github.com) the same is:

```sh
gh run download --repo Tim-van-Oudheusden/pindu-os --name pindu-os-iso
```

## 2. Write it to a USB stick

Use [Fedora Media Writer](https://fedoraproject.org/workstation/download) ("Select .iso file"), or on Linux:

```sh
lsblk                      # find the USB stick, for example /dev/sdb
sudo dd if=pindu-os.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

Replace `/dev/sdX` with the stick. `dd` overwrites whatever you point it at.

## 3. Install

1. Plug the network cable and the USB stick into the PC.
2. Start the PC and open its boot menu (often F12, F8 or Esc) and choose the USB stick.
3. Leave it alone. The installer starts by itself, installs and restarts the PC. It takes five to ten minutes.
4. Remove the USB stick when the PC restarts.

The PC then boots straight into the launcher: there is no login and no password. Connect a controller with a cable, or
pair it later from the dev image (Bluetooth has no setup screen yet).

## Updates

The console looks for an update ten minutes after it starts and every four hours while it is on. An update is
downloaded in the background and takes effect **the next time the console starts**; it never restarts by itself.
Every update is checked against the project's signature and refused without it.

Nothing needs to be done. To get an update sooner, restart the console twice: once so it has time to download, once to
start the new version.

## Rollback

Every update keeps the previous version on disk.

- **With a keyboard:** restart the console and press the down arrow as soon as the boot menu shows. It lists two
  entries; the second one is the previous version. Select it and press Enter. This boots the previous version once.
- **On the dev image:** make the previous version the default again with

  ```sh
  sudo bootc rollback
  sudo systemctl reboot
  ```

The production image has no shell, so it cannot run `bootc rollback` itself until the launcher has a system panel.

## Try it in a virtual machine

The `pindu-os-qcow2` artifact of the same workflow run is a disk image for QEMU, GNOME Boxes or virt-manager (UEFI
firmware, 4 GB of memory, a virtio GPU). Unpack it first:

```sh
zstd -d pindu-os.qcow2.zst
```

A virtual GPU has no Vulkan, so in a VM the launcher runs in the fallback compositor (cage) instead of gamescope. It
looks the same, and games will not perform.

## The dev image

`pindu-os-dev` is the same system for test machines, with ways in that the production image does not have. Install it
from the `pindu-os-dev-iso` artifact (run the Disk images workflow with variant `dev`).

- **Shell:** press Ctrl+Alt+F2 for a shell, logged in as `pindu`. Ctrl+Alt+F1 returns to the launcher.
- **Root:** `sudo` works without a password.
- **SSH:** the server runs and accepts keys only. Add yours from the shell on VT 2:

  ```sh
  mkdir -m 700 -p ~/.ssh
  curl -fsSL https://github.com/<your-github-user>.keys >> ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
  ip -brief address          # the address to connect to
  ```

  Then, from another machine: `ssh pindu@<address>`.

### Wi-Fi

On the dev image, run `nmtui` in the shell on VT 2 and choose "Activate a connection". The production image needs a
network cable until the launcher has a network panel.

### Looking at a system

```sh
cat /usr/share/pindu-os/image-info.json       # image, version, kernel, launcher version
sudo bootc status                             # booted, staged and rollback images
systemctl status bootc-fetch-apply-updates.timer
journalctl --user -u pindu-session            # the session: gamescope or cage, and the launcher
```

### Switching channel

A device follows the tag it was installed from (`:stable` for the ISO). To follow test builds instead:

```sh
sudo bootc switch --enforce-container-sigpolicy ghcr.io/tim-van-oudheusden/pindu-os-dev:testing
sudo systemctl reboot
```

## Checking an image yourself

```sh
cosign verify --new-bundle-format=false \
    --key https://raw.githubusercontent.com/Tim-van-Oudheusden/pindu-os/main/cosign.pub \
    ghcr.io/tim-van-oudheusden/pindu-os:stable
gh attestation verify oci://ghcr.io/tim-van-oudheusden/pindu-os:stable --repo Tim-van-Oudheusden/pindu-os
```

The first command checks the project's signature, the second that the image was built by this repository's workflow
from a commit on `main`. `--new-bundle-format=false` makes cosign 3 read the signature in the classic format, which is
the one the devices check; without it cosign reports "expected key signature, not certificate".

## When something is wrong

| What you see | What to do |
| --- | --- |
| A black screen with a cursor, or the launcher appears only after about 20 seconds | gamescope could not start on this GPU and the fallback took over. On the dev image, `journalctl --user -u pindu-session` says why; `vulkaninfo --summary` shows whether the GPU has a Vulkan driver. |
| The installer stops with an error | It found no disk it could use, or the download of the image inside the ISO is damaged. Check `SHA256SUMS` and write the stick again. |
| No update arrives | The console needs a network cable and must stay on for ten minutes. On the dev image, `sudo bootc upgrade` shows the error. |
| The console does not start after an update | Choose the previous version in the boot menu (see [Rollback](#rollback)), then report it in the [issue tracker](https://github.com/Tim-van-Oudheusden/pindu-os/issues). |
