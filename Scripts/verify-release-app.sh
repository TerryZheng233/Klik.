#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
app="${1:?Usage: verify-release-app.sh KLIK_APP}"
fingerprint="$(cat "$root/Scripts/release-certificate.sha1")"
[[ "$fingerprint" =~ ^[[:xdigit:]]{40}$ ]] || { echo 'Invalid certificate fingerprint.' >&2; exit 1; }
fingerprint="$(printf '%s' "$fingerprint" | tr '[:upper:]' '[:lower:]')"
requirement="identifier \"local.klik.capture\" and certificate leaf = H\"$fingerprint\""
[[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist")" == local.klik.capture ]]
/usr/bin/codesign --verify --strict -R "=$requirement" "$app"
actual="$(/usr/bin/codesign -d -r- "$app" 2>&1 | /usr/bin/sed -n 's/^designated => //p')"
expected="identifier \"local.klik.capture\" and certificate leaf = H\"$fingerprint\""
[[ "$actual" == "$expected" ]] || { echo 'Unexpected designated requirement.' >&2; exit 1; }
