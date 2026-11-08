# NXForge Sidebar changelog

The in-game Quick settings sidebar has its own version, separate from NXForge's (UPSTREAM.md, Versions). Each release is a tag `sidebar-vX.Y.Z` and a GitHub release "NXForge Sidebar X.Y.Z". The sidebar shows its version under the button legend. The NXForge release that first ships a sidebar version is named in its entry.

What counts as the sidebar: `dm/host/quick_settings_mac.swift` and `.h`, `dm/host/capture_mac.*`, `dm/host/nxforge/` and `dm/gfx/nvn/nxforge/` (its glue, controller navigation, remapping and the present filters).

## 0.1.0 (2026-11-07)

The first versioned sidebar: the sidebar as it is in NXForge 0.15.0, now numbered on its own. Ships in NXForge 0.16.0.

- **Opens** with Esc, ⇧⌘G, the Graphics menu or a controller's Home button, on a Liquid Glass panel on macOS 26 and later.
- **Quick bar:** Screenshot, Record, the FPS counter and volume.
- **Six pages** in tabs (Graphics, FPS, Capture, Mods, Cheats, Controls). L and R, or Tab and Shift-Tab, turn the page, and the last page is remembered per game.
- **Graphics:** CRT filter with Strength and Line size, FXAA anti-aliasing, MetalFX upscaling, an anisotropic filtering floor, a dot on each changed setting and Reset.
- **FPS:** the counter's corner, and Record frame times under Advanced.
- **Mods** (folders overlaid at the next launch), **Cheats** (a switch per code, Refresh, Open cheats folder) and **Controls** (keys and buttons remapped per game).
- **Footer:** what applies after a restart with Restart game, Resume, Quit (pressed twice), and a button legend in the controller's own glyphs or as keys.
- The pointer hides over the game after 3 seconds.
