#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
build_dir="$(mktemp -d /private/tmp/booklet-build.XXXXXX)"
trap 'rm -rf "$build_dir"' EXIT
app_bundle="$build_dir/Booklet.app"
app_archive="$project_root/outputs/Booklet.zip"
contents="$app_bundle/Contents"
sparkle_framework="$project_root/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
signing_identity="${BOOKLET_SIGNING_IDENTITY:--}"
notary_profile="${BOOKLET_NOTARY_PROFILE:-}"
update_feed_url="${BOOKLET_UPDATE_FEED_URL:-}"
update_public_key="${BOOKLET_UPDATE_PUBLIC_KEY:-}"

if [[ -n "$update_feed_url" || -n "$update_public_key" ]]; then
    if [[ "$update_feed_url" != https://* || -z "$update_public_key" ]]; then
        echo "Set both BOOKLET_UPDATE_FEED_URL (HTTPS) and BOOKLET_UPDATE_PUBLIC_KEY." >&2
        exit 1
    fi
    if ! decoded_key_length="$(printf '%s' "$update_public_key" | base64 -D 2>/dev/null | wc -c | tr -d '[:space:]')" || [[ "$decoded_key_length" != "32" ]]; then
        echo "BOOKLET_UPDATE_PUBLIC_KEY must be a 32-byte base64 Sparkle EdDSA public key." >&2
        exit 1
    fi
fi

if [[ -n "$notary_profile" && "$signing_identity" == "-" ]]; then
    echo "BOOKLET_NOTARY_PROFILE requires a Developer ID signing identity." >&2
    exit 1
fi

cd "$project_root"

export SWIFTPM_MODULECACHE_OVERRIDE="$project_root/.build/ModuleCache"
export CLANG_MODULE_CACHE_PATH="$project_root/.build/ModuleCache"

swift build -c release --product Booklet

iconset="$build_dir/Booklet.iconset"
swift "$project_root/scripts/generate-icon.swift" "$project_root/Resources/BookletIcon.png" "$iconset"
iconutil -c icns "$iconset" -o "$build_dir/Booklet.icns"

mkdir -p "$contents/MacOS" "$contents/Resources" "$contents/Frameworks"
mkdir -p "$project_root/outputs"
cp "$project_root/.build/release/Booklet" "$contents/MacOS/Booklet"
cp "$project_root/Resources/Info.plist" "$contents/Info.plist"
cp "$build_dir/Booklet.icns" "$contents/Resources/Booklet.icns"
ditto "$sparkle_framework" "$contents/Frameworks/Sparkle.framework"

if [[ -n "$update_feed_url" ]]; then
    plutil -insert SUFeedURL -string "$update_feed_url" "$contents/Info.plist"
    plutil -insert SUPublicEDKey -string "$update_public_key" "$contents/Info.plist"
    plutil -insert SUEnableAutomaticChecks -bool YES "$contents/Info.plist"
fi

entitlements="$project_root/Resources/Booklet.entitlements"
if [[ "$signing_identity" == "-" ]]; then
    entitlements="$build_dir/BookletDevelopment.entitlements"
    cp "$project_root/Resources/Booklet.entitlements" "$entitlements"
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$entitlements"
fi

printf 'APPL????' > "$contents/PkgInfo"
xattr -cr "$app_bundle"

embedded_sparkle="$contents/Frameworks/Sparkle.framework"
for helper in \
    "$embedded_sparkle/Versions/B/Autoupdate" \
    "$embedded_sparkle/Versions/B/Updater.app" \
    "$embedded_sparkle/Versions/B/XPCServices/Downloader.xpc" \
    "$embedded_sparkle/Versions/B/XPCServices/Installer.xpc"; do
    codesign --force --sign "$signing_identity" --options runtime "$helper"
done
codesign --force --sign "$signing_identity" --options runtime "$embedded_sparkle"

codesign \
    --force \
    --sign "$signing_identity" \
    --options runtime \
    --entitlements "$entitlements" \
    "$app_bundle"

xattr -cr "$app_bundle"
codesign --verify --deep --strict "$app_bundle"
ditto -c -k --norsrc --keepParent "$app_bundle" "$app_archive"

if [[ -n "$notary_profile" ]]; then
    xcrun notarytool submit "$app_archive" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple "$app_bundle"
    ditto -c -k --norsrc --keepParent "$app_bundle" "$app_archive"
fi

verification_dir="$build_dir/verification"
mkdir -p "$verification_dir"
ditto -x -k "$app_archive" "$verification_dir"
codesign --verify --deep --strict "$verification_dir/Booklet.app"

echo "Built $app_archive"
