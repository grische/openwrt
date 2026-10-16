#!/usr/bin/env bash
# Build an image with LuCI for every board in the ImageBuilder, against the
# assembled download tree instead of the server. This is what a user's
# ImageBuilder does, so it checks the signatures and that the image packages
# resolve across the feeds.
#
# Usage: ib-smoke.sh <imagebuilder-tarball> <repo-url> <out-dir>
#
# <out-dir> is assemble.sh's output directory.
set -euo pipefail

ib_tar=$(readlink -f "$1")
url=${2%/}
out=$(readlink -f "$3")

work=$(mktemp -d)
mkdir "$work/ib" "$work/root"
ln -s "$out/targets-root/targets" "$work/root/targets"
ln -s "$out/packages-root/packages" "$work/root/packages"
tar -I zstd -xf "$ib_tar" -C "$work/ib" --strip-components=1

sed -i "s|^$url/|$work/root/|" "$work/ib/repositories"
cat "$work/ib/repositories"
if grep -q '://' "$work/ib/repositories"; then
	echo "::error::The ImageBuilder's repositories do not start with $url."
	exit 1
fi

for dev in avm_fritz7560 avm_fritz7580 avm_fritz7590 avm_fritz7590ax \
	avm_fritz7590ax-v2; do
	make -C "$work/ib" image PROFILE="$dev" PACKAGES="luci" BIN_DIR="$work/bin"
	if ! compgen -G "$work/bin/*-$dev-squashfs-sysupgrade.bin" >/dev/null; then
		echo "::error::The ImageBuilder built no sysupgrade image for $dev."
		exit 1
	fi
done
# The work directory stays. The runner is discarded, and a build tree can hold
# read-only directories that rm -r would fail on.
ls -l "$work/bin"
