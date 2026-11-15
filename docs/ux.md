# NXForge UX rules

The rules every change to the NXForge app (`app/`) and the in-game sidebar follows, so the app behaves the same wherever a thread works on it. Taken from the UX principles of RetroReplay (an emulation front end by the same author) and fitted to NXForge. When a change needs to break one, change this page in the same pull request and say why.

## Selecting and playing

| Input | Does |
| --- | --- |
| Click | Selects the game (focus only) |
| Return, controller A (front end) | Plays it, or does the step that stops it from playing (see Status words) |
| Double-click | Plays from Home's shelf; opens the game's page from the Library |
| Space, controller Y | Shows details without playing |
| Context menu, controller X | Play Options and the other ways to start |
| Typing letters (Game Files page) | Jumps to the first game starting with them, as in Finder |
| ⌘K | Go to Anything: a game, a page or an action |

- Moving focus never opens a page or starts a game.
- Coming back from a game, a page or a relaunch puts focus back on the same game (by its title ID or app, never by its position in a list). If it has gone, the nearest one takes focus.
- A second press while a game is starting does nothing.

## Status words, not dimming

A game that cannot play says why, on its cover, in its status line and on its page, with its own symbol and words:

| Status | Means | The main button |
| --- | --- | --- |
| Not built yet | The files are there; no app yet | Build |
| Keys needed | A Switch game, and no prod.keys is saved or beside it | Choose Keys… |
| Drive offline | Its files are on a drive or share that is not connected | Check Again |
| Files missing | The folder the scan found it in has gone | Scan Again |

Dimming alone never says it. Colour alone never says it either: each status has a word and a symbol.

## Launching

A launch goes **preparing** (shaders copied to this Mac first) → **opening** → the game's first picture, when the launch screen leaves.

- No success toast or sound once a game is up: the game is the confirmation.
- Past 12 seconds the launch screen says it is taking longer and why that can happen.
- A game that closes before its first picture leaves the launch screen up with what happened (`LaunchDiagnosis`), Try Again, the step that helps, and Show Log. Never a spinner that just goes away.
- Only a session of 30 seconds or more counts as played, and the app says "time played" for what it timed, never an estimate.

## Problems and repairs

- Health lists what is wrong before anything changes. A repair runs only when its button is pressed, says what it touches, and asks first when it removes anything.
- Every error names the state and the next step. "Something went wrong" is never enough.
- NXForge's own data (time played, settings, favourites, build records, the library list, own covers) is copied and checked once a day. A restore copies what is there first.
- Names on disk are never the link between things: games are matched by title ID, apps by path recorded at build time, covers by title ID or normalised name.

## Controllers

- Button hints show the symbol printed on the connected pad's button (✕ on a PlayStation pad), from the system's own symbol names, never a letter assumed from position. Without a controller the hints keep their letters.
- A button already held when NXForge comes to the front (pressed to quit a game, say) does nothing until it is let go.
- The pad does nothing while a sheet, an alert or a text field has the keyboard.

## Home

- Never show an empty shelf or card: hide it until it has something.
- Home's extras (Your Week, Random Pick) appear only when there is play to count or more than one game to pick from.

## Writing

- British English. Buttons start with a verb ("Choose Keys…", "Scan Again", "Back Up Now"); an ellipsis when more is asked before it acts.
- Say "click", not "tap". Empty states say what to do next.
- Short sentences, plain words, the game's own name.

## Motion and access

- Motion explains where something went or confirms an action; with Reduce Motion it becomes a fade or nothing, and nothing depends on motion alone.
- Every control has an accessibility label; a cover's label includes its status.
- Liquid Glass gets a dark fill under it, and Reduce Transparency is honoured.
