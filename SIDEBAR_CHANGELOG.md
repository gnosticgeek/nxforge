# NXForge Sidebar changelog

The in-game Quick settings sidebar has its own version, separate from NXForge's (UPSTREAM.md, Versions). Each release is a tag `sidebar-vX.Y.Z` and a GitHub release "NXForge Sidebar X.Y.Z". The sidebar shows its version under the button legend. The NXForge release that first ships a sidebar version is named in its entry.

What counts as the sidebar: `dm/host/quick_settings_mac.swift` and `.h`, `dm/host/capture_mac.*`, `dm/host/nxforge/` and `dm/gfx/nvn/nxforge/` (its glue, controller navigation, remapping and the present filters).

## 0.2.0 (2026-11-07)

Ten quality-of-life improvements and a settings file. Ships in NXForge 0.17.0.

- **General page** (new, first tab): what happens while the sidebar is open, a save backup, the settings file and your defaults.
- **Pause while open** (on by default): once the picture has slid aside, the game, its sound and its clock stop until you resume, as when the window is minimized. Off keeps the game running so graphics changes show at once. A screenshot taken from the sidebar resumes for one frame.
- **Back up save now**: a checked copy of the save (every file hashed, copied, checked again) in `save-snapshots` beside it, the same format as the Converter's save snapshots, so the Builds page restores it. The page shows when the last backup was made.
- **Display section** on Graphics: Full screen, and Picture size: Fit (as before), Stretch, or Pixel-perfect (the game's pixels enlarged by the largest whole number that fits). `DM_PRESENT_SCALE=fit|stretch|integer` sets it for one run.
- **Controls swap instead of clearing**: giving an action a key or button another action has swaps the two, with a toast saying so. Keys or buttons two actions share (from an older map or a hand edit) are marked in orange, and the Controls tab gets a dot.
- **Mod load order**: arrows on each mod move it up or down (the higher one wins when two have the same file), and an enabled mod that shares files with another says how many and which one wins. The order applies at the next launch, with a Next launch tag.
- **Mute and quieter sound**: the speaker icon (or M) mutes and unmutes; A on the volume row does the same from a controller. "Quieter sound" plays the game at a quarter of its volume while the sidebar is open and the game is not paused.
- **Recent captures** on the Capture page: the newest six screenshots and recordings as thumbnails, with Copy (paste a screenshot straight into a message), Open and Show in Finder.
- **Frame-time graph** on the FPS page: the last four seconds of frame times with 60 and 30 FPS lines, the average, the 1% low and the longest frame. The FPS counter can show milliseconds too.
- **My defaults**: "Make these my defaults" saves the graphics, sound, counter, pausing and controls settings for every game; a game opened for the first time starts from them, and "Use my defaults" applies them to this game.
- **Cheats**: sections from the cheat file fold open and closed with a count of what is on, a search field appears for long lists, and "Turn all off" switches every cheat off.
- **Restart list**: the footer names the settings waiting for a restart, not only how many.
- **Settings file** (Tom's request): each game's settings as plain text, `name = value` a line, in `NXForge settings.txt` in the game folder. It is rewritten whenever a setting changes and read at launch, so an edit made with the game closed applies; an edit made while it runs is read when the sidebar next opens. Defaults show as `#` lines with their choices. `DM_SETTINGS_FILE=0` turns it off.

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
