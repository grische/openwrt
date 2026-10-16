#!/usr/bin/env bash
# Install the apk signing key from the XRX500_APK_KEY secret as
# private-key.pem and public-key.pem in <dir>, which is where the OpenWrt
# build looks for it.
#
# Usage: setup-key.sh <dir>
set -euo pipefail

dir=$1
mkdir -p "$dir"
sec=$dir/private-key.pem
pub=$dir/public-key.pem

if [ -z "${XRX500_APK_KEY:-}" ]; then
	echo "::error::The XRX500_APK_KEY secret is not set. See .github/xrx500/README.md."
	exit 1
fi
(umask 077 && printf '%s\n' "$XRX500_APK_KEY" > "$sec")

if ! openssl ec -in "$sec" -check -noout >/dev/null 2>&1; then
	echo "::error::XRX500_APK_KEY is not a PEM EC private key."
	exit 1
fi
if ! openssl ec -in "$sec" -text -noout 2>/dev/null | grep -q 'prime256v1'; then
	echo "::error::XRX500_APK_KEY must be a prime256v1 (P-256) key, which is what apk expects."
	exit 1
fi

openssl ec -in "$sec" -pubout -out "$pub" 2>/dev/null
chmod 644 "$pub"
