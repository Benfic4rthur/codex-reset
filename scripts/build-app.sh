#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

swift build -c release
app_dir="$project_dir/.build/CodexReset.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$project_dir/.build/release/CodexReset" "$app_dir/Contents/MacOS/CodexReset"
cp "$project_dir/.build/release/CodexResetCompanion" "$app_dir/Contents/MacOS/CodexResetCompanion"
cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
icon_file="$project_dir/Assets/CodexReset.icns"
icon_png="$project_dir/Assets/CodexReset.png"
if [[ -f "$icon_file" ]]; then
    cp "$icon_file" "$app_dir/Contents/Resources/CodexReset.icns"
elif [[ -f "$icon_png" ]]; then
    iconset_dir="$project_dir/.build/CodexReset.iconset"
    mkdir -p "$iconset_dir"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$icon_png" --out "$iconset_dir/icon_${size}x${size}.png" >/dev/null
        retina_size=$((size * 2))
        sips -z "$retina_size" "$retina_size" "$icon_png" --out "$iconset_dir/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$iconset_dir" -o "$app_dir/Contents/Resources/CodexReset.icns"
else
    print -u2 -- "Missing app icon: add Assets/CodexReset.png (1024x1024) or Assets/CodexReset.icns"
    exit 1
fi
codesign --force --deep --sign - "$app_dir"
print -r -- "$app_dir"
