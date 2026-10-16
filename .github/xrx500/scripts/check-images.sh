#!/usr/bin/env bash
# Fail unless the target build produced everything a user needs, for every
# board.
#
# Usage: check-images.sh <bin-targets-dir>
set -euo pipefail

cd "$1"
missing=0
need() {
	if ! compgen -G "$1" >/dev/null; then
		echo "::error::Missing $1"
		missing=1
	fi
}

for dev in avm_fritz7560 avm_fritz7580 avm_fritz7590; do
	# pick-packages.py reads the installed packages of each board from its
	# rootfs tarball.
	for img in initramfs-kernel.bin squashfs-eva-kernel.bin \
		squashfs-eva-filesystem.bin squashfs-sysupgrade.bin \
		targz-rootfs.tar.gz; do
		need "*-$dev-$img"
	done
done
need 'openwrt-sdk-*.tar.zst'
need 'openwrt-imagebuilder-*.tar.zst'
need profiles.json
need sha256sums
need packages/packages.adb
need 'packages/kmod-dsa-lantiq-gswip-xrx500-*.apk'

ls -l
exit "$missing"
