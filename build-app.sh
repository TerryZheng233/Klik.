#!/bin/bash
set -euo pipefail

source_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$source_dir"
destination="${1:-$source_dir/.build}"
if [[ $# -gt 0 ]]; then shift; fi
swift build -c release "$@"
binary="$(swift build -c release --show-bin-path "$@")/Klik"
mkdir -p "$destination"
stage="$(mktemp -d "$destination/.klik.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/Klik.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
install -m 755 "$binary" "$app/Contents/MacOS/Klik"
cp Info.plist "$app/Contents/Info.plist"
cp -R Resources/Lucide "$app/Contents/Resources/"
swift make-icon.swift "$stage/Klik.iconset"
/usr/bin/iconutil -c icns "$stage/Klik.iconset" -o "$app/Contents/Resources/Klik.icns"
/usr/bin/xattr -cr "$app"
/usr/bin/codesign --force --sign "${KLIK_SIGN_IDENTITY:--}" "$app"
/usr/bin/codesign --verify --strict "$app"
if [[ -e "$destination/Klik.app" ]]; then
    # Ditto updates the bundle at its existing path.
    /usr/bin/ditto "$app" "$destination/Klik.app"
else
    mv "$app" "$destination/Klik.app"
fi
/usr/bin/codesign --verify --strict "$destination/Klik.app"
printf '%s\n' "$destination/Klik.app"
