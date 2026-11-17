# Install guide

This guide takes a PC from nothing to Pindu OS showing the launcher, and covers updates and rollback. You do not need
to have seen any other document.

## What you need

- A 64-bit Intel or AMD PC with UEFI firmware. Secure Boot can stay on.
- An AMD or Intel GPU. gamescope needs Vulkan; NVIDIA cards are not supported yet.
- A wired network connection. Wi-Fi has no setup screen yet (see [Wi-Fi](#wi-fi)).
- A USB stick of 8 GB or more, a keyboard for the installer, and a controller.
- A PC with exactly one disk, and nothing on it that you want to keep.

> **The installer erases the PC's disk.** It installs only on a PC with exactly one disk, shows you that disk and
> erases it once you type `erase`. A PC with more than one disk is refused: see
> [A PC with several disks](#a-pc-with-several-disks).

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

1. Plug the network cable, a keyboard and the USB stick into the PC.
2. Start the PC and open its boot menu (often F12, F8 or Esc) and choose the USB stick.
3. The installer starts by itself and counts the disks of the PC. The USB stick it runs from does not count; every
   other disk does, including a second USB stick or a memory card.
   - **One disk:** it shows the disk's name, model and size and the partitions on it, and asks you to type `erase`.
     Type `erase` and press Enter to erase that disk and install Pindu OS. Anything else turns the PC off and leaves
     the disk as it was.
   - **No disk, or more than one:** it says so and lists the disks it found. Press Enter to turn the PC off. Nothing
     is written to any disk.
4. After `erase` it installs and restarts the PC by itself. It takes five to ten minutes.
5. Remove the USB stick when the PC restarts.

The PC then boots straight into the launcher: there is no login and no password. Connect a controller with a cable, or
pair it later from the dev image (Bluetooth has no setup screen yet).

### A PC with several disks

The installer never chooses between disks, so that it cannot erase the wrong one. To install on a PC with more than
one disk, turn it off and disconnect every disk except the one for Pindu OS: unplug USB disks and memory cards, and
unplug the data or power cable of the other internal drives (or take out the extra NVMe drive). Then start the
installer again. Once Pindu OS is installed you can connect the other disks again. If the PC then starts another
system, make the Pindu OS disk the first boot device in its firmware settings.

### Unattended installation

For automated installations (and the project's VM test), the confirmation can come from the systemd credential
`pindu.install.confirm`, set to the kernel name of the disk to erase, for example `sda` or `nvme0n1`. In the boot menu,
press `e` on the install entry and add to the end of the `linux` line:

```text
systemd.set_credential=pindu.install.confirm:nvme0n1
```

then press Ctrl+X. A VM can pass the same credential over SMBIOS (`tests/vm/install.sh` does). The installer still
shows the disk, then installs without asking. It still refuses a PC with more than one disk, and a credential that
names a different disk turns the PC off without changes. Nothing sets this credential by default.

## Updates

The console looks for an update ten minutes after it starts and every four hours while it is on. An update is
downloaded in the background and takes effect **the next time the console starts**; it never restarts by itself.
Every update is checked against the project's signature and refused without it.

Nothing needs to be done. To get an update sooner, restart the console twice: once so it has time to download, once to
start the new version.

## Rollback

Every update keeps the previous version on disk.

- **With a controller:** open Quick Access in the launcher and choose **System Update**. It shows the installed
  version, an update that is ready, and **Roll Back to *version***. Confirm, and the console restarts into the previous
  version. If an update was downloaded but not started yet, rolling back drops it. The console keeps looking for
  updates, so it downloads the newer version again and starts it at the restart after that: rollback is a way out of a
  bad update until a fixed one is published.
- **With a keyboard:** restart the console and press the down arrow as soon as the boot menu shows. It lists two
  entries; the second one is the previous version. Select it and press Enter. This boots the previous version once.
- **On the dev image:** make the previous version the default again with

  ```sh
  sudo bootc rollback
  sudo systemctl reboot
  ```

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
| The installer says the PC has no disk, or more than one | It counts every disk except the USB stick it runs from. Disconnect the others (see [A PC with several disks](#a-pc-with-several-disks)); if it finds none, check that the disk shows up in the firmware settings. |
| The installer stops with an error | The download of the image inside the ISO is damaged. Check `SHA256SUMS` and write the stick again. |
| No update arrives | The console needs a network cable and must stay on for ten minutes. On the dev image, `sudo bootc upgrade` shows the error. |
| The console does not start after an update | Choose the previous version in the boot menu (see [Rollback](#rollback)), then report it in the [issue tracker](https://github.com/Tim-van-Oudheusden/pindu-os/issues). |
