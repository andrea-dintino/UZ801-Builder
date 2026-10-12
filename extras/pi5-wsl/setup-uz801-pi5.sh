#!/usr/bin/env bash
# Set up the native ARM64 UZ801 image build environment on a Raspberry Pi 5.
# Run as a normal user; sudo is used only for package installation.
set -Eeuo pipefail

REPO_URL='https://github.com/andrea-dintino/UZ801-Builder.git'
REPO_DIR="${UZ801_DIR:-write path here}"

usage() {
  cat <<'USAGE'
Usage: ./setup-uz801-pi5.sh

Prerequisites: Raspberry Pi 5 running 64-bit Debian / Raspberry Pi OS,
working network connection, sudo access, and about 8+ GiB free disk space.

Environment:
  UZ801_DIR  Directory in which to clone the repository
             (required; placeholder: write path here)

This script will not overwrite or reset an existing checkout.
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') ;;
  *) usage >&2; exit 2 ;;
esac

say() { printf '\n==> %s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -n "$REPO_DIR" && "$REPO_DIR" != 'write path here' ]] || fail 'Set UZ801_DIR to your checkout path (replace write path here).'
[[ "$REPO_DIR" == /* ]] || fail 'UZ801_DIR must be an absolute path.'

(( EUID != 0 )) || fail 'Run this as your normal user, not with sudo.'
[[ $(uname -m) == aarch64 ]] || fail 'Requires 64-bit ARM64 Linux (uname -m must show aarch64).'
[[ $(dpkg --print-architecture) == arm64 ]] || fail 'Userland is not arm64. Install a 64-bit Raspberry Pi OS.'
command -v apt-get >/dev/null || fail 'Requires Debian/Ubuntu with apt.'
command -v sudo >/dev/null || fail 'sudo is required.'
[[ "$REPO_DIR" != *' '* ]] || fail 'Project path must not contain spaces (upstream scripts do not quote paths).'

say 'Machine and storage'
uname -m
cat /etc/os-release | grep -E '^(PRETTY_NAME|VERSION_CODENAME)=' || true
printf 'Build directory: %s\n' "$REPO_DIR"
# Measure the filesystem that will actually hold the checkout.
space_dir="$REPO_DIR"
while [[ ! -d "$space_dir" ]]; do
  space_dir=$(dirname -- "$space_dir")
done
df -h "$space_dir"
free_kb=$(df -Pk "$space_dir" | awk 'NR==2 {print $4}')
if (( free_kb < 5 * 1024 * 1024 )); then
  fail 'Less than 5 GiB free. Move the build to a larger SSD/disk before continuing.'
elif (( free_kb < 8 * 1024 * 1024 )); then
  printf 'WARNING: Less than 8 GiB free; image creation may exhaust disk space.\n' >&2
fi

say 'Acquire sudo privileges'
sudo -v

say 'Install essential host tools'
sudo env DEBIAN_FRONTEND=noninteractive apt-get update
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
  git ca-certificates curl file python3 tar xz-utils gzip unzip coreutils util-linux

say 'Clone or reuse the fork'
if [[ ! -e "$REPO_DIR" ]]; then
  git clone --recurse-submodules "$REPO_URL" "$REPO_DIR"
else
  [[ -d "$REPO_DIR/.git" ]] || fail "$REPO_DIR already exists but is not a Git checkout."
  origin=$(git -C "$REPO_DIR" remote get-url origin)
  case "$origin" in
    https://github.com/andrea-dintino/UZ801-Builder|https://github.com/andrea-dintino/UZ801-Builder.git|git@github.com:andrea-dintino/UZ801-Builder.git)
      printf 'Existing fork checkout found. Keeping all local changes and current branch.\n' ;;
    *) fail "Unexpected origin: $origin (refusing to modify another checkout)." ;;
  esac
  git -C "$REPO_DIR" submodule update --init --recursive
fi

[[ -x "$REPO_DIR/scripts/install_deps.sh" ]] || fail 'Missing scripts/install_deps.sh in checkout.'

say 'Install the exact host dependencies declared by this fork'
sudo env DEBIAN_FRONTEND=noninteractive "$REPO_DIR/scripts/install_deps.sh"

say 'Check toolchain availability'
for bin in aarch64-linux-gnu-gcc arm-none-eabi-gcc debootstrap sfdisk img2simg \
           mkfs.ext2 mkfs.ext4 cmake autoreconf dtc git; do
  command -v "$bin" >/dev/null || fail "Missing $bin after package installation."
  printf '  %-24s %s\n' "$bin" "$(command -v "$bin")"
done

say 'Repository revision'
git -C "$REPO_DIR" log -1 --format='%h %cs %s'

cat <<EOF

SETUP COMPLETE.

To build, copy build-uz801-pi5.sh onto this Pi and run:
  chmod +x ./build-uz801-pi5.sh
  ./build-uz801-pi5.sh

Repository: $REPO_DIR
Target Debian release: trixie (Debian 13), regardless of the Pi's host release.
NOTE: This only builds firmware images. It does NOT flash the USB stick.
EOF
