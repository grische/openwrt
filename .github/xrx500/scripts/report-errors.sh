#!/usr/bin/env bash
# Print the packages that failed in an OpenWrt build and the end of each of
# their logs, grouped so the job log stays readable.
#
# Usage: report-errors.sh <openwrt-dir> [<list-file>]
#
# <list-file> receives the error lines, one per failed build. It stays empty
# if nothing failed.
set -uo pipefail

list=${2:+$(readlink -m "$2")}
cd "$1" || exit 0

# include/subdir.mk logs failed host builds in logs/error.txt, because it gives
# them no subdirectory.
errors=$(cat logs/package/error.txt logs/error.txt 2>/dev/null | sort -u)
[ -z "$list" ] || { [ -z "$errors" ] || echo "$errors"; } > "$list"
[ -n "$errors" ] || { echo "No package failed."; exit 0; }

echo "$errors"
sed -n 's/.*ERROR: \([^ ]*\) .*/\1/p' <<< "$errors" | sort -u |
while read -r path; do
	echo "::group::$path"
	# A build variant keeps its logs in a subdirectory named after it.
	for f in "logs/$path"/*.txt "logs/$path"/*/*.txt; do
		[ -f "$f" ] || continue
		echo "==> $f"
		tail -n 60 "$f"
	done
	echo "::endgroup::"
done
