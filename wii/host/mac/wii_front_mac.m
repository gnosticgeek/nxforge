// SPDX-License-Identifier: GPL-2.0-or-later
// NXForge's Wii and GameCube player: the window a converted Wii or GameCube game runs in. Dolphin (nxdolphin.dylib, built from
// wii/bridge by scripts/wii_engine.py) runs the game and draws it with Metal into a view of this window; this file is the Mac
// side: the window, the keyboard and controllers, and NXForge's own in-game sidebar (layer/files/dm/host/quick_settings_mac.swift,
// the same file the Switch and Game Boy Advance players build). The sidebar talks to its player through the C calls in
// quick_settings_mac.h; they are implemented here. front_qs_gba() answers 2, which the sidebar reads as a Wii or GameCube game.
// GPL-2.0-or-later because it loads Dolphin.
//
// The app bundle holds the player (Contents/MacOS/nxnative), Dolphin (Contents/Frameworks/nxdolphin.dylib), Dolphin's data
// (Contents/Resources/Sys) and Contents/Resources/wii/port.json, which names the disc image: the disc stays where it is.
// Saves (the Wii's NAND and the GameCube's memory cards), save states and screenshots live where a Switch game's do,
// ~/Library/Application Support/nxnative/<title ID>.
//
// NXWII_SNAPSHOT=<file.png> runs without showing anything: the game runs NXWII_SNAPSHOT_SECONDS (20), pressing Start and A now
// and then when NXWII_SNAPSHOT_INPUT=menus, then the window's picture is written to the file and the player quits (the
// conversion's trial run, and checks).
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <GameController/GameController.h>
#include <dlfcn.h>
#include <mach/mach_time.h>
#include <sys/clonefile.h>
#include "quick_settings_mac.h"

#define LOG(...) do { fprintf(stderr, "nxwii: " __VA_ARGS__); fputc('\n', stderr); } while (0)

// ---- Dolphin (wii/bridge/nxdolphin.mm) ----
enum { C_A, C_B, C_X, C_Y, C_Z, C_START, C_UP, C_DOWN, C_LEFT, C_RIGHT, C_L, C_R, C_LA, C_RA, C_MX, C_MY, C_CX, C_CY, C_MINUS, C_HOME, C_RECENTRE, C_N };
enum { NXD_SCALE, NXD_SHOW_FPS, NXD_MSAA, NXD_WIDESCREEN, NXD_ASPECT, NXD_VSYNC, NXD_ANISO, NXD_SPEED, NXD_REMOTE };
static struct {
    int (*abi)(void);
    int (*start)(void *view, const char *disc, const char *user);
    int (*tick)(void);
    void (*pause)(int);
    void (*input)(int port, int control, double value);
    void (*resize)(void);
    void (*volume)(int);
    void (*stop)(void);
    const char *(*error)(void);
    void (*set)(int key, int value);
    uint64_t (*frames)(void);
    int (*state_save)(const char *path);
    int (*state_load)(const char *path);
    int (*screenshot)(const char *path);
    void (*save_root)(const char *path);
} D;
static BOOL dolphin_load(NSString *path) {
    void *h = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (!h) { LOG("%s", dlerror()); return NO; }
#define SYM(f, n) if (!(*(void **)&D.f = dlsym(h, "nxdolphin_" n))) { LOG("nxdolphin.dylib has no %s", n); return NO; }
    SYM(abi, "abi") SYM(start, "start") SYM(tick, "tick") SYM(pause, "pause") SYM(input, "input") SYM(resize, "resize") SYM(volume, "volume")
    SYM(stop, "stop") SYM(error, "error") SYM(set, "set") SYM(frames, "frames") SYM(state_save, "state_save") SYM(state_load, "state_load") SYM(screenshot, "screenshot") SYM(save_root, "save_root")
#undef SYM
    if (D.abi() != 1) { LOG("nxdolphin.dylib speaks ABI %d, this player 1", D.abi()); return NO; }
    return YES;
}

static NSString *g_name, *g_id, *g_root, *g_disc;
static NSWindow *g_win;
static NSView *g_view, *g_game, *g_side;
static int g_open, g_peek, g_open_by_pad, g_snapshot, g_started, g_playing, g_paused;
static double g_kb[C_N], g_pad[2][C_N];

static double now_s(void) { static mach_timebase_info_data_t tb; if (!tb.denom) mach_timebase_info(&tb); return (double)mach_absolute_time() * tb.numer / tb.denom * 1e-9; }
static NSString *opt_key(NSString *what) { return [NSString stringWithFormat:@"DMQuickSettings.%@.%@", what, g_name]; }
static BOOL opt_bool(NSString *what, BOOL def) { id v = [NSUserDefaults.standardUserDefaults objectForKey:opt_key(what)]; return v ? [v boolValue] : def; }
static void toast(NSString *msg) { dm_qs_toast((__bridge void *)g_view, msg.UTF8String); }
static const char *keep(NSString *s) { static NSString *held[8]; static int at; held[at = (at + 1) % 8] = s ?: @""; return held[at].UTF8String; }

// ---- the picture settings the sidebar's Switch rows read (front.h): Dolphin draws its own picture, so they hold values and do nothing ----
static int g_fpfx, g_aniso_p, g_up, g_aa_p, g_edr, g_edrs = 50, g_interp, g_pixel, g_scan, g_scale, g_border; static float g_strength = 0.5f;
int mtl_present_filter(float *k) { if (k) *k = g_strength; return g_fpfx; }
void mtl_present_filter_set(int mode, float k) { g_fpfx = mode; g_strength = k; }
int mtl_aniso(void) { return g_aniso_p; }
void mtl_aniso_set(int n) { g_aniso_p = n; }
int mtl_present_upscale(void) { return g_up; }
void mtl_present_upscale_set(int on) { g_up = on; }
int mtl_present_aa(void) { return g_aa_p; }
void mtl_present_aa_set(int m) { g_aa_p = m; }
int mtl_present_edr(void) { return g_edr; }
void mtl_present_edr_set(int on) { g_edr = on; }
int mtl_present_edr_strength(void) { return g_edrs; }
void mtl_present_edr_strength_set(int s) { g_edrs = s; }
float mtl_present_edr_headroom(void) { return 1; }
int mtl_present_interp(void) { return g_interp; }
void mtl_present_interp_set(int m) { g_interp = m; }
int mtl_present_interp_active(void) { return 0; }
int mtl_present_pixel(void) { return g_pixel; }
void mtl_present_pixel_set(int m) { g_pixel = m; }
int mtl_present_pixel_active(void) { return 0; }
int mtl_present_pixel_grid(float *w, float *h, float *s) { (void)w; (void)h; (void)s; return 0; }
int mtl_present_scanline(void) { return g_scan; }
void mtl_present_scanline_set(int rows) { g_scan = rows; }
int mtl_present_scale(void) { return g_scale; }
void mtl_present_scale_set(int m) { g_scale = m; }
int mtl_present_border(void) { return g_border; }
void mtl_present_border_set(int m) { g_border = m; }
uint64_t mtl_present_count(void) { return g_started ? D.frames() : 0; }
void mtl_present_inset(float share) { (void)share; }
// the Performance page's frame times: the gaps between Dolphin's presents, sampled by the tick
static double g_times[254]; static int g_times_n, g_times_at; static double g_last_present; static uint64_t g_last_frames;
int mtl_present_times(double *ms, int max, double *age) {
    int n = MIN(max, g_times_n);
    for (int i = 0; i < n; i++) ms[i] = g_times[(g_times_at - n + i + 254) % 254];
    if (age) *age = g_last_present ? now_s() - g_last_present : 0;
    return n;
}

// ---- cheats: not yet for Wii and GameCube games ----
int dm_cheats_found(void) { return 0; }
int dm_cheats_ncheats(void) { return 0; }
const char *dm_cheats_build(void) { return ""; }
const char *dm_cheats_version(void) { return ""; }
const char *dm_cheats_dir_path(void) { return keep([g_root stringByAppendingPathComponent:@"cheats"]); }
int dm_cheats_nothers(void) { return 0; }
const char *dm_cheat_name_at(int i) { (void)i; return ""; }
const char *dm_cheat_why_at(int i) { (void)i; return ""; }
const char *dm_cheat_note_at(int i) { (void)i; return ""; }
int dm_cheat_kind_at(int i) { (void)i; return 0; }
int dm_cheat_on_at(int i) { (void)i; return 0; }
int dm_cheat_flags_at(int i) { (void)i; return 0; }
const char *dm_cheat_section_at(int i) { (void)i; return ""; }
void dm_cheat_toggle(int i) { (void)i; }
void dm_cheats_reload(void) {}
int dm_cheats_master(void) { return 1; }
void dm_cheats_master_set(int on) { (void)on; }
int dm_cheats_safe(void) { return 0; }
void dm_cheats_safe_restore(void) {}

// ---- saves, save states ----
// Dolphin's user folder for this game (its settings, shader cache and logs), and the saves apart from it where a Switch game's are, save/: the Wii's
// NAND in save/Wii, the GameCube's memory cards in save/GC. NXForge's save backups and snapshots take the save folder.
static NSString *user_dir(void) { return [g_root stringByAppendingPathComponent:@"dolphin"]; }
static NSString *save_dir(void) { return [g_root stringByAppendingPathComponent:@"save"]; }
int dm_fs_clone_committed(const char *dir, const char *to) { return clonefile(dir, to, 0); }   // Dolphin writes the NAND as the game saves
static NSString *state_path(int slot) { return [g_root stringByAppendingFormat:@"/states/state%d.sav", slot]; }
static void state_do(int slot, int load) {
    if (!g_playing) { toast(@"The game is still starting"); return; }
    NSString *p = state_path(slot);
    if (load && ![NSFileManager.defaultManager fileExistsAtPath:p]) { toast([NSString stringWithFormat:@"State %d is empty", slot]); return; }
    [NSFileManager.defaultManager createDirectoryAtPath:p.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    int was = g_paused;
    if (was) D.pause(0);   // Dolphin saves and loads states on its CPU thread, which a pause holds
    int ok = load ? D.state_load(p.fileSystemRepresentation) : D.state_save(p.fileSystemRepresentation);
    if (was) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ if (g_paused) D.pause(1); });
    toast(load ? (ok ? [NSString stringWithFormat:@"State %d loaded", slot] : @"The state could not be loaded")
               : (ok ? [NSString stringWithFormat:@"State %d saved", slot] : @"The state could not be saved"));
    if (g_open) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 600 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ dm_qs_refresh(); });
}

// ---- the sidebar's Wii settings (quick_settings_mac.swift gbaChoices 6 to 12) and the GBA calls it shares ----
int front_qs_gba(void) { return 2; }
int front_qs_gba_opt(int which) { (void)which; return 0; }
void front_qs_gba_opt_set(int which, int on) { (void)which; (void)on; }
int front_qs_gba_state(int slot, int op) {
    if (op == 0) return [NSFileManager.defaultManager fileExistsAtPath:state_path(slot)];
    state_do(slot, op == 2); return 1;
}
const char *front_qs_gba_sound(void) { return ""; }
// 6 Internal resolution (1, 2, 3, 4, 6), 7 Anti-aliasing (MSAA 1, 2, 4), 8 Aspect ratio (0 auto, 1 16:9, 2 4:3, 3 stretch), 9 Widescreen hack,
// 10 Texture filtering (-1 the game's own, 2 4x, 4 16x), 11 Wii Remote (0 upright with a Nunchuk, 1 sideways, 2 upright alone), 12 Speed limit (percent, 0 none)
static const int kDefaults[13] = {0, 0, 0, 0, 0, 0, 3, 1, 0, 0, -1, 0, 100};
static NSString *const kKeys[13] = {nil, nil, nil, nil, nil, nil, @"wiiScale", @"wiiMSAA", @"wiiAspect", @"wiiWide", @"wiiAniso", @"wiiRemote", @"wiiSpeed"};
static int g_val[13];
static void value_apply(int which) {
    if (!g_started) return;
    int v = g_val[which];
    switch (which) {
        case 6: D.set(NXD_SCALE, v); break;
        case 7: D.set(NXD_MSAA, v); break;
        case 8: D.set(NXD_ASPECT, v); break;
        case 9: D.set(NXD_WIDESCREEN, v); break;
        case 10: D.set(NXD_ANISO, v == 2 ? 2 : v == 4 ? 4 : -1); break;   // Dolphin's: 2 is 4x, 4 is 16x
        case 11: D.set(NXD_REMOTE, v); break;
        case 12: D.set(NXD_SPEED, v); break;
    }
}
int front_qs_gba_value(int which) { return which >= 6 && which < 13 ? g_val[which] : 0; }
void front_qs_gba_value_set(int which, int v) {
    if (which < 6 || which >= 13) return;
    g_val[which] = v; [NSUserDefaults.standardUserDefaults setInteger:v forKey:opt_key(kKeys[which])];
    value_apply(which);
}
static void values_load(void) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    for (int i = 6; i < 13; i++) { id v = [d objectForKey:opt_key(kKeys[i])]; g_val[i] = v ? [v intValue] : kDefaults[i]; }
}

// ---- the sidebar's player side (quick_settings_mac.h) ----
static NSString *capture_dir(int video) {
    NSString *own = [NSUserDefaults.standardUserDefaults stringForKey:opt_key(@"captureDir")];
    return own.length ? own : [g_root stringByAppendingPathComponent:video ? @"Recordings" : @"Screenshots"];
}
void front_qs_screenshot(void) {
    if (!g_playing) { toast(@"The game is still starting"); return; }
    NSString *dir = capture_dir(0); [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"yyyy-MM-dd 'at' HH.mm.ss";
    NSString *path = [dir stringByAppendingFormat:@"/%@ %@.png", [g_name stringByReplacingOccurrencesOfString:@"/" withString:@"-"], [f stringFromDate:NSDate.date]];
    if (!D.screenshot(path.fileSystemRepresentation)) { toast(@"The screenshot could not be saved"); return; }
    // Dolphin writes it at the next frame
    __block int tries = 0;
    __block void (^check)(void) = ^{
        if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
            toast([NSString stringWithFormat:@"Screenshot saved to %@ › %@", dir.stringByDeletingLastPathComponent.lastPathComponent, dir.lastPathComponent]); dm_qs_captures_changed(); check = nil; return;
        }
        if (++tries > 30) { toast(@"The screenshot could not be saved"); check = nil; return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), check);
    };
    check();
}
void front_qs_record(void) { toast(@"Recording is not in Wii and GameCube games yet"); }
int front_qs_recording(void) { return 0; }
void front_qs_compare(int on) { (void)on; }
void front_qs_slot_shot(const char *path, void (*done)(int ok)) { (void)path; if (done) done(0); }
int front_qs_replay(void) { return 0; }
void front_qs_replay_set(int on) { if (on) toast(@"Instant replay is not in Wii and GameCube games yet"); }
void front_qs_replay_save(void) { toast(@"Instant replay is not in Wii and GameCube games yet"); }
int front_qs_can_restart(void) { return 0; }
void front_qs_restart(void) {}
const char *front_qs_capture_folder(int video) { return keep(capture_dir(video)); }
int front_qs_capture_custom(void) { return [NSUserDefaults.standardUserDefaults stringForKey:opt_key(@"captureDir")].length > 0; }
void front_qs_capture_folder_set(const char *dir) {
    if (dir && *dir) [NSUserDefaults.standardUserDefaults setObject:@(dir) forKey:opt_key(@"captureDir")]; else [NSUserDefaults.standardUserDefaults removeObjectForKey:opt_key(@"captureDir")];
}
void front_qs_assign(int action, int pad) { (void)action; (void)pad; }
int front_qs_assigning(void) { return -1; }
void front_qs_controls_reload(void) {}
static NSArray<GCController *> *pads(void) {
    NSMutableArray *out = [NSMutableArray array];
    for (GCController *c in GCController.controllers) if (c.extendedGamepad) [out addObject:c];
    return out;
}
int front_qs_player(int p, char *name, int cap) {
    NSArray *ps = pads(); if (p < 0 || p >= (int)MIN(ps.count, 2)) return 0;
    GCController *c = ps[p];
    if (name && cap > 0) snprintf(name, (size_t)cap, "%s", (c.vendorName ?: @"Controller").UTF8String);
    return 2;
}
int front_qs_player_swap(int a, int b) { (void)a; (void)b; return 0; }
static void volume_apply(void) {
    if (!g_started) return;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    float v = [d objectForKey:opt_key(@"volume")] ? [d floatForKey:opt_key(@"volume")] : 1;
    if ([d boolForKey:opt_key(@"muted")]) v = 0;
    if (g_open && !g_peek && [d boolForKey:opt_key(@"duckOpen")]) v *= 0.25f;
    if (g_snapshot) v = 0;   // a trial run is silent
    D.volume((int)lrintf(fminf(fmaxf(v, 0), 1) * 100));
}
static void set_paused(int on) {
    if (on == g_paused) return;
    g_paused = on; memset(g_kb, 0, sizeof g_kb);
    if (g_started) D.pause(on);
}
int front_qs_paused(void) { return g_paused; }
static void sidebar_toggle(void);
void front_qs_pause_set(int on) { [NSUserDefaults.standardUserDefaults setBool:on != 0 forKey:opt_key(@"pauseOpen")]; if (g_open && !g_peek) set_paused(on != 0); }
void front_qs_suspend(void) { if (!g_open) sidebar_toggle(); set_paused(1); }
void front_qs_volume_apply(void) { volume_apply(); }
int front_qs_fullscreen(void) { return (g_win.styleMask & NSWindowStyleMaskFullScreen) != 0; }
void front_qs_fullscreen_toggle(void) { [g_win toggleFullScreen:nil]; }
const char *front_qs_settings_path(void) { return ""; }
const char *front_qs_defaults_path(void) { return ""; }
int front_qs_defaults_exist(void) { return 0; }
void front_qs_defaults_save(void) { toast(@"My defaults are not in Wii and GameCube games yet"); }
void front_qs_defaults_use(void) {}
const char *front_qs_title_id(void) { return keep(g_id); }
void front_qs_toast_text(const char *msg) { toast(@(msg)); }
void front_qs_live_changed(void) {}
void front_qs_settings_reapply(void) { values_load(); for (int i = 6; i < 13; i++) value_apply(i); volume_apply(); }

// The frame-rate counter: Dolphin's presents in the last half second, in the corner the sidebar chose
static NSTextField *g_fps_label; static NSTimer *g_fps_timer;
static void fps_counter(void) {
    BOOL on = opt_bool(@"fps", NO);
    [g_fps_timer invalidate]; g_fps_timer = nil;
    if (!on) { [g_fps_label removeFromSuperview]; g_fps_label = nil; return; }
    if (!g_fps_label) {
        g_fps_label = [NSTextField labelWithString:@""]; g_fps_label.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightSemibold];
        g_fps_label.textColor = NSColor.whiteColor; g_fps_label.drawsBackground = YES; g_fps_label.backgroundColor = [NSColor colorWithWhite:0 alpha:0.55];
        [g_view addSubview:g_fps_label positioned:NSWindowAbove relativeTo:g_game];
    }
    __block uint64_t n0 = mtl_present_count(); __block double t0 = now_s();
    void (^tick)(NSTimer *) = ^(NSTimer *t) {
        (void)t; double t1 = now_s(); uint64_t n1 = mtl_present_count();
        g_fps_label.stringValue = [NSString stringWithFormat:@" %.0f fps ", (double)(n1 - n0) / fmax(t1 - t0, 1e-3)]; n0 = n1; t0 = t1;
        [g_fps_label sizeToFit];
        int c = (int)MIN(MAX([NSUserDefaults.standardUserDefaults integerForKey:opt_key(@"fpsPos")], 0), 3); NSSize s = g_fps_label.frame.size; NSRect b = g_game.frame;
        [g_fps_label setFrameOrigin:NSMakePoint(c & 1 ? NSMaxX(b) - s.width - 10 : b.origin.x + 10, c & 2 ? 10 : b.size.height - s.height - 10)];
    };
    g_fps_timer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:tick]; tick(nil);
}

// The sidebar: 460 points down the window's right; the game's view moves aside for it, and Dolphin fits its picture to the rest
static void layout_game(void) {
    NSRect b = g_view.bounds; CGFloat w = MIN(460, b.size.width);
    g_game.frame = g_open && !g_peek && w < b.size.width ? NSMakeRect(0, 0, b.size.width - w, b.size.height) : b;
    if (g_started) D.resize();
}
static void sidebar_close(void) { if (g_open) sidebar_toggle(); }
static void sidebar_toggle(void) {
    if (!g_open) {
        if (!g_side) {
            NSString *mods = [g_root stringByAppendingPathComponent:@"mods"];
            g_side = (__bridge_transfer NSView *)dm_qs_make(g_name.UTF8String, mods.fileSystemRepresentation, NULL, sidebar_close, fps_counter);
            g_side.autoresizingMask = NSViewMinXMargin | NSViewHeightSizable;
        }
        CGFloat W = g_view.bounds.size.width, w = MIN(460, W);
        g_side.frame = NSMakeRect(W - w, 0, w, g_view.bounds.size.height);
        dm_qs_opened(g_open_by_pad); dm_qs_refresh();
        [g_view addSubview:g_side positioned:NSWindowAbove relativeTo:nil]; g_open = 1; layout_game();
        memset(g_kb, 0, sizeof g_kb); volume_apply();
        if (opt_bool(@"pauseOpen", YES)) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 80 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ if (g_open && !g_peek) { set_paused(1); dm_qs_refresh(); } });
    } else {
        set_paused(0);
        if (g_peek) { g_peek = 0; g_side.alphaValue = 1; dm_qs_peeked(0); }
        [g_side removeFromSuperview]; g_open = 0; layout_game(); volume_apply();
        [g_win makeFirstResponder:g_game];
    }
}
void front_qs_peek(int on) {
    if (!g_open || (on != 0) == g_peek) return;
    g_peek = on != 0; g_side.animator.alphaValue = on ? 0 : 1; layout_game(); volume_apply();
    set_paused(!on && opt_bool(@"pauseOpen", YES));
    dm_qs_peeked(on);
}

// ---- keyboard and controllers ----
// Keys (wii/README.md): arrows the main stick and D-pad, X A, Z B, S X, A Y, Return Start, Q L, W R, E Z, Tab Remote −, H Remote Home
static int key_control(unsigned short code) {
    switch (code) {
        case 7: return C_A; case 6: return C_B; case 1: return C_X; case 0: return C_Y;
        case 36: return C_START; case 12: return C_L; case 13: return C_R; case 14: return C_Z; case 48: return C_MINUS; case 4: return C_HOME;
    }
    return -1;
}
static BOOL typing(void) { return [g_win.firstResponder isKindOfClass:NSTextView.class]; }
static NSEvent *key_event(NSEvent *e) {
    BOOL down = e.type == NSEventTypeKeyDown; unsigned short c = e.keyCode;
    if (e.modifierFlags & NSEventModifierFlagCommand) return e;
    if (g_open) {
        if (typing() && c != 53) return e;
        if (c == 35) { if (!e.isARepeat) front_qs_peek(down); return nil; }
        if (!down) return nil;
        int cmd = c == 126 ? 1 : c == 125 ? 2 : c == 123 ? 3 : c == 124 ? 4 : c == 36 || c == 49 ? 5 : c == 53 ? 6 : c == 48 ? (e.modifierFlags & NSEventModifierFlagShift ? 7 : 8) : 0;
        if (cmd) { g_open_by_pad = 0; dm_qs_input(0, NULL, NULL, NULL, NULL); dm_qs_nav(cmd); }
        return nil;
    }
    if (c == 53) { if (down && !e.isARepeat) { g_open_by_pad = 0; sidebar_toggle(); } return nil; }
    double v = down ? 1 : 0;
    switch (c) {   // the arrows are the D-pad and the main stick (the Nunchuk's stick)
        case 126: g_kb[C_UP] = v; g_kb[C_MY] = v ? 1 : (g_kb[C_DOWN] ? -1 : 0); return nil;
        case 125: g_kb[C_DOWN] = v; g_kb[C_MY] = v ? -1 : (g_kb[C_UP] ? 1 : 0); return nil;
        case 123: g_kb[C_LEFT] = v; g_kb[C_MX] = v ? -1 : (g_kb[C_RIGHT] ? 1 : 0); return nil;
        case 124: g_kb[C_RIGHT] = v; g_kb[C_MX] = v ? 1 : (g_kb[C_LEFT] ? -1 : 0); return nil;
    }
    int k = key_control(c); if (k < 0) return e;
    g_kb[k] = v;
    if (k == C_L) g_kb[C_LA] = v;
    if (k == C_R) g_kb[C_RA] = v;
    return nil;
}
// A controller laid out as GameCube pad by letter: A, B, X, Y the same letters; the triggers L and R (pressed part way, analog); the right shoulder Z;
// Menu Start; the left shoulder and Options the Remote's −; the left stick pressed the Remote's Home; the right stick pressed re-centres the pointer. Home opens the sidebar.
static void pad_read(GCExtendedGamepad *p, double *o) {
    memset(o, 0, sizeof(double) * C_N);
    if (!p) return;
    o[C_A] = p.buttonA.pressed; o[C_B] = p.buttonB.pressed; o[C_X] = p.buttonX.pressed; o[C_Y] = p.buttonY.pressed;
    o[C_Z] = p.rightShoulder.pressed; o[C_START] = p.buttonMenu.pressed; o[C_MINUS] = p.leftShoulder.pressed || p.buttonOptions.pressed;
    o[C_HOME] = p.leftThumbstickButton.pressed; o[C_RECENTRE] = p.rightThumbstickButton.pressed;
    o[C_UP] = p.dpad.up.pressed; o[C_DOWN] = p.dpad.down.pressed; o[C_LEFT] = p.dpad.left.pressed; o[C_RIGHT] = p.dpad.right.pressed;
    o[C_LA] = p.leftTrigger.value; o[C_RA] = p.rightTrigger.value; o[C_L] = p.leftTrigger.value > 0.9; o[C_R] = p.rightTrigger.value > 0.9;
    o[C_MX] = p.leftThumbstick.xAxis.value; o[C_MY] = p.leftThumbstick.yAxis.value; o[C_CX] = p.rightThumbstick.xAxis.value; o[C_CY] = p.rightThumbstick.yAxis.value;
}
static void input_push(void) {
    if (!g_started) return;
    for (int port = 0; port < 2; port++)
        for (int i = 0; i < C_N; i++) {
            double v = g_pad[port][i];
            if (port == 0 && fabs(g_kb[i]) > fabs(v)) v = g_kb[i];
            if (g_open && !g_peek) v = 0;
            D.input(port, i, v);
        }
}
static void pad_poll(void) {   // main thread, 120 times a second
    static uint32_t was; static double held_since, last_rep;
    NSArray<GCController *> *ps = pads();
    for (int port = 0; port < 2; port++) pad_read(port < (int)ps.count ? ps[port].extendedGamepad : nil, g_pad[port]);
    GCExtendedGamepad *p = ps.firstObject.extendedGamepad;
    uint32_t all = 0;
    if (p) {
        float x = p.leftThumbstick.xAxis.value, y = p.leftThumbstick.yAxis.value;
        if (p.dpad.up.pressed || y > 0.5f) all |= 1; if (p.dpad.down.pressed || y < -0.5f) all |= 2;
        if (p.dpad.left.pressed || x < -0.5f) all |= 4; if (p.dpad.right.pressed || x > 0.5f) all |= 8;
        if (p.buttonA.pressed) all |= 16; if (p.buttonB.pressed || p.buttonMenu.pressed) all |= 32;
        if (p.leftShoulder.pressed) all |= 64; if (p.rightShoulder.pressed) all |= 128;
        if (p.buttonHome.pressed) all |= 1 << 16;
        if (p.buttonY.pressed) all |= 1 << 17;
    }
    uint32_t pressed = all & ~was; was = all;
    if (!g_open) { if (pressed & (1 << 16)) { g_open_by_pad = 1; sidebar_toggle(); } input_push(); return; }
    if (pressed & (1 << 16)) { sidebar_toggle(); input_push(); return; }
    int peek = (all >> 17) & 1; if (peek != g_peek) front_qs_peek(peek);
    if (pressed) dm_qs_input(1, "a.circle", "b.circle", "l1.rectangle.roundedbottom", "r1.rectangle.roundedbottom");
    double t = now_s(); uint32_t dirs = all & 15, go = pressed;
    if (dirs && !(pressed & dirs)) { if (t - held_since > 0.4 && t - last_rep > 0.09) { go |= dirs; last_rep = t; } } else held_since = t;
    if (go & 1) dm_qs_nav(1); else if (go & 2) dm_qs_nav(2); else if (go & 4) dm_qs_nav(3); else if (go & 8) dm_qs_nav(4);
    if (pressed & 16) dm_qs_nav(5); else if (pressed & 32) dm_qs_nav(6);
    if (pressed & 64) dm_qs_nav(7); else if (pressed & 128) dm_qs_nav(8);
    input_push();
}

// ---- the window ----
@interface GameView : NSView
@end
@implementation GameView
- (BOOL)acceptsFirstResponder { return YES; }
- (void)keyDown:(NSEvent *)e { (void)e; }
- (void)keyUp:(NSEvent *)e { (void)e; }
@end
@interface Container : NSView
@end
@implementation Container
- (void)resizeSubviewsWithOldSize:(NSSize)s { [super resizeSubviewsWithOldSize:s]; layout_game(); }
- (void)viewDidChangeBackingProperties { [super viewDidChangeBackingProperties]; if (g_started) D.resize(); }
@end
@interface OffscreenWindow : NSWindow
@end
@implementation OffscreenWindow
- (NSRect)constrainFrameRect:(NSRect)r toScreen:(NSScreen *)s { (void)s; return r; }
@end

static void quit_now(void);
@interface App : NSObject <NSApplicationDelegate, NSWindowDelegate>
@end
@implementation App
- (void)state:(NSMenuItem *)it { state_do((int)(it.tag % 10), it.tag >= 10); }
- (void)sidebar:(id)s { (void)s; g_open_by_pad = 0; sidebar_toggle(); }
- (void)shot:(id)s { (void)s; front_qs_screenshot(); }
- (void)full:(id)s { (void)s; front_qs_fullscreen_toggle(); }
- (void)windowDidResignKey:(NSNotification *)n { (void)n; memset(g_kb, 0, sizeof g_kb); }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)a { (void)a; return YES; }
- (void)applicationWillTerminate:(NSNotification *)n { (void)n; quit_now(); }
@end
static void quit_now(void) {
    static int done; if (done) return; done = 1;
    if (g_started) { if (g_paused) D.pause(0); D.stop(); }   // joins emulation and writes the memory cards
    NSDictionary *run = @{@"frames": @(g_last_frames), @"ended": @((long long)NSDate.date.timeIntervalSince1970)};
    [[NSJSONSerialization dataWithJSONObject:run options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[g_root stringByAppendingPathComponent:@"last-run.json"] atomically:YES];
}

static void menus(App *app) {
    NSMenu *bar = [NSMenu new];
    NSMenu *am = [NSMenu new]; NSMenuItem *ai = [bar addItemWithTitle:@"" action:nil keyEquivalent:@""]; ai.submenu = am;
    [am addItemWithTitle:[@"Hide " stringByAppendingString:g_name] action:@selector(hide:) keyEquivalent:@"h"];
    [am addItemWithTitle:[@"Quit " stringByAppendingString:g_name] action:@selector(terminate:) keyEquivalent:@"q"];
    NSMenu *gm = [[NSMenu alloc] initWithTitle:@"Game"]; NSMenuItem *gi = [bar addItemWithTitle:@"Game" action:nil keyEquivalent:@""]; gi.submenu = gm;
    NSMenuItem *it;
    it = [gm addItemWithTitle:@"Sidebar" action:@selector(sidebar:) keyEquivalent:@"g"]; it.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift; it.target = app;
    it = [gm addItemWithTitle:@"Screenshot" action:@selector(shot:) keyEquivalent:@"s"]; it.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift; it.target = app;
    it = [gm addItemWithTitle:@"Full Screen" action:@selector(full:) keyEquivalent:@"f"]; it.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl; it.target = app;
    [gm addItem:NSMenuItem.separatorItem];
    for (int load = 0; load < 2; load++) for (int n = 1; n <= 3; n++) {
        it = [gm addItemWithTitle:[NSString stringWithFormat:load ? @"Load State %d" : @"Save State %d", n] action:@selector(state:) keyEquivalent:[NSString stringWithFormat:@"%d", n]];
        it.keyEquivalentModifierMask = NSEventModifierFlagCommand | (load ? NSEventModifierFlagOption : 0); it.tag = load * 10 + n; it.target = app;
    }
    NSApp.mainMenu = bar;
}

// The tick: Dolphin's host jobs, whether the game has started or stopped, and the frame times
static void tick(void) {
    if (!g_started) return;
    int s = D.tick();
    if (s == 1 && !g_playing) { g_playing = 1; LOG("playing"); }
    uint64_t f = D.frames();
    if (f != g_last_frames) {
        double t = now_s();
        if (g_last_present) { g_times[g_times_at] = (t - g_last_present) * 1000 / (double)(f - g_last_frames); g_times_at = (g_times_at + 1) % 254; if (g_times_n < 254) g_times_n++; }
        g_last_present = t; g_last_frames = f;
    }
    if (s == 3) {
        const char *err = D.error();
        if (err && *err) LOG("stopped: %s", err);
        g_started = 0; [NSApp terminate:nil];
    }
}

// NXWII_SNAPSHOT: run a while with the menus pressed through, then a picture into a PNG, a line of JSON, and quit. The picture is the game's own
// frame (Dolphin's screenshot, at the internal resolution), or with NXWII_SNAPSHOT_SIDEBAR=<page> the window with the sidebar open on that page
static void snapshot_done(NSString *out, BOOL ok) {
    int n = MIN(g_times_n, 120); double sum = 0, fps = 0;
    for (int i = 0; i < n; i++) sum += g_times[(g_times_at - n + i + 254) % 254];
    if (n && sum > 0) fps = 1000.0 * n / sum;
    printf("{\"snapshot\": %s, \"playing\": %s, \"frames\": %llu, \"fps\": %.1f}\n", ok ? "true" : "false", g_playing ? "true" : "false", (unsigned long long)g_last_frames, fps);
    fflush(stdout);
    [NSApp terminate:nil];
}
static void snapshot(NSString *out, double seconds, BOOL press) {
    __block double t0 = now_s();
    const char *page = getenv("NXWII_SNAPSHOT_SIDEBAR");
    [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) {
        double el = now_s() - t0;
        if (press && g_playing) {   // Start and A in turn, a tenth of a second each, every two seconds
            int phase = (int)(el * 10) % 20;
            g_kb[C_START] = phase == 5; g_kb[C_A] = phase == 15;
        }
        static int stated;
        if (getenv("NXWII_SNAPSHOT_STATE") && el >= seconds - 3 && !stated) { stated = 1; state_do(1, 0); }   // checks: a save state to states/state1.sav
        if (page && el >= seconds - 1.5 && !g_open) {
            memset(g_kb, 0, sizeof g_kb);
            [NSUserDefaults.standardUserDefaults setInteger:atoi(page) forKey:[@"DMQuickSettings.page." stringByAppendingString:g_name]];
            sidebar_toggle();
        }
        if (el < seconds) return;
        [t invalidate];
        memset(g_kb, 0, sizeof g_kb);
        [NSFileManager.defaultManager removeItemAtPath:out error:nil];
        if (page) {
            typedef CGImageRef (*WindowImage)(CGRect, uint32_t, uint32_t, uint32_t);
            WindowImage window_image = (WindowImage)dlsym(RTLD_DEFAULT, "CGWindowListCreateImage");
            CGImageRef shot = window_image ? window_image(CGRectNull, 1 << 3, (uint32_t)g_win.windowNumber, 1 | (1 << 3)) : NULL;
            BOOL ok = NO;
            if (shot && CGImageGetWidth(shot) > 16) {
                CGImageDestinationRef dst = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:out], CFSTR("public.png"), 1, NULL);
                if (dst) { CGImageDestinationAddImage(dst, shot, NULL); ok = CGImageDestinationFinalize(dst); CFRelease(dst); }
            }
            if (shot) CGImageRelease(shot);
            snapshot_done(out, ok);
            return;
        }
        if (!g_playing || !D.screenshot(out.fileSystemRepresentation)) { snapshot_done(out, NO); return; }
        __block double t1 = now_s();
        [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *w) {
            BOOL there = [NSFileManager.defaultManager fileExistsAtPath:out];
            if (!there && now_s() - t1 < 5) return;
            [w invalidate];
            if (there) usleep(200000);   // written by Dolphin's thread: let it finish
            snapshot_done(out, there);
        }];
    }];
}

static NSString *disc_from_port(NSString *res) {
    NSData *d = [NSData dataWithContentsOfFile:[res stringByAppendingPathComponent:@"wii/port.json"]];
    NSDictionary *j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    return [j isKindOfClass:NSDictionary.class] ? j[@"disc"] : nil;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        NSBundle *b = NSBundle.mainBundle; NSDictionary *info = b.infoDictionary ?: @{};
        const char *e;
        BOOL named = argc > 1 && argv[1][0] != '-';
        g_disc = (e = getenv("NXWII_DISC")) ? @(e) : named ? @(argv[1]) : disc_from_port(b.resourcePath);
        g_name = (e = getenv("NXWII_NAME")) ? @(e) : info[@"CFBundleName"] ?: g_disc.lastPathComponent.stringByDeletingPathExtension ?: @"Game";
        g_id = (e = getenv("NXWII_ID")) ? @(e) : info[@"NXForgeTitleID"] ?: @"0E00000000000000";
        NSString *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject.path;
        g_root = (e = getenv("DM_ROOT")) && *e ? @(e) : [support stringByAppendingFormat:@"/nxnative/%@", g_id];
        [NSFileManager.defaultManager createDirectoryAtPath:user_dir() withIntermediateDirectories:YES attributes:nil error:nil];
        [NSFileManager.defaultManager createDirectoryAtPath:save_dir() withIntermediateDirectories:YES attributes:nil error:nil];
        setenv("DM_SAVE", save_dir().fileSystemRepresentation, 1);   // the sidebar's save backups read it
        setenv("DM_GAME_ID", g_id.UTF8String, 0);
        g_snapshot = getenv("NXWII_SNAPSHOT") != NULL;
        NSString *lib = (e = getenv("NXWII_LIB")) ? @(e) : [b.privateFrameworksPath stringByAppendingPathComponent:@"nxdolphin.dylib"];

        NSApplication *app = [NSApplication sharedApplication]; App *del = [App new]; app.delegate = del;
        [app setActivationPolicy:g_snapshot ? NSApplicationActivationPolicyAccessory : NSApplicationActivationPolicyRegular];
        NSString *problem = nil;
        if (!g_disc.length) problem = @"This app does not name its disc image. Convert the game again in NXForge.";
        else if (![NSFileManager.defaultManager fileExistsAtPath:g_disc])
            problem = [NSString stringWithFormat:@"The disc image is not at %@. If it is on a drive or a network share, connect it, then open the game again.", g_disc];
        else if (!dolphin_load(lib)) problem = @"Dolphin is missing from this app or does not match its player. Convert the game again in NXForge.";
        if (problem) {
            LOG("%s", problem.UTF8String);
            if (!g_snapshot) { NSAlert *a = [NSAlert new]; a.messageText = [g_name stringByAppendingString:@" could not start"]; a.informativeText = problem; [a runModal]; }
            return 1;
        }

        NSRect r = NSMakeRect(0, 0, 1280, 720);   // a 16:9 window; Dolphin letterboxes a 4:3 game in it
        NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
        g_win = g_snapshot ? [[OffscreenWindow alloc] initWithContentRect:r styleMask:style backing:NSBackingStoreBuffered defer:NO]
                           : [[NSWindow alloc] initWithContentRect:r styleMask:style backing:NSBackingStoreBuffered defer:NO];
        g_win.title = g_name; g_win.delegate = del; g_win.releasedWhenClosed = NO; g_win.minSize = NSMakeSize(480, 320); g_win.backgroundColor = NSColor.blackColor;
        g_win.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary; g_win.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        g_view = [[Container alloc] initWithFrame:r]; g_view.wantsLayer = YES; g_view.layer.backgroundColor = NSColor.blackColor.CGColor; g_win.contentView = g_view;
        g_game = [[GameView alloc] initWithFrame:r]; g_game.wantsLayer = YES; [g_view addSubview:g_game];
        values_load();
        if (g_snapshot) { g_win.ignoresMouseEvents = YES; [g_win setFrameOrigin:NSMakePoint(-30000, 100)]; [g_win orderFrontRegardless]; }
        else {
            menus(del); [g_win center]; [g_win setFrameAutosaveName:[@"NXWII." stringByAppendingString:g_id]];
            [g_win makeKeyAndOrderFront:nil]; [g_win makeFirstResponder:g_game]; [app activateIgnoringOtherApps:YES];
            [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown | NSEventMaskKeyUp handler:^NSEvent *(NSEvent *ev) { return key_event(ev); }];
        }
        layout_game();
        D.set(NXD_REMOTE, g_val[11]);   // before the start, so the Remote begins as it is held
        D.save_root(save_dir().fileSystemRepresentation);
        if (!D.start((__bridge void *)g_game, g_disc.fileSystemRepresentation, user_dir().fileSystemRepresentation)) {
            NSString *err = @(D.error() ?: ""); if (!err.length) err = @"Dolphin could not boot this game.";
            LOG("%s", err.UTF8String);
            if (!g_snapshot) { NSAlert *a = [NSAlert new]; a.messageText = [g_name stringByAppendingString:@" could not start"]; a.informativeText = err; [a runModal]; }
            return 1;
        }
        g_started = 1;
        for (int i = 6; i < 13; i++) value_apply(i);
        volume_apply();
        [NSTimer scheduledTimerWithTimeInterval:1 / 120.0 repeats:YES block:^(NSTimer *t) { (void)t; tick(); if (!g_snapshot) pad_poll(); else input_push(); }];
        if (g_snapshot) {
            const char *secs = getenv("NXWII_SNAPSHOT_SECONDS"), *in = getenv("NXWII_SNAPSHOT_INPUT");
            snapshot(@(getenv("NXWII_SNAPSHOT")), secs ? atof(secs) : 20, in && !strcmp(in, "menus"));
        }
        else fps_counter();
        [app run];
    }
    return 0;
}
