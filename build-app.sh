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
cp -R Sources/Klik/Localization/*.lproj "$app/Contents/Resources/"
swift make-icon.swift "$stage/Klik.iconset"
/usr/bin/iconutil -c icns "$stage/Klik.iconset" -o "$app/Contents/Resources/Klik.icns"
/usr/bin/xattr -cr "$app"
identity="${KLIK_SIGN_IDENTITY:-}"
local_signing=false
if [[ -z "$identity" ]]; then
    identity="$(/usr/bin/security find-identity -v -p codesigning | /usr/bin/awk '/"Apple Development: / { print $2 }')"
    if [[ "$identity" == *$'\n'* ]]; then
        printf '%s\n' 'More than one Apple Development identity is available. Set KLIK_SIGN_IDENTITY to choose one.' >&2
        exit 1
    fi
    if [[ -n "$identity" ]]; then local_signing=true; fi
fi
sign_options=(--force --sign "${identity:--}")
if [[ "$local_signing" == true ]]; then sign_options+=(--timestamp=none); fi
/usr/bin/codesign "${sign_options[@]}" "$app"
/usr/bin/codesign --verify --strict "$app"
if [[ -e "$destination/Klik.app" ]]; then
    requirement="$(/usr/bin/codesign -d -r- "$destination/Klik.app" 2>&1 | /usr/bin/sed -n 's/^designated => //p')"
    if [[ -n "$requirement" ]] && ! /usr/bin/codesign --verify -R "=$requirement" "$app"; then
        printf '%s\n' 'The update has a different signing identity. Use the existing signing identity or build to a new destination.' >&2
        exit 1
    fi
    # Ditto updates the bundle at its existing path.
    /usr/bin/ditto "$app" "$destination/Klik.app"
else
    mv "$app" "$destination/Klik.app"
fi
/usr/bin/codesign --verify --strict "$destination/Klik.app"
printf '%s\n' "$destination/Klik.app"
