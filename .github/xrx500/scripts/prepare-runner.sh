#!/usr/bin/env bash
# Make room on a GitHub-hosted Ubuntu runner and install the build
# dependencies.
#
# Usage: prepare-runner.sh [<build-dir>]
#
# With <build-dir>, that directory is placed on whichever filesystem has more
# free space. When that is /mnt, a directory there is bind-mounted onto
# <build-dir>, so later steps never see the difference.
set -euo pipefail

echo "$(nproc) CPUs, $(free -g | awk '/^Mem/ {print $2}') GB RAM"
df -h / /mnt 2>/dev/null || true

# Preinstalled SDKs the build never touches, about 30 GB on /.
for d in /usr/share/dotnet /usr/local/lib/android /opt/ghc /usr/local/.ghcup \
	/opt/hostedtoolcache/CodeQL /usr/share/swift /usr/local/share/powershell \
	/usr/local/share/chromium /opt/microsoft /opt/google /opt/az; do
	if [ -e "$d" ]; then
		sudo rm -r "$d" &
	fi
done
sudo docker image prune --all --force >/dev/null 2>&1 &

# The package list follows openwrt/buildbot's buildworker image. clang and llvm
# provide the eBPF toolchain (CONFIG_BPF_TOOLCHAIN_HOST), bc is used by the
# kernel build, and python3-setuptools supplies distutils on Python 3.12.
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
	bc build-essential clang curl file flex bison g++-multilib gawk \
	gcc-multilib gettext git libdw-dev libelf-dev libncurses-dev libssl-dev \
	libxml-parser-perl llvm python3 python3-cryptography python3-dev \
	python3-pip python3-pyelftools python3-setuptools python3-venv rsync \
	subversion swig unzip wget zlib1g-dev zstd >/dev/null

wait

if [ -n "${1:-}" ]; then
	dir=$1
	mkdir -p "$dir"
	root_free=$(df --output=avail -B1G / | tail -n1)
	mnt_free=$(df --output=avail -B1G /mnt 2>/dev/null | tail -n1 || echo 0)
	if [ "$(stat -c %d /mnt 2>/dev/null)" != "$(stat -c %d /)" ] &&
	   [ "${mnt_free:-0}" -gt "$root_free" ]; then
		sudo mkdir -p /mnt/build
		sudo chown "$(id -u):$(id -g)" /mnt/build
		sudo mount --bind /mnt/build "$dir"
	fi
	df -h "$dir"
fi

df -h / /mnt 2>/dev/null || true
