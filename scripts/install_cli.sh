#!/bin/sh
# Installs the nxforge command line and MCP server (docs/automation.md) where they do not depend on a checkout's branch: copies scripts/nxforge.py and scripts/nxforge_mcp.py
# into ~/Library/Application Support/NXForge Converter/cli/ and writes the `nxforge` and `nxforge-mcp` commands into ~/.local/bin (or the folder given). Run it again to update them.
# Usage: scripts/install_cli.sh [bin folder]
set -eu
here=$(cd "$(dirname "$0")" && pwd)
dest="${NXC_SUPPORT_DIR:-$HOME/Library/Application Support/NXForge Converter}/cli"
bin="${1:-$HOME/.local/bin}"
mkdir -p "$dest" "$bin"
for f in nxforge.py nxforge_mcp.py; do cp "$here/$f" "$dest/$f.tmp" && mv "$dest/$f.tmp" "$dest/$f"; done
py=$(command -v python3)
printf '#!/bin/sh\nexec "%s" "%s/nxforge.py" "$@"\n' "$py" "$dest" > "$bin/nxforge"
printf '#!/bin/sh\nexec "%s" "%s/nxforge_mcp.py" "$@"\n' "$py" "$dest" > "$bin/nxforge-mcp"
chmod +x "$bin/nxforge" "$bin/nxforge-mcp"
echo "installed $bin/nxforge and $bin/nxforge-mcp (scripts in $dest, $py)"
case ":$PATH:" in *":$bin:"*) ;; *) echo "note: $bin is not on PATH; call $bin/nxforge, or add it to PATH";; esac
