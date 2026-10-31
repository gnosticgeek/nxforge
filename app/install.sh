#!/bin/bash
# Builds the converter from this checkout into ~/Applications (where Spotlight, Launchpad and the Dock find it) and
# opens it. Usage: app/install.sh [folder, default ~/Applications]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
dest="${1:-$HOME/Applications}"
mkdir -p "$dest"
if pgrep -xq NXForgeConverter || pgrep -xq NxNativeConverter; then   # the second: the executable's name before 0.8.0
  echo "NXForge Converter is open: quit it first (a build in it would be cut off)" >&2
  exit 1
fi
app="$("$here/bundle.sh" "$dest" | tail -1)"
open "$app"
