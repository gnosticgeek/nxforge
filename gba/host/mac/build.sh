#!/bin/bash
# Build the Game Boy Advance player (gba/build/nxgba-player): gba_front_mac.m, NXForge's sidebar (the same Swift file
# the Switch player builds) and the host library (cargo build --release in gba/host; scripts/gba.py build does both).
set -euo pipefail
cd "$(dirname "$0")"
ROOT=../../..; OUT=$ROOT/gba/build; QS=$ROOT/layer/files/dm/host; MIN=${MACOS_MIN:-26.0}
mkdir -p "$OUT"
SDK=$(xcrun --show-sdk-path)
if [ ! -f "$OUT/quick_settings_mac.o" ] || [ "$QS/quick_settings_mac.swift" -nt "$OUT/quick_settings_mac.o" ] || [ "$QS/quick_settings_mac.h" -nt "$OUT/quick_settings_mac.o" ] || [ front.h -nt "$OUT/quick_settings_mac.o" ]; then
  swiftc -O -target arm64-apple-macos$MIN -parse-as-library -module-name dmquick -import-objc-header "$QS/quick_settings_mac.h" -Xcc -I. \
    -c "$QS/quick_settings_mac.swift" -o "$OUT/quick_settings_mac.o"
fi
clang -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter -target arm64-apple-macos$MIN -I. -I.. -I"$QS" gba_front_mac.m "$OUT/quick_settings_mac.o" ../target/release/libnxgba.a \
  -framework Cocoa -framework Metal -framework QuartzCore -framework GameController -framework AudioToolbox -framework CoreAudio -framework IOKit -framework Security \
  -L"$SDK/usr/lib/swift" -L"$(dirname "$(xcrun -f swiftc)")/../lib/swift/macosx" -Wl,-rpath,/usr/lib/swift -o "$OUT/nxgba-player"
echo "built $OUT/nxgba-player"
