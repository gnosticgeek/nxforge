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
// The sidebar has just opened: Quit game starts unarmed again, so a press left armed before it closed needs its second press anew; main thread
void dm_qs_opened(void);
// The front end's side (front_mac.m), for the sidebar's Capture section: a screenshot, starting or stopping the recording, and whether one is running. Main thread
void front_qs_screenshot(void);
void front_qs_record(void);
int front_qs_recording(void);
// A short message over the top of the game picture for a moment (quick_settings_mac.swift): parent is the game view; main thread
void dm_qs_toast(void *parent, const char *msg);
// Controller and keyboard navigation (front_mac.m sends it while the sidebar is up): 1 up, 2 down, 3 left, 4 right (change the value), 5 activate, 6 close, 7 / 8 the previous / next section
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
