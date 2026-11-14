// Quick settings (quick_settings_mac.swift): the C side the SwiftUI sidebar sees (swiftc -import-objc-header), and the two calls front_mac.m makes into it.
#pragma once
#include "front.h"
// The host's cheats (hle_cheats.c; dm.h has them with the rest of the engine, which needs the game profile this header goes without), listed in the Cheats section. Main thread
int dm_cheats_found(void);
int dm_cheats_ncheats(void);
const char *dm_cheats_build(void);
const char *dm_cheats_version(void);
const char *dm_cheats_dir_path(void);
int dm_cheats_nothers(void);
const char *dm_cheat_name_at(int i);
const char *dm_cheat_why_at(int i);
const char *dm_cheat_note_at(int i);
int dm_cheat_kind_at(int i);   // 0 a plain cheat, 1 a master code, 2 disabled, 3 a label
int dm_cheat_on_at(int i);
int dm_cheat_flags_at(int i);
void dm_cheat_toggle(int i);
void dm_cheats_reload(void);
int dm_cheats_master(void);
void dm_cheats_master_set(int on);
int dm_cheats_safe(void);
void dm_cheats_safe_restore(void);
enum { QS_CHEAT_LABEL = 1, QS_CHEAT_SECTION_START = 2, QS_CHEAT_SECTION_END = 4, QS_CHEAT_PAIR_ON = 8, QS_CHEAT_PAIR_OFF = 16, QS_CHEAT_ONCE = 32 };   // dm.h DM_CHEAT_* (front_mac.m checks they agree)
// The sidebar's view (an NSHostingView, retained: front_mac.m takes it with __bridge_transfer). game: the name the per-game settings keys carry (DM_GAME_NAME); mods_dir: this game's mods
// folder; mods_run: the mods this launch overlaid, one per line, NULL when DM_ROMFS_OVERLAY came from the environment. close: Resume game / the close button; fps: the counter setting changed
void *dm_qs_make(const char *game, const char *mods_dir, const char *mods_run, void (*close)(void), void (*fps)(void));
// Read the settings again (the Graphics menu may have changed the filter while the sidebar was closed); main thread
void dm_qs_refresh(void);
// The sidebar has just opened (pad: from a controller, which starts with a selection on the page): Quit and Restart start unarmed again, so a press left armed before it
// closed needs its second press anew; main thread
void dm_qs_opened(int pad);
// What drives the sidebar now, for its button legend: the keyboard (pad 0) or a controller (1), with that controller's SF Symbols for its choose, close, previous and next page
// buttons (NULL: as before); main thread
void dm_qs_input(int pad, const char *ok, const char *back, const char *prev, const char *next);
// The front end's side (front_mac.m), for the sidebar's Capture section: a screenshot, starting or stopping the recording, and whether one is running. Main thread
void front_qs_screenshot(void);
void front_qs_record(void);
int front_qs_recording(void);
// Restart game: whether this launch can (the app's launcher started it), and doing it (the host quits as ⌘Q does and the launcher starts it again). Main thread
int front_qs_can_restart(void);
void front_qs_restart(void);
// A short message over the top of the game picture for a moment (quick_settings_mac.swift): parent is the game view; main thread
void dm_qs_toast(void *parent, const char *msg);
// Controller and keyboard navigation (front_mac.m sends it while the sidebar is up): 1 up, 2 down, 3 left, 4 right (change the value, or move along a row), 5 activate, 6 close, 7 / 8 the previous / next page
void dm_qs_nav(int cmd);
// The Controls section's map (front_mac.m): assign the next key (pad 0, actions 0–20) or controller button (pad 1, 0–11) to an action (-1 cancels); what is waiting (-1, or action * 2 + pad);
// read the saved map again after the sidebar reset it
void front_qs_assign(int action, int pad);
int front_qs_assigning(void);
void front_qs_controls_reload(void);
// Where captures go (front_mac.m): the folder of the next screenshot (0) or recording (1); whether this game has a folder of its own; choose one (NULL: back to the default,
// Screenshots / Recordings in the game folder). Main thread
const char *front_qs_capture_folder(int video);
int front_qs_capture_custom(void);
void front_qs_capture_folder_set(const char *dir);
// The cheat's section (hle_cheats.c: the name of the [--SectionStart:…--] it is under, "" outside one), for the Cheats page's groups. Main thread
const char *dm_cheat_section_at(int i);
// Pause while open (General page): whether the game is paused now, and the switch (saved per game; applies at once while the sidebar is up). Main thread
int front_qs_paused(void);
void front_qs_pause_set(int on);
// The game's sound after a change to the volume, mute or "quieter while open" settings (front_mac.m reads them from the user defaults). Main thread
void front_qs_volume_apply(void);
// Full screen (Display section). Main thread
int front_qs_fullscreen(void);
void front_qs_fullscreen_toggle(void);
// The settings file (front_mac_settings_file.inc): this game's ("" when there is none) and my defaults; save the settings now as my defaults, or read my defaults into this game. Main thread
const char *front_qs_settings_path(void);
const char *front_qs_defaults_path(void);
int front_qs_defaults_exist(void);
void front_qs_defaults_save(void);
void front_qs_defaults_use(void);
// A screenshot or recording was saved (front_mac.m): the Capture page lists it. Main thread
void dm_qs_captures_changed(void);
// SHA-256 for the save backups' checks (quick_settings_mac.swift), from libSystem
#include <CommonCrypto/CommonDigest.h>
// This game's title ID (DM_GAME_ID, 16 hex digits). Any thread
const char *front_qs_title_id(void);
// A toast over the game picture (front_mac.m toast). Main thread
void front_qs_toast_text(const char *msg);
// GPU memory nearly full with the game slow (nvn_mtl.m guard_low_tick): a longer toast, and a note on the Performance page for the rest of the run. Main thread
void dm_qs_toast_long(void *parent, const char *msg, double seconds);
void dm_qs_gpu_memory_low(unsigned long long used_mb, unsigned long long low_mb);
// Quick-save slots (quick_settings_mac.swift SaveSlots): a clone of the committed save taken under the host's commit locks (hle_fs.c; -1 with errno on failure), and the
// Save Slots menu's save and load (load asks twice). Main thread
int dm_fs_clone_committed(const char *dir, const char *to);
void dm_qs_slot_save(int slot);
void dm_qs_slot_load(int slot);
// Hold to peek (Sidebar 0.5.0): while it is held (the header's eye button, the P key or a controller's top face button) the sidebar fades, the picture takes the whole window and the
// game runs; let go and the sidebar is back (paused again when that is on). front_qs_peek starts or ends one; dm_qs_peeked tells the sidebar, dm_qs_peek_glyph gives it the
// controller's symbol for that button (NULL: the keyboard's P). Main thread
void front_qs_peek(int on);
void dm_qs_peeked(int on);
void dm_qs_peek_glyph(const char *symbol);
// The saved settings put to work again after the sidebar put several back at once (Undo this session), as after the settings file is read while the game runs. Main thread
void front_qs_settings_reapply(void);
