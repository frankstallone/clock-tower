#!/bin/bash
# Build the two release slices independently; ship only the executable and app resources.
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Packaging/Info.plist)
minimum=$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' Packaging/Info.plist)
stage=$(mktemp -d "${TMPDIR:-/tmp}/clock-tower.XXXXXXXX")
trap 'rm -rf "$stage"' EXIT
app="$stage/Clock Tower.app"
contents="$app/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources" dist
cp Packaging/Info.plist "$contents/"
plutil -lint "$contents/Info.plist"

bins=()
for arch in arm64 x86_64; do
    triple="$arch-apple-macosx$minimum"
    swift build -c release --triple "$triple" --product ClockTower
    bin=$(swift build -c release --triple "$triple" --show-bin-path)
    cp "$bin/ClockTower" "$stage/ClockTower-$arch"
    bins+=("$stage/ClockTower-$arch")
done
lipo -create "${bins[@]}" -output "$contents/MacOS/ClockTower"
archs=$(lipo -archs "$contents/MacOS/ClockTower")
for arch in arm64 x86_64; do
    [[ " $archs " == *" $arch "* ]] || { echo "Missing $arch in executable: $archs" >&2; exit 1; }
done
cp -R "$bin/ClockTower_ClockTowerCore.bundle" "$contents/Resources/"
cp LICENSE "$contents/Resources/LICENSE.txt"

iconset="$stage/AppIcon.iconset"
mkdir "$iconset"
sips -s format png Packaging/AppIcon.svg --out "$stage/icon.png" >/dev/null
for size in 16 32 128 256 512; do
    for scale in 1 2; do
        suffix=""
        if [[ $scale == 2 ]]; then suffix=@2x; fi
        px=$((size * scale))
        sips -z "$px" "$px" "$stage/icon.png" --out "$iconset/icon_${size}x${size}$suffix.png" >/dev/null
    done
done
iconutil -c icns "$iconset" -o "$contents/Resources/AppIcon.icns"

codesign --force --sign - --timestamp=none "$app"
codesign --verify --deep --strict --all-architectures "$app"
name="Clock-Tower-$version-universal-mac.zip"
ditto --norsrc -c -k --keepParent "$app" "$stage/$name"
mv "$stage/$name" "dist/$name"
(cd dist && shasum -a 256 "$name" > "$name.sha256")
cat "dist/$name.sha256"
