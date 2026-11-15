# NXForge Converter changelog

The NXForge Converter (the Mac app under `app/`) has its own version, separate from NXForge's (UPSTREAM.md, Versions). Each release is a tag `converter-vX.Y.Z` and a GitHub release "NXForge Converter X.Y.Z". Since 0.9.0 the app itself is named NXForge (the library front end plus the converter); it shows this version under the NXForge name in the converter's sidebar and in About NXForge. The NXForge release that first ships a converter version is named in its entry.

What counts as the converter: everything under `app/` (the SwiftUI app, its tests, `bundle.sh`, `install.sh` and `make_icon.swift`).

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
