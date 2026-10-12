#!/usr/bin/env bash
# Build UZ801 image artifacts on native ARM64 Raspberry Pi 5.
# Run as a normal user. Sub-builds are invoked with sudo because they
# install packages in a chroot and mount loopback image files.
set -Eeuo pipefail

REPO_DIR="${UZ801_DIR:-write path here}"
LOG_DIR="${UZ801_LOG_DIR:-write path here}"
RELEASE="${RELEASE:-trixie}"  # Pin Debian 13; 'stable' changes over time.
STAGES=(bootloaders firmware rootfs gadget images)
FROM='bootloaders'

usage() {
  cat <<'USAGE'
Usage:
  ./build-uz801-pi5.sh
  ./build-uz801-pi5.sh --from rootfs
  ./build-uz801-pi5.sh --from gadget
  ./build-uz801-pi5.sh --from images

Stages (in order): bootloaders, firmware, rootfs, gadget, images
--from STAGE: rerun the named stage and all subsequent stages.
              Use only after previous stages have completed successfully.

Environment:
  UZ801_DIR      Repo directory (required; placeholder: write path here)
  UZ801_LOG_DIR  Log directory (required; placeholder: write path here)
  RELEASE        Debian target release (default: trixie)

Output: $UZ801_DIR/files/{aboot.mbn,hyp.mbn,rpm.mbn,sbl1.mbn,
                             tz.mbn,gpt_both0.bin,boot.bin,rootfs.bin}
IMPORTANT: Does NOT flash the device.
USAGE
}

while (( $# > 0 )); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --from)
      (( $# >= 2 )) || { usage >&2; exit 2; }
      FROM=$2; shift 2 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

say() { printf '\n==> %s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -n "$REPO_DIR" && "$REPO_DIR" != 'write path here' ]] || fail 'Set UZ801_DIR to your checkout path (replace write path here).'
[[ -n "$LOG_DIR" && "$LOG_DIR" != 'write path here' ]] || fail 'Set UZ801_LOG_DIR to your log path (replace write path here).'
[[ "$REPO_DIR" == /* && "$LOG_DIR" == /* ]] || fail 'Build and log directories must be absolute paths.'

(( EUID != 0 )) || fail 'Run as your normal user (NOT sudo).'
[[ $(uname -m) == aarch64 ]] || fail 'Requires native aarch64 Linux, not x86/QEMU.'
[[ "$REPO_DIR" != *' '* ]] || fail 'Upstream build scripts require paths without spaces.'
[[ -d "$REPO_DIR/.git" ]] || fail "No repository at $REPO_DIR. Run setup-uz801-pi5.sh first."

from_index=-1
for i in "${!STAGES[@]}"; do
  [[ "${STAGES[$i]}" != "$FROM" ]] || from_index=$i
done
(( from_index >= 0 )) || fail "Unknown stage '$FROM'. Try --help."

for command_name in git debootstrap aarch64-linux-gnu-gcc img2simg findmnt awk flock sudo; do
  command -v "$command_name" >/dev/null || fail "Missing $command_name; run setup first."
done

mkdir -p "$LOG_DIR"
exec 9>"$LOG_DIR/build.lock"
flock -n 9 || fail "Another UZ801 build is already running (lock: $LOG_DIR/build.lock)."

cd "$REPO_DIR"
REPO_DIR=$(pwd -P)

# Critically important: the upstream debootstrap script does rm -rf rootfs;
# if /dev is still bind-mounted there, rm may delete host /dev entries.
# REFUSE to run when any such mount exists; do NOT try to auto-delete it.
active_mounts() {
  findmnt -rn -o TARGET | awk -v root="$REPO_DIR/rootfs" -v img="$REPO_DIR/mnt" '
    $0 == root || index($0, root "/") == 1 ||
    $0 == img  || index($0, img "/") == 1 { print }
  '
}

check_mounts() {
  local leaked
  leaked=$(active_mounts)
  if [[ -n "$leaked" ]]; then
    printf '\nBLOCKED: Existing mounts under rootfs/ or mnt/:\n%s\n\n' "$leaked" >&2
    printf 'DO NOT run rm -rf rootfs. Investigate and unmount safely first.\n' >&2
    return 1
  fi
}

check_mounts || fail 'Unsafe mount state detected.'

finish() {
  local status=$?
  trap - EXIT
  if ! check_mounts; then
    printf 'WARNING: Build left active mounts; fix them before any retry.\n' >&2
    (( status != 0 )) || status=1
  fi
  if (( status != 0 )); then
    printf '\nBUILD STOPPED (exit %d). Logs: %s\n' "$status" "$LOG_DIR" >&2
  fi
  exit "$status"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

say 'Host and build revision'
uname -m
printf 'Repository: %s\nTarget Debian release: %s\n' "$REPO_DIR" "$RELEASE"
git log -1 --format='%h %cs %s'
printf 'Starting from stage: %s\nLogs: %s\n' "$FROM" "$LOG_DIR"

timestamp=$(date +%Y%m%d-%H%M%S)
for i in "${!STAGES[@]}"; do
  (( i >= from_index )) || continue
  stage=${STAGES[$i]}
  check_mounts || fail "Cannot start stage $stage."
  say "Stage: $stage"
  log="$LOG_DIR/$timestamp-$stage.log"
  case "$stage" in
    bootloaders)
      # Upstream appends a compile flag to a submodule Makefile. A fresh
      # checkout avoids duplicate additions; do not reset local user changes.
      sudo scripts/build_hyp_aboot.sh 2>&1 | tee "$log" ;;
    firmware)
      sudo scripts/extract_fw.sh 2>&1 | tee "$log" ;;
    rootfs)
      sudo env "RELEASE=$RELEASE" scripts/debootstrap.sh 2>&1 | tee "$log" ;;
    gadget)
      sudo scripts/build_gt.sh 2>&1 | tee "$log" ;;
    images)
      # Remove previous outputs so stale successful images cannot be mistaken
      # for images produced by this run.
      sudo rm -f files/boot.bin files/rootfs.bin
      sudo scripts/build_images.sh 2>&1 | tee "$log" ;;
  esac
  check_mounts || fail "Stage $stage finished with leaked mounts."
  printf 'Stage %s completed. Log: %s\n' "$stage" "$log"
done

say 'Verify complete flash payload'
required=(aboot.mbn hyp.mbn rpm.mbn sbl1.mbn tz.mbn gpt_both0.bin boot.bin rootfs.bin)
for f in "${required[@]}"; do
  [[ -s "files/$f" ]] || fail "Missing or empty files/$f"
  ls -lh "files/$f"
done

# Android sparse files begin with little-endian magic 0xED26FF3A.
for f in boot.bin rootfs.bin; do
  magic=$(od -An -tx1 -N4 "files/$f" | tr -d '[:space:]')
  [[ "$magic" == '3aff26ed' ]] || fail "files/$f is not an Android sparse image (magic: $magic)."
done

( cd files && sha256sum "${required[@]}" ) > "$LOG_DIR/SHA256SUMS.local"
printf '\nChecksums saved to %s/SHA256SUMS.local\n' "$LOG_DIR"
cat <<EOF

BUILD SUCCESSFUL.
Flash payload: $REPO_DIR/files/
Logs:          $LOG_DIR/

Next: copy files/ to your Windows/WSL machine, then proceed with EDL.
Do not flash without first reading and preserving the device-specific
fsc, fsg, modem, modemst1, modemst2, persist, and sec partitions.
EOF
