#!/bin/bash
# The Mac checks GitHub's runners cannot make, run before tagging a release (UPSTREAM.md, Versions). On an Apple-silicon Mac
# with the project's Xcode:
#   1. the host unit tests and every GPU (Metal 4) graphics test, for one profile;
#   2. the NXForge Converter's unit tests;
#   3. for each <id>_build folder given, the game left running without input (scripts/bench.py --idle): it must present
#      frames; its frames per second, worst frame and [RED] lines are reported.
# Then it prints the hands-on list in docs/release-checklist.md, for the things only a person can judge.
# Usage: scripts/smoke_mac.sh [--game <title ID>] [--seconds N] [--out <folder>] [<id>_build folder ...]
#   --game: the profile the tests are built for (default Super Mario Bros. Wonder, as in CI); --seconds: each game's run (default 60);
#   --out: where the logs and results go (default ~/Library/Logs/NXForge/smoke/<date-time>). Exit status 0 when everything passed.
set -uo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
game=010015100B514000 seconds=60 out="" builds=()
while [ $# -gt 0 ]; do
  case "$1" in
    --game) game="$2"; shift 2 ;;
    --seconds) seconds="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) builds+=("$1"); shift ;;
  esac
done
[ "$(uname -s)/$(uname -m)" = "Darwin/arm64" ] || { echo "smoke_mac.sh runs on an Apple-silicon Mac" >&2; exit 2; }
out="${out:-$HOME/Library/Logs/NXForge/smoke/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$out"
summary="$out/SUMMARY.md"
version="$(git -C "$repo" describe --tags --match 'v[0-9]*' --dirty 2>/dev/null || git -C "$repo" rev-parse --short HEAD)"
{
  echo "# NXForge smoke test, $version"
  echo
  echo "$(date '+%Y-%m-%d %H:%M'), $(sysctl -n machdep.cpu.brand_string), macOS $(sw_vers -productVersion), $(xcodebuild -version | head -1)"
  echo
  echo "| Check | Result | Log |"
  echo "|---|---|---|"
} > "$summary"
failed=0

step() {   # step <name> <log name> <command...>: runs it, records ✓ or ✗
  local name="$1" log="$out/$2.log"; shift 2
  echo "== $name"
  if "$@" > "$log" 2>&1; then echo "| $name | ✓ | $(basename "$log") |" >> "$summary"; echo "   ✓"
  else echo "| $name | ✗ (exit $?) | $(basename "$log") |" >> "$summary"; echo "   ✗ see $log"; tail -20 "$log"; failed=1; fi
}

step "Host unit tests ($game)" host-tests make -C "$repo/dm/host/tests" GAME="$game" -j8 run
step "GPU graphics tests ($game)" gfx-tests make -C "$repo/dm/gfx/tests" GAME="$game" -j8 run
step "Converter unit tests" converter-tests swift test --package-path "$repo/app"

for b in "${builds[@]}"; do
  id="$(basename "$b" | sed -n 's/^\([0-9A-Fa-f]\{16\}\)_build$/\1/p')"
  [ -n "$id" ] || { echo "| $b | ✗ not an <id>_build folder | |" >> "$summary"; failed=1; continue; }
  step "$id runs ${seconds} s" "game-$id" python3 "$repo/scripts/bench.py" "$b" --idle "$seconds" --runs 1 --no-hud --out "$out/game-$id"
  if [ -f "$out/game-$id/results.json" ]; then
    python3 - "$out/game-$id/results.json" >> "$summary" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))['results']['base'][0]
print(f"|  ↳ {r.get('frames', 0)} frames, {r.get('fps', '–')} fps, worst frame {r.get('frame_max', '–')} ms, {r.get('red_lines', 0)} [RED] lines | | |")
PY
  fi
done

echo >> "$summary"
if [ $failed = 0 ]; then echo "All automatic checks passed." >> "$summary"; else echo "**Some checks failed.**" >> "$summary"; fi
echo
cat "$summary"
echo
echo "Now the hands-on list (docs/release-checklist.md):"
sed -n '/^## Hands-on/,$p' "$repo/docs/release-checklist.md"
exit $failed
