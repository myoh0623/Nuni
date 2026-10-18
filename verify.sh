#!/bin/sh
set -eu

NUNI_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR="$NUNI_DIR/build/Nuni.app"
BINARY="$APP_DIR/Contents/MacOS/Nuni"
RESOURCES="$APP_DIR/Contents/Resources"

"$NUNI_DIR/test.sh"

swiftc \
    -swift-version 6 \
    -target arm64-apple-macosx13.0 \
    -typecheck \
    -strict-concurrency=complete \
    "$NUNI_DIR/Sources/Nuni"/*.swift \
    -framework AppKit \
    -framework CoreGraphics \
    -framework IOKit \
    -framework ServiceManagement

if xcrun --find swift-format >/dev/null 2>&1; then
    xcrun swift-format lint \
        --strict \
        --configuration "$NUNI_DIR/.swift-format" \
        "$NUNI_DIR/Sources/Nuni"/*.swift \
        "$NUNI_DIR/Tests"/*.swift
fi

"$NUNI_DIR/build.sh"

plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

ARCHITECTURES=$(lipo -archs "$BINARY")
case " $ARCHITECTURES " in
    *" arm64 "*) ;;
    *) echo "Missing arm64 executable" >&2; exit 1 ;;
esac
case " $ARCHITECTURES " in
    *" x86_64 "*) ;;
    *) echo "Missing x86_64 executable" >&2; exit 1 ;;
esac

test -f "$RESOURCES/AppIcon.icns"
cmp "$NUNI_DIR/LICENSE" "$RESOURCES/LICENSE.txt"
cmp "$NUNI_DIR/LICENSES/Lunar-MIT.txt" "$RESOURCES/LICENSES/Lunar-MIT.txt"
cmp "$NUNI_DIR/THIRD_PARTY_NOTICES.md" "$RESOURCES/THIRD_PARTY_NOTICES.md"

if find "$RESOURCES" -type f -name 'ddcctl' | grep -q .; then
    echo "Unexpected ddcctl binary in app resources" >&2
    exit 1
fi

if otool -L "$BINARY" | grep -Eq '^[[:space:]]+/Users/'; then
    echo "Executable contains a local dynamic-library path" >&2
    exit 1
fi

echo "Nuni release verification passed for: $ARCHITECTURES"
