#!/bin/sh
set -eu

NUNI_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEST_BINARY="$NUNI_DIR/build/NuniSmokeTests"

mkdir -p "$NUNI_DIR/build"

swiftc \
    -swift-version 5 \
    -o "$TEST_BINARY" \
    "$NUNI_DIR/Sources/Nuni/AdaptiveMath.swift" \
    "$NUNI_DIR/Sources/Nuni/SolarCalculator.swift" \
    "$NUNI_DIR/Tests/SmokeTests.swift"

"$TEST_BINARY"
