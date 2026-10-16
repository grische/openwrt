#!/usr/bin/env bash
# Re-pin feeds.conf to the last commit of each feed before a point in time.
#
# Usage: update-feeds.sh <upstream-commit|date>
#
# Pass the upstream OpenWrt commit the branch is based on. Its committer date
# then selects the feed commits, which keeps the feeds as close as possible to
# what upstream built against at that time. Run it from the OpenWrt checkout.
set -euo pipefail

ci=$(dirname "$(readlink -f "$0")")/..
conf=$ci/feeds.conf
if git rev-parse -q --verify "$1^{commit}" >/dev/null; then
	when=$(git log -1 --format=%cI "$1")
	what="the upstream commit the branch is based on ($(git log -1 --format='%h, %cs' "$1"))"
else
	when=$1
	what="$1"
fi

tmp=$(mktemp -d)
trap 'rm -r "$tmp"' EXIT

{
	echo "# Feeds for the xRX500 CI build, pinned to the last commit of each feed before"
	echo "# $what."
	echo "# Refresh with scripts/update-feeds.sh after rebasing onto a newer upstream."
	grep '^src-git ' "$conf" | while read -r _ name url; do
		url=${url%%^*}
		git clone -q --bare --filter=blob:none "$url" "$tmp/$name"
		rev=$(git -C "$tmp/$name" rev-list -1 --before="$when" HEAD)
		echo "src-git $name $url^$rev"
	done
} > "$tmp/feeds.conf"

mv "$tmp/feeds.conf" "$conf"
cat "$conf"
