#!/usr/bin/env bash
# Build one shard of the shared packages in the SDK.
#
# Usage: build-shard.sh <sdk-dir> <openwrt-dir> <packages-file> <out-dir>
#
# <openwrt-dir> is a checkout of this branch inside <sdk-dir>. Its package/
# directory is the base feed, so the SDK builds the base packages of exactly
# this commit. Some base packages reach into target/linux/ from there, so it
# has to be the whole tree. Others find their own files through their path
# relative to the SDK, which only works inside it.
#
# <packages-file> names the binary packages to build, one per line. Every feed
# is installed, but only these packages are selected, so Kconfig adds just the
# dependencies they need.
#
# The build stops after SHARD_BUDGET_MINUTES (default 300) so that whatever
# finished can still be uploaded inside the 6 hour job limit. <out-dir> then
# holds packages/<feed>/*.apk, failed.txt, logs/ for the failed packages and
# downloads, download-errors.txt with the failed download attempts,
# timings.txt with the CPU time of every build step, config with the shard's
# final .config, and a file named timed-out if the budget ran out.
#
# With SHARD_CONFIG_ONLY=1 the script stops once config is written, before
# any download or build.
set -euo pipefail

ci=$(dirname "$(readlink -f "$0")")/..
sdk=$(readlink -f "$1")
src=$(readlink -f "$2")
list=$(readlink -f "$3")
mkdir -p "$4"
out=$(readlink -f "$4")
budget=${SHARD_BUDGET_MINUTES:-300}
start=$(date +%s)

case $src in
"$sdk"/*) ;;
*)
	echo "::error::The OpenWrt checkout $src has to be inside the SDK at $sdk."
	exit 1
	;;
esac

cd "$sdk"
{
	echo "src-link base $src/package"
	grep '^src-' "$ci/feeds.conf"
} > feeds.conf
./scripts/feeds update -a
./scripts/feeds install -a >/dev/null

# Config-build.in turns the target build's package selection into defaults
# without a prompt. "is not set" cannot override a symbol without a prompt,
# so hidden packages would stay selected, and so would kernel modules whose
# prompt goes away with a package the shard turns off. Only the kernel's own
# modules keep their entries. The SDK leaves the linux source out of its
# menu, so these entries are all that defines them, and the kernel modules of
# the feeds need them to pass their dependency check.
info=tmp/.packageinfo
if [ ! -s "$info" ]; then
	echo "::error::$info is missing after installing the feeds."
	exit 1
fi
awk '/^Source-Makefile: / { core = $2 ~ /(^|\/)kernel\/linux\/Makefile$/ }
	core && /^Package: / { print $2 }' "$info" > .config.kmods
if [ ! -s .config.kmods ]; then
	echo "::error::$info lists no kernel modules of package/kernel/linux."
	exit 1
fi
awk 'NR == FNR { keep["PACKAGE_" $0] = 1; next }
	/^[^ \t]/ { drop = $1 == "config" && $2 ~ /^PACKAGE_/ && !($2 in keep) }
	!drop' .config.kmods Config-build.in > Config-build.in.new
mv Config-build.in.new Config-build.in

# CONFIG_ALL also covers the hidden packages that only it turns on, such as
# LuCI's translations. Every other package it turns on is turned off again
# below. Indexing and signing happen once, in the assemble job.
{
	cat <<-EOF
	CONFIG_ALL=y
	# CONFIG_ALL_NONSHARED is not set
	# CONFIG_ALL_KMODS is not set
	# CONFIG_SIGNED_PACKAGES is not set
	CONFIG_AUTOREMOVE=y
	EOF
	cat "$ci/shard.config"
	sed 's/.*/CONFIG_PACKAGE_&=m/' "$list"
} > .config.shard
cp .config.shard .config
make defconfig

# Everything CONFIG_ALL and the target's default packages turned on is turned
# off again. A dependency's select overrides that, so what the shard's
# packages need stays, and so do hidden packages whose dependencies it builds.
# Only names that tmp/.packageinfo lists as packages are turned off. Package
# options such as CONFIG_PACKAGE_dnsmasq_full_dhcp share the prefix and keep
# their defaults. plan-shards.py adds what the enabled ones need to the list.
# The kernel's own modules stay too, and every shard packages them again.
sed -n 's/^Package: //p' "$info" | sort -u > .config.packages
sed -n 's/^CONFIG_PACKAGE_\(.*\)=[ym]$/\1/p' .config |
	{ grep -xFf .config.packages || true; } |
	{ grep -vxF -f "$list" -f .config.kmods || true; } > .config.defaults
{
	cat .config.shard
	sed 's/.*/# CONFIG_PACKAGE_& is not set/' .config.defaults
} > .config
make defconfig

# defconfig drops what this target cannot build, e.g. packages for other
# architectures.
kept=$(sed 's/.*/CONFIG_PACKAGE_&=m/' "$list" | grep -cxFf - .config || true)
echo "$kept of $(grep -c . "$list") requested packages are selectable."
cp .config "$out/config"
if [ "${SHARD_CONFIG_ONLY:-0}" = 1 ]; then
	exit 0
fi

jobs=$(($(nproc) + 1))

# OpenWrt's source mirror sometimes fails for a while, and every shard starts
# its downloads at the same moment. A git source then falls back to a clone,
# and its repack does not match PKG_MIRROR_HASH. That file stays in dl/, so
# every later download of the source fails its hash check before it asks the
# mirror again. A source that fails therefore loses the dl/ files of its
# failed make targets and gets up to three more attempts after growing pauses.
# The pauses count against the budget, so together they take at most a
# twentieth of it. The downloads keep their logs, which show the mirror's
# error, and only eight of them run at a time to spare the mirror.
errors=logs/package/error.txt
mkdir -p logs/package
: > "$out/download-errors.txt"

# Lists the sources that failed download attempt $1 in .download-failed,
# keeps their logs and deletes the files of their failed targets.
check_downloads() {
	sed -n 's/.*ERROR: \([^ ]*\) failed to build.*/\1/p' "$errors" | sort -u > .download-failed
	sed "s/failed to build/failed to download/; s/^ */attempt $1: /" "$errors" >> "$out/download-errors.txt"
	while read -r path; do
		[ ! -d "logs/$path" ] || find "logs/$path" -name download.txt
	done < .download-failed | while read -r log; do
		mkdir -p "$out/${log%/*}"
		cp "$log" "$out/${log%.txt}-$1.txt"
		# make names each target it failed, as in
		# "make[2]: *** [Makefile:58: <sdk>/dl/foo-1.0.tar.zst] Error 1".
		awk -v dl="$sdk/dl/" '/^make\[[0-9]+\]: \*\*\* \[/ && (i = index($0, dl)) {
			f = substr($0, i + length(dl)); sub(/\] Error.*/, "", f); print f }' "$log"
	done | sort -u | while read -r f; do
		rm -f "dl/$f"
	done
}

: > "$errors"
make -j8 IGNORE_ERRORS="n m y" BUILD_LOG=1 package/download || true
attempt=1
check_downloads "$attempt"
waited=0
for pause in 1 3 9; do
	[ -s .download-failed ] || break
	[ $((waited + pause)) -le $((budget / 20)) ] || break
	echo "Retrying $(wc -l < .download-failed) failed downloads in $pause min."
	sleep "${pause}m"
	waited=$((waited + pause))
	attempt=$((attempt + 1))
	: > "$errors"
	sed 's|$|/download|' .download-failed |
		xargs make -j8 IGNORE_ERRORS="n m y" BUILD_LOG=1 || true
	check_downloads "$attempt"
done
if [ -s .download-failed ]; then
	echo "::warning::$(wc -l < .download-failed) sources failed all $attempt download attempts. download-errors.txt names them."
fi
# The compile step starts new error lists. include/subdir.mk logs failed host
# builds in logs/error.txt, because it gives them no subdirectory.
host_errors=logs/error.txt
rm -f "$errors" "$host_errors"

# In the full tree, apk's host build brings lua/host in before any package is
# built, and apk's target build relies on it. The SDK ships apk prebuilt.
make package/lua/host/compile || true

# Several Python packages need python-setuptools/host without declaring it,
# so they only build if another package happened to build it first.
if grep -qx 'CONFIG_PACKAGE_python3-light=[ym]' .config; then
	make -j"$jobs" package/python-setuptools/host/compile || true
fi

# timeout treats 0 as no limit at all.
left=$((budget - ($(date +%s) - start) / 60))
[ "$left" -ge 10 ] || left=10
status=0
timeout "${left}m" make -j"$jobs" IGNORE_ERRORS="n m y" BUILD_LOG=1 package/compile || status=$?
if [ "$status" -eq 124 ]; then
	echo "::warning::Shard $(basename "$list" .list) ran out of its ${budget} minute budget. The packages it did not reach are missing."
	touch "$out/timed-out"
elif [ "$status" -ne 0 ]; then
	echo "::warning::make exited with $status."
fi

# A package that was being written when the budget ran out is truncated.
# Keep only the ones apk can read.
apk=$sdk/staging_dir/host/bin/apk
mkdir -p "$out/packages"
for d in bin/packages/*/*/; do
	[ -d "$d" ] || continue
	feed=$(basename "$d")
	mkdir -p "$out/packages/$feed"
	for f in "$d"*.apk; do
		[ -e "$f" ] || continue
		if "$apk" adbdump "$f" >/dev/null 2>&1; then
			cp "$f" "$out/packages/$feed/"
		else
			echo "::warning::Dropping unreadable $(basename "$f")"
		fi
	done
done

# error.txt holds lines like "ERROR: package/feeds/packages/foo failed to
# build." A host build adds "[host]" after the path. The logs of that package
# live under logs/ at the same path. A source that failed every download
# attempt usually fails to build as well. Its line then says that it failed to
# download. It is listed even if the budget ran out before the compile step
# reached it, which leaves it without a compile log.
{
	for f in "$errors" "$host_errors"; do
		[ ! -f "$f" ] || cat "$f"
	done
	while read -r path; do
		[ -n "$(find "logs/$path" -name compile.txt 2>/dev/null)" ] ||
			echo "   ERROR: $path failed to build."
	done < .download-failed
} | awk 'FILENAME == ARGV[1] { gone[$0]; next }
	{ path = $0; sub(/.*ERROR: /, "", path); sub(/ .*/, "", path) }
	path in gone { sub(/failed to build/, "failed to download") }
	1' .download-failed - | sort -u > "$out/failed.txt"
sed -n 's/.*ERROR: \([^ ]*\) .*/\1/p' "$out/failed.txt" | sort -u |
while read -r path; do
	[ -d "logs/$path" ] || continue
	mkdir -p "$out/logs/$path"
	cp -r "logs/$path/." "$out/logs/$path/"
done

# time.pl ends every step's log with "time: <step>#<user>#<sys>#<real>".
# collect-weights.py turns these into weights for plan-shards.py.
grep -rh '^time: ' logs/ 2>/dev/null | sort -u > "$out/timings.txt" || true

echo "Built $(find "$out/packages" -name '*.apk' | wc -l) packages, $(wc -l < "$out/failed.txt") failed."
