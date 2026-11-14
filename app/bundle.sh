#!/bin/bash
# Builds "NXForge.app" (named "NXForge Converter.app" before Converter 0.9.0) from this package: swift build -c release, then a minimal bundle, signed ad-hoc
# (or with the identity in $SIGN). Usage: app/bundle.sh [output folder, default app/.build]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out="${1:-$here/.build}"
swift build -c release --package-path "$here"
app="$out/NXForge.app"
old="$out/NXForge Converter.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$here/.build/release/NXForgeConverter" "$app/Contents/MacOS/"
# the icon, drawn by make_icon.swift at every size macOS asks for
icons="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$icons"
swift "$here/make_icon.swift" "$icons/icon_512x512@2x.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$icons/icon_512x512@2x.png" --out "$icons/icon_${s}x${s}.png" >/dev/null
  [ $s -lt 512 ] && sips -z $((s * 2)) $((s * 2)) "$icons/icon_512x512@2x.png" --out "$icons/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$icons" -o "$app/Contents/Resources/AppIcon.icns"
# What's New reads the changelog the app was built with (ConverterUpdate.bundledChangelog), not the engine checkout's, which can be on another branch
cp "$here/../CONVERTER_CHANGELOG.md" "$app/Contents/Resources/"
# the app's version is the Converter's own (CONVERTER_VERSION in Version.swift, tags converter-vX.Y.Z); the build
# number is the NXForge release it was built from (git describe on the v* tags only: v0.1.1 → 0.1.1, v0.1.1-3-g… → 0.1.1)
version="$(sed -nE 's/^let CONVERTER_VERSION = "([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' "$here/Sources/NXForgeConverter/Version.swift")"
version="${version:-0.0.0}"
build="$(git -C "$here" describe --tags --match 'v[0-9]*' 2>/dev/null | sed -E 's/^v//; s/-[0-9]+-g[0-9a-f]+$//')"
build="${build:-0.0.0}"
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>NXForge</string>
  <key>CFBundleDisplayName</key><string>NXForge</string>
  <key>CFBundleIdentifier</key><string>org.nxforge.converter</string>
  <key>CFBundleExecutable</key><string>NXForgeConverter</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$build</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>Game folder</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSHandlerRank</key><string>Alternate</string>
    <key>LSItemContentTypes</key><array><string>public.folder</string></array>
  </dict><dict>
    <key>CFBundleTypeName</key><string>Switch 2 game (NUP container)</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSHandlerRank</key><string>Alternate</string>
    <key>CFBundleTypeExtensions</key><array><string>nup</string></array>
  </dict></array>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
codesign --force --sign "${SIGN:--}" "$app"
# the copy under the old name goes, so there is one app. An updater from before 0.9.0 opens the old name afterwards, which
# is gone: open the new one for it here.
if [ -d "$old" ]; then
  rm -rf "$old"
  open "$app" || true
fi
echo "$app"
