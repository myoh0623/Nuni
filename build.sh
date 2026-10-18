#!/bin/sh
set -eu

NUNI_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE_DIR="$NUNI_DIR/Sources/Nuni"
APP_DIR="$NUNI_DIR/build/Nuni.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ARCH_BUILD_DIR="$NUNI_DIR/build/architectures"
ICONSET_DIR="$ARCH_BUILD_DIR/AppIcon.iconset"
ICON_MASTER="$ARCH_BUILD_DIR/AppIcon-1024.png"

rm -rf "$APP_DIR" "$ARCH_BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR/LICENSES" "$ARCH_BUILD_DIR" "$ICONSET_DIR"

for NUNI_ARCH in arm64 x86_64; do
    swiftc \
        -swift-version 5 \
        -target "$NUNI_ARCH-apple-macosx13.0" \
        -O \
        -whole-module-optimization \
        -Xlinker -dead_strip \
        -o "$ARCH_BUILD_DIR/Nuni-$NUNI_ARCH" \
        "$SOURCE_DIR"/*.swift \
        -framework AppKit \
        -framework CoreGraphics \
        -framework IOKit \
        -framework ServiceManagement
done

lipo -create \
    "$ARCH_BUILD_DIR/Nuni-arm64" \
    "$ARCH_BUILD_DIR/Nuni-x86_64" \
    -output "$MACOS_DIR/Nuni"

sips -s format png "$NUNI_DIR/Assets/AppIcon.svg" --out "$ICON_MASTER" >/dev/null
for ICON_ENTRY in \
    "16:icon_16x16.png" \
    "32:icon_16x16@2x.png" \
    "32:icon_32x32.png" \
    "64:icon_32x32@2x.png" \
    "128:icon_128x128.png" \
    "256:icon_128x128@2x.png" \
    "256:icon_256x256.png" \
    "512:icon_256x256@2x.png" \
    "512:icon_512x512.png" \
    "1024:icon_512x512@2x.png"
do
    ICON_SIZE=${ICON_ENTRY%%:*}
    ICON_NAME=${ICON_ENTRY#*:}
    sips -z "$ICON_SIZE" "$ICON_SIZE" "$ICON_MASTER" --out "$ICONSET_DIR/$ICON_NAME" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"

cp "$NUNI_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$NUNI_DIR/LICENSE" "$RESOURCES_DIR/LICENSE.txt"
cp "$NUNI_DIR/THIRD_PARTY_NOTICES.md" "$RESOURCES_DIR/THIRD_PARTY_NOTICES.md"
cp "$NUNI_DIR/LICENSES/Lunar-MIT.txt" "$RESOURCES_DIR/LICENSES/Lunar-MIT.txt"

codesign --force --sign - "$APP_DIR"
echo "$APP_DIR"
