# Pi 5 build and Windows/WSL flashing session

This folder records a successful native Raspberry Pi 5 build of Debian 13
(`trixie`) for a UZ801/MSM8916 USB stick, followed by installation using
Windows, Ubuntu WSL, EDL and fastboot.

The two shell scripts are the recovered build wrappers from that session,
sanitized for publication. They build images; neither flashes a device.
[SESSION-NOTES.md](SESSION-NOTES.md) records the installation problems and
the observed result, separately from what the archived scripts implement.

## Files

| File | Purpose |
| --- | --- |
| `setup-uz801-pi5.sh` | Check native ARM64 host, install dependencies, clone or reuse this fork without resetting local changes |
| `build-uz801-pi5.sh` | Run the five build stages with logs, a build lock, mount checks and final payload checksums |
| `SESSION-NOTES.md` | Anonymized build/USB handover/flashing/boot account and the remaining evidence limits |
| `.gitignore` | Keep local payloads, dumps and logs out of this folder's Git history |

The original `flash-uz801-fastboot.sh` and the `diagnostics*.sh` iterations
were not recoverable for this archive. They are **not** replaced here with
an inferred flashing script. Copying an incomplete recipe into an executable
hardware-writing script would misrepresent what was actually run.

## Configure paths

User-chosen directories use the literal placeholder `write path here`.
Set the environment variables or replace those quoted defaults before use.
Both scripts refuse an unset/unchanged placeholder before doing setup or
building. Host usernames, personal folders, device serials, calibration
contents, passwords and private network addresses have been omitted.

Essential operating-system paths such as `/dev`, `/boot` and `/usr` remain
because changing them would break the scripts. The public repository URL
also remains because setup needs to clone the intended fork.

On the Pi, set an absolute checkout path **without spaces**:

```bash
export UZ801_DIR='write path here'
export UZ801_LOG_DIR='write path here'
export RELEASE=trixie
```

Replace both path placeholders. The log directory should be outside the
checkout and on a filesystem with room for build logs.

## Build on the Pi

Use a normal user with sudo access, native `aarch64` Linux and an `arm64`
Debian/Raspberry Pi OS userland. Have at least the documented 8 GiB of free
space available on the filesystem holding the checkout; this is a starting
budget, not a guarantee for every dependency/source revision.

After downloading the two scripts into the same directory:

```bash
bash ./setup-uz801-pi5.sh
bash ./build-uz801-pi5.sh
```

Do not run the wrappers themselves with sudo. They invoke sudo for the
underlying scripts that install packages, create chroots or mount images.

The stages are:

1. `bootloaders` — build hyp and aboot/lk2nd;
2. `firmware` — extract the firmware payload and generated GPT;
3. `rootfs` — build the Debian root filesystem with `RELEASE=trixie`;
4. `gadget` — build the USB gadget utilities;
5. `images` — package boot/rootfs as Android sparse images.

Resume only after earlier stages have completed successfully:

```bash
bash ./build-uz801-pi5.sh --from rootfs
# Or: --from gadget / --from images
```

The wrappers do not pin all submodules, downloaded firmware or Debian
packages. Record the checkout/submodule revisions and retain the logs if
you need to reproduce a particular build.

## Outputs and transfer

The required files under `$UZ801_DIR/files/` are:

```text
aboot.mbn
hyp.mbn
rpm.mbn
sbl1.mbn
tz.mbn
gpt_both0.bin
boot.bin
rootfs.bin
```

The wrapper writes `$UZ801_LOG_DIR/SHA256SUMS.local`. Copy that manifest
with the payload to the receiving machine, then check the transferred
bytes before flashing:

```bash
cd 'write path here'
sha256sum --check SHA256SUMS.local
```

This matters: a corrupted transferred rootfs was one of the failures in
the recorded session. An existing filename or plausible file size did not
prove that the copy was correct.

The script also checks the sparse magic on `boot.bin` and `rootfs.bin`;
this is a format sanity check, not a complete sparse-container validator.
Sparse file size is not the expanded image size or its destination capacity.

## Mount protection

The builder uses chroot bind mounts and image mounts. The wrapper refuses
to start/retry while mounts remain under its `rootfs/` or `mnt/` paths and
checks again after each stage and at exit. Do not delete a rootfs directory
while it still contains mounted host filesystems. Inspect and unmount the
actual mounts before retrying; the wrapper does not blindly force-clean them.

## Installation and result

Read [the session notes](SESSION-NOTES.md) together with the repository's
[installation instructions](../../README.md#firmware-installation).
The archived wrappers are not an automatic installation procedure.
Bootloader/GPT writes and restoration of device-specific partitions must
use the correct device, board image, destination geometry and original data.

The observed device booted Debian 13.7 (`trixie`) with kernel
`6.6.0-msm8916`; SSH over its USB network worked, and ModemManager listed
a modem. The root filesystem still reported about 1.5 GiB after flashing.
That does not prove filesystem expansion to the full partition capacity.
No SIM was installed, and LTE connectivity and joining a local Wi-Fi
network had not been validated at the recorded checkpoint.

## Validation of these published copies

The original wrappers were used during the build session. The anonymized
copies received shell syntax, help and placeholder-refusal checks before
publication. A new Pi build or hardware flash was not performed as part
of publishing this folder. The files use the repository's existing license.
