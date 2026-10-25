// Quick settings (quick_settings_mac.swift): the C side the SwiftUI sidebar sees (swiftc -import-objc-header), and the two calls front_mac.m makes into it.
#pragma once
#include "front.h"
#include "cheats.h"   // the host's cheats (dm_cheats_*), listed in the Cheats section
// The sidebar's view (an NSHostingView, retained: front_mac.m takes it with __bridge_transfer). game: the name the per-game settings keys carry (DM_GAME_NAME); mods_dir: this game's mods
// folder; mods_run: the mods this launch overlaid, one per line, NULL when DM_ROMFS_OVERLAY came from the environment. close: Resume game / the close button; fps: the counter setting changed
void *dm_qs_make(const char *game, const char *mods_dir, const char *mods_run, void (*close)(void), void (*fps)(void));
// Read the settings again (the Graphics menu may have changed the filter while the sidebar was closed); main thread
void dm_qs_refresh(void);
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
