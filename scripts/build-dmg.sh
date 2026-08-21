#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
version="${APP_VERSION:-0.2.0}"
dmg_path="$project_dir/dist/PluginDeck-$version.dmg"
stage_dir=$(mktemp -d)

cleanup() {
    rm -rf "$stage_dir"
}
trap cleanup EXIT

UNIVERSAL="${UNIVERSAL:-1}" APP_VERSION="$version" "$project_dir/scripts/build-app.sh"
cp -R "$project_dir/dist/PluginDeck.app" "$stage_dir/"
ln -s /Applications "$stage_dir/Applications"

rm -f "$dmg_path" "$dmg_path.sha256"
hdiutil create \
    -volname "PluginDeck" \
    -srcfolder "$stage_dir" \
    -format UDZO \
    -ov \
    "$dmg_path"

(
    cd "${dmg_path:h}"
    LC_ALL=C LANG=C shasum -a 256 "${dmg_path:t}" > "${dmg_path:t}.sha256"
)

echo "$dmg_path"
