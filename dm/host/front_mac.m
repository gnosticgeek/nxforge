// Mac front end: with DM_WINDOW=1 open a window (CAMetalLayer, for the graphics backend to present frames) + keyboard and controllers → dm_input; the guest runs on a large-stack thread instead and the main thread belongs to AppKit.
// Without DM_WINDOW: the guest runs directly on the current thread, behaving the same as with no front end (windowless tests use this).
// The window is fullscreen-capable (the green button and ⌃⌘F); DM_FULLSCREEN starts it that way. ⌘Q quits; the left mouse button is the touchscreen.
// Esc (or ⇧⌘G, or the Graphics menu) opens the Quick settings sidebar over the game (DmSettings): the present filter, a frame-rate counter and mods, kept per game.
// Key map (Nintendo layout): WASD left stick, arrow keys D-pad, J=A K=B U=X I=Y, Q=L E=R, Z=ZL C=ZR, F=press left stick G=press right stick, Return=+ Tab=−, Space=shake the controller.
// Controllers: buttons by position as on the iPhone (right A, bottom B, top X, left Y), shoulders L R, triggers ZL ZR, Menu + Options −, both sticks and their presses.
// Each controller is a player of its own (local co-op): the first one connected is player 1, together with the keyboard, the next player 2, and so on up to 8 (pad_slots.h);
// DM_PAD_MERGE=1 merges every controller into player 1 instead, DM_KBD_PLAYER=own makes the keyboard player 1 on its own, with the controllers from player 2 on.
#import <Cocoa/Cocoa.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#import <GameController/GameController.h>
#include "dm.h"
#include "dm_input.h"
#include "front.h"
#include "quick_settings_mac.h"
#include "hle.h"
#include "pad_slots.h"
#include "haptics_apple.h"
#include <signal.h>
#include <math.h>

static CAMetalLayer *g_layer;
static uint64_t g_btn;
static int g_w, g_a, g_s, g_d;
static int g_input_on = 1;   // main thread: the game window is key, so its keyboard, mouse and controllers reach the game (input_release / input_resume)

void *front_metal_layer(void) { return (__bridge void *)g_layer; }
static _Atomic int g_screen_fps;   // the window's screen's maximumFramesPerSecond, kept up to date when the window moves to another screen
int front_screen_max_fps(void) { return g_screen_fps; }
// The screen's refresh rate matched to the game's frame rate in fullscreen (front_screen_match, from PR #79; DM_SCREEN_MATCH=0 turns it off). 60 fps on a 144 Hz screen cannot be paced
// evenly: the display link counts a tick on the refresh nearest each 1/60 s slot (nvn_mtl.m link_range), so frames stay up 2 and 3 refreshes in turn (13.9 / 20.8 ms) and Apple's HUD shows
// the frame interval jumping between them. In fullscreen, a screen whose rate is not a multiple of the game's switches to the mode of the same size with the highest rate that is (144 → 120 Hz
// for 60 and 30 fps), for this app only: macOS switches it back when the host quits, crashes included, and leaving fullscreen or that screen switches it back at once. A window keeps the
// screen's rate, because the switch changes the whole screen for every app and most external screens go black for a second or more. A screen with no such mode keeps the virtual ticks
static NSWindow *g_win; static _Atomic int g_match_want;   // the game's window; the frame rate to match (0 = not known yet), written by the present thread only
static CGDirectDisplayID g_match_id; static CGDisplayModeRef g_match_orig;   // main thread: the screen this host switched and its own mode (NULL = none switched)
static double mode_hz(CGDisplayModeRef m) { double hz = CGDisplayModeGetRefreshRate(m); return hz > 0 ? hz : 0; }   // 0 = not known (older built-in screens report none)
static int hz_multiple(double hz, int fps) { double k = round(hz / fps); return k >= 1 && fabs(hz / fps - k) < 0.01; }   // 59.94 Hz counts as 60
static CGError screen_set_mode(CGDirectDisplayID id, CGDisplayModeRef m) {   // for this app only (kCGConfigureForAppOnly)
    CGDisplayConfigRef cfg; CGError r = CGBeginDisplayConfiguration(&cfg);
    if (r != kCGErrorSuccess) return r;
    r = CGConfigureDisplayWithDisplayMode(cfg, id, m, NULL);
    if (r != kCGErrorSuccess) { CGCancelDisplayConfiguration(cfg); return r; }
    return CGCompleteDisplayConfiguration(cfg, kCGConfigureForAppOnly);
}
static void screen_match_restore(int on_it) {   // main thread: the screen this host switched gets its own mode again; on_it: the window is on that screen
    double hz = mode_hz(g_match_orig); CGError r = screen_set_mode(g_match_id, g_match_orig);
    LOG("front end: screen %s %.0f Hz", r == kCGErrorSuccess ? "back at" : "could not be switched back to", hz);
    if (r == kCGErrorSuccess && on_it && hz > 0) g_screen_fps = (int)round(hz);
    CGDisplayModeRelease(g_match_orig); g_match_orig = NULL;
}
static void screen_match_apply(void) {   // main thread: on a new frame rate, on entering and leaving fullscreen and on a move to another screen
    static int off = -1; if (off < 0) { const char *e = getenv("DM_SCREEN_MATCH"); off = e && !strcmp(e, "0"); if (off) LOG("front end: the screen keeps its refresh rate in fullscreen too (DM_SCREEN_MATCH=0)"); }
    NSScreen *scr = g_win.screen; int want = g_match_want, full = (g_win.styleMask & NSWindowStyleMaskFullScreen) != 0;
    CGDirectDisplayID id = scr ? [scr.deviceDescription[@"NSScreenNumber"] unsignedIntValue] : kCGNullDirectDisplay;
    if (g_match_orig && (!full || id != g_match_id)) screen_match_restore(id == g_match_id);
    if (off || !full || want <= 0 || !scr) return;
    CGDisplayModeRef cur = CGDisplayCopyDisplayMode(id);
    if (!cur) return;
    double hz = mode_hz(cur);
    if (hz <= 0 || hz_multiple(hz, want)) {   // already a multiple, or not known
        if (g_match_orig && hz > 0) g_screen_fps = (int)round(hz);   // the screen this host switched: its rate from the mode, which maximumFramesPerSecond (the screen observer) may not show yet
        CGDisplayModeRelease(cur); return;
    }
    size_t w = CGDisplayModeGetWidth(cur), h = CGDisplayModeGetHeight(cur), pw = CGDisplayModeGetPixelWidth(cur), ph = CGDisplayModeGetPixelHeight(cur);
    CFArrayRef modes = CGDisplayCopyAllDisplayModes(id, (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGDisplayShowDuplicateLowResolutionModes: @YES});
    CGDisplayModeRef pick = NULL; double pick_hz = 0;
    for (CFIndex i = 0; modes && i < CFArrayGetCount(modes); i++) {
        CGDisplayModeRef m = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, i); double r = mode_hz(m);
        if (CGDisplayModeGetWidth(m) != w || CGDisplayModeGetHeight(m) != h || CGDisplayModeGetPixelWidth(m) != pw || CGDisplayModeGetPixelHeight(m) != ph || !CGDisplayModeIsUsableForDesktopGUI(m)) continue;
        if (hz_multiple(r, want) && r > pick_hz) { pick = m; pick_hz = r; }
    }
    if (!pick) LOG("front end: screen at %.0f Hz has no mode of this size at a multiple of %d Hz: frames are paced on the nearest refreshes", hz, want);
    else {
        CGError r = screen_set_mode(id, pick);
        LOG("front end: screen at %.0f Hz %s %.0f Hz for %d fps in fullscreen (DM_SCREEN_MATCH=0 keeps it)", hz, r == kCGErrorSuccess ? "switched to" : "could not be switched to", pick_hz, want);
        if (r == kCGErrorSuccess) { if (!g_match_orig) { g_match_orig = CGDisplayModeRetain(cur); g_match_id = id; } g_screen_fps = (int)round(pick_hz); }
    }
    if (modes) CFRelease(modes);
    CGDisplayModeRelease(cur);
}
void front_screen_match(int fps) {
    if (!g_layer || g_match_want == fps) return;   // no window (a windowless run's main thread runs the guest), or the rate as before
    g_match_want = fps; dispatch_async(dispatch_get_main_queue(), ^{ screen_match_apply(); });
}
static void push(void) {
    int32_t lx = (g_d - g_a) * 32767, ly = (g_w - g_s) * 32767;
    dm_input_set(g_btn, lx, ly, 0, 0);
}
static int key_bit(unsigned short code) {
    switch (code) {
        case 38: return 0;  case 40: return 1;  case 32: return 2;  case 34: return 3;    // J K U I → A B X Y
        case 3: return 4;   case 5: return 5;                                            // F G → press stick
        case 12: return 6;  case 14: return 7;  case 6: return 8;   case 8: return 9;    // Q E Z C → L R ZL ZR
        case 36: return 10; case 48: return 11;                                          // Return Tab → + −
        case 123: return 12; case 126: return 13; case 124: return 14; case 125: return 15; // ← ↑ → ↓
    }
    return -1;
}
static void on_key(NSEvent *e, int down) {
    if (!g_input_on) return;
    unsigned short c = e.keyCode;
    switch (c) { case 13: g_w = down; break; case 0: g_a = down; break; case 1: g_s = down; break; case 2: g_d = down; break; }
    int b = key_bit(c);
    uint64_t m = b >= 0 ? 1ull << b : c == 49 ? DM_BTN_SHAKE : 0;   // Space: shaken while held
    g_btn = down ? (g_btn | m) : (g_btn & ~m);
    push();
}

// Physical controllers (GameController) go to dm_pad_set_player, mapped as the iPhone's (DmGamepad.m read_pad, same layout); player 1's is ORed with the keyboard, a stick takes
// whichever is deflected more (hle_hid.c). DM_KEYS uses player 1's path, so player 1's controller touched during a script takes it over.
// Players: every controller with an extended gamepad profile holds a slot (pad_slots.h: player 1 first, a reconnected controller gets its player back), and hle_hid.c reports
// player n on its own npad while the slot is held (dm_pad_players). A one-player game that supports only No1 / Handheld still sees every controller as player 1 (hle_hid.c).
// With DM_PAD_MERGE=1 every controller is player 1, as before (the last one moved wins; when the last one goes away its buttons and sticks are released)
static pad_slots g_slots;
static GCController *g_held[DM_PLAYERS];   // the controller of each slot, kept alive while it holds it (the slot table keys on its pointer)
static int g_merge, g_kbd_own;
static int32_t pad_axis(float v) { return (int32_t)(fmaxf(-1.f, fminf(1.f, v)) * DM_STICK_MAX); }
static void pad_read(GCExtendedGamepad *g) {
    if (!g_input_on) return;
    int p = g_merge ? 0 : pad_slot_of(&g_slots, (__bridge const void *)g.controller); if (p < 0) return;
    dm_haptics_apple_controller(p, g.controller);
    uint64_t m = 0;
    #define K(btn, bit) if (btn.isPressed) m |= bit
    K(g.buttonB, DM_BTN_A); K(g.buttonA, DM_BTN_B); K(g.buttonY, DM_BTN_X); K(g.buttonX, DM_BTN_Y);   // by position: right A, bottom B, top X, left Y
    K(g.leftShoulder, DM_BTN_L); K(g.rightShoulder, DM_BTN_R); K(g.leftTrigger, DM_BTN_ZL); K(g.rightTrigger, DM_BTN_ZR);
    K(g.buttonMenu, DM_BTN_PLUS); K(g.buttonOptions, DM_BTN_MINUS); K(g.leftThumbstickButton, DM_BTN_LS); K(g.rightThumbstickButton, DM_BTN_RS);   // nil on pads without them: not pressed
    K(g.dpad.left, DM_BTN_LEFT); K(g.dpad.up, DM_BTN_UP); K(g.dpad.right, DM_BTN_RIGHT); K(g.dpad.down, DM_BTN_DOWN);
    #undef K
    dm_pad_set_player(p, m, pad_axis(g.leftThumbstick.xAxis.value), pad_axis(g.leftThumbstick.yAxis.value), pad_axis(g.rightThumbstick.xAxis.value), pad_axis(g.rightThumbstick.yAxis.value));
}
static const char *pad_name(GCController *c) { return c.vendorName.UTF8String ?: "?"; }
static void npad_name(int p, char *out, size_t cap) { uint32_t id = dm_player_npad(p); if (id == 0x20) snprintf(out, cap, "handheld"); else snprintf(out, cap, "%u", id); }
// Called at start and on every connect / disconnect (gone: the controller that was just removed, nil on a connect)
static void pads_changed(GCController *gone) {
    if (g_merge) {
        int any = 0;
        for (GCController *c in GCController.controllers) if (c.extendedGamepad && c != gone) {
            any = 1; c.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad *g, GCControllerElement *el) { (void)el; pad_read(g); };
            pad_read(c.extendedGamepad);
        }
        if (!any) { dm_pad_set(0, 0, 0, 0, 0); dm_haptics_apple_controller(0, nil); }
        return;
    }
    NSArray<GCController *> *now = GCController.controllers; char nb[16];
    for (int p = 0; p < DM_PLAYERS; p++) if (g_held[p] && (g_held[p] == gone || ![now containsObject:g_held[p]])) {
        npad_name(p, nb, sizeof nb); LOG("controller '%s' disconnected: player %d (npad %s) is free", pad_name(g_held[p]), p + 1, nb);
        g_held[p].extendedGamepad.valueChangedHandler = nil;
        dm_haptics_apple_controller(p, nil);
        pad_slot_free(&g_slots, (__bridge const void *)g_held[p]); g_held[p] = nil;
        dm_pad_set_player(p, 0, 0, 0, 0, 0);   // nothing stays pressed
    }
    for (GCController *c in now) if (c.extendedGamepad && c != gone && pad_slot_of(&g_slots, (__bridge const void *)c) < 0) {
        int p = pad_slot_take(&g_slots, (__bridge const void *)c, pad_name(c));
        if (p < 0) { LOG("controller '%s' connected: all %d players are taken, not used", pad_name(c), DM_PLAYERS); continue; }
        g_held[p] = c;
        c.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad *g, GCControllerElement *el) { (void)el; pad_read(g); };
        npad_name(p, nb, sizeof nb); LOG("controller '%s' connected: player %d (npad %s)", pad_name(c), p + 1, nb);
        pad_read(c.extendedGamepad);
    }
    dm_pad_players(pad_slot_mask(&g_slots));
}
// Focus: a window that is no longer key sees no key-up, mouse-up or controller release, so whatever is held when it loses focus (another app, the text box, minimized) would
// stay pressed in the game. The front end releases only what it pressed itself: player 1's pad and the touch are also DM_KEYS / DM_CTL's (hle_hid.c), and a scripted hold goes on.
// Out of focus a controller's changes are ignored, so back in focus each controller is read as it is now (a button still held, a stick still deflected)
static int g_mouse_down;   // the mouse holds the touch (DmGameView)
static void input_release(void) {
    g_input_on = 0;
    g_btn = 0; g_w = g_a = g_s = g_d = 0; push();
    if (g_mouse_down) { g_mouse_down = 0; dm_touch_set(NULL, 0); }
    if (g_merge) { for (GCController *c in GCController.controllers) if (c.extendedGamepad) { dm_pad_set(0, 0, 0, 0, 0); break; } }
    else for (int p = 0; p < DM_PLAYERS; p++) if (g_held[p]) dm_pad_set_player(p, 0, 0, 0, 0, 0);
}
static void input_resume(void) {
    g_input_on = 1;
    if (g_merge) { for (GCController *c in GCController.controllers) if (c.extendedGamepad) pad_read(c.extendedGamepad); }
    else for (int p = 0; p < DM_PLAYERS; p++) if (g_held[p].extendedGamepad) pad_read(g_held[p].extendedGamepad);
}
static void pads_start(void) {
    const char *e = getenv("DM_PAD_MERGE"); g_merge = e && atoi(e);
    e = getenv("DM_KBD_PLAYER"); g_kbd_own = !g_merge && e && !strcmp(e, "own");
    static const char kbd = 0;
    if (g_kbd_own) pad_slot_take(&g_slots, &kbd, "keyboard");   // holds player 1 for good
    LOG("front end: %s", g_merge ? "every controller is player 1 (DM_PAD_MERGE)" : g_kbd_own ? "the keyboard is player 1, each controller a player of its own from player 2 on (DM_KBD_PLAYER=own)"
                                                                           : "each controller is a player of its own, the keyboard plays with player 1");
    pads_changed(nil);
}

// Mouse as a single-point touchscreen (front.h dm_touch_set): left button down / drag = finger 0, release = lifted. The content view takes the clicks,
// not a window-wide event monitor, so clicks on the title bar, the window buttons and the resize edges still reach AppKit.
@interface DmGameView : NSView @end
@implementation DmGameView
- (void)mouseDown:(NSEvent *)e { [self mouseDragged:e]; }
- (void)mouseDragged:(NSEvent *)e {
    if (!g_input_on) return;
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil]; NSSize b = self.bounds.size;
    double w = b.width, h = b.height;
    if (w <= 0 || h <= 0) return;
    if (w / h > 16.0 / 9.0) w = h * 16.0 / 9.0; else h = w * 9.0 / 16.0;   // the centered 16:9 picture the present fits into the view, as on the iPhone (DmGamepad.m)
    double x0 = (b.width - w) / 2, y0 = (b.height - h) / 2;
    dm_touch t = {0, (float)fmin(fmax((p.x - x0) / w, 0), 0.999), (float)fmin(fmax(1 - (p.y - y0) / h, 0), 0.999)};   // The AppKit view origin is at bottom left, the touchscreen origin is at top left
    dm_touch_set(&t, 1); g_mouse_down = 1;
}
- (void)mouseUp:(NSEvent *)e { (void)e; if (g_mouse_down) { g_mouse_down = 0; dm_touch_set(NULL, 0); } }
// The drawable follows the view in pixels: a layer assigned to a layer-backed view kept the drawable at the first window's 1280x720 in fullscreen too, so the game picture was
// scaled down to it and up again by the compositor
- (void)fitDrawable {
    CAMetalLayer *l = (CAMetalLayer *)self.layer; if (![l isKindOfClass:CAMetalLayer.class] || !self.window) return;
    l.contentsScale = self.window.backingScaleFactor;
    NSSize px = [self convertSizeToBacking:self.bounds.size]; if (px.width < 1 || px.height < 1 || CGSizeEqualToSize(l.drawableSize, px)) return;
    l.drawableSize = px; LOG("front end: drawable %.0fx%.0f", px.width, px.height);
}
- (void)setFrameSize:(NSSize)s { [super setFrameSize:s]; [self fitDrawable]; }
- (void)viewDidChangeBackingProperties { [super viewDidChangeBackingProperties]; [self fitDrawable]; }
@end

// Quick settings: a sidebar over the right of the game picture (Esc, ⇧⌘G or the Graphics menu opens it; Esc, its close button or Resume game closes it), fullscreen too. The sidebar itself is
// SwiftUI (quick_settings_mac.swift: the system's controls on a Liquid Glass panel); this side opens and closes it, draws the frame-rate counter and loads the mods at launch. Kept per game in the
// user defaults (the app bundle's own domain; the keys name the game for a bare dmhost); a setting the environment names wins over its saved value and is not saved.
// - Graphics & shaders: the present filter (front.h mtl_present_filter_set, nvn_mtl.m), from the next frame, so the game runs on behind the sidebar and shows the change at once.
//   DM_PRESENT_FILTER / DM_PRESENT_FILTER_STRENGTH / DM_PRESENT_SCANLINE in the environment.
// - Performance: a frame-rate counter in a corner of the game picture, the frames put on screen in the last second (nvn_mtl.m mtl_present_count, as on the iPhone). DM_SHOW_FPS=0 / 1.
// - Mods: each folder in ~/Library/Application Support/nxnative/<title ID>/mods is a mod, the game's RomFS files it replaces either in it or in its romfs folder (the layout other
//   Switch tools use). The enabled ones are overlaid on the RomFS at launch in name order, the first one holding a file winning (hle_fs.c DM_ROMFS_OVERLAY, which names them),
//   so a change applies on the next launch. DM_ROMFS_OVERLAY in the environment replaces them.
// - Cheats: this build's cheat file (cheats_host.c), a switch per cheat; the host reads the saved names at launch (DMQuickSettings.cheats.<game>), and the sidebar
//   switches the running set (dm_cheats_set). Code patches are made only at launch. DM_CHEATS / DM_CHEATS_ON in the environment win.
// While the sidebar is up the game sees what it sees when its window loses focus: its input is released (input_release) and its focus state is out of focus (dm_focus_set 2), so a game
// that pauses for the HOME menu pauses; the keyboard goes to the sidebar's controls. The game itself is not suspended, so the filter shows live
static NSString *const g_pfx_title[DM_PFX_N] = {@"Off", @"Sharpen", @"Pixel-perfect", @"CRT"};
static NSString *pfx_key(NSString *what) { return [NSString stringWithFormat:@"DMPresentFilter.%@.%s", what, DM_GAME_NAME]; }
static NSString *opt_key(NSString *what) { return [NSString stringWithFormat:@"DMQuickSettings.%@.%s", what, DM_GAME_NAME]; }
static int g_menu_open;   // main thread: the sidebar is up (the window's focus notifications leave the game out of focus meanwhile)

static NSString *mods_dir(void) {
    NSURL *u = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return [u.path stringByAppendingFormat:@"/nxnative/%s/mods", DM_GAME_ID];
}
static NSArray<NSString *> *mods_list(void) {   // the mod folders, in the order they are overlaid (quick_settings_mac.swift lists them the same way)
    NSMutableArray *r = [NSMutableArray array]; NSString *d = mods_dir();
    for (NSString *n in [NSFileManager.defaultManager contentsOfDirectoryAtPath:d error:nil] ?: @[]) {
        BOOL dir = NO;
        if (![n hasPrefix:@"."] && [NSFileManager.defaultManager fileExistsAtPath:[d stringByAppendingPathComponent:n] isDirectory:&dir] && dir) [r addObject:n];
    }
    return [r sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}
static NSString *mod_root(NSString *name) {
    NSString *p = [mods_dir() stringByAppendingPathComponent:name], *rf = [p stringByAppendingPathComponent:@"romfs"]; BOOL dir = NO;
    return [NSFileManager.defaultManager fileExistsAtPath:rf isDirectory:&dir] && dir ? rf : p;
}
static NSSet<NSString *> *g_mods_run;   // the mods this launch overlaid (nil: DM_ROMFS_OVERLAY came from the environment)
static void mods_start(void) {   // main thread, before the guest runs (the game mounts its RomFS later, hle_fs.c h_fs_MountRom)
    if (getenv("DM_ROMFS_OVERLAY")) { LOG("front end: RomFS overlay from DM_ROMFS_OVERLAY; this game's enabled mods are not used"); return; }
    NSArray *want = [NSUserDefaults.standardUserDefaults arrayForKey:opt_key(@"mods")] ?: @[];
    NSMutableArray *roots = [NSMutableArray array]; NSMutableSet *on = [NSMutableSet set]; size_t len = 0;
    for (NSString *n in mods_list()) {
        if (![want containsObject:n]) continue;
        NSString *r = mod_root(n); size_t k = strlen(r.fileSystemRepresentation) + 1;
        if ([r containsString:@":"]) { LOG("[RED] mod '%s' not used: its path has a ':' (the overlay list separator)", n.UTF8String); continue; }
        if (len + k > 4096) { LOG("[RED] mod '%s' and the ones after it not used: the overlay list is full (4,096 bytes of paths)", n.UTF8String); break; }
        [roots addObject:r]; [on addObject:n]; len += k;
    }
    g_mods_run = on;
    if (!roots.count) return;
    setenv("DM_ROMFS_OVERLAY", [roots componentsJoinedByString:@":"].fileSystemRepresentation, 1);
    LOG("front end: %lu mod%s over the RomFS (Quick settings): %s", (unsigned long)roots.count, roots.count == 1 ? "" : "s", [on.allObjects componentsJoinedByString:@", "].UTF8String);
}


@interface DmSettings : NSObject
@property NSView *view; @property NSMutableArray<NSMenuItem *> *items; @property NSTextField *fpsLabel; @property NSTimer *fpsTimer; @property uint64_t fpsN0; @property double fpsT0;
- (void)toggle:(id)sender; - (void)fpsCounter;
@end
static DmSettings *g_opts;
static void qs_close(void) { if (g_menu_open) [g_opts toggle:nil]; }
static void qs_fps(void) { [g_opts fpsCounter]; }
@implementation DmSettings
- (BOOL)fpsOn {
    const char *e = getenv("DM_SHOW_FPS"); if (e) return atoi(e) != 0;
    return [NSUserDefaults.standardUserDefaults boolForKey:opt_key(@"fps")];
}
// The frame-rate counter, in the chosen corner of the game view, under the sidebar
- (void)fpsCounter {
    if (!self.fpsOn) { [self.fpsTimer invalidate]; self.fpsTimer = nil; [self.fpsLabel removeFromSuperview]; self.fpsLabel = nil; return; }
    NSView *gv = g_win.contentView;
    if (!self.fpsLabel) {
        NSTextField *l = [NSTextField labelWithString:@"-- FPS"]; l.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightSemibold]; l.textColor = NSColor.whiteColor;
        NSShadow *sh = [NSShadow new]; sh.shadowColor = [NSColor colorWithWhite:0 alpha:0.8]; sh.shadowBlurRadius = 2; sh.shadowOffset = NSMakeSize(0, -1); l.shadow = sh;
        if (self.view.superview) [gv addSubview:l positioned:NSWindowBelow relativeTo:self.view]; else [gv addSubview:l];
        self.fpsLabel = l; self.fpsN0 = mtl_present_count(); self.fpsT0 = CACurrentMediaTime();
        __weak DmSettings *me = self;
        self.fpsTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) {
            (void)t; DmSettings *s = me; if (!s) return;
            uint64_t n = mtl_present_count(); double now = CACurrentMediaTime();
            if (now - s.fpsT0 < 1.5) s.fpsLabel.stringValue = [NSString stringWithFormat:@"%.0f FPS", (n - s.fpsN0) / (now - s.fpsT0)];   // a longer span was a stall (minimized): no reading
            s.fpsN0 = n; s.fpsT0 = now;
        }];
        LOG("front end: frame-rate counter on");
    }
    [self.fpsLabel sizeToFit];
    int c = (int)MIN(MAX([NSUserDefaults.standardUserDefaults integerForKey:opt_key(@"fpsPos")], 0), 3);
    NSSize b = gv.bounds.size, s = self.fpsLabel.frame.size; s.width += 24;   // room for wider readings
    self.fpsLabel.frame = NSMakeRect(c & 1 ? b.width - s.width - 12 : 12, c & 2 ? 10 : b.height - s.height - 10, s.width, s.height);
    self.fpsLabel.alignment = c & 1 ? NSTextAlignmentRight : NSTextAlignmentLeft;
    self.fpsLabel.autoresizingMask = (c & 1 ? NSViewMinXMargin : NSViewMaxXMargin) | (c & 2 ? NSViewMaxYMargin : NSViewMinYMargin);
}
- (void)toggle:(id)sender {
    (void)sender;
    if (!g_menu_open) {
        if (!self.view) {
            NSString *run = g_mods_run ? [g_mods_run.allObjects componentsJoinedByString:@"\n"] : nil;
            self.view = (__bridge_transfer NSView *)dm_qs_make(DM_GAME_NAME, mods_dir().fileSystemRepresentation, run.UTF8String, qs_close, qs_fps);
            self.view.autoresizingMask = NSViewMinXMargin | NSViewHeightSizable;
        }
        NSView *gv = g_win.contentView; CGFloat w = MIN(460, gv.bounds.size.width);
        self.view.frame = NSMakeRect(gv.bounds.size.width - w, 0, w, gv.bounds.size.height);
        dm_qs_refresh();
        [gv addSubview:self.view]; g_menu_open = 1;
        input_release(); dm_focus_set(2);   // as when the window loses focus: nothing stays held, and a game that pauses for the HOME menu pauses
        LOG("front end: Quick settings open");
    } else {
        [self.view removeFromSuperview]; g_menu_open = 0;
        [g_win makeFirstResponder:g_win.contentView];
        if (g_win.isKeyWindow) { input_resume(); dm_focus_set(1); }   // otherwise the window's becoming key resumes them
        LOG("front end: Quick settings closed");
    }
}
- (void)pickItem:(NSMenuItem *)it {
    float k; mtl_present_filter(&k); mtl_present_filter_set((int)it.tag, k);
    if (!getenv("DM_PRESENT_FILTER")) { NSUserDefaults *d = NSUserDefaults.standardUserDefaults; [d setInteger:it.tag forKey:pfx_key(@"mode")]; [d setFloat:k forKey:pfx_key(@"strength")]; }
    if (g_menu_open) dm_qs_refresh();
}
- (BOOL)validateMenuItem:(NSMenuItem *)it {   // check marks: the filter now, and the sidebar while it is up
    if (it.action == @selector(toggle:)) it.state = g_menu_open ? NSControlStateValueOn : NSControlStateValueOff;
    else if (it.action == @selector(pickItem:)) it.state = it.tag == mtl_present_filter(NULL) ? NSControlStateValueOn : NSControlStateValueOff;
    return YES;
}
- (void)menuIn:(NSMenu *)bar {
    NSMenu *gm = [[NSMenu alloc] initWithTitle:@"Graphics"]; self.items = [NSMutableArray array];
    [[bar addItemWithTitle:@"Graphics" action:nil keyEquivalent:@""] setSubmenu:gm];
    for (int i = 0; i < DM_PFX_N; i++) {
        NSMenuItem *it = [gm addItemWithTitle:[NSString stringWithFormat:@"Filter: %@", g_pfx_title[i]] action:@selector(pickItem:) keyEquivalent:@""];
        it.target = self; it.tag = i; [self.items addObject:it];
    }
    [gm addItem:NSMenuItem.separatorItem];
    NSMenuItem *it = [gm addItemWithTitle:@"Quick Settings" action:@selector(toggle:) keyEquivalent:@"g"];   // ⇧⌘G (and Esc in the game window), checked while the sidebar is up (validateMenuItem)
    it.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift; it.target = self;
    g_opts = self; [self fpsCounter];
}
@end
static void graphics_start(void) {   // main thread, before the guest runs: the saved filter and mods, unless the environment names them
    mods_start();
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if (!getenv("DM_PRESENT_SCANLINE") && [d objectForKey:pfx_key(@"scanline")]) mtl_present_scanline_set((int)[d integerForKey:pfx_key(@"scanline")]);
    if (getenv("DM_PRESENT_FILTER")) return;
    if (![d objectForKey:pfx_key(@"mode")]) return;
    int m = (int)[d integerForKey:pfx_key(@"mode")]; float k = [d objectForKey:pfx_key(@"strength")] ? [d floatForKey:pfx_key(@"strength")] : 0.5f;
    mtl_present_filter_set(m, k); LOG("front end: present filter from the saved choice for this game (Quick settings)");
}

typedef struct { void (*fn)(void); } guest_arg;
static void *guest_tramp(void *p) {
    static char alt[65536];                       // The signal alternate stack is per thread; crash printing must also work on the guest thread
    stack_t ss = {.ss_sp = alt, .ss_size = sizeof alt}; sigaltstack(&ss, 0);
    ((guest_arg *)p)->fn(); LOG("guest thread finished"); exit(0);
}

// Metal reads MTL_HUD_ENABLED when the process makes its first device, which can be before the window: set from DM_METAL_HUD before main (set in front_run, the HUD did not show)
__attribute__((constructor)) static void hud_env(void) { if (getenv("DM_METAL_HUD") && atoi(getenv("DM_METAL_HUD"))) setenv("MTL_HUD_ENABLED", "1", 0); }
void front_run(void (*guest)(void)) {
    // A game: tell macOS its work is latency-critical, so the system does not trade its frame time for power while the frame rate is capped
    static id activity; activity = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiated | NSActivityLatencyCritical reason:@"game"];
    if (!getenv("DM_WINDOW")) { guest(); return; }
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        NSRect r = NSMakeRect(0, 0, 1280, 720);
        NSWindow *win = [[NSWindow alloc] initWithContentRect:r
                                                    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                      backing:NSBackingStoreBuffered defer:NO];
        win.title = @DM_GAME_NAME;   // the game profile's name (game name label)
        // Fullscreen: without FullScreenPrimary the green button only zooms the window. The present path already scales
        // the game picture to fit the drawable with black bars around it, so fullscreen keeps the game's aspect ratio.
        win.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
        NSView *v = win.contentView = [[DmGameView alloc] initWithFrame:r];
        v.wantsLayer = YES;
        g_layer = [CAMetalLayer layer];
        g_layer.device = MTLCreateSystemDefaultDevice();
        g_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        g_layer.contentsScale = win.backingScaleFactor;
        if (getenv("DM_METAL_HUD") && atoi(getenv("DM_METAL_HUD"))) { g_layer.developerHUDProperties = @{@"mode": @"default"}; LOG("front end: Metal performance HUD on (DM_METAL_HUD)"); }   // Apple's HUD over the game: frame rate, frame and GPU time, memory
        v.layer = g_layer; [(DmGameView *)v fitDrawable];
        [win center];
        [win makeKeyAndOrderFront:nil];
        g_screen_fps = (int)(win.screen ?: NSScreen.mainScreen).maximumFramesPerSecond;
        g_win = win;
        [NSApp activateIgnoringOtherApps:YES];
        // Main menu: AppKit runs ⌘ shortcuts only through menu items, so ⌘Q quits and ⌃⌘F toggles fullscreen from here (AppKit shows the item as Globe-F and keeps ⌃⌘F as a hidden twin)
        NSMenu *bar = [NSMenu new], *app = [NSMenu new], *wm = [[NSMenu alloc] initWithTitle:@"Window"];
        [[bar addItemWithTitle:@"" action:nil keyEquivalent:@""] setSubmenu:app];
        [app addItemWithTitle:@"Quit " DM_GAME_NAME action:@selector(terminate:) keyEquivalent:@"q"];
        [[bar addItemWithTitle:@"Window" action:nil keyEquivalent:@""] setSubmenu:wm];
        [wm addItemWithTitle:@"Enter Full Screen" action:@selector(toggleFullScreen:) keyEquivalent:@"f"].keyEquivalentModifierMask = NSEventModifierFlagControl | NSEventModifierFlagCommand;
        graphics_start();
        static DmSettings *opts; opts = [DmSettings new]; [opts menuIn:bar];
        NSApp.mainMenu = bar;
        if (getenv("DM_FULLSCREEN")) dispatch_async(dispatch_get_main_queue(), ^{ [win toggleFullScreen:nil]; });   // start in fullscreen
        for (NSNotificationName nm in @[GCControllerDidConnectNotification, GCControllerDidDisconnectNotification])
            [NSNotificationCenter.defaultCenter addObserverForName:nm object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
                GCController *c = n.object; int conn = n.name == GCControllerDidConnectNotification;
                if (!c.extendedGamepad || g_merge) LOG("controller %s: %s%s", conn ? "connected" : "disconnected", pad_name(c), c.extendedGamepad ? "" : " (no extended gamepad profile: not used)");
                pads_changed(conn ? nil : c); }];
        dm_haptics_apple_init();
        pads_start();
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown | NSEventMaskKeyUp handler:^NSEvent *(NSEvent *e) {
            if (e.window != win) return e;   // Only swallow keys for the game window; other windows such as the software keyboard input box receive typing as usual
            if (e.type == NSEventTypeKeyDown && (e.modifierFlags & NSEventModifierFlagCommand)) return e;   // ⌘ shortcuts go to the menu; a key released while ⌘ is held still reaches the game, or it would stay pressed
            if (e.keyCode == 53) { if (e.type == NSEventTypeKeyDown && !e.isARepeat) [opts toggle:nil]; return nil; }   // Esc: the Quick settings sidebar (no game button is on it)
            if (g_menu_open) return e;   // the sidebar's controls take the keyboard; the game's input was released when it opened
            if (!e.isARepeat) on_key(e, e.type == NSEventTypeKeyDown);
            return nil;   // Swallow it to avoid the system beep
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification object:win queue:nil
                                                      usingBlock:^(NSNotification *n) { (void)n; exit(0); }];
        // Lifecycle (hle.h / dm.h): focus lost → 2, focus regained → 1; minimized → 3 + audio paused + GPU suspended, restored → resume (followed by focus regained → 1).
        // Input is released when the window stops being key (and when it is minimized) and taken up again when it is key again
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserverForName:NSWindowDidChangeScreenNotification object:win queue:nil usingBlock:^(NSNotification *n) { (void)n; if (win.screen) { g_screen_fps = (int)win.screen.maximumFramesPerSecond; g_layer.contentsScale = win.backingScaleFactor; } screen_match_apply(); }];
        // Entering and leaving fullscreen: the layer is layer-backed, so its frame (and with it the drawable) follows the
        // content view by itself; only the scale factor has to be carried over to the screen the window ended up on. The screen's rate is matched in fullscreen only (screen_match_apply)
        [nc addObserverForName:NSWindowDidEnterFullScreenNotification object:win queue:nil usingBlock:^(NSNotification *n) { (void)n; g_layer.contentsScale = win.backingScaleFactor; screen_match_apply(); }];
        [nc addObserverForName:NSWindowDidExitFullScreenNotification object:win queue:nil usingBlock:^(NSNotification *n) { (void)n; g_layer.contentsScale = win.backingScaleFactor; screen_match_apply(); }];
        [nc addObserverForName:NSWindowDidResignKeyNotification object:win queue:nil usingBlock:^(NSNotification *n) { (void)n; input_release(); if (!win.miniaturized) dm_focus_set(2); }];
        [nc addObserverForName:NSWindowDidBecomeKeyNotification object:win queue:nil usingBlock:^(NSNotification *n) { (void)n; if (g_menu_open) return; input_resume(); dm_focus_set(1); }];   // the sidebar keeps the game out of focus until it closes
        [nc addObserverForName:NSWindowDidMiniaturizeNotification object:win queue:nil usingBlock:^(NSNotification *n) { (void)n; input_release(); dm_focus_set(3); dm_audio_suspend(1); dm_gfx_suspend(1); }];
        [nc addObserverForName:NSWindowDidDeminiaturizeNotification object:win queue:nil usingBlock:^(NSNotification *n) { (void)n; dm_gfx_suspend(0); dm_audio_suspend(0); dm_focus_set(2); }];
        // Guest thread: 64 MiB stack (the Switch main thread stack is specified by npdm; the host gives plenty)
        static guest_arg ga; ga.fn = guest;
        pthread_attr_t a; pthread_attr_init(&a); pthread_attr_setstacksize(&a, 64u << 20);
        pthread_t th; if (pthread_create(&th, &a, guest_tramp, &ga)) die("pthread_create guest");
        [NSApp run];
    }
}

// Software keyboard input box (front.h): the main thread shows an NSAlert + text field and the guest thread waits synchronously for the result. Not shown in windowless mode (returns -1, the caller treats it as cancel)
extern int g_swkbd_min_chars;   // hle_swkbd.c: this input's minimum length from ShowKeyboardArg; the applet keeps OK disabled until the text is long enough
int front_text_input(const char *title, const char *sub, const char *guide, const char *initial, int max_chars, char *out, int out_cap) {
    if (!g_layer) return -1;
    __block int r = 0;
    __block NSString *text = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        // The box takes the keyboard and the mouse, so the game window never sees the key-up of the button or the touch-up of the click that opened it: nothing may stay pressed
        // while it is up, or the game reads the stuck button / touch the moment the box closes (Stardew Valley's character creation re-opened the keyboard endlessly)
        g_btn = 0; g_w = g_a = g_s = g_d = 0; push();
        dm_touch_set(NULL, 0);
        int min_chars = g_swkbd_min_chars > 0 ? g_swkbd_min_chars : 0;
        NSString *info = [NSString stringWithFormat:@"%s%s%s", sub ? sub : "", sub && *sub && guide && *guide ? "\n" : "", guide ? guide : ""];
        for (;;) {
            NSAlert *a = [NSAlert new];
            a.messageText = title && *title ? @(title) : @"Input";
            a.informativeText = info;
            [a addButtonWithTitle:@"OK"]; [a addButtonWithTitle:@"Cancel"];
            NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
            f.stringValue = text ?: (initial ? @(initial) : @"");
            if (guide && *guide) f.placeholderString = @(guide);
            a.accessoryView = f; a.window.initialFirstResponder = f;
            r = [a runModal] == NSAlertFirstButtonReturn;
            text = f.stringValue;
            if (!r || (int)text.length >= min_chars) break;
            // On hardware the applet would not have accepted the shorter text (OK stayed disabled); a game that rejects it re-opens the keyboard for ever, so the box comes back with the rule instead
            info = [info stringByAppendingFormat:@"\nAt least %d characters are needed here.", min_chars];
        }
    });
    if (!r) return 0;
    (void)max_chars;                              // Truncation is done uniformly in hle_swkbd.c in UTF-16 units
    snprintf(out, out_cap, "%s", text.UTF8String);
    return 1;
}
