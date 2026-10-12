# UZ801 build and installation notes — October 2026

This is a retrospective of one successful device session, not a universal
recipe for every MSM8916 dongle. It combines the saved build scripts,
an intermediate EDL handoff and the subsequently reported flash/boot
results. Intermediate failures are kept separate from the later success.

## 1. Native ARM64 build

Firmware was built from this fork on a Raspberry Pi 5 running native
64-bit ARM Linux. The target Debian release was pinned to `trixie`, rather
than the moving `stable` alias. The wrapper ran the existing repository's
bootloader, firmware extraction, debootstrap, gadget and image stages.

The final payload contained the five bootloader/firmware files, generated
GPT, boot image and rootfs image listed in this folder's README. Stage logs,
payload existence checks, sparse magic checks and a SHA-256 manifest were
produced. Neither Pi wrapper performed flashing.

The scripts guard against leaked chroot/image mounts before a build retry.
This is important because a recursive cleanup traversing a bind-mounted
host `/dev` would affect the host rather than just disposable build files.

## 2. EDL through Windows and WSL

The stick was initially handled through Windows and Ubuntu WSL. Qualcomm
EDL enumeration (`05c6:9008`) was passed to WSL using usbipd-win; an EDL
loader was selected and the partition table could be read.

USB ownership and mode changes needed attention. A device attached to WSL
is not simultaneously available to native Windows fastboot. USB bus IDs
and the applicable Windows driver can change when the stick changes mode.
Enumerate the current device again instead of reusing a session-specific
bus ID. Do not accidentally select a laptop's built-in modem or another
USB device.

An EDL executable resolved by the normal user's shell was not found under
sudo's PATH. The session used its resolved executable path. Personal EDL
checkout/loader locations and device identifiers are omitted here.

## 3. Original device data

The session already had a raw eMMC dump. Its initial full-device read
stalled near the end and was interrupted, leaving a small missing tail.
A separate tail read was subsequently taken. Do not describe that initial
dump as a verified complete backup solely because most bytes were present.

The partitions needed for restoration were:

```text
fsc fsg modem modemst1 modemst2 persist sec
```

The final flash output reported extraction and restoration of these
partitions from this same device's original data. Their actual bytes,
device-specific GPT offsets, serial identifiers and firmware/calibration
contents are not published. Do not substitute another device's calibration
or copy this session's offsets to a different partition layout.

## 4. EDL write acknowledgement problem

An early aboot write reached 100% transferred bytes, then ended with a
Firehose error. The intermediate handoff explicitly did not consider this
a successful verified write. The intended next observation was a readback
and byte comparison before continuing boot-mode changes.

The retained intermediate evidence does not contain that readback result.
The later successful fastboot/boot outcome demonstrates that the installation
ultimately progressed, but it does not establish which individual EDL
acknowledgement/recovery step resolved the earlier error. Do not turn a
100% progress line into a claim of verified storage contents.

## 5. Image-transfer and sparse-image problems

The copied rootfs on the receiving Windows machine was initially corrupt.
It was recopied and checked against the build-side SHA-256 manifest.
The personal paths and per-build checksum values have been removed;
users should generate and verify their own manifests.

The boot/rootfs payloads were Android sparse containers. Their physical
file sizes are different from the logical image sizes fastboot writes.
Checking a partition against only the compressed/sparse file size is wrong.
Sparse structure, checksums and expanded size must be validated before
assuming an image is usable or fits its destination.

The final log reported an lk/fastboot GPT expansion of the rootfs partition,
followed by successful image flashing and restoration. Do not hard-code the
recorded device capacity into another installation. A GPT change and an
ext4 filesystem resize are separate operations.

## 6. Final flash and observed boot

The final script output reported:

```text
ALL_FLASH_AND_RESTORE_COMMANDS_SUCCEEDED
REBOOT_REQUESTED
```

Those markers alone are not boot verification. The user then reported the
running system:

| Observation | Reported result |
| --- | --- |
| Operating system | Debian GNU/Linux 13.7 (`trixie`) |
| Kernel | `6.6.0-msm8916` |
| Access | SSH over the USB network worked |
| Root filesystem | About 1.5 GiB, about 383 MiB used, about 1 GiB available |
| ModemManager | Listed one modem |
| SIM/LTE test | No SIM installed; network registration/data not tested |
| Wi-Fi client connection | Requested next; not yet verified in this record |

The USB network address documented by this image is a stock configuration,
not a private LAN address to be copied from another user's setup. Consult
the repository's network configuration and the actual device interfaces.

The filesystem size confirms boot, but not full-disk filesystem growth.
Inspect the actual partition and mounted filesystem before applying any
resize procedure. Likewise, discovering a modem is not evidence of a
working LTE connection without a SIM and a connection test.

## 7. Archive completeness and anonymization

Included: the recovered Pi setup and build wrappers, edited to require
explicit path configuration. Their main build-stage logic is retained;
the setup free-space check follows the selected checkout filesystem and
the host report avoids printing a personal hostname.

Not included: the exact `flash-uz801-fastboot.sh` and `diagnostics*.sh`
iterations. Their successful invocation is known, but their complete source
was not retrievable when this folder was published. This archive does not
present reconstructed commands as copies of those scripts. Add sanitized
copies only after retrieving the real files and checking their parameters.

Removed: personal usernames and home/desktop locations, workstation names, bus IDs,
device serial/HWID/key hashes, passwords, private network details, raw dumps,
calibration data and original session logs. Kept: public repository identity,
standard USB mode identifiers, required partition/file names and operating-
system paths needed to understand or execute the build wrappers.
