#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

app_dir="$project_dir/.build/CodexReset.app"
architecture="$(uname -m)"
while (( $# )); do
    case "$1" in
        --arch)
            (( $# >= 2 )) || { print -u2 'Falta a arquitetura.'; exit 1; }
            architecture="$2"; shift 2 ;;
        --output)
            (( $# >= 2 )) || { print -u2 'Falta o destino do aplicativo.'; exit 1; }
            app_dir="$2"; shift 2 ;;
        *) print -u2 "Argumento desconhecido: $1"; exit 1 ;;
    esac
done
case "$architecture" in
    arm64|x86_64) ;;
    *) print -u2 "Arquitetura não suportada: $architecture"; exit 1 ;;
esac

build_args=(-c release --triple "$architecture-apple-macosx14.0"
    -Xswiftc -gnone)
swift build "${build_args[@]}"
bin_dir="$(swift build "${build_args[@]}" --show-bin-path)"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/CodexReset" "$app_dir/Contents/MacOS/CodexReset"
cp "$bin_dir/CodexResetCompanion" "$app_dir/Contents/MacOS/CodexResetCompanion"
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
for executable in CodexReset CodexResetCompanion; do
    strip -S "$app_dir/Contents/MacOS/$executable"
done
codesign --force --deep --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
for executable in CodexReset CodexResetCompanion; do
    actual_arch="$(lipo -archs "$app_dir/Contents/MacOS/$executable")"
    if [[ "$actual_arch" != "$architecture" ]]; then
        print -u2 "Arquitetura incorreta em $executable: $actual_arch"
        exit 1
    fi
done
print -r -- "$app_dir"
