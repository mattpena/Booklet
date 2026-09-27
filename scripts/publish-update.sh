#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
sparkle_tools="$project_root/.build/artifacts/sparkle/Sparkle/bin"
releases_dir="$project_root/outputs/releases"
feed_path="$project_root/docs/updates/appcast.xml"
feed_url="https://mattpena.github.io/Booklet/updates/appcast.xml"
repository="mattpena/Booklet"

cd "$project_root"

if [[ -n "$(git status --porcelain)" || "$(git branch --show-current)" != "main" ]]; then
    echo "Commit all changes on main before publishing an update." >&2
    exit 1
fi

if [[ "$(git rev-parse HEAD)" != "$(git rev-parse '@{upstream}')" ]]; then
    echo "Push main before publishing an update." >&2
    exit 1
fi

release_flags=(--generate-notes)
if [[ -z "${BOOKLET_SIGNING_IDENTITY:-}" || "${BOOKLET_SIGNING_IDENTITY:-}" == "-" ]]; then
    if [[ "${BOOKLET_ALLOW_ADHOC_RELEASE:-}" != "1" ]]; then
        echo "A public release requires Developer ID signing and notarization." >&2
        echo "For an unnotarized personal preview only, explicitly set BOOKLET_ALLOW_ADHOC_RELEASE=1." >&2
        exit 1
    fi
    release_flags+=(--prerelease --notes "Unnotarized personal preview; macOS may require manual approval to open it.")
elif [[ -z "${BOOKLET_NOTARY_PROFILE:-}" ]]; then
    echo "Set BOOKLET_NOTARY_PROFILE to notarize a Developer ID release." >&2
    exit 1
fi

swift package resolve
if [[ ! -x "$sparkle_tools/generate_keys" ]]; then
    echo "Sparkle's signing tools are unavailable after package resolution." >&2
    exit 1
fi

public_key="$("$sparkle_tools/generate_keys" --account booklet -p)"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"
tag="v${version}-${build}"
release_dir="$releases_dir/$tag"
archive="$release_dir/Booklet-${version}-${build}.zip"

BOOKLET_UPDATE_FEED_URL="$feed_url" \
BOOKLET_UPDATE_PUBLIC_KEY="$public_key" \
./scripts/build-app.sh

mkdir -p "$release_dir" "${feed_path:h}"
cp outputs/Booklet.zip "$archive"
if [[ -f "$feed_path" ]]; then
    cp "$feed_path" "$release_dir/appcast.xml"
fi

"$sparkle_tools/generate_appcast" \
    --account booklet \
    --maximum-deltas 0 \
    --download-url-prefix "https://github.com/$repository/releases/download/$tag/" \
    -o "$release_dir/appcast.xml" \
    "$release_dir"
"$sparkle_tools/sign_update" --account booklet --verify "$release_dir/appcast.xml"

gh release create "$tag" "$archive" \
    --repo "$repository" \
    --target "$(git rev-parse HEAD)" \
    --title "Booklet $version (build $build)" \
    "${release_flags[@]}"

cp "$release_dir/appcast.xml" "$feed_path"
git add "$feed_path"
git commit -m "Publish update feed for $tag"
git push origin main

echo "Published $tag. GitHub Pages may take a few minutes to serve the updated feed."
