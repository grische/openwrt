#!/usr/bin/env bash
# Merge the target build and the package shards into the download tree, then
# index and sign every package feed.
#
# Usage: assemble.sh <in-dir> <out-dir>
#
# <in-dir> holds
#   target/            the target job's bin/ directory, plus its failed.txt
#   sdk-tarball/       the SDK tarball, published next to the images
#   sdk/               that SDK extracted, for its host apk and index scripts
#   plan/              the shard plan, whose shard-<n>.list names the sources
#                      each shard owns
#   shards/shard-<n>/  one directory per shard artifact
#   keys/              private-key.pem and public-key.pem
#
# <out-dir> receives targets-root/targets/... and packages-root/packages/...,
# which unpack side by side into the root of CONFIG_VERSION_REPO, and
# report/ with the failed packages, the public key, packages.tsv and
# weights.tsv. packages.tsv names the job each feed package comes from, and
# weights.tsv holds the measured build times for the next shard plan.
set -euo pipefail

ci=$(dirname "$(readlink -f "$0")")/..
in=$(readlink -f "$1")
mkdir -p "$2"
out=$(readlink -f "$2")
arch=mips_24kc
board=intel-mips/xrx500
apk=$in/sdk/staging_dir/host/bin/apk

tdir=$out/targets-root/targets/$board
pdir=$out/packages-root/packages/$arch
mkdir -p "$tdir" "$pdir" "$out/report"

cp -a "$in/target/targets/$board/." "$tdir/"
cp -a "$in"/sdk-tarball/*.tar.zst "$tdir/"

# Most packages arrive several times, because every shard also builds the
# dependencies of its own packages. pick-packages.py keeps the target job's
# copy of the packages in the images, else the copy of the shard that owns
# the package's source.
trees=("target=$in/target/packages/$arch")
for s in "$in"/shards/*/packages; do
	[ -d "$s" ] || continue
	trees+=("$(basename "${s%/packages}")=$s")
done
"$ci/scripts/pick-packages.py" "$apk" "$in/sdk" "$in/plan" "$tdir" "$pdir" "${trees[@]}" \
	> "$out/report/packages.tsv"

for d in "$pdir"/*/; do
	# apk cannot read back an index without packages, so package/Makefile
	# skips such a feed too. Images still list it and get a 404 for it.
	if ! compgen -G "$d*.apk" >/dev/null; then
		echo "::warning::Feed $(basename "$d") has no packages and is left out."
		rm -r "$d"
		continue
	fi
	(
		cd "$d"
		rm -f packages.adb index.json
		# shellcheck disable=SC2035 # apk file names never start with a dash
		"$apk" mkndx \
			--root "$in/sdk" \
			--keys-dir "$in/keys" \
			--allow-untrusted \
			--sign "$in/keys/private-key.pem" \
			--output packages.adb \
			*.apk
		"$apk" adbdump --format json packages.adb |
			"$in/sdk/scripts/make-index-json.py" -f apk -a "$arch" - > index.json
	)
done

# The signature gate. apk refuses an index whose signature does not match the
# public key the images ship with.
pubkeys=$(mktemp -d)
cp "$in/keys/public-key.pem" "$pubkeys/"
for idx in "$tdir/packages/packages.adb" "$pdir"/*/packages.adb; do
	"$apk" verify --root / --keys-dir "$pubkeys" "$idx"
done
rm -r "$pubkeys"

# Same format as rules.mk's sha256sums.
# shellcheck disable=SC2094 # find skips the file being written
(
	cd "$pdir"
	find . -type f -not -name sha256sums -printf '%P\n' | sort |
		xargs -r sha256sum -b > sha256sums
)

cp "$in/keys/public-key.pem" "$out/report/"
shopt -s nullglob
"$ci/scripts/collect-weights.py" "$in"/shards/*/timings.txt > "$out/report/weights.tsv"
shopt -u nullglob
{
	[ -s "$in/target/failed.txt" ] && sed 's|^|target: |' "$in/target/failed.txt"
	for s in "$in"/shards/*/; do
		name=$(basename "$s")
		[ -s "$s/failed.txt" ] && sed "s|^|$name: |" "$s/failed.txt"
		[ -e "$s/timed-out" ] && echo "$name ran out of time, so some of its packages are missing."
	done
} > "$out/report/failed.txt" || true
