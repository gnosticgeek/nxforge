#!/bin/bash
# Build the Wii and GameCube player (wii/build/nxwii-player): wii_front_mac.m and NXForge's sidebar (the same Swift file the Switch and
# GBA players build, with the GBA player's front.h). Dolphin itself is loaded at run time from the app's Frameworks (scripts/wii_engine.py).
set -euo pipefail
cd "$(dirname "$0")"
ROOT=../../..; OUT=$ROOT/wii/build; QS=$ROOT/layer/files/dm/host; FRONT=$ROOT/gba/host/mac; MIN=${MACOS_MIN:-26.0}
mkdir -p "$OUT"
SDK=$(xcrun --show-sdk-path)
if [ ! -f "$OUT/quick_settings_mac.o" ] || [ "$QS/quick_settings_mac.swift" -nt "$OUT/quick_settings_mac.o" ] || [ "$QS/quick_settings_mac.h" -nt "$OUT/quick_settings_mac.o" ] || [ "$FRONT/front.h" -nt "$OUT/quick_settings_mac.o" ]; then
  swiftc -O -target arm64-apple-macos$MIN -parse-as-library -module-name dmquick -import-objc-header "$QS/quick_settings_mac.h" -Xcc -I"$FRONT" \
    -c "$QS/quick_settings_mac.swift" -o "$OUT/quick_settings_mac.o"
fi
clang -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter -target arm64-apple-macos$MIN -I"$FRONT" -I"$QS" wii_front_mac.m "$OUT/quick_settings_mac.o" \
  -framework Cocoa -framework QuartzCore -framework GameController -framework IOKit -framework Security -framework ImageIO -framework AVFoundation \
  -L"$SDK/usr/lib/swift" -L"$(dirname "$(xcrun -f swiftc)")/../lib/swift/macosx" -Wl,-rpath,/usr/lib/swift -Wl,-dead_strip -o "$OUT/nxwii-player"
strip "$OUT/nxwii-player"
echo "built $OUT/nxwii-player"
