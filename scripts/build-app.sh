#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
app_dir="$project_dir/dist/PluginDeck.app"
version="${APP_VERSION:-0.1.0}"
universal="${UNIVERSAL:-0}"

if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "APP_VERSION must use MAJOR.MINOR.PATCH" >&2
    exit 2
fi

cd "$project_dir"
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"

if [[ "$universal" == "1" ]]; then
    for architecture in arm64 x86_64; do
        scratch="$project_dir/.build/$architecture"
        swift build -c release --arch "$architecture" --scratch-path "$scratch"
        binary_dir=$(swift build -c release --arch "$architecture" --scratch-path "$scratch" --show-bin-path)
        cp "$binary_dir/PluginDeck" "$project_dir/.build/PluginDeck-$architecture"
    done
    lipo -create \
        "$project_dir/.build/PluginDeck-arm64" \
        "$project_dir/.build/PluginDeck-x86_64" \
        -output "$app_dir/Contents/MacOS/PluginDeck"
else
    swift build -c release
    binary_dir=$(swift build -c release --show-bin-path)
    cp "$binary_dir/PluginDeck" "$app_dir/Contents/MacOS/PluginDeck"
fi

cp "$project_dir/Sources/PluginDeck/Resources/catalog.json" "$app_dir/Contents/Resources/catalog.json"

cat > "$app_dir/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>PluginDeck</string>
    <key>CFBundleExecutable</key>
    <string>PluginDeck</string>
    <key>CFBundleIdentifier</key>
    <string>dev.plugindeck.app</string>
    <key>CFBundleName</key>
    <string>PluginDeck</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
    <key>CFBundleVersion</key>
    <string>$version</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 PluginDeck Contributors</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$app_dir"
echo "$app_dir"
