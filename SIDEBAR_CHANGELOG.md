# NXForge Sidebar changelog

The in-game Quick settings sidebar has its own version, separate from NXForge's (UPSTREAM.md, Versions). Each release is a tag `sidebar-vX.Y.Z` and a GitHub release "NXForge Sidebar X.Y.Z". The sidebar shows its version under the button legend. The NXForge release that first ships a sidebar version is named in its entry.

What counts as the sidebar: `dm/host/quick_settings_mac.swift` and `.h`, `dm/host/capture_mac.*`, `dm/host/nxforge/` and `dm/gfx/nvn/nxforge/` (its glue, controller navigation, remapping and the present filters).

## 0.5.0 (2026-11-14)

Four improvements, two to the look and two to what it does. Ships in NXForge 0.34.0.

- **The game's own look**: the glass panel is tinted and lit from the top left in a colour taken from the game's banner or icon (the way the NXForge app lights its stage), with a lit top edge. The header shows the game's icon in its glow and its name in the app's heavy title type under a wide-set "QUICK SETTINGS" label, with a Paused chip while the game is paused; a long name takes two lines. Switches, the selection outline, the changed dots and Resume game take the game's colour. A bare `dmhost` keeps the app's blue.
- **Hold to peek**: hold P, a controller's top face button, or the eye button beside Close, and the sidebar fades away while the game shows at full size and runs; let go and the sidebar is back (paused again when Pause the game is on). The game's input stays released meanwhile. The legend shows it ("Hold to peek").
- **Presets** at the top of the Graphics page: the app's Battery, Balanced and Quality presets (PlayOptions.swift) as cards, with the one the settings match lit, or a note that they are a custom mix. MetalFX upscaling, HDR highlights and frame interpolation change at once; frame rate and render scale apply at the next launch or Restart game, with a Next launch line in the footer. Only the settings the game offers (its `dm/launcher.json`) are set.
- **Undo this session**: once anything has changed since the game started, the General page lists what (by the pages' names) with **Put it all back**, which restores every setting the sidebar and the settings window keep for the game, and the cheats, as they were at the start. The General tab gets a dot meanwhile.

## 0.4.0 (2026-11-12)

Pixel art. Ships in NXForge 0.29.0.

- **Graphics › Pixel art** (Auto, Off, Sharp pixels, Smooth edges; `dm/gfx/nvn/nxforge/pixel_art.inc`): crisp, even pixels for 2D games, on the art's own pixel grid where the game enlarged it. The note under it says what it does now: waiting for pixel art (Auto), or the art's size while it is on. Saved per game, in the settings file (`pixel_art`) and in the settings window (`launcher.DM_PIXEL_ART`).
- MetalFX upscaling, Anti-aliasing, HDR highlights and Frame interpolation say "Waits while Pixel art is on" while it is; MetalFX says it is not used with a Pixel-perfect picture size.

## 0.3.3 (2026-11-12)

A warning when GPU memory is nearly full. Ships in NXForge 0.28.2.

- **"GPU memory is nearly full, so the game is slow"**: when the player finds the game's GPU memory past the level from which macOS's GPU driver slows every frame, with the game at under 40% of its best frame rate for three seconds, a toast says so for 8 seconds and the **Performance** page keeps a note with the sizes for the rest of the run (`front_gpu_memory_low` in `dm/host/nxforge/front_mac_quick_settings.inc`). Saving and restarting the game frees the memory. Found on Ocarina of Time in Hyrule Field, 15 minutes into a session on a 24 GB Mac.
- Toasts can stay longer than 2 seconds (`dm_qs_toast_long`).

## 0.3.2 (2026-11-12)

Frame interpolation, and the settings window shares the picture options. Ships in NXForge 0.27.4.

- **FPS › Frame interpolation** (Off, On, Auto; `dm/gfx/nvn/nxforge/frame_interp.inc`): 60 fps games shown at 120 fps on a 120 Hz screen with in-between pictures. Saved per game and in the settings file (`frame_interpolation`).
- **The settings window shows anti-aliasing, HDR highlights, its strength and frame interpolation too** (`dm/host/nxforge/front_mac_launcher_sync.inc`): the sidebar's choice is copied to the window's, and a change made in the window is taken at launch. A setting the window set is no longer shown as fixed ("Set by … for this run"); only `env.txt` and the launch environment fix one.

## 0.3.1 (2026-11-11)

Full screen without the title bar. Ships in NXForge 0.27.3.

- **Full screen hides the title bar and menu bar** (`dm/host/nxforge/front_mac_fullscreen.inc`), whether it is entered from the green button, ⌃⌘F, the Full screen row or at launch. Before, macOS showed them again while the pointer was at the top of the screen, where the green button leaves it. `DM_FULLSCREEN_MENU_BAR=1` keeps macOS's behaviour.

## 0.3.0 (2026-11-09)

HDR highlights. Ships in NXForge 0.24.0.

- **HDR highlights** (Graphics page, off by default): on an HDR or XDR screen, the brightest parts of the picture are lifted above SDR white, up to the screen's headroom (at most 4x). White HUD text brightens with them. On a screen without EDR headroom the row's note says the picture stays the same.
- **Brightness boost** (shown while HDR highlights is on): how far the highlights are lifted, 0 to 100 %, 50 by default. Left and right change it in steps of 5 %, A steps it by 25 %.
- Both are saved per game, reset with the Graphics page's Reset button, and set from the settings file (`hdr_highlights`, `hdr_strength`) or the environment (`DM_PRESENT_EDR`, `DM_PRESENT_EDR_STRENGTH`, not saved).

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
