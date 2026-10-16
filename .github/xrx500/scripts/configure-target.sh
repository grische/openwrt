#!/usr/bin/env bash
# Write the target build's .config from config.seed and check that every seed
# line survived `make defconfig`.
#
# Usage: configure-target.sh <openwrt-dir> <repo-url>
#
# <repo-url> becomes CONFIG_VERSION_REPO, the root of the download tree the
# images fetch packages from.
set -euo pipefail

ci=$(dirname "$(readlink -f "$0")")/..
cd "$1"
repo_url=${2%/}

# The host LLVM prefix, e.g. /usr/lib/llvm-18, from the clang on PATH.
# include/bpf.mk looks for these tools there.
clang=$(command -v clang) || { echo "::error::clang is not installed"; exit 1; }
llvm=$(dirname "$(dirname "$(readlink -f "$clang")")")
for tool in clang llc opt llvm-dis llvm-strip; do
	if [ ! -x "$llvm/bin/$tool" ]; then
		echo "::error::$llvm/bin/$tool is missing"
		exit 1
	fi
done

seed=$(mktemp)
{
	cat "$ci/config.seed"
	echo "CONFIG_VERSION_REPO=\"$repo_url\""
	echo "CONFIG_BPF_TOOLCHAIN_HOST_PATH=\"$llvm\""
} > "$seed"

cp "$seed" .config
make defconfig

# Kconfig drops a value it cannot honour without saying so. A dropped
# CONFIG_VERSION_REPO would point every image at the upstream MIPS16 feeds,
# so every seed line has to be present verbatim.
missing=0
while IFS= read -r line; do
	case $line in
	CONFIG_*|'# CONFIG_'*' is not set') ;;
	*) continue ;;
	esac
	if ! grep -qxF -- "$line" .config; then
		echo "::error::'$line' did not survive make defconfig"
		missing=1
	fi
done < "$seed"
rm "$seed"
exit "$missing"
