# NXForge Converter changelog

The NXForge Converter (the Mac app under `app/`) has its own version, separate from NXForge's (UPSTREAM.md, Versions). Each release is a tag `converter-vX.Y.Z` and a GitHub release "NXForge Converter X.Y.Z". Since 0.9.0 the app itself is named NXForge (the library front end plus the converter); it shows this version under the NXForge name in the converter's sidebar and in About NXForge. The NXForge release that first ships a converter version is named in its entry.

What counts as the converter: everything under `app/` (the SwiftUI app, its tests, `bundle.sh`, `install.sh` and `make_icon.swift`).

## 0.22.9 (2026-11-21)

Shipped in NXForge 0.48.9.

- **Showcase**: Theatre's Carousel and Fan themes are now one theme, Showcase, with two layouts of the same boxes, Carousel and Fan. Up and down on a controller switch layout on Theatre (the game in focus, the filter and the music stay as they are); the Theatre menu's Showcase row switches it with left and right, and Settings › Theatre has a "Showcase layout" row. The top bar reads "Showcase · Fan". ZL and ZR now step through three themes: Showcase, Cinema and Trailer. A saved Carousel or Fan theme (or the older Gallery and Shelf) opens Showcase on that layout. Sounds stay the quiet ticks, the right stick still only turns the box in front, and the music folder keeps playing on Showcase as before (off only on Trailer).

## 0.22.8 (2026-11-20)

Shipped in NXForge 0.48.8.

- **Keep shader work only**: a fourth choice for Settings › Building › "Build folder after a build". It deletes the build's copies of the game files once the app is ready and keeps the shader work beside the game, so a rebuild skips the shader steps while they are unchanged (`--cleanup shaders`). The Convert page's "Clean up build files" switch now turns this on rather than "Remove build cache"; a saved "Remove build cache" stays as it is until changed.

## 0.22.7 (2026-11-20)

Shipped in NXForge 0.48.7.

- **Build log in batches**: the script's plain output lines join the log about ten times a second instead of one main-thread hop and redraw per line, and the log view reads each line's level once per redraw (one pass for the shown lines and the tabs' counts, not three).
- **Icons kept while unchanged** (IconImage): game icons are decoded once per file version, not on every redraw of a tile or header.
- **Settings saved after a pause**: settings.json is written half a second after the last change (and at quit), not on every step of a slider drag.
- **Library tiles get their own focus and tick**, so moving the focus redraws two tiles, not all of them.
- **VoiceOver**: names for the mods list's and the cleanup list's icon-only buttons; the Home rows' tiles have an activate action (play, or open the game page).
- **Modern API**: `@Entry` for Theatre's unit; a plain binding for Group Library by Console; `import Combine` where a timer publisher is kept.

## 0.22.5 (2026-11-20)

Shipped in NXForge 0.48.5.

- **Theatre's whoosh removed**: the turn and the theme switch are quiet wooden ticks (587 Hz and 494 Hz) at the step's level; the breeze and whoosh synths are gone.

## 0.22.4 (2026-11-20)

Shipped in NXForge 0.48.4.

- **Fan replaces Gallery in Theatre**: the boxes fanned out round a point below the screen, the focused one upright in the middle, lifted out by 46 px, scaled up and lit; neighbours turn 7.5° each and darken with distance, eight either side are drawn. Left and right swing the fan, a click brings a box to the middle, the right stick turns the box in front. A saved Gallery (or the older Shelf) theme opens as Fan.
- **Mellower sounds**: the turn is a low-passed breeze with a soft tick under it and the theme switch a slower breeze; steps, spins and opens are short rounded ticks; every sound is soft-limited and quieter.
- **The right stick no longer sets the volume**: up and down fought with turning the box; the volume stays in Settings and on - and =.
- **Music folder**: Settings › Theatre › Music folder chooses a folder; its MP3, Opus, M4A, AAC, FLAC, WAV and AIFF files (subfolders too, up to 3000) play shuffled, one after another, in the background while Theatre is open, except on Trailer, while a game plays or a box is opening. A game with its own music still takes over while it is in focus, and the folder carries on where it paused. Files macOS cannot play are skipped.

## 0.22.3 (2026-11-20)

One Settings panel, wider and in sections. Ships in NXForge 0.48.3.

- **Settings is a wide panel with its sections down the left**: General, Playing, Library, Artwork, Theatre, Saves, Building, Updates and Storage. The chosen section's rows fill the right side, in cards by what they are about, so a section is read without scrolling on most windows and the notes run in one or two lines instead of three. It was one narrow column (640 pt) that scrolled through everything; it is now up to 1020 pt wide and narrows with the window. The app's version is at the foot of the list.
- **Everything is in it.** The converter's options had a Settings window of their own (⌘,, or Converter Settings… at the foot of the panel): notifications, opening the app after a build, keeping previous builds, what a build leaves in its build folder, where new apps are saved, the signing identity, reusing finished steps and log detail are the Building section now, beside the keys file. ⌘, opens the panel, and that window is gone.
- **Options that were only elsewhere**: Saves has Cloud saves for every game and its folder (the Saves page's switch), a snapshot after every session, the snapshot folder and the Git backup; Updates has the version, What's New, Check Now and Update automatically; Storage has Manage Storage, What NXForge Keeps, Health and Restore Defaults; Library shows the games folder's path with Change and Refresh, and Group Game Files by console; Theatre has a Volume slider (the right stick's setting).
- **New: Look for new games** (Library): how often the games folder is looked at, every minute, every 10 minutes (as before), hourly, or Manual, which leaves it to Refresh.
- **Find a setting** (⌘F) looks through every section at once and shows the matches under their sections' names; a section's name finds its rows ("theatre").
- **A controller** walks the rows with up and down, turning to the next section at the end of one, and L and R step through the sections; every new switch and choice can be changed from the pad.
- Snapshot hook: `NXC_SETTINGS=<section>` with `NXC_STAGE=settings`.

## 0.22.2 (2026-11-20)

New games look themselves up, and find their sub-genres. Ships in NXForge 0.48.2.

- **Refresh is in the top bar** (a round arrow beside Full Screen, turning while it scans), on Home and Discover alike, instead of on Discover's title row. ⌥⌘R and Go to Anything's Refresh Library still work.
- **The games folder is looked at every 10 minutes**, in front or not, and each time NXForge comes to the front (it was every minute, only while in front).
- **A new game fetches its art and details at once**: when a scan finds games the last one did not have, their front, back and square covers, wide art and store details (publisher, release date, description, screenshots, trailers) are fetched as soon as their names are read, as the Artwork settings allow, rather than when each is first shown or opened, and their genres follow. A banner names the games added.
- **Genre files for 18 more games** in the library (10 beat 'em ups, 3 more run and guns, and the rest), so they show under Beat 'em up, Run and gun and the other sub-genres.
- **A game with no file in the library reads its sub-genres from its store description** as well as the store's categories: "beat 'em up", "run and gun", "shoot 'em up", "Metroidvania", "kart racing", "first-person shooter" (Genres.hints). Nintendo's store has no Beat 'em up or Run and gun category, so before this a new game only ever reached Action or Fighting.

## 0.22.1 (2026-11-20)

Refresh the library. Ships in NXForge 0.48.1.

- **Refresh** on Discover's title row scans the games folder again (the arrow spins while it scans); also View › Refresh Library (⌥⌘R) and Refresh Library in Go to Anything (⌘K).
- **New games show up by themselves**: the scan keeps what the games folder itself holds (`top` in library.json), and NXForge looks at the folder each time it comes to the front and once a minute while it is in front, scanning again when a folder or game file was added or removed. Before, the library scanned only on a mount, when its list was a day old, or from Settings' Scan Again, so games filed by the Switch Downloads Watcher stayed hidden.

## 0.22.0 (2026-11-20)

Theatre's small delights, on every theme. Ships in NXForge 0.47.4.

- **Lights down on launch**: starting a game from Theatre dims the room, flies the game's box forward and opens its front like a door; the light inside fills the screen, and the launch screen comes up under it, so the game comes out of its box. Reduce Motion keeps only the dimming.
- **Sound**: a soft click for each step, a whoosh as the Carousel turns, a swish between themes, a low thunk on launch and a chime for a moment, all made by the app (no sound files) and quiet. The right stick's press (or S) now mutes on every theme, and up and down set the volume of everything Theatre plays. Settings › Theatre › Sounds turns them off.
- **The game's music**: once the focus rests on a game, its music fades in, looped and quiet, and fades out as you move on. Put `music`, `theme` or `soundtrack` (.m4a, .mp3, .aac, .wav, .aiff, .caf or .flac) in the game's `media/` folder, or a file named by its title ID or its name in `~/Library/Application Support/NXForge Converter/Theatre Music/`. Not on Trailer, which has the trailer's sound; never while a game runs. Settings › Theatre › Game music.
- **Welcome back**: Theatre opens on the game you played last (in the last 30 days) with a card: "Good evening · Welcome back, Day 3 in Ocarina of Time, 8 h 25 min played · last played yesterday", and A to Continue.
- **Time of day**: a cooler, brighter room in the morning, the stage as it is in the afternoon, a warm evening, and a dimmer, cosy room after 10 pm, with the sun or moon by the clock. Settings › Theatre › Light follows the time of day.
- **Shelf moments**: confetti, the game in focus and a "Ready to play" card when a game finishes building while Theatre is up; a spotlight and a "New arrival" card on a built game Theatre has not shown before (the first time Theatre opens, every game counts as seen).
- **What should I play?** L3 (the left stick's press), ? on the keyboard, or the Theatre menu's new row: the games whirl past with ticks, slow down and land on one (a built one when there are any), with a card to play it or spin again. B stops it.
- Snapshot hooks: `NXC_MOMENT=welcome|arrival|built|shuffle`, `NXC_CONFETTI=<s>`, `NXC_CURTAIN=<s>`, `NXC_DAYLIGHT=morning|day|evening|night`.

## 0.21.3 (2026-11-20)

Genres of NXForge's own, with sub-genres. Ships in NXForge 0.47.3.

- **New genres: Run and gun and Beat 'em up** (Cuphead, Contra, Valfaris, The Mummy Demastered, Blazing Chrome, Huntdown...; the Turtles games).
- **Sub-genres on Discover**: a genre with sub-genres shows a chevron, and choosing it opens them under it with their own counts (Sports › Football, Golf, Baseball, Multi-sport; Platformer › 2D platformer, 3D platformer, Metroidvania; Shooter › Shoot 'em up, First-person shooter; Racing › Kart racing, Arcade racing; RPG › Action RPG, Turn-based RPG; Fighting › Platform fighter; Music › Rhythm; Arcade › Retro collection). A game in a sub-genre counts under its genre too. L and R walk into the open genre's sub-genres. Theatre's filters and rows stay on the genres.
- **Each game's genres come from its own file** in the game library (`library/<title ID>/game.md`, front matter `nxforge_game`, `title_id`, `genres`), bundled into the app; a game without one falls back to the store's genres, put into NXForge's names. The game page, Theatre and each game folder's `media/game.md` (a new top-level `genres:`) show the same genres.

## 0.21.2 (2026-11-20)

A save manager for the whole library. Ships in NXForge 0.47.2.

- **Saves is in the top bar** (Home, Discover, Saves, Converter), no longer one of the converter's pages; Converter goes back to the page it was on.
- **Cloud saves for every game**: one switch at the top of Saves gives every built game the same sync folder, written into each game's `cloudSaves.folder` (the key its settings window's Cloud saves shows), so the engine brings the save in at each start and sends it after each save. The location is iCloud Drive › NXForge Saves unless you choose another (any folder, a NAS or another app's iCloud folder); with the switch first turned on, a folder a game already used is offered instead. A game built later, or one opened from NXForge, joins in. Off turns every game's Cloud saves off; the copies stay in the folder. Games with a folder of their own are named under the switch.
- **Each game's row** now shows where it syncs (iCloud, a folder, or "Sends at next start" before its first sync), when the cloud copy was saved and on which device (read from the copy's header, nothing downloaded), and its quick-save slots, beside the snapshots it had.

## 0.21.1 (2026-11-20)

Theatre's themes refined, the Carousel most. Ships in NXForge 0.47.1.

- **Carousel shows five boxes, not three**: five games or more always make a ring of at least 12 places, so two boxes stand either side of the one in front (a short list made a small ring, with one box either side turned almost edge on). The boxes beside the front one turn part of the way back towards you, so their covers read, and are lit by how near the front they are rather than all falling into the same muddy shade. The ring is spread a little wider.
- **The box in front stands in a pool of light**, warmed by the game's colour, and the room's sides fall into shadow. The ring sits higher on the screen and its reflection fades out sooner, so the game's name is no longer written over the reflection.
- **Cinema's cards keep their size**: the art filled each card past its edges, so the cards ran into each other with no gap and lost their round corners. The cards beside the one in focus are a shade darker.
- **The filter between L and R** shows "3 of 17" rather than a row of 17 dots when there are many genres.
- The game counter reads "07 / 08" on Carousel, as on Gallery, and Gallery says "12 min played" rather than "12 min time played".

## 0.21.0 (2026-11-19)

Enhancements: a game's own improvements, apart from its cheats. Ships in NXForge 0.47.0.

- **An Enhancements card** on the game's page (also Enhancements… in the game's menu on Home and in the Library) and an **Enhancements tab in Play options**: the game's enhancements with a switch each, what each changes (Settings, Game code, Mod) and a line on what it does. One for another version of the game is marked and cannot be switched on.
- **Each enhancement is one Markdown file** in the game's `enhancements/` folder, beside `cheats/` and `media/` (in Application Support when the app's folder has neither). The front matter names it, the title and the builds it is for and whether it is on; the blocks say what it does: ` ```env ` launch settings, ` ```dmnt ` an Atmosphère code (a 60 fps patch and the like), ` ```mods ` mods to switch on. **New…** makes a file to fill in and opens it.
- **A switch applies at once, however the game is opened** (front end, Theatre, Finder): settings go in a block of the game's `env.txt` in Application Support, which the game reads first, codes go in its cheat file as master codes named "NXForge enhancement: …", and mods are switched on. Switching off takes them back. A launch from NXForge applies them again first, so a file edited by hand counts. The Cheats card, the cheats Markdown and Get Cheats leave the enhancements' codes out.
- **Get from Library**: lists the game's enhancements in NXForge's library on GitHub (`library/<title ID>/enhancements/` in the repository) and adds the ones you pick, switched off.

## 0.20.2 (2026-11-18)

Buttons that never wrap, and small refinements. Ships in NXForge 0.46.3.

- **Resume stays on one line**: with a game running, Home's row (Resume, Play options, Quit game, Details, the star) was wider than the space beside the box, so Resume wrapped to "Resu / me". Every large button now keeps its label on one line at its own width. Where the whole row does not fit, Quit game becomes a round ✕ first, then Play options and Details become round icons, each with its name as the tooltip, so Resume or Play is never squeezed. The same row is on the game's page. Play options' own Play still fills its row.
- **Home's game is given more room in a large window**, so the full row with Quit game and Details fits as words.
- **The A hint says Resume** while the game in focus is running, as its button does.
- **Play options' presets**: a note is no longer cut off ("where the game ha…"), the four cards are the same height, and Custom no longer looks greyed out when it is the preset in use.
- **Sentence case for Play options** on the launch screen's fix button and message, and in Theatre, as everywhere else in the front end.
- **Updates**: upstream's newest commit date reads "19 Nov 2026" rather than "2026-11-19", and "Last checked today at 19:39" loses its colon and full stop.
- **Health**: a backup's size reads in KB or MB rather than "0.0 GB".
- Snapshot hook: `NXC_PLAYING=1` shows the chosen game as running (Resume and Quit game) without starting it.

## 0.20.1 (2026-11-18)

Free space from the drive the app is saved to. Ships in NXForge 0.46.1.

- **"Available" is the target drive's free space**: with the app saved to an external drive, Ready to build showed the Mac's own free space (79 GB) because the shared Metal cache on the Mac had the least room to spare. The line now names the drive the app is saved to, with what the build needs there. The Mac's disk and the build folder's drive are still checked, and Not enough space still names whichever is short.

## 0.20.0 (2026-11-18)

Ten Theatre improvements. Ships in NXForge 0.46.0.

- **Filters on L and R**: All games, Favourites, Recently played (the last 30 days) and each genre your games are in, shown in the middle of the top bar with a dot per filter. Cinema shows one row of the filter's games; a filter with none of the built games shows them all. **ZL and ZR now switch the theme** (keyboard: [ and ] filter, , and . or Tab the theme).
- **Trailer sound on the controller**: press the right stick to mute, push it up or down for the volume in tens (keyboard S, − and =). A card at the top right shows the level; the volume is kept, a quarter of it while browsing and all of it while watching. Both work in Watch without leaving it.
- **TV edges**: Settings › Theatre › TV edges (Full, Inset 3 %, Inset 5 %) and a TV Edges row in Theatre's menu, which draws the picture's four corners while it is chosen so you can see whether the TV crops them. Theatre's sizes now also follow the width on a screen narrower than 16:10.
- **Continue**: the main button and the A hint say Continue for a built game you have played, and favourites then games played in the last 30 days (newest first) lead every theme.
- **Button hints in every theme**: A, Y, X, L R Filter, ZL ZR Theme, + Menu and B along the foot, with the connected pad's own symbols; Trailer's panel adds R3 Mute and the right stick for Volume, and Watch shows them too. The TV offer's "Always" and "Never ask" have X and Y.
- **Smoother changes of game**: one 0.55 s fade for art, caption, colour and trailer on every theme; a trailer's sound fades in as its picture does, glides between Browse and Watch levels, and fades out when you move on instead of stopping dead.
- **Details on rest**: a moment after the focus rests on a game, capsules fade in with when it was last played, its genre, players, size and Built (or what it needs); the same line is the pointer's tooltip on cards and covers. The game's store details are read as it rests.
- **Screensaver**: left alone 5 minutes (Settings › Theatre › Screensaver: 5 min, 15 min, Never), Theatre cycles the games' wide art with a slow drift and a dim clock and name that move corner to corner; any button, key or the pointer wakes it, and that press does nothing else. No trailers play in it, and after an hour the TV may sleep.
- **Reopens where you left it**: the theme, the filter and the game in focus are kept (the game only when you moved to it or played it), and Settings › Open on has Theatre.
- **The game's colour everywhere**: Cinema glows with it from the foot, Trailer's panel and Theatre's menu take a wash of it, and Gallery's ivory wall the faintest one behind the covers.
- Snapshot hooks: `NXC_FILTER`, `NXC_EDGES`, `NXC_THEATREMENU=edges`, `NXC_SAVER=1`, `NXC_VOLUME`.

## 0.19.7 (2026-11-18)

Theatre's Trailer theme rebuilt to Tom's Browse / Watch mock-up. Ships in NXForge 0.45.8.

- **Browse**: the focused game's trailer plays across the top two thirds, with "TRAILER • 00:24 / 01:32" and a speaker button at the top right. A dark panel under it holds the game's name, publisher, console and status, the main button (Play or the step the game needs) and Details on the left, and a strip of every game (favourites first, built or not) on the right; ← → move along it. The words never sit on the video.
- **Watch**: after 6 s with no input, or ↓, the panel and bar fade away and the trailer fills the screen, with only the game's name and ↑ Browse at the foot. Any button, or moving the pointer, brings Browse back, and that press does nothing else.
- **Sound**: 25 % while browsing, full while watching; S or the speaker mutes it.
- **No playable trailer**: the wide art drifts slowly, and Watch shows the store's screenshots in turn, a new one every 6 s.
- The trailer fades in a second after it starts (past YouTube's pause sign), YouTube's captions are turned off, and the trailer time comes from YouTube's player.
- Snapshot hooks: `NXC_THEATRE=trailer`, `NXC_WATCH=1` (sound is off while snapshotting).

## 0.19.6 (2026-11-18)

A test of video on Theatre. Ships in NXForge 0.45.7.

- **Trailer theme (test)**: a fourth Theatre theme (L/R or the Theatre menu) with Cinema's words and rows over the focused game's YouTube trailer, playing full bleed from 5 s in (past most trailers' opening logos), with sound at 60 %, looping back to 5 s. It starts once the focus rests on a game for about a second, fades in over the art once the picture moves, and stops while a game runs, a viewer is open or NXForge is in the background. A trailer whose owner only allows it on YouTube (Blazing Chrome's) is skipped for the game's next one; with none left the art stays. Snapshot hook `NXC_THEATRE=trailer` with `NXC_WAIT=<seconds>`.

## 0.19.5 (2026-11-18)

Eight small touches to the game page. Ships in NXForge 0.45.6.

- **Media row shows there is more**: the edge with more tiles beyond it fades out, and round arrows appear over the row's edges while the pointer is over it (a click moves three tiles).
- **Description and More details on one line**: the store's one-line pitch and More details now sit centred on the same line, on the page's edges like View all.
- **No repeated status under the title**: a game not built yet no longer says "Drive offline" (or Not built) under its name; the Build card below says it.
- **One separator under the title**: the store line uses the same dots as the line above ("Action, Arcade · 1–2 players · PEGI 7 · 3.6 GB") instead of slashes.
- **Smaller Trailer label**: a small dark label at the trailer's top left, clear of the logo trailers carry at their foot.
- **Fainter glow behind the box**: the game's colour behind the box on its page is much fainter, so it no longer muddies the key art.
- **Glass tab switch**: the selected Official media / Your captures tab is glass with a hint of the game's colour instead of a solid fill.
- **Hint bar line on the page's edges**: on a game's page the line above the button hints lines up with the page's other lines.

## 0.19.4 (2026-11-18)

Game page polish. Ships in NXForge 0.45.5.

- **Swipe through Media**: the row under Media now holds every trailer and screenshot, three across; a two-finger swipe on the trackpad (or a scroll wheel) moves along it and settles on a tile's edge. Switching between Official media and Your captures starts again at the first tile.
- **The header art reaches the line**: the game's wide art at the top of its page now runs all the way down to the line above Media at any window size (it stopped short of it, fading out above the line), softening into the line instead of fading out before it.

## 0.19.3 (2026-11-17)

The Battery preset keeps the choices you saved for a game. Ships in NXForge 0.45.4.

- **Saved choices win on battery**: Battery preset on battery (Settings › Launching) used to lower the frame rate, render scale, upscaling, HDR highlights and frame interpolation for a run on battery, whatever the game had saved. It now lowers only the ones still on the game's default; a frame rate (or any of the others) you set in Play options or the game's sidebar is kept. Turn the setting off to have no run-only changes at all.
- **The starting note says what changed**: "On battery: the Battery preset for this run (frame rate 30 fps, render scale 75 %)" instead of the bare line, and the setting's description says the same.

## 0.19.2 (2026-11-17)

Cheats live in each game's folder as Markdown. Ships in NXForge 0.45.2.

- **`cheats/` beside `media/`**: every game's cheats, from the Cheats card, Get Cheats or the game's sidebar, are written to `cheats/<build ID>.md` in the game's own folder (beside a built game's `media` folder; for a game not built yet, its files' folder when no other game shares it). One file per build: front matter with the title, title ID, build ID and version, then a `## Name` per cheat with its code in a ```` ```dmnt ```` block; ```` ```dmnt on ```` is a cheat switched on, ```` ```dmnt master ```` a master code. Text under a heading is a note NXForge keeps.
- **Both ways**: the engine still runs its Atmosphère copy in Application Support, kept in step. A file edited by hand (newer than NXForge's copy) is read back, switches included, and a Mac with no cheats for a game takes them from its folder. Synced when the library opens or changes, when a game ends, and on every change in the Cheats card; a running game is left alone. Show Folder in the Cheats card opens the game's cheats folder.
- The setting is now **Keep media and cheats in each game's folder** (Settings › Artwork), on by default.

## 0.19.1 (2026-11-17)

Theatre's Shelf theme becomes Gallery, to Tom's brief. Ships in NXForge 0.45.1.

- **Gallery** replaces Shelf: three covers on a plain ivory wall (no shelf, grain or vignette), the game in focus in the middle with a fine bronze outline, a small lift and a "Selected" marker, one neighbour either side, all inside their own region so nothing reaches the words on the left. The left column has the name (up to three lines), the platform, the time played when there is some, the status word and symbol when the game cannot play, and the main button. Covers keep their own proportions; a game with no cover shows its icon, sharp and no larger than it has pixels for, on a plain card with its name. Steps slide the covers in about 0.2 s (a fade with Reduce Motion) and nothing moves on its own. The foot shows Your collection with the real position, and Play, Details, Options, Menu and Back; themes switch from the menu. A narrow screen drops the neighbours before any text shrinks. A saved Shelf choice opens as Gallery.
- **The main button tells the truth** in every theme: Play, or the step that stops the game playing (Build, Choose Keys…, Check Again, Scan Again, as in docs/ux.md), the same word on the button and in the hints, and A does that step. Cinema no longer says Resume.

## 0.19.0 (2026-11-17)

Theatre: a full-screen front end for a TV. Ships in NXForge 0.45.0.

- **Theatre** replaces Couch Mode: the Theatre button in the top bar, Theatre in the menu bar (⇧⌘F), the command palette or the controller's Menu button on the converter pages open it. It moves the window to the TV (or keeps the screen it is on), goes full screen, hides the pointer and keeps the Mac and the TV awake; Leave Theatre puts the window back where it was.
- **Three themes**: Carousel, a lit 3D ring of your game cases on a reflective floor that turns to the game you pick, with the front case in the right stick's hands and a slow turn on its own when nobody touches it; Cinema, a full-screen hero image of the game with Continue playing, Favourites and a row per genre underneath; and Shelf, your cases stood on a stone shelf against a sunlit wall that takes the colour of the game in front, with its art washed through it and leaf shadows drifting over it. L and R switch theme, and the theme is remembered.
- **TV offer**: plugging in a TV (a screen named as one, or 88 cm wide or more) with a controller connected asks "Open Theatre on <TV>?" once per TV; Settings › Theatre can make it always open there or never ask. Unplugging the TV leaves Theatre.
- **Controller**: A plays (or opens the page of a game not built yet), Y the game's page, X Play options, − favourites, Menu the Theatre menu (themes, Settings, Leave Theatre), B the menu at Leave. The keyboard works too: arrows, Return, Space, Esc, M, [ and ].

## 0.18.1 (2026-11-17)

Discover is your games by genre, and takes the Library's place. Ships in NXForge 0.44.1.

- **Only your games**: Discover no longer lists the store's games. All games is every game in your games folder (and apps built from files outside it), and each genre lists the ones of yours in it, with a count beside it; only genres you have a game in are listed. The genres come from each game's store page, looked up once by title ID; a game the store does not list goes under Other.
- **The Library page is gone**: the top bar is Home, Discover and Converter. What the Library had is in Discover: Owned and Built with their counts, the All, Favourites, Switch 2, Switch and Not built yet filters, the square covers button, the status under every cover (Ready on Mac, Playing now, Building, Not built yet, Older engine), the cover menu, and the top bar's search. Home's See all opens All games, and Settings › Open on says Discover where it said Library (the saved setting is unchanged).
- **Controller**: A plays, X opens Play options, Y the game's page, − favourites, L and R step through All games and the genres (L from All games goes Home), B goes Home.
- The Wishlist, the store search, the Platform, Players, Library and Sort menus, and the store-game panel are removed with the store's games. wishlist.json is left where it was.

## 0.18.0 (2026-11-16)

A save manager. Ships in NXForge 0.43.0.

- **Saves page**: a new page beside Builds lists every built game's save, most recently saved first, with when it last saved, the Mac its newest snapshot came from, how many snapshots it has and their size, and whether the save has changed since the last one. The top shows the total and where snapshots are kept. Open a game for its Save snapshots card (restore, import, export, Git backup).
- **A snapshot after every session**: when a game quits with a changed save, a checked snapshot is made on its own (nothing is copied when the save did not change). The newest 10 of these stay for each game, counted apart from the ones made before a restore or a rebuild, so a run of sessions never pushes those out. On by default; Saves and Settings › Saves turn it off.
- **A snapshot folder of your choice**: snapshots can go to another drive, a NAS or iCloud Drive (`<folder>/<title ID>/`) so they survive the save's own drive. The ones already made can move there: each is copied, checked file by file against its record, and only then is the old copy put in the Trash. While that folder is away, new snapshots go beside the save, and both places are listed.
- **Undo Restore**: after a restore, the game's card offers to put back the save it replaced (and pressing it again goes forward to the restored one).
- Each snapshot records the Mac it was made on, shown in a new Mac column.
- Ideas from [RecompLauncher](https://github.com/elripalda/RecompLauncher)'s save backups (GPL-3.0); written fresh, no code taken.

## 0.17.0 (2026-11-16)

Discover, and square covers. Ships in NXForge 0.42.0.

- **Discover**: a new tab between Home and Library for browsing Switch and Switch 2 games from Nintendo's European store. Browse has All games, In your library and Wishlist; Genres lists Action, Adventure, Platformers, RPGs, Racing, Puzzles, Strategy, Sports, Fighting, Shooters, Party, Simulation, Arcade, Music, Board games and Lifestyle. Each game shows its square store art, its name and genres, with **In library** on the ones in your games folder (by title ID, else by name) and a heart on the ones on your Wishlist.
- **Filters and sort**: Platform (All, Switch, Switch 2), Players (Any, 1 player, 2+, 4+), Library (All, In library, Not in library) and Sort (Popular, the store's own ranking and the default; Newest; Title A–Z, over ranked games only), plus a search field. The grid loads more as you scroll; Newest leaves out games with no release date yet. The Wishlist keeps the order games were added under Popular.
- **The bar along the foot** names the game in focus with its genres, players and console, with Wishlist and View game. View game opens a game's page in your Library when you have it, else a panel with its wide art, publisher, year, genres, the store's description, Wishlist and Nintendo eShop (opens its store page).
- **Wishlist**: kept on this Mac only, in wishlist.json beside the settings. Y or the heart adds and removes a game.
- **Controller and keyboard**: the arrows walk the grid, A views the game, Y wishlists it, X opens its store page, L and R step through Browse and the genres, B goes back to Home.
- **Square covers**: Settings › Artwork › Square covers (or the square button beside the Library's filters) shows each game's square shop art instead of its box on Home and in the Library, so more fit in a row. The art is Nintendo Life's for download-only games, else the square picture of the game's entry on Nintendo's store, found by title ID (one search for 40 games at a time) or exact name, kept as <key>-square-store.jpg; a game with none falls back to its own icon. Every game in the library is looked up once (Look Again does it over); one with none is tried again after a week.
- Only the genre, the filters and what is typed go to the store; the pictures are cached on this Mac.

## 0.16.0 (2026-11-16)

Convert, Game Files and Builds to Tom's mock-ups. Ships in NXForge 0.41.0.

- **One top bar**: the NXForge name at the left, the Home / Library / Converter switch in the middle, Full Screen and Settings at the right; under the converter a hairline, then its pages as centred text tabs with the open one underlined. Health's count is red for a problem and amber for warnings, and hovering it names what is wrong; Toolchain carries an amber dot when a check fails. Game Files and Builds have their own search fields.
- **Convert is one card** read top to bottom: GAME (icon, name, "Nintendo Switch · Base game + update", its folder, keys, Change game…, "2 files" opening the file table, a Recent games menu), SAVE APP TO (the folder's name, then its drive and full path), Build options folded under one line that names the main choices (clean up build files, rebuild from scratch, an engine update), the app already built with Open app and Show in Finder, and a foot that says Ready to build with the space needed, the space free and about how long it takes, beside one Build Mac app button. Rebuild from scratch is now a switch in Build options (still asked once more). The game's wide art lies faintly behind the card and the room takes its colour. Build progress and the log come in under the card once a build starts.
- **Game Files is a table**: Game, Contents, Size and Status columns with a tick-all box, Platform and Status menus, Sort (click Game or Size to sort by them), "65 games" beside the title, Change folder… and Scan again at the right, Last scanned under the list. A bar along the foot shows the game in focus with Show in Finder, Details and the next step as the white button: Play a current build, Rebuild an old one, else Convert…; ticked games show the Build bar there instead. Continue playing moves to Home.
- **Builds is a list and a panel**: larger rows with Older engine labels and a lilac selection, "2 builds use an older engine" with Review… (show only them, or rebuild them all) under the list; the panel has the icon large, Ready to play, Play, Show in Finder, Game page, one line with when it was built, how long it took and the engine, Keep this build, Build details (files, location, steps and log) folded, and Rebuild… with Rebuild from Scratch in its menu.
- Snapshot hooks: `NXC_CONVERT=<name part>` puts that game on Convert without saving settings, `NXC_OPTIONS=1` opens Build options, `NXC_FOCUS=<name part>` focuses a Game Files row.

## 0.15.0 (2026-11-16)

The build in sight on every page, and the Library's Owned and Built. Ships in NXForge 0.40.0.

- **The build along the foot of the window**: while a game builds, a strip under every page (Home, the Library, a game's page and the converter's pages) names the game and shows the step, how many files are done, the time left and the percent, with View Build (the Convert page) and Stop. Games waiting in a batch build are counted beside the name. The Convert page shows the build itself, so the strip steps aside there; the Building capsule in the top bar is gone.
- **Owned and Built**: the Library has a pair beside its title, Owned (every game in your games folder) and Built (only the games built and ready to play on this Mac), each with its count, and the number of games on screen. The filters (All, Favourites, Switch 2, Switch, Not built yet) work inside either one; Ready to play is now Built. L and R walk Owned's filters, then Built's.
- **A status under every cover**: Ready on Mac (green) for a built game not played yet, how it was last played (green) after that, Building with its percent (amber), Not built yet (grey), and Older engine (amber) for a game built with an older NXForge, which still plays as it is.
- The game in focus has a short line in its colour under its name.
- **Home fits a shorter window**: the shelf's covers size to the room the headline leaves, so the names under them no longer run into the hints along the foot (they did in a window under about 1,000 points tall, and the build strip takes 60 more).

## 0.14.5 (2026-11-16)

Settings scrolls. Ships in NXForge 0.39.4.

- **The panel fits the window and scrolls**: Settings (the front end's slider button, or a controller's Menu button) was one tall card with no scroll, cut off at the top and foot of a smaller window. Its rows now scroll inside it with a visible scroll bar, by trackpad, mouse wheel or the keyboard (arrows, Page Up and Down, Space, Home and End).
- **Pinned header and foot**: Settings, Find a setting and Done stay at the top, and Games Folder…, Scan Again and Converter Settings… stay at the foot; a hairline shows when there is more above or below.
- **Section jumps**: Launching, Artwork, Building and On Open under the title scroll to their section, and the one in view is lit.
- **Find a setting** (⌘F): shows only the rows whose title or note has a word starting with what is typed; Esc clears it, then closes Settings.
- **A controller reaches every row**: Show a recap and Rest while a game runs join the rows a controller steps through, and the panel scrolls to keep the lit row in view. Open on has a note saying what it does.

## 0.14.4 (2026-11-16)

Game page to the Blaster Master Zero 2 mock-up. Ships in NXForge 0.39.3.

- **The store's facts under the name**: the console, publisher and release date on the first line, then genres, players, age rating and size, from the game's page on Nintendo's store (a game without store details keeps "Not played yet" or how it was last played).
- **Media across the page**: Official media and Your captures sit beside the Media title with View all at the right, and the three tiles span the page; a trailer has a red Trailer badge.
- **The pitch and More details**: the store's one-line pitch sits under the tiles, and More details opens About (the whole description and the facts table) below it, in place of the About column beside Media.
- A larger box, no View box link under it (the box viewer is Y, a click on View box in the hint bar, or the box's right-click menu), and every hint along the foot of the window can be clicked.

## 0.14.3 (2026-11-16)

Nintendo Life art. Ships in NXForge 0.39.2.

- **Wide art from Nintendo Life first**: each game's wide art (behind Home and its page) is the header art of its page on Nintendo Life, found by the game's name (a second between requests, done once per game; a game not found is looked for again after a week). Nintendo's European store is now the fallback, and its banner stays when Nintendo Life's picture is too small to enlarge well. Art already downloaded from the store is replaced on the next start.
- **One size for wide art**: every wide picture is kept at 2560 × 1280 (2:1, cut about its middle), the shape Home fills on a Mac's screen; the game page's banner shows a narrower band of the same picture.
- **eShop boxes made from the game's square art**: a download-only game (GameTDB's red "Nintendo eShop" stand-in, or no box at all) gets a box made from its square art on Nintendo Life: the console's red band across the top, the art full width, its name under it with the developer and the year it came out (from the same page). The shelf, the grid, the 3D box and the box viewer all show it; GameTDB's stand-in is kept beside it as `-front-eshop.jpg`. Settings › Artwork › Look again makes them again.
- The pictures stay on this Mac (the artwork folder and each game's `media` folder), as before.

## 0.14.2 (2026-11-16)

Less work on every redraw. Ships in NXForge 0.39.1.

- **Build records, play times and app details read once**: Home, the Library, Builds and the menus asked for the build records and the time played several times per redraw, and each time `builds.json` and `playtime.json` were read and decoded again; each built app's `Info.plist` was read again too, often on an external drive or a share. They are now kept while the file is unchanged (its date and size), and the app's own writes refresh them.
- **Build records written in one piece**: `builds.json` is written atomically, so a write cut off by a crash or a full disk can no longer lose every record.
- **Build times**: one date formatter for every build time (one was made per row per redraw), with fixed digits and a 24-hour clock whatever the Mac's region.
- `bundle.sh` keeps the drawn app icon in `app/.build` and reuses it while `make_icon.swift` is unchanged, so an install no longer compiles and runs the icon script each time.
- Three unused members removed.

## 0.14.1 (2026-11-15)

Cheats are easy to find, and work before a game is built. Ships in NXForge 0.38.2.

- **Cheats on the front end's game page**: the row along the foot of a game's page has a **Cheats** tile (how many are on, or Get cheats) that opens the game's cheats with Get Cheats, their switches and Show Folder. Before, the Cheats card was only on the converter's own game page, and only for a built game, so it could not be found from Home or the Library's covers.
- **Also in the menus**: **Cheats…** in a game's ⋯ menu and in the Library's game menu.
- **Before the first build**: a game not built yet looks its build up by the version its files hold (switch-cheats-db's version table), so its cheats can be fetched and switched on now; the build reads the same folder. The converter's game page shows the Cheats card for such a game too, and the card comes before Mods.
- Snapshot hook: `NXC_SHEET=cheats` (with `NXC_GAME`) opens the Cheats sheet, and a snapshot with a sheet pictures the sheet.

## 0.14.0 (2026-11-15)

Ten ideas from RetroReplay, an emulation front end by the same author: games say why they cannot play, a Health page, button symbols that match your controller, a launch screen that says why a game closed, Your Week and Random Pick on Home, a daily checked backup of NXForge's own data, and smarter searching. Ships in NXForge 0.38.0.

- **Status words instead of dimming**: a game without an app says why on its cover, in the Library's status line and on its page: **Not built yet**, **Keys needed** (no prod.keys saved or beside its files), **Drive offline** (its files are on a drive or share that is not connected) or **Files missing** (the folder the scan found it in has gone). The main button becomes the fix: Build, Choose Keys…, Check Again or Scan Again; a controller's A does the same.
- **Health page**: a new converter page lists what needs a look, most pressing first, each with what it means and one repair: the games folder or the keys file away, games that need keys, games whose drive is offline or whose files have gone, build records whose app has gone (Forget Them…, after asking), a last run that crashed (Show Log), saves only on this Mac, games built with an older NXForge, toolchain gaps, a drive under 12 GB free, and a backup that did not complete. Reading it changes nothing. Its tab shows how many problems and warnings there are.
- **Daily backup of NXForge's own data**: once a day the time played, settings with favourites, build records, the library list and your own covers are copied to `~/Library/Application Support/NXForge Converter/backups/<date>`, each copy read back and compared (SHA-256); the last 7 are kept. Health has Back Up Now, Show in Finder and Restore… for each copy; a restore copies what is there first.
- **Button symbols that match the controller**: the hints along the foot of the front end and the launch screen show the symbol printed on the connected pad's button (✕ and ○ on a PlayStation pad, the face letters where they really are on an Xbox or Nintendo pad, L1 or LB), from the system's own symbol names, so Confirm is never assumed to be "A". Without a controller they keep their letters.
- **Safer controller input**: a button still held when NXForge comes to the front (pressed to quit a game) does nothing until it is let go, and the pad does nothing while an alert, a sheet or a text field has the keyboard.
- **Launch screen states**: it says Getting it ready while shaders are copied, then Starting the game; past 12 seconds it says it is taking longer and why. A second press of Play while a game starts does nothing.
- **Why a game closed while starting**: a game that closes before its first picture leaves the launch screen up with what its log says (stopped by the GPU memory guard, stopped by macOS for memory, the engine could not start, a crash with its signal and last error, an error code), with Try Again, the step that helps (Play Options or Rebuild) and Show Log. A game that does not open says what macOS said.
- **Your Week and Random Pick on Home**: beside "Your games", seven small bars show the time played each day this week with the total and the number of games (a session over midnight counts on both days); Random Pick puts a built game you have not played this week in front of you, marked RANDOM PICK.
- **Smarter searching**: Go to Anything (⌘K), the front end's search and the Game Files and Builds searches fold case and accents ("pokemon" finds Pokémon), match words in any order and pass over a leading "The"; ⌘K ranks a title that starts with what you typed first, then a later word, then the game played last, and with nothing typed lists the five games played most recently. On the Game Files page, letters typed quickly jump to the first game starting with them, as in Finder.
- **UX rules**: `docs/ux.md` writes down how the app behaves (selecting and playing, status words, launch states, repairs, controllers, writing), linked from AGENTS.md.

## 0.13.4 (2026-11-15)

Each built game keeps its media and details in its own folder. Ships in NXForge 0.37.4.

- **`media/` beside the app**: a built game's folder (the one holding its `.app`) gets a `media` folder with the covers NXForge shows (`cover-front`, `cover-back`, `cover-spine`; your own cover as `.png`, a downloaded one as `.jpg`), the wide art (`wide-art.jpg`), the game's icon, the store's screenshots (`screenshots/01.jpg` …), the trailers' pictures (`trailers/01.jpg` …) and a manual added in NXForge (`manual.pdf`). Trailers stay links; nothing extra is downloaded. When several apps share one output folder, the media goes in the game files' folder instead.
- **`media/game.md`**: Markdown with YAML front matter that lists what NXForge knows about the game: title, title ID, console, version and update, publisher, game files, app and game folder, the build (date, NXForge version, engine commit, shaders, time), the play preset and changed settings, time played, the store's details (page, release date, genres, players, rating, size, languages, play modes, description), the screenshots with their sources and the trailers' links. Below the front matter the same reads as a page, with the cover and screenshots shown.
- **Kept in step**: written after every build and a moment after covers, wide art, store details or playtime change, so a new own cover, Go Back to the Downloaded Covers or a removed manual shows in the folder too. Only the files NXForge writes there are replaced or removed; anything else you put in `media/` is left alone. A drive that cannot be written is skipped until NXForge starts again.
- **Read back**: on a Mac that has no artwork or store details for a game yet (a new Mac, the artwork folder emptied), the library takes the covers, wide art, store details, screenshots, trailers and manual back from the game's `media` folder instead of downloading them.
- **Settings › Artwork › Keep media in each game's folder** turns it off (on by default); the game menu has **Show Media Folder**.

## 0.13.3 (2026-11-15)

"Remove build cache" leaves nothing of the build beside the game. Ships in NXForge 0.37.3.

- **The build folders go after a build**: with Settings › Builds › After a build set to Remove build cache, the build script deletes the unpacked game and shaders but keeps `<id>_build/logs` and `profile/`, a provisional profile's `<id>_survey`, and the app's pack key (`<name>.app.key`) beside the app, so a Blazing Chrome build looked as if nothing had been cleaned. Once the build succeeds the converter now moves the logs to `~/Library/Logs/NXForge/<title ID>` (the Builds page, Copy log and the time estimates read them there) and removes the `_build` and `_survey` folders, the `.app.key`, and an emptied `NXForge Builds/<game>` folder. The game files, the keys and the app are never touched. The next build starts over, as before.

## 0.13.2 (2026-11-15)

Cleared builds no longer show as ready. Ships in NXForge 0.37.2.

- **A game is ready only while its app is there**: Home and the Library said "3 ready" after every build was cleared, because the saved library list remembered the app found beside each game's files at the last scan and the cover trusted it without looking. A game now counts as built only while its app exists, the saved list drops apps that have gone when it is read, and the library looks again whenever NXForge comes to the front, so a build deleted in Finder or by `nxforge clean` stops showing at once.

## 0.13.1 (2026-11-15)

The engine checkout no longer stays on an old release branch. Ships in NXForge 0.37.1.

- **Updates follows main once a release branch is done**: an engine checkout left on a release branch (`release-X.Y.Z`) with commits main never got followed only that branch, which never moves again, so the Updates page said "Up to date" at 0.30.2+2 with 0.37.0 out, and new games were built with the old engine. Once main has that release or a newer one, Check Now and Update follow main's newest release tag; the branch and its commits are left as they are. A release branch ahead of main's newest release is still followed.

## 0.13.0 (2026-11-15)

The app's side of the engine's 0.37.0. Ships in NXForge 0.37.0.

- **A game kept running behind the library**: a game built on NXForge 0.37.0 or later pauses and hides itself when you choose Library in its sidebar, instead of quitting. Its page and Home say "Paused · still running", Resume brings it back exactly where you left it, and Quit game ends it. Quit game is there for any running game.
- **Resume** brings a running game's own window back to the front; it no longer opens the app a second time.
- **Play options** shows the new settings where the game's own window has them: mouse camera, its speed and the microphone on General, and foliage, model detail and shadow detail on Graphics, for the games that have them.

## 0.12.3 (2026-11-15)

Box art from a link, and a shop's case picture cut down to its cover. Ships in NXForge 0.36.5.

- **Change Box Art** in a game's menu (right-click a box on Home or in the Library, or the ••• button on a game's page) gathers what was there: Choose Front Cover… and Choose Back Cover… (a picture file), and new **Front Cover from a Link…** and **Back Cover from a Link…**, which take a picture's web address (filled in when one is on the clipboard), download it once and keep it on the Mac like a chosen file. **Go Back to the Downloaded Covers** (was Remove My Covers) drops your own. Your covers are used on the shelf, in the grid, on the game's page and in the box viewer. Nothing is bundled or fetched beyond the link you give.
- **A shop's picture of the whole case** (a product render on a see-through background, the cover inside the case's plastic) is cut down to the printed cover: the see-through margin and the grey plastic rim go, so the cover no longer shows a case inside the case. A picture without see-through corners is kept as it is.

## 0.12.2 (2026-11-15)

A game's page closer to Tom's mock-up. Ships in NXForge 0.36.4.

- **Headline**: the box is smaller and sits beside the title, with **View box** (the box viewer) and Manual under it; the title has the console's mark and "Nintendo Switch · Not played yet" under it, and the preset line names the preset and one setting. The "In your library" line above the title is gone; the game's version shows when the pointer rests on the console line.
- **Key art as a banner**: the wide art fills the top right of the window only, as tall as the headline, fading to the left and into the line under it. The room's coloured light is dimmer on a game's page.
- **Media**: one section for pictures, with **From the store (n)** and **Your captures (n)** as a switch, a line that counts them (1 trailer · 4 screenshots), three large tiles (the trailer first, with a play button and a Trailer label) and **View all n** for the gallery. A game without the store's pictures shows your own screenshots alone.
- **About** beside Media on a wide window (under it on a narrow one): the store's pitch with **Read more** for the publisher's whole description, a table of Publisher, Released (11 Jul 2019), Players (1–2), Rating, Size and Genres, **More details** for play modes and languages, and a **Nintendo UK store** link.
- **Save, Playtime and Build** sit at the foot of the window, larger, the detail line moved into the pointer's tooltip.
- **Controller hints**: on a game's page Y now opens the box viewer (as R did), so the footer reads A Play, X Play options, Y View box, B Back. − still adds the game to Favourites.

## 0.12.1 (2026-11-15)

A game's box, pictures, trailers and manual, full screen. Ships in NXForge 0.36.2.

- **Box viewer**: the expand button under the box on a game's page (or R on a controller, Tab on the keyboard, View Box in a cover's menu) opens the game's box alone, full screen. Drag to turn it any way, pinch or scroll to zoom, double-click to stand it back up; Front, Spine, Back, zoom and Reset buttons; the arrow keys, + and −, and a controller's D-pad, right stick and shoulders work too.
- **The box, measured**: 105 × 170 × 10.5 mm like a real Switch case (it was 10 mm deep, with sharp corners). The printed cover now sits inside the case's plastic, which is see-through: clear on a Switch game, red on a Switch 2 game, with rounded corners, a gloss on its faces and a clear lip along the side that opens, where the edges of the cover and the inside of the case show through.
- **Gallery**: screenshots (the game's own and the store's) open in NXForge instead of Preview, full screen: arrows, a two-finger swipe or a drag go to the next one, pinch, the scroll wheel, a double-click or + and − zoom, a drag pans, and a strip along the bottom shows them all. View all opens every screenshot of the game. Esc or B closes it.
- **Trailers**: the game's trailer comes first in the store row and the gallery, with a play button, and plays full screen in the app. It is the one on the game's Nintendo UK store page: a video of Nintendo's on YouTube, played in YouTube's own embedded player (youtube-nocookie.com) with the requests that fetch and count ads blocked, or one of Nintendo's own video files, played by AVPlayer. Nintendo's older files were on a video network that has since shut down; those are skipped, and a game whose page has no trailer that plays gets the trailer from YouTube's search, only from Nintendo's channels or the game's publisher's.
- **Manuals**: a PDF beside the game's files (one with "manual" in its name, or the only PDF in a game's own folder) shows as a Manual button on the game's page and in the box viewer, and opens full screen, two pages side by side on a wide window, with arrows, a swipe or a controller to turn the pages and pinch to zoom. Add Manual… in a game's menu keeps a copy of any PDF as its manual.

## 0.12.0 (2026-11-14)

Cheats and mods from the app, and five things around a play session. Ships in NXForge 0.36.0. Several come from other nxnative front ends (README, Acknowledgements).

- **Get Cheats**: a game's page (Manage) has a Cheats card with this build's cheats and a switch each. Get Cheats looks the game and its build up in two public collections on GitHub (switch-cheats-db and NX-60FPS-RES-GFX-Cheats), lists what they have that you do not, and adds the ones you tick to the game's cheat file, switched off. A cheat that rewrites the game's instructions is marked "Changes game code" and is not ticked for you. When the collections only have codes for another version of the game, the card says so instead of adding codes that would not work. Nothing ships with NXForge: the files are fetched when you ask.
- **Mods**: a Mods card on the same page. Drop a folder or a zip, 7z or rar archive on it (or Add Mod…) and NXForge finds the game files inside, whichever layout the download uses, and installs it switched on. Each mod has a switch, arrows for its load order, and a warning that names the files two mods both replace and which one wins. A mod made for another game is refused by its title ID, and one that also patches the game's program is marked, since that part is not loaded. Changes apply at the next launch with no rebuild, and the game's sidebar shows the same mods.
- **Browse GameBanana**: the game's mods on GameBanana, a page at a time with search. Install downloads the mod's file, checks it against GameBanana's checksum and installs it like a dropped archive, with a link back to its page.
- **Rest while a game runs**: behind a running game, the window shows a plain "Playing" card and lets go of the covers and art it held, so the game has the memory. It comes back when you click it. Settings turns it off.
- **Recap when a game quits**: a card with how long you played this time and in total, the number of sessions and the game's peak memory, plus the frame rate when frame times were recorded. Each session's memory is kept with its playtime, and a game's page lists the last five sessions. Settings turns the card off.
- **Controller test** (Settings › Controllers): every connected controller with its buttons named as a Switch game reads them, both sticks, the triggers' travel, the battery, the gyro and a rumble test.
- **What NXForge Keeps** (Settings › Storage): the settings, artwork, logs, game data, preferences and command line tool NXForge and its games leave outside the games' folders, with sizes, to move to the Trash. Game data, which holds your saves, is not ticked for you.

## 0.11.7 (2026-11-14)

A game's compiled shaders, kept on this Mac. Ships in NXForge 0.35.7.

- **Keep shaders on this Mac** (Settings › Launching, on): Play copies a game's pipeline archive (`Contents/Resources/pso`) from another drive to `~/Library/Caches/NXForge/pso/<game>` and starts the game with `DM_PSO_BUNDLE` on the copy. Metal maps an archive on the internal disk (16 MB of footprint for Mario Kart World's 496 MB file) and reads one on any other volume into the game's memory (512 MB for the same file; 4.4 GB and 7 to 11 s a start for Ocarina of Time). The launch screen says "Copying its shaders to this Mac", once per build of the game: a rebuild changes the folder and the copy is made again.
- **Not at the disk's expense**: no copy when it would leave the internal disk under 10 GB free (a banner says so and the game starts as before), and a copy whose game is gone from a connected drive is removed at the app's next start. A game on a drive that is not connected keeps its copy. Deleting the shader cache on the Storage page (`~/Library/Caches/NXForge`) removes the copies with it; the next Play makes them again.
- A game on the internal disk has nothing copied. A game opened from the Finder or the Dock, not through NXForge, starts as before.

## 0.11.6 (2026-11-14)

Store details and screenshots on a game's page. Ships in NXForge 0.35.6.

- **From the store**: under your own screenshots, a row of the game's official screenshots from the gallery of its page on Nintendo's European store (up to 12 kept, 1280 x 720 or larger; Mario Kart World has 37, Super Mario Odyssey 26, Blazing Chrome 4). Click one to open it.
- **About**: the store's one-line pitch and the publisher's description (More shows all of it), beside a card of the facts the store lists: publisher, release date, genres, players, age rating, size, play modes and languages, with a link to the store page.
- **Fetched when you open the game's page**, by title ID (else by exact name) through the same store search as the wide art, then the store page once; kept on this Mac in the covers folder's `store` folder and looked at again after 30 days (a game not found: after a week, or Look Again). Only the title ID or name is sent, with no cookies.
- **Settings › Artwork › Download store details** turns it off and hides the section.

## 0.11.5 (2026-11-14)

Wide game art from Nintendo's store. Ships in NXForge 0.35.5.

- **Each game's banner behind its page and Home**: the 2:1 banner a game's page on Nintendo's European store shares (the picture behind a link to it, 1600 px wide) now fills the top of the game's page and of Home, ahead of the newest screenshot. Games without one keep the screenshot, the blurred cover or the 3D case as before.
- **Found by title ID**: one search of the store's own product search (searching.nintendo-europe.com, what nintendo.com/en-gb uses) for every game's title ID at once, then a search by exact name for games it did not find. A new Switch 2 game with no banner yet gets the picture its store page shares (Ocarina of Time). 57 of the 60 games in the test library were found.
- **Polite and local**: each game is looked up once; the pictures are kept on this Mac beside the covers (`<title ID>-hero.jpg`) and never sent anywhere. A game with no art is looked for again after a week, or with Look Again. Only title IDs and names are sent, with no cookies.
- **Settings › Artwork** (was Covers) has **Download wide art** beside Download box art; turning it off hides the banners too.

## 0.11.4 (2026-11-14)

Covers that do not hold up a scroll. Ships in NXForge 0.35.4.

- **Smaller copies for the shelf and the grid**: a tile read its whole 864 x 1400 cover on the main thread at its first draw (about 4 ms each on an M4 Pro, so a new grid row of seven about 30 ms) and kept it whole. A tile now draws a copy no longer than 920 pixels, the grid's largest cover on a Retina screen, decoded on a background task; for the moment that takes it shows its plain case. 40 covers hold 72 MB instead of 167 MB. A game's own case on its page still uses the whole cover.
- **A cover's colour is read once**: the colour a game lights the stage and its focus ring with comes from a 64-pixel read of the cover (about 3 ms) and is kept between starts in `tints.json` beside the covers; a new or changed cover reads it again. A game without a cover still takes its icon's colour, which is not kept (a rebuild can change the icon).

## 0.11.3 (2026-11-14)

Your prod.keys, chosen once. Ships in NXForge 0.35.3.

- **Keys file in Settings**: Settings (on the stage, under Building, and the converter's Settings window, under Files & Folders) keeps one prod.keys for every build, rebuild, Rebuild all, Build Selected and the Library's Convert. It shows whether the file is found (with how many keys), missing (a drive not connected), unreadable or incomplete (no header_key).
- **Found for you**: while none is saved, NXForge looks in the usual places (your games folder and the folder above it, `~/.switch`, the Ryujinx and yuzu-style emulators' keys folders, Documents, Downloads, Desktop) and offers the one it finds with **Use This**.
- **Asked once**: a build or rebuild with no keys file asks for one (offering the one it found) and saves the answer, so the next build does not ask. The first keys chosen or dropped on Convert are saved too.
- The saved keys file now wins over a prod.keys in the game's folder, which is used only when none is saved or the saved one is not there. **Change Keys…** on Convert still picks other keys for one game.
- The command line follows: `NXForgeConverter --validate / --convert / --rebuild / --library` without a keys file use the saved one, and so does `nxforge build`.
- Only the file's location is saved. Its keys are read to check it and are never copied, logged or put in a report.

## 0.11.2 (2026-11-14)

A new look for Home, to match the game's page. Ships in NXForge 0.35.2.

- **The game in focus fills the room**: when it has a screenshot, the newest one spreads across the top of Home behind the headline and changes as you move along the shelf. A game with no screenshots keeps its 3D case on the right.
- **A cleaner headline**: the console and playtime on one line and when it was last played on the next, Play, Play options, **Details →** and the star, then what it starts with in one quiet line ("Balanced · 60 fps · Docked"), which opens Play options.
- **Your games** as a large heading with how many are ready and **See all**, and each cover on the shelf has the game's name and console under it.
- The controller legend has a divider above it on every screen.

## 0.11.1 (2026-11-14)

A new look for a game's page. Ships in NXForge 0.35.1.

- **The game's art fills the top of the page.** GameTDB has box art but no wide key art, so the page uses the game's newest screenshot, sharp, fading into the room below and darker on the left where the title stands. A game with no screenshots gets its front cover, enlarged and blurred. Reduce Transparency leaves it out.
- **A bigger headline beside the box**: the eyebrow, a much larger title, the console and when it was last played on one line, then Play and Play options, and the preset it starts with ("Balanced · 60 fps · …"), which opens Play options. Turn over sits under the box.
- **Screenshots as a row of three large shots** with **View all** (shows them in Finder). A game with none says where they come from.
- **Save, Playtime and Build as three columns** under a divider, each with its icon, the value, a detail line and a chevron that opens the game in the converter. Up to date carries a green tick. The controller legend has a divider above it.

## 0.11.0 (2026-11-14)

Ten improvements to the app. Ships in NXForge 0.34.0.

- **Quit to Library.** A game NXForge starts has **Library** beside Quit in its sidebar: press it twice and the game ends and NXForge comes to the front on that game's page. (Needs the game rebuilt with NXForge 0.34.0, which brings Sidebar 0.5.0.)
- **Play checks the cloud save.** Play from a cover goes straight into the game and now still compares this Mac's save with the cloud's first, asking only when both changed (or the cloud's file is slow to come). Before, only the game's own settings window ran that check. (Needs the game rebuilt.)
- **From the launch screen straight into the picture.** The game's window stays see-through until the game draws its first frame, so the turning case leads into the game with no empty black window between; the launch screen leaves at that moment. Games built before 0.34.0 hand over as soon as their window is on screen.
- **What's New reads the app's own notes.** The changelog is inside NXForge.app, so the sheet always describes the version you run, whatever branch the engine checkout is on.
- **Favourites.** The star beside Play (or F, or − on a controller) adds a game to Favourites: Home's shelf starts with them, the Library has a Favourites filter, and their covers carry a star. Home opens on the game you played last.
- **Marks on covers when a game needs a look**: its last run crashed, or its save is only on this Mac (no Cloud saves and no snapshot). The Library's line under the cover and the game's page say what it is and what to do; Update ready stays in the line under the cover.
- **Screenshots on a game's page**: the ones its sidebar took, newest first, from the game's own folder, the folder chosen in the sidebar or ~/Pictures/NXForge. Click to open; the menu shows one in Finder, copies or shares it.
- **Controller**: a held direction repeats, Settings works from a pad (up and down, A or left and right to change), − adds or removes a Favourite, and the hint bar says so.
- **Reduce Motion and Reduce Transparency**: with Reduce Motion the case does not sway or spin when turned over, covers do not tilt under the pointer and the starting bar glows instead of running; with Reduce Transparency the room shows the game's colour without its art and the Play options and Settings panels are solid.
- **Lighter on big displays**: the room's blurred art is blurred once, small, instead of the whole window every frame; the stage is composited as one layer; the 3D case stops drawing while NXForge is covered (a game in front of it) and uses lighter antialiasing on screens over 4K wide.

## 0.10.0 (2026-11-14)

A design pass over the whole app. Ships in NXForge 0.33.0.

- **The room is lit by the game's own art.** The cover of the game in focus, far out of focus, fills the stage behind everything, with its colour brightest top left; the corners fall away, a fine grain stops the big gradients banding, and the two lights drift slowly. Moving to another game fades one room into the next. The converter's pages sit in the same room, dimmer.
- **Cases look like cases.** A cover has the crease at its spine and light along its top edge, leans towards the pointer with a highlight under it, and in focus lifts inside a ring that glows in the game's colour. Home's shelf reflects its covers in the floor.
- **The 3D case stands on a floor that reflects it**, in a pool of its own colour with a second light behind it, on Home, on a game's page and while a game starts.
- **Covers drawn for games without box art** (Switch 2 games) use the game's icon as artwork across the whole cover, with the icon sharp on top, instead of an icon on a flat colour. An app built without an icon gets a controller symbol rather than the system's blank icon.
- **Real glass** for the top bar's tabs (the selection slides between them), the search field, the round buttons, the big buttons beside Play, and the Play options and Settings panels. The app's icon sits beside its name.
- **Type and detail**: small labels are set wide, titles tighter with a soft shade; the line under a game's name has a symbol for each fact; the preset in use is a chip in the game's colour; Play glows in it. Cards have a lit top edge and a symbol for what they hold; presets have symbols; the Library's filters show how many games each holds, and its covers fade out under the heading as they scroll.
- **Starting a game** shows its case turning in its own light over a bar with a light running along it.
- Buttons press in a little when clicked, in the converter's pages too. With Reduce Motion on, the lights stay still.

## 0.9.1 (2026-11-14)

One app, one look: the converter's pages take the library's. Ships in NXForge 0.32.1.

- **The converter is on the same stage as your games.** Its pages (Convert, Game Files, Builds, Storage, Toolchain, Updates) sit under the same top bar as Home and Library, on the same dark backdrop lit in the colour of the game you were on, so going to Converter changes the page and nothing else. The sidebar, its "NXForge · Game Conversion Toolkit" header, the window's toolbar and the painted banners are gone.
- **The pages are a row of capsules** under the top bar, like the Library's filters; Updates carries the number waiting. Toolchain's state ("Toolchain ready") is at the right of the row and opens Toolchain; a waiting update shows beside it.
- **The same pieces everywhere**: the Library's heavy page titles with each page's actions beside them (Scan Again, Measure Again, Rebuild All, the Builds filters), the white capsule for a view's main action and translucent capsules for the rest, translucent cards, white instead of blue for step numbers, the drop area and the log's tabs.
- **One search field**, in the top bar: games on Library and Game Files, builds on Builds.
- **Settings (the sliders button, or + on a controller) opens from the converter too**, with Converter Settings… (⌘,) for the build's own.
- **The converter's own Library page is named Game Files**, so there is one Library. It is the same page (⌘2).
- **The app is always dark**, like the stage. Settings › Appearance is gone.
- Fixed: opening Game Files on the game it showed last time could end the app ("ScrollViewProxy may not be accessed during view updates"), also at launch when Game Files was the last page.
- Couch Mode's sofa button is gone from Game Files (Home and Library are the couch now); View › Couch Mode (⇧⌘F) still works.

## 0.9.0 (2026-11-14)

The app is now **NXForge**, and it opens on your games. Ships in NXForge 0.32.0.

- **A library front end.** NXForge opens on **Home**: the game you played last with Play beside it, and a shelf of your built games. **Library** is every game as a box cover, with filters (All, Ready to play, Switch 2, Switch, Not built) and search; games not built yet are dimmed and A converts them. The dark stage is lit from the top left in the game's own colour.
- **Play goes straight into the game.** The game's own settings window stays closed (`--no-launcher`) and it starts with the options kept for it. NXForge shows the game's case while it starts, and comes back to the front when the game quits.
- **Play options live here, per game**: what the game's settings window offered (General, Graphics, Advanced, read from the game's own list, so each game shows only what it has), with **Battery**, **Balanced** (the tested defaults) and **Quality** presets on top. **Play** keeps them for next time; **Play once, don't keep** uses them for one run. A game you have not played yet shows its options once first. On battery, a run takes the Battery preset without changing what is saved (Settings turns both off).
- **Box art, front and back.** Covers are looked up on GameTDB by the game's name (only the cover's ID is sent) and kept in `covers` in the app's support folder; the wrap gives the back and the spine. A game it has no box for (Switch 2 games today, download-only games) gets a cover drawn from its icon and colours. Right-click a cover › Choose Cover… for your own picture.
- **A 3D case on the game page**: drag it, or use the right stick, to turn it all the way round; Turn over (Y) shows the back. The page also has what the game plays with, its save, playtime or last frame-time recording, and its build, with Rebuild, snapshots and the rest under ⋯ or Manage in Converter.
- **Made for a controller**: A plays, X opens Play options, Y details or turn over, B back, L/R switch tabs, + opens settings; the bar along the bottom shows what each button does on the screen you are on. The keyboard does the same (Return, O, Space, Esc, Tab).
- **A window by default, full screen from a button** in the top bar (or ⌃⌘F).
- **The converter is one tab away** (Converter in the top bar, ⇧⌘G; Games or ⌘G comes back), unchanged. Settings › When NXForge opens picks Home, Library or Converter.
- **The app is named NXForge.** `NXForge Converter.app` becomes `NXForge.app`: updating from the Updates page or `app/install.sh` replaces the old one, so there is still one app. Its settings, builds and tags (`converter-vX.Y.Z`) stay where they were.
- Fixed: a game's own option list (`launcher.json`) was read with the wrong key for each option's default, so the Library's game page never showed a game's real options.

Not in this release: the game's cloud save check only runs from its own settings window, so a straight-in Play skips it. For a game you sync that way, right-click its cover › Play with the Game's Own Settings Window, or turn off "Play goes straight into the game" in Settings.
## 0.8.0 (2026-11-14)

A rebuild that says what it will redo, and a rebuild from scratch. Ships in NXForge 0.31.1.

- **Rebuild from scratch.** A normal rebuild already reuses every step whose inputs have not changed (the unpacked game, the rewritten code, each shader, the pipeline archive) and redoes only the rest. **From scratch…** beside Preview build on Convert, **Rebuild from Scratch…** in the Game page's Rebuild menu, on a build's right-click menu and in the Build menu (⇧⌘R) reuses none of it: the game's build folder is emptied (its logs, a provisional profile and the run folder stay), so the game is unpacked and its shaders are translated again. It asks first, with how long a full build of that game takes. Your saves and the Metal cache all games share are kept. For a build that looks wrong after a normal rebuild. On the command line: `--rebuild <app> --scratch`.
- **Preview build lists every step.** The preview was a block of text that stopped at the first step to redo. It is now a list of the build's steps: reused, redone (with why, and how long the step took last time) or "only if a step above changes what it reads", with the total underneath. The app's packing counts as redone whenever a step before it is, and a shader step that runs again says whether the engine's shader chain changed (every shader is translated again) or not (shaders whose own inputs are unchanged come back from the cache).
- **The Older engine badge says what a rebuild costs**: "Older engine · quick rebuild" (only the player and the app are made again), "· shader rebuild" (the engine's shader chain changed, so every shader is translated again), "· partial rebuild" (the build's tools or the game's own profile changed) or "· full rebuild" (the build folder is gone), with the time from the last run of those steps where one is recorded. On the Library's covers, the Game page (also under Since this build) and Convert. It is read from the build folder and the engine's changed files without running anything; a changed layer patch counts for the engine files it really changes. Preview build stays the exact answer.

## 0.7.0 (2026-11-14)

Ten changes to how the converter looks and behaves, and every drive on Storage. Ships in NXForge 0.31.0.

- **The build on the sidebar.** While a build runs, the Convert row shows a ring filling with it and the time left ("1 h 12 m"), so it stays in sight from Library, Storage and the rest.
- **Storage is a real table.** Click a heading (Item, Size, Type) to sort by it and again to reverse, drag the edges to resize, click, ⌘-click or ⇧-click rows, ⌘A for all, ⌫ to delete. Right-click for Show in Finder, Copy Path and Delete; a double-click shows the item in Finder. Apps and game files can be picked too, and are left out of a delete.
- **Storage deletes can be undone.** Delete moves the item aside under a hidden name at once, and for 20 seconds Undo on the banner (or Edit › Undo, ⌘Z) puts it back; then it is deleted and the space is free. It never goes through the Trash, which would keep the space taken. Anything a quit leaves held is deleted at the next launch.
- **Delete buttons name the size**: "Delete 14 GB", "Move 3.2 GB to Trash" (Storage, a built app on Builds, Settings' Clear the build cache).
- **VoiceOver**: icon-only buttons have names (Show in Finder, More, Play, Clear Search and the rest), a cover reads as the game, its console and whether it is built, with Play or Convert, Select and Open Game Page as actions, and pass/fail marks say so. The sidebar and Storage's big number use text styles instead of fixed sizes.
- **Covers in any size, and by console.** A slider over the covers (and View › Bigger Covers ⌘+, Smaller Covers ⌘−; ⌘= works too) sets their size, kept between launches. Sort › Group by Console (or View › Group Library by Console) puts Switch 2 games and Switch games under their own headings; the arrow keys follow.
- **Banners instead of alerts** for what ended in the background: a deleted or freed item, a restored app or a failed restore, a game to quit before its save is changed, an update that has to wait for a build. They go by themselves, have Undo or Copy where it helps, and VoiceOver reads them.
- **Recent games on Convert**: the last five games chosen show under the drop area, one click to choose one again (an offline one says so; right-click to remove it).
- **A Dock menu**: right-click the Dock icon for the recently played games, each with Play, Rebuild, Game Page and Show in Finder, the build running now with Stop Build…, and Build for the chosen game.
- **Every drive on Storage**: a card with used and free space for each drive and share plugged in (USB, Thunderbolt, SD card, network share), not only the ones the games are on, marked External drive or Network share. It updates when a drive is plugged in or ejected; right-click to show it in Finder.
- **The window opens where it was**: the same page, the build picked on Builds and the game the Library was on, scrolled into view.

## 0.6.2 (2026-11-14)

Ships in NXForge 0.30.2.

- **The Delete button shows on delete questions again.** Questions that delete, stop or quit something (Storage's Delete… and Clean Up…, Move to Trash, Stop Build, Stop and Quit) drew their answer with Apple's red destructive style. In dark mode on macOS 26 and later that style puts a red label on a red fill (Apple FB20158292), and it could vanish completely: "Delete shared metal shader cache (14 GB)?" showed only Cancel. The answer is now the normal default button (Return still picks it), and the question shows the caution icon instead.

## 0.6.1 (2026-11-11)

Ships in NXForge 0.27.2.

- **The step tiles follow a Switch 2 game's build.** A .nup or dump build has no "Extract tools" or "extract" stage, so tiles 1 and 2 stayed unticked for the whole build, and the pipeline archive lit no tile. Unpacking or packing the game now ticks "Extract game files", "Extract tools" shows "Not needed" once a later step starts, and the pipeline archive lights "Package Mac app".
- **The time left counts the Mac shader stage.** Its summary ("Metal libraries: 9,807 reused, 33,041 compiled") was read as a reused stage, so the history left out the longest stage of a build (51 minutes for Ocarina of Time). Only a stage reused as a whole counts as reused now, and earlier records of a "reused" stage that took two minutes or more count as work.
- With NXForge 0.27.2's separate counts for the pipeline archive's batches and compute groups, "About 4 h 35 min left" for Ocarina of Time's archive is gone.

## 0.6.0 (2026-11-11)

Ships in NXForge 0.27.0.

- **A game's `DLC` subfolder counts.** The build now reads a subfolder named `DLC` or `DLCs` (any letter case) for the game's DLC, and the converter follows: the Convert page checks those files with the rest (shown as `DLC/<name>`), the Library counts them as the game's DLC instead of noting them as unused and offering to move them, and the build history's "Base game + 2 DLC" includes them. A base game or update put in that folder is flagged as not used, with Move Beside the Game still offered for it.

## 0.5.2 (2026-11-09)

Ships in NXForge 0.23.0.

- **Save snapshots follow a save kept off a non-APFS drive.** For a game whose folder is on an exFAT, FAT or HFS+ drive the launcher now keeps the save in the Library (NXForge 0.23.0), and the Saves tools look there too.

## 0.5.1 (2026-11-09)

Fixes for 0.5.0. Ships in NXForge 0.22.0.

- **A Switch 2 dump folder is read in seconds.** "Reading the game's container…" walked every file of the dump twice, one `stat` at a time, to size it: Mario Kart World's dump (411,696 files) on an exFAT drive took over five minutes. The game now shows as soon as its code and title are read, the Convert page says "measuring the game files…" while its size comes in the background, and that measure is one walk that gets each folder's sizes with its listing (`getattrlistbulk`): 18 s for the same dump. Choosing the game again reuses the measure while the folder is unchanged.
- **Check for updates survives a deleted branch.** An engine checkout whose remote fetches only named branches failed every check ("Check failed") once one of those branches was deleted on GitHub, since git refuses the whole fetch. The check now fetches again with every branch, and a failure shows git's own message.
- **No more 8-hour estimates for a big game.** A build's time left was scaled from other games' builds by size, however far apart: Bloodstained's 93 s for 47 MB made Mario Kart World's 24 GB look like 8 h 42 min. Only games within four times the size count now.
- **Get Upstream Now names every clashing patch.** When upstream's commits clash with NXForge's patches, the page listed only the last one the check reported (for example "0009-docs.patch: conflicts") although others clashed too. It now reads the whole report and lists each patch once.

## 0.5.0 (2026-11-09)

Ships in NXForge 0.21.0.

- **Get Upstream Now.** The Updates page's upstream line has a button that takes upstream nxnative's newest commits on this Mac, without waiting for an NXForge release. It first checks that every NXForge patch still applies to them; if one clashes, nothing changes and the page names the patches (NXForge has to update them first, which the daily sync does). If they all apply, the engine is assembled on upstream and the host unit tests run on it. The engine row then reads "+ upstream", games count as built on another engine until rebuilt, and **Back to <release>** returns to the release's engine. Updating the engine to a newer release ends it by itself.

## 0.4.1 (2026-11-08)

A fix for 0.4.0. Ships in NXForge 0.20.1.

- **Free space on network shares and non-APFS drives is read right.** macOS gives its "important usage" free space only for APFS volumes, so a game on an SMB share or an output folder on an exFAT drive read as 0.0 GB free: the converter asked "Build with too little free space?" and, during a build, could stop it as soon as it started. It now takes the plain free space there (the same as Finder and `df`), in the space check, the build's watch, Storage and save snapshots.
- **A game on a network share builds on a local drive.** macOS marks every file written to an SMB share as downloaded, so Gatekeeper killed the tools a build compiles for itself ("Apple could not verify nx_extract", exit -9 at the build ID lookup). For a game folder on a network share, the build folder (and the survey of a game without a profile) now goes to `NXForge Builds/<game folder>` in the output folder (or in ~/Documents when the output folder is on a share too), via the script's `--work-dir`; the game files are only read. Storage, the Builds page's times and the space check look there.
- **Each drive is checked for its own share of a build.** With the output folder on another drive, the build folder (beside the game files) and the app (in the output folder) are checked against their own drives, and the shared Metal cache against the home folder's, instead of the whole build against the game folder's drive. Changing the output folder checks again.

## 0.4.0 (2026-11-08)

For NXForge's new layout (an untouched nxnative engine plus NXForge's layer). Ships in NXForge 0.19.0.

- **Builds use the assembled engine.** Before a build, and in the tool check, the converter runs `scripts/layer.py assemble`, then builds in `tree/`. If assembling fails, the tool check says why and how to fix it.
- **Game notes, profiles and the library read the engine's files** from `tree/` (or `layer/files/` before the first assemble).
- **Updates:** "what changed" for a game understands a new engine pin and changed patches, the sidebar's version is read from its new place, and the upstream count is counted from the pinned commit.
- A checkout from before 0.19.0 still works as it did.

## 0.3.1 (2026-11-08)

A fix for 0.3.0. Ships in NXForge 0.18.1.

- **The pages in the sidebar can be clicked again.** 0.3.0's Updates count badge took the rows' tags, so the list could not select any page.

## 0.3.0 (2026-11-08)

One updater for everything. Ships in NXForge 0.18.0.

- **Updates page** (⌘6, and Help › Check for Updates…): the engine, the converter and the in-game sidebar side by side, each with its version, what is newer and its own Update button. The sidebar item shows how many updates wait.
- **The engine follows NXForge releases.** Check and Update go to the newest `vX.Y.Z` tag on main, never to a release PR merged but not tagged yet. Update fetches first and checks again afterwards, so the status says "Updated to 0.17.1" and then shows anything that landed meanwhile, instead of a stale "Updated". The page also says how many upstream nxnative commits NXForge has not merged yet (for information; they come with the next NXForge release).
- **A sheet at launch** when the converter or the engine has a newer release: what changed, with Update and Relaunch, Later and Skip This Version.
- **Update automatically** (on the Updates page or in the sheet): at launch and when the converter comes back to the front an hour or more after the last check, the engine and the converter update without asking, never while a build runs.
- **Sidebar in your games:** lists the built games whose sidebar is older than the engine's and rebuilds them one after another with Update Sidebar in N Games (their cached stages are reused). Kept builds are left alone.
- The capsule over the sidebar now opens the Updates page, and also appears for a new NXForge release.

## 0.2.1 (2026-11-08)

A fix for 0.2.0. Ships in NXForge 0.17.1.

- **No more hang at launch.** 0.2.0 stopped answering for 20 seconds or more each time it started: SwiftUI's menu bar item for build progress kept redrawing its button. The progress is now a plain status item, made only while a build runs (click it for the time left, the step, Show Log and Stop Build).

## 0.2.0 (2026-11-08)

Twenty improvements, some from other nxnative forks' ideas. Ships in NXForge 0.17.0.

- **What's New and updates:** this sheet, shown once after the converter changes; Help › Update NXForge Converter… rebuilds it from the engine checkout (or its update branch) and opens the new one, with an "available" capsule over the sidebar.
- **A new look for Library and Builds:** big headings over banners of their own (an aurora, a moonlit sea), glass filter chips, and a sort menu.
- **Covers:** the Library as a grid of game icons on their own colours, with Play or Convert on hover, a check for built games and a focus ring; or the list, as before.
- **A page per game:** double-click (or Return) on a game in the Library or Builds opens one page with everything about it over a backdrop tinted from its icon.
- **Launch settings** on the game page: the game's own settings window's choices (resolution, frame rate, controls and the rest), set without opening the game, and "Show this window at launch".
- **Playtime:** each session of a built game is timed while the converter is open, however the game was started; Continue Playing over the Library, Recently played order, and a weekly chart on the game page.
- **Is a rebuild worth it?** The engine commits since a build that touch what that game's build reads, its own profile's changes marked, with a verdict and how long the last build took.
- **NXForge notes:** the game's profile README (what it is, open issues) on the game page and on Convert before a long build.
- **Menu bar progress:** a build's percent in the menu bar, with the time left, the step, Show Log and Stop Build.
- **Notifications with actions:** Play and Show in Finder on a finished build; Show Log and Copy Error Summary on a failed one.
- **Build later:** Build selected tonight at 2:00, at a time, or once the Mac is on power; the Mac stays awake while it waits, the queue survives a quit, and games in it can be moved up, down or out.
- **Offline drives:** a games folder or game files on a drive or share that is away say so, with Mount (the address is remembered) and Locate Game Files…; Rebuild asks instead of failing.
- **Save import and export:** a save as one zip, or in from a zip, a folder or another Mac's save, with a side-by-side preview; checked and kept as snapshots both ways.
- **Git save backup:** with a repository chosen in Settings › Saves, a game's save is committed (and pushed, if chosen) each time the game quits, or from Back Up to Git Now.
- **Go to Anything (⌘K):** any game, built app, page or action by typing a few letters.
- **Controller and couch mode (⇧⌘F):** the covers full screen; the pad moves, A opens or plays, B goes back, X plays, Y previews, Menu leaves.
- **Undo for tidying:** moving a game into its own folder, or its update and DLC beside it, can be undone (Undo under the list, or ⌘Z); every move is logged.
- **Keyboard and preview:** arrow keys move between games, Space shows a quick preview (in Builds too), Return opens the game's page, ⌘[ goes back.
- **Performance history:** the game page charts every play session's frame rate, with Copy Report.
- **iPhone and iPad IPA:** Build › Build iPhone and iPad IPA… (⌥⌘B) builds the chosen game for iOS (`--platform ios`) and shows the .ipa to sideload.

## 0.1.0 (2026-11-07)

The first versioned converter: the app as it is in NXForge 0.15.0, now numbered on its own. Ships in NXForge 0.16.0.

- **Convert:** drop or choose a game folder, a Switch 2 `.nup` or a dump folder; keys are checked in under a second without showing any key; Build Mac app shows one bar with the time left, with the steps and a filterable log under Show details; Preview build lists which steps a rebuild would reuse.
- **Library:** every game under a games folder with its own name, icon, publisher and version, badges for plays / profile / older engine / newer update, Build selected as a queue with a free-space estimate, and one-click tidying of shared folders and loose DLC.
- **Builds:** every app built with its engine release, Rebuild and Rebuild all on older engines, previous builds kept as backups to restore, Keep this build, save snapshots, frame-time summaries and failure explanations with Copy error summary.
- **Toolchain:** each tool checked the way the script finds it, Fix and Set up (the converter's own Python), the engine's version with Check for updates and Update engine, and Copy diagnostics.
- **Storage:** build caches, older app copies, apps and the shared Metal cache with sizes and free space, and Clean Up; a build warns below 12 GB free and stops below 3 GB.
- **Mac app:** Settings window (⌘,), pages on ⌘1 to ⌘5, Build menu, Dock progress, guarded quit during a build, and the navy theme of the Convert, Toolchain and Storage pages.
