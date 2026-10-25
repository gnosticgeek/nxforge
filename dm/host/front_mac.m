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

// Quick settings: a sidebar over the right of the game picture (Esc, ⇧⌘G or the Graphics menu opens it; Esc, its close button or Resume game closes it), fullscreen too. Kept per game in the user
// defaults (the app bundle's own domain; the keys name the game for a bare dmhost); a setting the environment names wins over its saved value and is not saved.
// - Graphics & shaders: the present filter (front.h mtl_present_filter_set, nvn_mtl.m), from the next frame, so the game runs on behind the sidebar and shows the change at once.
//   DM_PRESENT_FILTER / DM_PRESENT_FILTER_STRENGTH / DM_PRESENT_SCANLINE in the environment.
// - Performance: a frame-rate counter in a corner of the game picture, the frames put on screen in the last second (nvn_mtl.m mtl_present_count, as on the iPhone). DM_SHOW_FPS=0 / 1.
// - Mods: each folder in ~/Library/Application Support/nxnative/<title ID>/mods is a mod, the game's RomFS files it replaces either in it or in its romfs folder (the layout other
//   Switch tools use). The enabled ones are overlaid on the RomFS at launch in name order, the first one holding a file winning (hle_fs.c DM_ROMFS_OVERLAY, which names them),
//   so a change applies on the next launch. DM_ROMFS_OVERLAY in the environment replaces them.
// - Cheats: not in the host yet; the row says so.
// While the sidebar is up the game sees what it sees when its window loses focus: its input is released (input_release) and its focus state is out of focus (dm_focus_set 2), so a game
// that pauses for the HOME menu pauses; the keyboard goes to the sidebar's controls. The game itself is not suspended, so the filter shows live
static NSString *const g_pfx_title[DM_PFX_N] = {@"Off", @"Sharpen", @"Pixel-perfect", @"CRT"};
static NSString *const g_fps_pos[4] = {@"Top left", @"Top right", @"Bottom left", @"Bottom right"};
static NSString *pfx_key(NSString *what) { return [NSString stringWithFormat:@"DMPresentFilter.%@.%s", what, DM_GAME_NAME]; }
static NSString *opt_key(NSString *what) { return [NSString stringWithFormat:@"DMQuickSettings.%@.%s", what, DM_GAME_NAME]; }
static int g_menu_open;   // main thread: the sidebar is up (the window's focus notifications leave the game out of focus meanwhile)

static NSString *mods_dir(void) {
    NSURL *u = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return [u.path stringByAppendingFormat:@"/nxnative/%s/mods", DM_GAME_ID];
}
static NSArray<NSString *> *mods_list(void) {   // the mod folders, in the order they are overlaid
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

static NSTextField *label(NSString *s, CGFloat size, NSFontWeight w, NSColor *c) {
    NSTextField *l = [NSTextField labelWithString:s]; l.font = [NSFont systemFontOfSize:size weight:w]; l.textColor = c;
    l.lineBreakMode = NSLineBreakByTruncatingTail; [l setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return l;
}
static NSImageView *symbol(NSString *name, CGFloat size, NSColor *c) {
    NSImageView *v = [NSImageView imageViewWithImage:[[NSImage imageWithSystemSymbolName:name accessibilityDescription:nil] imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:size weight:NSFontWeightRegular]]];
    v.contentTintColor = c; return v;
}
static NSView *hrow(NSArray<NSView *> *views, CGFloat spacing) {   // left to right, vertically centred, the first view taking the room left over
    NSStackView *s = [NSStackView stackViewWithViews:views]; s.orientation = NSUserInterfaceLayoutOrientationHorizontal; s.alignment = NSLayoutAttributeCenterY; s.spacing = spacing;
    s.distribution = NSStackViewDistributionFill; [views.firstObject setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return s;
}
static NSView *spacer(void) { NSView *v = [NSView new]; [v setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal]; return v; }
static NSView *separator(void) { NSBox *b = [NSBox new]; b.boxType = NSBoxSeparator; return b; }

@interface DmFlipped : NSView @end
@implementation DmFlipped
- (BOOL)isFlipped { return YES; }
- (void)mouseDown:(NSEvent *)e { (void)e; }   // a click on the sidebar's background is not a touch on the game behind it
@end

// One collapsible section: a header row (icon, title, a summary or a count, chevron) whose click shows or hides its body
@interface DmSection : NSObject
@property NSView *header, *body; @property NSTextField *detail; @property NSTextField *badge; @property NSImageView *chevron; @property BOOL enabled;
@end
@implementation DmSection @end

@interface DmSettings : NSObject
@property NSView *view; @property NSStackView *stack; @property NSMutableArray<DmSection *> *sections; @property NSMutableArray<NSMenuItem *> *items;
@property NSSegmentedControl *seg; @property NSSlider *slider; @property NSTextField *pct, *rowsNote; @property NSPopUpButton *rows, *fpsPos; @property NSSwitch *fps;
@property NSStackView *modList; @property NSTextField *fpsLabel; @property NSTimer *fpsTimer; @property uint64_t fpsN0; @property double fpsT0;
@end
@implementation DmSettings
// ---- the settings
- (void)apply:(int)mode strength:(float)k save:(BOOL)save {
    mtl_present_filter_set(mode, k);
    if (save && !getenv("DM_PRESENT_FILTER")) { NSUserDefaults *d = NSUserDefaults.standardUserDefaults; [d setInteger:mode forKey:pfx_key(@"mode")]; [d setFloat:k forKey:pfx_key(@"strength")]; }
    [self sync];
}
- (BOOL)fpsOn {
    const char *e = getenv("DM_SHOW_FPS"); if (e) return atoi(e) != 0;
    return [NSUserDefaults.standardUserDefaults boolForKey:opt_key(@"fps")];
}
- (int)fpsCorner { return (int)MIN(MAX([NSUserDefaults.standardUserDefaults integerForKey:opt_key(@"fpsPos")], 0), 3); }
- (NSArray<NSString *> *)modsWanted { return [NSUserDefaults.standardUserDefaults arrayForKey:opt_key(@"mods")] ?: @[]; }
- (void)sync {   // every control, menu check mark and section summary shows the settings now
    float k; int m = mtl_present_filter(&k);
    for (NSMenuItem *it in self.items) it.state = it.tag == m ? NSControlStateValueOn : NSControlStateValueOff;
    if (!self.view) return;
    self.seg.selectedSegment = m; self.slider.floatValue = k; self.pct.stringValue = [NSString stringWithFormat:@"%.0f%%", k * 100];
    BOOL strength = m == DM_PFX_SHARPEN || m == DM_PFX_CRT;   // the pixel filter has no strength
    self.slider.enabled = strength; self.pct.textColor = strength ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor;
    [self.rows selectItemAtIndex:mtl_present_scanline()]; self.rows.enabled = m == DM_PFX_CRT; self.rowsNote.hidden = m == DM_PFX_CRT;
    self.fps.state = self.fpsOn ? NSControlStateValueOn : NSControlStateValueOff; [self.fpsPos selectItemAtIndex:self.fpsCorner]; self.fpsPos.enabled = self.fpsOn;
    NSArray *want = self.modsWanted; NSUInteger on = 0; for (NSString *n in mods_list()) on += [want containsObject:n];
    self.sections[0].detail.stringValue = m ? g_pfx_title[m] : @"";
    self.sections[1].detail.stringValue = self.fpsOn ? @"FPS on" : @"FPS off";
    self.sections[2].detail.stringValue = on ? @"" : @"None enabled"; self.sections[2].badge.hidden = !on;
    self.sections[2].badge.stringValue = [NSString stringWithFormat:@"%lu enabled", (unsigned long)on];
}
- (void)pickItem:(NSMenuItem *)it { float k; mtl_present_filter(&k); [self apply:(int)it.tag strength:k save:YES]; }
- (void)pickSeg:(NSSegmentedControl *)c { [self apply:(int)c.selectedSegment strength:self.slider.floatValue save:YES]; }
- (void)slide:(NSSlider *)sl { [self apply:mtl_present_filter(NULL) strength:sl.floatValue save:YES]; }
- (void)pickRows:(NSPopUpButton *)p {   // 0 = auto, else source rows per scanline
    mtl_present_scanline_set((int)p.indexOfSelectedItem);
    if (!getenv("DM_PRESENT_SCANLINE")) [NSUserDefaults.standardUserDefaults setInteger:p.indexOfSelectedItem forKey:pfx_key(@"scanline")];
    [self sync];
}
- (void)pickFps:(NSSwitch *)s { if (!getenv("DM_SHOW_FPS")) [NSUserDefaults.standardUserDefaults setBool:s.state == NSControlStateValueOn forKey:opt_key(@"fps")]; [self fpsCounter]; [self sync]; }
- (void)pickFpsPos:(NSPopUpButton *)p { [NSUserDefaults.standardUserDefaults setInteger:p.indexOfSelectedItem forKey:opt_key(@"fpsPos")]; [self fpsCounter]; [self sync]; }
- (void)pickMod:(NSSwitch *)s {
    NSString *n = s.identifier; NSMutableArray *want = [self.modsWanted mutableCopy];
    [want removeObject:n]; if (s.state == NSControlStateValueOn) [want addObject:n];
    [NSUserDefaults.standardUserDefaults setObject:want forKey:opt_key(@"mods")];
    [self fillMods]; [self sync];
}
- (void)openMods:(id)sender {
    (void)sender; NSString *d = mods_dir();
    [NSFileManager.defaultManager createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:d]];
}
- (void)refreshMods:(id)sender { (void)sender; [self fillMods]; [self sync]; }

// ---- the frame-rate counter, in the chosen corner of the game view
- (void)fpsCounter {
    if (!self.fpsOn) { [self.fpsTimer invalidate]; self.fpsTimer = nil; [self.fpsLabel removeFromSuperview]; self.fpsLabel = nil; return; }
    NSView *gv = g_win.contentView;
    if (!self.fpsLabel) {
        NSTextField *l = label(@"-- FPS", 13, NSFontWeightSemibold, NSColor.whiteColor);
        l.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightSemibold];
        NSShadow *sh = [NSShadow new]; sh.shadowColor = [NSColor colorWithWhite:0 alpha:0.8]; sh.shadowBlurRadius = 2; sh.shadowOffset = NSMakeSize(0, -1); l.shadow = sh;
        [gv addSubview:l positioned:NSWindowBelow relativeTo:self.view]; self.fpsLabel = l;
        self.fpsN0 = mtl_present_count(); self.fpsT0 = CACurrentMediaTime();
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
    int c = self.fpsCorner; NSSize b = gv.bounds.size, s = self.fpsLabel.frame.size; s.width += 24;   // room for wider readings
    self.fpsLabel.frame = NSMakeRect(c & 1 ? b.width - s.width - 12 : 12, c & 2 ? 10 : b.height - s.height - 10, s.width, s.height);
    self.fpsLabel.alignment = c & 1 ? NSTextAlignmentRight : NSTextAlignmentLeft;
    self.fpsLabel.autoresizingMask = (c & 1 ? NSViewMinXMargin : NSViewMaxXMargin) | (c & 2 ? NSViewMaxYMargin : NSViewMinYMargin);
}

// ---- the sidebar
- (void)add:(NSView *)v to:(NSStackView *)s { [s addArrangedSubview:v]; [v.widthAnchor constraintEqualToAnchor:s.widthAnchor].active = YES; }
- (DmSection *)section:(NSString *)icon title:(NSString *)title body:(NSView *)body {
    DmSection *x = [DmSection new]; x.body = body; x.enabled = body != nil;
    NSColor *tc = body ? NSColor.labelColor : NSColor.tertiaryLabelColor;
    NSImageView *ic = symbol(icon, 20, body ? NSColor.systemBlueColor : NSColor.tertiaryLabelColor); [ic.widthAnchor constraintEqualToConstant:28].active = YES;
    x.detail = label(@"", 13, NSFontWeightRegular, NSColor.secondaryLabelColor);
    x.badge = label(@"", 12, NSFontWeightMedium, NSColor.systemBlueColor); x.badge.hidden = YES; x.badge.wantsLayer = YES;
    x.badge.layer.backgroundColor = [NSColor.systemBlueColor colorWithAlphaComponent:0.18].CGColor; x.badge.layer.cornerRadius = 9; x.badge.alignment = NSTextAlignmentCenter;
    [x.badge.heightAnchor constraintEqualToConstant:20].active = YES; [x.badge.widthAnchor constraintGreaterThanOrEqualToConstant:80].active = YES;
    x.chevron = symbol(@"chevron.right", 12, NSColor.secondaryLabelColor); x.chevron.hidden = !body; [x.chevron.widthAnchor constraintEqualToConstant:16].active = YES;
    NSView *row = hrow(@[label(title, 16, NSFontWeightSemibold, tc), x.detail, x.badge, x.chevron], 10);
    NSView *h = hrow(@[row], 0); NSStackView *hs = (NSStackView *)h; [hs insertArrangedSubview:ic atIndex:0]; hs.spacing = 12;
    [h.heightAnchor constraintEqualToConstant:50].active = YES;
    if (body) {   // the whole row is the button
        NSButton *b = [NSButton buttonWithTitle:@"" target:self action:@selector(toggleSection:)]; b.bordered = NO; b.transparent = YES; b.tag = self.sections.count;
        b.translatesAutoresizingMaskIntoConstraints = NO; [h addSubview:b];
        [NSLayoutConstraint activateConstraints:@[[b.leadingAnchor constraintEqualToAnchor:h.leadingAnchor], [b.trailingAnchor constraintEqualToAnchor:h.trailingAnchor],
                                                  [b.topAnchor constraintEqualToAnchor:h.topAnchor], [b.bottomAnchor constraintEqualToAnchor:h.bottomAnchor]]];
        b.toolTip = title;
    } else x.detail.stringValue = @"Coming later";
    x.header = h; [self.sections addObject:x];
    if (self.sections.count > 1) [self add:separator() to:self.stack];
    [self add:h to:self.stack];
    if (body) { body.hidden = YES; [self add:body to:self.stack]; }
    return x;
}
- (void)expand:(NSInteger)i {   // one section open at a time; i < 0 closes them all
    for (NSInteger j = 0; j < (NSInteger)self.sections.count; j++) {
        DmSection *x = self.sections[j]; if (!x.body) continue; BOOL open = j == i;
        x.body.hidden = !open; x.chevron.image = [[NSImage imageWithSystemSymbolName:open ? @"chevron.down" : @"chevron.right" accessibilityDescription:nil]
                                                 imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightRegular]];
        x.detail.hidden = open && j != 2;   // the mods count stays up while its list is open, as a reminder of what the next launch loads
    }
    [NSUserDefaults.standardUserDefaults setInteger:i forKey:opt_key(@"section")];
}
- (void)toggleSection:(NSButton *)b { [self expand:self.sections[b.tag].body.hidden ? b.tag : -1]; }
- (NSStackView *)vstack:(CGFloat)spacing { NSStackView *s = [NSStackView new]; s.orientation = NSUserInterfaceLayoutOrientationVertical; s.alignment = NSLayoutAttributeLeading; s.spacing = spacing; return s; }
- (NSView *)graphicsBody {
    NSStackView *s = [self vstack:12]; s.edgeInsets = NSEdgeInsetsMake(0, 0, 16, 0);
    [self add:label(@"Filter", 13, NSFontWeightRegular, NSColor.secondaryLabelColor) to:s];
    self.seg = [NSSegmentedControl segmentedControlWithLabels:[NSArray arrayWithObjects:g_pfx_title count:DM_PFX_N] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(pickSeg:)];
    self.seg.segmentDistribution = NSSegmentDistributionFillEqually; self.seg.controlSize = NSControlSizeLarge; [self add:self.seg to:s];
    self.slider = [NSSlider sliderWithValue:0.5 minValue:0 maxValue:1 target:self action:@selector(slide:)]; self.slider.continuous = YES;
    self.pct = label(@"50%", 13, NSFontWeightRegular, NSColor.secondaryLabelColor); self.pct.alignment = NSTextAlignmentRight; [self.pct.widthAnchor constraintEqualToConstant:44].active = YES;
    NSTextField *l1 = label(@"Strength", 14, NSFontWeightRegular, NSColor.labelColor), *l2 = label(@"Scanlines", 14, NSFontWeightRegular, NSColor.labelColor);
    for (NSTextField *l in @[l1, l2]) [l.widthAnchor constraintEqualToConstant:92].active = YES;
    NSView *r1 = hrow(@[self.slider, self.pct], 10); NSStackView *r1s = (NSStackView *)r1; [r1s insertArrangedSubview:l1 atIndex:0]; [self add:r1 to:s];
    // CRT scanline height in the game's frame rows: Auto gives about 240 lines; a pixel-art game's own pixel size (frame rows per art pixel) lines them up with its art
    self.rows = [NSPopUpButton new]; [self.rows addItemWithTitle:@"Auto"];
    for (int i = 1; i <= 8; i++) [self.rows addItemWithTitle:[NSString stringWithFormat:@"%d frame row%s", i, i == 1 ? "" : "s"]];
    self.rows.target = self; self.rows.action = @selector(pickRows:); self.rows.controlSize = NSControlSizeLarge;
    NSView *r2 = hrow(@[self.rows], 10); [(NSStackView *)r2 insertArrangedSubview:l2 atIndex:0]; [self add:r2 to:s];
    self.rowsNote = label(@"Available with CRT", 11, NSFontWeightRegular, NSColor.tertiaryLabelColor);
    NSView *r3 = hrow(@[spacer()], 0); NSStackView *r3s = (NSStackView *)r3; [r3s insertArrangedSubview:self.rowsNote atIndex:0]; r3s.edgeInsets = NSEdgeInsetsMake(-6, 102, 0, 0);
    [self add:r3 to:s];
    return s;
}
- (NSView *)performanceBody {
    NSStackView *s = [self vstack:12]; s.edgeInsets = NSEdgeInsetsMake(0, 0, 16, 0);
    self.fps = [NSSwitch new]; self.fps.target = self; self.fps.action = @selector(pickFps:);
    [self add:hrow(@[label(@"Show FPS", 14, NSFontWeightRegular, NSColor.labelColor), self.fps], 10) to:s];
    self.fpsPos = [NSPopUpButton new]; [self.fpsPos addItemsWithTitles:[NSArray arrayWithObjects:g_fps_pos count:4]];
    self.fpsPos.target = self; self.fpsPos.action = @selector(pickFpsPos:); self.fpsPos.controlSize = NSControlSizeLarge; [self.fpsPos.widthAnchor constraintEqualToConstant:190].active = YES;
    [self add:hrow(@[label(@"Counter position", 14, NSFontWeightRegular, NSColor.labelColor), self.fpsPos], 10) to:s];
    return s;
}
- (NSView *)modsBody {
    NSStackView *s = [self vstack:12]; s.edgeInsets = NSEdgeInsetsMake(0, 0, 16, 0);
    NSTextField *about = label(@"Each folder in this game's mods folder replaces game files. Enabled mods load in name order; the first one with a file wins.", 12, NSFontWeightRegular, NSColor.secondaryLabelColor);
    about.lineBreakMode = NSLineBreakByWordWrapping; about.maximumNumberOfLines = 0; about.preferredMaxLayoutWidth = 360;
    [self add:about to:s];
    self.modList = [self vstack:14]; [self add:self.modList to:s];
    NSButton *open = [NSButton buttonWithTitle:@"Open mods folder" image:[NSImage imageWithSystemSymbolName:@"folder" accessibilityDescription:nil] target:self action:@selector(openMods:)];
    NSButton *ref = [NSButton buttonWithTitle:@"Refresh" image:[NSImage imageWithSystemSymbolName:@"arrow.clockwise" accessibilityDescription:nil] target:self action:@selector(refreshMods:)];
    for (NSButton *b in @[open, ref]) { b.controlSize = NSControlSizeLarge; b.imagePosition = NSImageLeading; }
    NSStackView *bs = (NSStackView *)hrow(@[open, ref], 10); bs.distribution = NSStackViewDistributionFillEqually; [self add:bs to:s];
    [self add:label(@"Restart the game to apply mod changes.", 12, NSFontWeightRegular, NSColor.secondaryLabelColor) to:s];
    [self fillMods];
    return s;
}
- (void)fillMods {
    if (!self.modList) return;
    for (NSView *v in self.modList.arrangedSubviews.copy) [v removeFromSuperview];
    NSArray *want = self.modsWanted, *all = mods_list();
    if (!all.count) {
        NSTextField *t = label(@"No mods yet. Put each mod in a folder of its own in the mods folder (its files, or a romfs folder holding them), then Refresh.", 13, NSFontWeightRegular, NSColor.tertiaryLabelColor);
        t.lineBreakMode = NSLineBreakByWordWrapping; t.maximumNumberOfLines = 0; t.preferredMaxLayoutWidth = 360; [self add:t to:self.modList]; return;
    }
    for (NSString *n in all) {
        BOOL on = [want containsObject:n], ran = [g_mods_run containsObject:n];
        NSStackView *txt = [self vstack:3]; [txt addArrangedSubview:label(n, 14, NSFontWeightMedium, NSColor.labelColor)];
        NSString *note = !g_mods_run ? @"Not used: DM_ROMFS_OVERLAY is set" : on != ran ? @"Restart required" : on ? @"Loaded" : @"Off";
        NSTextField *nl = label(note, 12, NSFontWeightRegular, NSColor.secondaryLabelColor);
        if (g_mods_run && on != ran) [txt addArrangedSubview:hrow(@[symbol(@"circle.fill", 7, NSColor.systemOrangeColor), nl], 6)]; else [txt addArrangedSubview:nl];
        [txt setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSSwitch *sw = [NSSwitch new]; sw.state = on ? NSControlStateValueOn : NSControlStateValueOff; sw.identifier = n; sw.target = self; sw.action = @selector(pickMod:);
        [self add:hrow(@[txt, sw], 10) to:self.modList];
    }
}
- (void)build {
    NSView *gv = g_win.contentView; CGFloat w = 440;
    DmFlipped *v = [[DmFlipped alloc] initWithFrame:NSMakeRect(gv.bounds.size.width - w, 0, w, gv.bounds.size.height)];
    v.autoresizingMask = NSViewMinXMargin | NSViewHeightSizable; v.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    v.wantsLayer = YES; v.layer.backgroundColor = [NSColor colorWithSRGBRed:0.106 green:0.114 blue:0.133 alpha:1].CGColor;   // opaque: the game's picture showed through a translucent one as stray lines
    CALayer *edge = [CALayer layer]; edge.backgroundColor = [NSColor colorWithWhite:1 alpha:0.08].CGColor; edge.frame = CGRectMake(0, 0, 1, 10000); [v.layer addSublayer:edge];
    // Header: what this is and for which game, with a close button
    NSTextField *kicker = label(@"IN-GAME OPTIONS", 11, NSFontWeightSemibold, NSColor.secondaryLabelColor);
    kicker.attributedStringValue = [[NSAttributedString alloc] initWithString:@"IN-GAME OPTIONS" attributes:@{NSKernAttributeName: @1.2, NSFontAttributeName: kicker.font, NSForegroundColorAttributeName: NSColor.secondaryLabelColor}];
    NSStackView *head = [self vstack:4];
    [head addArrangedSubview:kicker]; [head setCustomSpacing:8 afterView:kicker];
    [head addArrangedSubview:label(@"Quick settings", 28, NSFontWeightBold, NSColor.labelColor)];
    [head addArrangedSubview:label(@DM_GAME_NAME, 15, NSFontWeightRegular, NSColor.secondaryLabelColor)];
    NSButton *close = [NSButton buttonWithImage:[[NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"Close"] imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightSemibold]]
                                         target:self action:@selector(toggle:)];
    close.bordered = NO; close.wantsLayer = YES; close.layer.cornerRadius = 18; close.layer.backgroundColor = [NSColor colorWithWhite:1 alpha:0.1].CGColor; close.contentTintColor = NSColor.labelColor;
    // Sections, scrolling when the window is short
    self.stack = [self vstack:0]; self.sections = [NSMutableArray array];
    [self section:@"display" title:@"Graphics & shaders" body:[self graphicsBody]];
    [self section:@"chart.bar.fill" title:@"Performance" body:[self performanceBody]];
    [self section:@"puzzlepiece.extension" title:@"Mods" body:[self modsBody]];
    [self section:@"wand.and.stars" title:@"Cheats" body:nil];
    DmFlipped *doc = [DmFlipped new]; doc.translatesAutoresizingMaskIntoConstraints = NO; self.stack.translatesAutoresizingMaskIntoConstraints = NO; [doc addSubview:self.stack];
    NSScrollView *sc = [NSScrollView new]; sc.drawsBackground = NO; sc.hasVerticalScroller = YES; sc.autohidesScrollers = YES; sc.documentView = doc;
    // Footer: resume, and how else to close
    NSTextField *saved = label(@"Settings saved for this game", 12, NSFontWeightRegular, NSColor.secondaryLabelColor);
    NSButton *resume = [NSButton buttonWithTitle:@"" target:self action:@selector(toggle:)]; resume.bordered = NO; resume.wantsLayer = YES;
    resume.layer.backgroundColor = NSColor.systemBlueColor.CGColor; resume.layer.cornerRadius = 10; resume.keyEquivalent = @"\r";
    resume.attributedTitle = [[NSAttributedString alloc] initWithString:@"Resume game" attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:16 weight:NSFontWeightMedium], NSForegroundColorAttributeName: NSColor.whiteColor}];
    NSTextField *esc = label(@"Esc", 12, NSFontWeightMedium, NSColor.labelColor); esc.alignment = NSTextAlignmentCenter; esc.wantsLayer = YES;
    esc.layer.backgroundColor = [NSColor colorWithWhite:1 alpha:0.1].CGColor; esc.layer.cornerRadius = 5; esc.layer.borderWidth = 1; esc.layer.borderColor = [NSColor colorWithWhite:1 alpha:0.15].CGColor;
    [esc.widthAnchor constraintEqualToConstant:40].active = YES; [esc.heightAnchor constraintEqualToConstant:24].active = YES;
    NSView *hint = hrow(@[esc, label(@"Close menu", 13, NSFontWeightRegular, NSColor.secondaryLabelColor)], 10);
    NSView *savedRow = hrow(@[symbol(@"gearshape", 14, NSColor.secondaryLabelColor), saved], 8);
    for (NSView *x in @[head, close, sc, savedRow, resume, hint]) { x.translatesAutoresizingMaskIntoConstraints = NO; [v addSubview:x]; }
    NSView *top = separator(), *bottom = separator(); for (NSView *x in @[top, bottom]) { x.translatesAutoresizingMaskIntoConstraints = NO; [v addSubview:x]; }
    CGFloat m = 28;
    [NSLayoutConstraint activateConstraints:@[
        [head.topAnchor constraintEqualToAnchor:v.topAnchor constant:34], [head.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:m],
        [head.trailingAnchor constraintLessThanOrEqualToAnchor:close.leadingAnchor constant:-8],
        [close.topAnchor constraintEqualToAnchor:v.topAnchor constant:28], [close.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-24],
        [close.widthAnchor constraintEqualToConstant:36], [close.heightAnchor constraintEqualToConstant:36],
        [top.topAnchor constraintEqualToAnchor:head.bottomAnchor constant:20], [top.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:m], [top.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-m],
        [sc.topAnchor constraintEqualToAnchor:top.bottomAnchor constant:4], [sc.leadingAnchor constraintEqualToAnchor:v.leadingAnchor], [sc.trailingAnchor constraintEqualToAnchor:v.trailingAnchor],
        [sc.bottomAnchor constraintEqualToAnchor:bottom.topAnchor constant:-4],
        [doc.leadingAnchor constraintEqualToAnchor:sc.contentView.leadingAnchor], [doc.trailingAnchor constraintEqualToAnchor:sc.contentView.trailingAnchor], [doc.topAnchor constraintEqualToAnchor:sc.contentView.topAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:doc.topAnchor], [self.stack.bottomAnchor constraintEqualToAnchor:doc.bottomAnchor],
        [self.stack.leadingAnchor constraintEqualToAnchor:doc.leadingAnchor constant:m], [self.stack.trailingAnchor constraintEqualToAnchor:doc.trailingAnchor constant:-m],
        [bottom.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:m], [bottom.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-m],
        [savedRow.topAnchor constraintEqualToAnchor:bottom.bottomAnchor constant:16], [savedRow.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:m],
        [resume.topAnchor constraintEqualToAnchor:savedRow.bottomAnchor constant:18], [resume.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:m],
        [resume.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-m], [resume.heightAnchor constraintEqualToConstant:46],
        [hint.topAnchor constraintEqualToAnchor:resume.bottomAnchor constant:12], [hint.centerXAnchor constraintEqualToAnchor:v.centerXAnchor],
        [hint.bottomAnchor constraintEqualToAnchor:v.bottomAnchor constant:-18],
    ]];
    self.view = v;
    NSInteger open = [NSUserDefaults.standardUserDefaults objectForKey:opt_key(@"section")] ? [NSUserDefaults.standardUserDefaults integerForKey:opt_key(@"section")] : 0;
    [self expand:open >= 0 && open < 3 ? open : -1];
}
- (void)toggle:(id)sender {
    (void)sender;
    if (!g_menu_open) {
        if (!self.view) [self build];
        NSView *gv = g_win.contentView; CGFloat w = MIN(440, gv.bounds.size.width);
        self.view.frame = NSMakeRect(gv.bounds.size.width - w, 0, w, gv.bounds.size.height);
        [self fillMods]; [self sync];
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
- (BOOL)validateMenuItem:(NSMenuItem *)it { if (it.action == @selector(toggle:)) it.state = g_menu_open ? NSControlStateValueOn : NSControlStateValueOff; return YES; }
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
    [self sync]; [self fpsCounter];
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
