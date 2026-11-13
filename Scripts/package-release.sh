#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd -P)"
app="${1:?Usage: package-release.sh SIGNED_KLIK_APP OUTPUT_DIRECTORY}"
output="${2:?Usage: package-release.sh SIGNED_KLIK_APP OUTPUT_DIRECTORY}"
fingerprint="$(cat "$root/Scripts/release-certificate.sha1")"
[[ "$fingerprint" =~ ^[[:xdigit:]]{40}$ ]] || { echo 'Invalid certificate fingerprint.' >&2; exit 1; }
fingerprint="$(printf '%s' "$fingerprint" | tr '[:upper:]' '[:lower:]')"
app="$(cd "$app" && pwd -P)"
mkdir -p "$output"
output="$(cd "$output" && pwd -P)"
version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid version.' >&2; exit 1; }
name="Klik-$version-arm64.dmg"
[[ ! -e "$output/$name" && ! -e "$output/$name.sha256" && ! -e "$output/$name.sig" ]] || {
    echo 'Output already exists.' >&2; exit 1;
}
verify_app() {
    local candidate="$1"
    [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw "$candidate/Contents/Info.plist")" == local.klik.capture ]]
    [[ "$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$candidate/Contents/Info.plist")" == "$version" ]]
    [[ "$(/usr/bin/lipo -archs "$candidate/Contents/MacOS/Klik")" == arm64 ]]
    "$root/Scripts/verify-release-app.sh" "$candidate"
}
verify_app "$app"
command -v dmgbuild >/dev/null || { echo 'dmgbuild is required.' >&2; exit 1; }
stage="$(mktemp -d "$output/.klik-release.XXXXXX")"
mounted=false
cleanup() {
    if [[ "$mounted" == true ]]; then /usr/bin/hdiutil detach "$stage/mount" >/dev/null || return; fi
    rm -rf "$stage"
}
trap cleanup EXIT
dmgbuild -s "$root/Packaging/dmg-settings.py" -D app="$app" \
    -D background="$root/Packaging/background.png" 'Klik.' "$stage/$name"
/usr/bin/hdiutil verify "$stage/$name"
mkdir "$stage/mount"
/usr/bin/hdiutil attach -readonly -nobrowse -mountpoint "$stage/mount" "$stage/$name"
mounted=true
verify_app "$stage/mount/Klik.app"
[[ "$(/usr/bin/readlink "$stage/mount/Applications")" == /Applications ]]
/usr/bin/cmp "$app/Contents/MacOS/Klik" "$stage/mount/Klik.app/Contents/MacOS/Klik"
/usr/bin/hdiutil detach "$stage/mount"
mounted=false
(cd "$stage" && /usr/bin/shasum -a 256 "$name" > "$name.sha256")
/usr/bin/swift "$root/Scripts/update-signing.swift" sign "v$version" "$stage/$name" "$stage/$name.sig"
# Publish all assets only after verification and update signing succeed.
mv "$stage/$name" "$stage/$name.sha256" "$stage/$name.sig" "$output/"
printf 'Prepared %s\n' "$output/$name"
