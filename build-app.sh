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
installed_app="$destination/Klik.app"
replace_existing=false
if [[ -e "$installed_app" ]]; then
    requirement="$(/usr/bin/codesign -d -r- "$installed_app" 2>&1 | /usr/bin/sed -n 's/^designated => //p')"
    # Ad hoc designated requirements include a build-specific hash, so two
    # valid ad hoc builds cannot satisfy one another's requirement.
    existing_signing="$(/usr/bin/codesign -dv --verbose=2 "$installed_app" 2>&1)"
    if [[ "$existing_signing" == *"Signature=adhoc"* && "${identity:--}" == "-" ]]; then
        /usr/bin/codesign --verify --strict "$installed_app"
    elif [[ -n "$requirement" ]] && ! /usr/bin/codesign --verify -R "=$requirement" "$app"; then
        printf '%s\n' 'The update has a different signing identity. Use the existing signing identity or build to a new destination.' >&2
        exit 1
    fi
    replace_existing=true
fi

# Swap the signed bundles on the same volume without merging files or changing metadata.
swift - "$app" "$installed_app" "$replace_existing" <<'SWIFT'
import Darwin

let flags = CommandLine.arguments[3] == "true" ? RENAME_SWAP : RENAME_EXCL
if renamex_np(CommandLine.arguments[1], CommandLine.arguments[2], UInt32(flags)) != 0 {
    perror("Could not place Klik.app in the build destination")
    exit(1)
}
SWIFT
/usr/bin/codesign --verify --strict "$installed_app"
printf '%s\n' "$installed_app"
