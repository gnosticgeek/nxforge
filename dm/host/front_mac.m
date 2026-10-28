// Mac front end: with DM_WINDOW=1 open a window (CAMetalLayer, for the graphics backend to present frames) + keyboard and controllers → dm_input; the guest runs on a large-stack thread instead and the main thread belongs to AppKit.
// Without DM_WINDOW: the guest runs directly on the current thread, behaving the same as with no front end (windowless tests use this).
// The window is fullscreen-capable (the green button and ⌃⌘F); DM_FULLSCREEN=1 starts it that way. ⌘Q quits; the left mouse button is the touchscreen.
// Esc (or ⇧⌘G, or the Graphics menu) opens the Quick settings sidebar over the game (DmSettings): the present filter, a frame-rate counter and mods, kept per game.
// Key map (Nintendo layout): WASD left stick, arrow keys D-pad, J=A K=B U=X I=Y, Q=L E=R, Z=ZL C=ZR, F=press left stick G=press right stick, Return=+ Tab=−, Space=shake the controller; the sidebar's Controls section remaps it and the controllers' buttons per game (controls_load).
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
#include "capture_mac.h"
#include "hle.h"
#include "pad_slots.h"
#include "haptics_apple.h"
#include "motion_apple.h"
#include "motion_pro_mac.h"
#include <signal.h>
#include <math.h>

static CAMetalLayer *g_layer;
static uint64_t g_btn;
static int g_w, g_a, g_s, g_d;
static int g_input_on = 1;   // main thread: the game window is key, so its keyboard, mouse and controllers reach the game (input_release / input_resume)
static int g_menu_open;   // main thread: the Quick settings sidebar is up (the window's focus notifications leave the game out of focus meanwhile)
static void (*g_menu_toggle)(void);   // opens or closes it (DmSettings toggle:), for the controller's Home button
static NSString *opt_key(NSString *what);

void *front_metal_layer(void) { return (__bridge void *)g_layer; }
static _Atomic int g_fullscreen;   // the window is in fullscreen (set on NSWindowDidEnter/ExitFullScreenNotification); the present path does without the display link there, or sets its latency (nvn_mtl.m link_sync)
int front_fullscreen(void) { return g_fullscreen; }
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
// Key and controller map (the sidebar's Controls section, quick_settings_mac.swift; saved per game). Actions 0–15 are the NpadButton bits (dm_input.h: A B X Y, the stick presses,
// L R ZL ZR, + −, the D-pad), 16–19 the left stick (up, left, down, right) and 20 shaking the controller. The keyboard map holds a key code per action (0xffff: none), the controller map a
// GameController input name (GCInputButtonA…, a key of the controller's physicalInputProfile.buttons) per button 0–11; a controller's D-pad and sticks stay where they are. The defaults are
// the fixed map from before: WASD left stick, arrow keys D-pad, J=A K=B U=X I=Y, Q=L E=R, Z=ZL C=ZR, F / G the stick presses, Return=+ Tab=−, Space shakes; buttons by position
enum { ACT_STICK_UP = 16, ACT_STICK_LEFT, ACT_STICK_DOWN, ACT_STICK_RIGHT, ACT_SHAKE, ACT_N, PAD_N = 12, KEY_NONE = 0xffff };
static const unsigned short g_key_default[ACT_N] = {38, 40, 32, 34, 3, 5, 12, 14, 6, 8, 36, 48, 123, 126, 124, 125, 13, 0, 1, 2, 49};
static unsigned short g_keys[ACT_N];
static NSString *g_pad[PAD_N];
static NSString *pad_default(int i) {
    NSString *d[PAD_N] = {GCInputButtonB, GCInputButtonA, GCInputButtonY, GCInputButtonX, GCInputLeftThumbstickButton, GCInputRightThumbstickButton,
                          GCInputLeftShoulder, GCInputRightShoulder, GCInputLeftTrigger, GCInputRightTrigger, GCInputButtonMenu, GCInputButtonOptions};
    return d[i];
}
static void controls_load(void) {   // main thread: the saved map over the defaults (at start, and when the sidebar changes it)
    NSDictionary *k = [NSUserDefaults.standardUserDefaults dictionaryForKey:opt_key(@"keys")], *p = [NSUserDefaults.standardUserDefaults dictionaryForKey:opt_key(@"pad")];
    for (int i = 0; i < ACT_N; i++) { NSNumber *n = k[@(i).stringValue]; g_keys[i] = n ? n.unsignedShortValue : g_key_default[i]; }
    for (int i = 0; i < PAD_N; i++) { NSString *n = p[@(i).stringValue]; g_pad[i] = [n isKindOfClass:NSString.class] ? n : pad_default(i); }
}
static void on_key(NSEvent *e, int down) {
    if (!g_input_on) return;
    unsigned short c = e.keyCode; uint64_t m = 0;
    for (int i = 0; i < ACT_N; i++) if (g_keys[i] == c) {
        if (i < 16) m |= 1ull << i; else if (i == ACT_SHAKE) m |= DM_BTN_SHAKE;   // shaken while held
        else if (i == ACT_STICK_UP) g_w = down; else if (i == ACT_STICK_LEFT) g_a = down; else if (i == ACT_STICK_DOWN) g_s = down; else g_d = down;
    }
    g_btn = down ? (g_btn | m) : (g_btn & ~m);
    push();
}
// Assigning (the Controls section: front_qs_assign): the next key, or the next controller button, becomes that action's; Esc cancels. Another action holding that key loses it
static int g_assign = -1, g_assign_pad;
void front_qs_assign(int action, int pad) { g_assign = action >= 0 && action < (pad ? PAD_N : ACT_N) ? action : -1; g_assign_pad = pad; }
int front_qs_assigning(void) { return g_assign < 0 ? -1 : g_assign * 2 + g_assign_pad; }
void front_qs_controls_reload(void) { controls_load(); }
static void toast(NSString *msg);
static void assign_save(NSString *map, NSString *names, int action, id value, NSString *label, BOOL key) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSMutableDictionary *m = [[d dictionaryForKey:opt_key(map)] mutableCopy] ?: [NSMutableDictionary dictionary], *n = [[d dictionaryForKey:opt_key(names)] mutableCopy] ?: [NSMutableDictionary dictionary];
    for (int i = 0; i < (key ? ACT_N : PAD_N); i++) if (i != action) {
        id cur = m[@(i).stringValue] ?: (key ? (id)@(g_key_default[i]) : pad_default(i));
        if ([cur isEqual:value]) { m[@(i).stringValue] = key ? @(KEY_NONE) : @""; n[@(i).stringValue] = @"Not set"; }
    }
    m[@(action).stringValue] = value; n[@(action).stringValue] = label;
    [d setObject:m forKey:opt_key(map)]; [d setObject:n forKey:opt_key(names)];
    g_assign = -1; controls_load(); dm_qs_refresh();
}
static NSString *key_label(NSEvent *e) {
    switch (e.keyCode) {
        case 36: return @"Return"; case 48: return @"Tab"; case 49: return @"Space"; case 51: return @"Delete"; case 76: return @"Enter";
        case 123: return @"←"; case 124: return @"→"; case 125: return @"↓"; case 126: return @"↑";
    }
    NSString *c = e.charactersIgnoringModifiers.uppercaseString;
    return c.length && [c characterAtIndex:0] > ' ' ? c : [NSString stringWithFormat:@"Key %d", e.keyCode];
}
static BOOL assign_key(NSEvent *e) {   // key monitor: the key that answers a pending assignment (YES: taken)
    if (g_assign < 0 || g_assign_pad || e.type != NSEventTypeKeyDown) return NO;
    if (e.keyCode == 53) { g_assign = -1; dm_qs_refresh(); return YES; }
    assign_save(@"keys", @"keyNames", g_assign, @(e.keyCode), key_label(e), YES);
    return YES;
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
static int g_pad_quiet;   // the sidebar just closed: controllers stay silent until every button is up, so the press that closed it does not reach the game
static void pad_read(GCExtendedGamepad *g) {
    if (!g_input_on) return;
    int p = g_merge ? 0 : pad_slot_of(&g_slots, (__bridge const void *)g.controller); if (p < 0) return;
    dm_haptics_apple_controller(p, g.controller);
    uint64_t m = 0; GCPhysicalInputProfile *pf = g.controller.physicalInputProfile;
    for (int i = 0; i < PAD_N; i++) if (g_pad[i].length && pf.buttons[g_pad[i]].isPressed) m |= 1ull << i;   // the map (default by position: right A, bottom B, top X, left Y); a button a pad lacks: not pressed
    #define K(btn, bit) if (btn.isPressed) m |= bit
    K(g.dpad.left, DM_BTN_LEFT); K(g.dpad.up, DM_BTN_UP); K(g.dpad.right, DM_BTN_RIGHT); K(g.dpad.down, DM_BTN_DOWN);
    #undef K
    if (g_pad_quiet) { if (m) { dm_pad_set_player(p, 0, 0, 0, 0, 0); return; } g_pad_quiet = 0; }
    dm_pad_set_player(p, m, pad_axis(g.leftThumbstick.xAxis.value), pad_axis(g.leftThumbstick.yAxis.value), pad_axis(g.rightThumbstick.xAxis.value), pad_axis(g.rightThumbstick.yAxis.value));
}
// The sidebar with a controller (after RetroReplay's pause menu): the D-pad or left stick moves the selection, left / right change its value, A (the right face button) activates it,
// B (the bottom one), + or Home close the sidebar, L / R jump between sections; a held direction repeats. quick_settings_mac.swift dm_qs_nav keeps the selection
enum { NAV_UP = 1, NAV_DOWN, NAV_LEFT, NAV_RIGHT, NAV_OK, NAV_BACK, NAV_PREV, NAV_NEXT };
static uint32_t g_nav_prev; static NSTimer *g_nav_rep;
static void pad_nav(GCExtendedGamepad *g) {
    float x = g.leftThumbstick.xAxis.value, y = g.leftThumbstick.yAxis.value; uint32_t now = 0;
    if (g.dpad.up.isPressed || y > 0.6f) now |= 1u << NAV_UP;
    if (g.dpad.down.isPressed || y < -0.6f) now |= 1u << NAV_DOWN;
    if (g.dpad.left.isPressed || x < -0.6f) now |= 1u << NAV_LEFT;
    if (g.dpad.right.isPressed || x > 0.6f) now |= 1u << NAV_RIGHT;
    if (g.buttonB.isPressed) now |= 1u << NAV_OK;
    if (g.buttonA.isPressed || g.buttonMenu.isPressed || g.buttonHome.isPressed) now |= 1u << NAV_BACK;
    if (g.leftShoulder.isPressed) now |= 1u << NAV_PREV;
    if (g.rightShoulder.isPressed) now |= 1u << NAV_NEXT;
    uint32_t pressed = now & ~g_nav_prev, dirs = (1u << NAV_UP) | (1u << NAV_DOWN) | (1u << NAV_LEFT) | (1u << NAV_RIGHT); g_nav_prev = now;
    for (int c = NAV_UP; c <= NAV_NEXT && g_menu_open; c++) if (pressed & (1u << c)) dm_qs_nav(c);
    if (!(now & dirs) || !g_menu_open) { [g_nav_rep invalidate]; g_nav_rep = nil; }
    else if (pressed & dirs) {
        [g_nav_rep invalidate];
        g_nav_rep = [NSTimer scheduledTimerWithTimeInterval:0.4 repeats:NO block:^(NSTimer *t0) { (void)t0;
            g_nav_rep = [NSTimer scheduledTimerWithTimeInterval:0.09 repeats:YES block:^(NSTimer *t) { (void)t;
                for (int c = NAV_UP; c <= NAV_RIGHT; c++) if (g_menu_open && (g_nav_prev & (1u << c))) dm_qs_nav(c); }]; }];
    }
}
static BOOL assign_pad(GCExtendedGamepad *g, GCControllerElement *el) {   // a controller button that answers a pending assignment
    if (g_assign < 0 || !g_assign_pad || ![el isKindOfClass:GCControllerButtonInput.class] || !((GCControllerButtonInput *)el).isPressed) return g_assign >= 0 && g_assign_pad;
    GCPhysicalInputProfile *pf = g.controller.physicalInputProfile; NSString *name = nil;
    for (NSString *a in el.aliases) if (pf.buttons[a] && (!name || a.length < name.length)) name = a;
    if (!name || [name hasPrefix:@"Direction Pad"] || [name isEqualToString:GCInputButtonHome]) return YES;   // the D-pad and Home stay as they are
    assign_save(@"pad", @"padNames", g_assign, name, el.localizedName ?: name, NO);
    return YES;
}
static void pad_event(GCExtendedGamepad *g, GCControllerElement *el) {
    if (assign_pad(g, el)) return;
    if (g_menu_open) { pad_nav(g); return; }
    // The controller opens the sidebar: Home, or − and + pressed together (a game sees those two for a moment)
    static BOOL held; BOOL now = g.buttonHome.isPressed || (g.buttonMenu.isPressed && g.buttonOptions.isPressed);
    if (now && !held && g_menu_toggle) { held = YES; g_nav_prev = ~0u; g_menu_toggle(); return; }   // every button counts as held, so the opening press does not also act in the sidebar
    held = now;
    pad_read(g);
}
// Home and Capture: without this macOS takes them as system gestures (Home opens the Games app); the host gives them no function
static void pad_keep_system_buttons(GCController *c) { for (NSString *b in @[GCInputButtonHome, GCInputButtonShare]) c.physicalInputProfile.buttons[b].preferredSystemGestureState = GCSystemGestureStateDisabled; }
static const char *pad_name(GCController *c) { return c.vendorName.UTF8String ?: "?"; }
static void npad_name(int p, char *out, size_t cap) { uint32_t id = dm_player_npad(p); if (id == 0x20) snprintf(out, cap, "handheld"); else snprintf(out, cap, "%u", id); }
static void pro_players_changed(GCController *gone) {
    int count = 0, player = -1;
    for (GCController *c in GCController.controllers) if (c != gone && c.extendedGamepad && [c.productCategory isEqualToString:@"Switch Pro Controller"]) {
        count++; player = g_merge ? 0 : pad_slot_of(&g_slots, (__bridge const void *)c);
    }
    dm_motion_pro_players(count, player);
}
static void pro_devices_changed(void) { pro_players_changed(nil); }
// Called at start and on every connect / disconnect (gone: the controller that was just removed, nil on a connect)
static void pads_changed(GCController *gone) {
    if (g_merge) {
        int any = 0;
        for (GCController *c in GCController.controllers) if (c.extendedGamepad && c != gone) {
            any = 1; pad_keep_system_buttons(c); c.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad *g, GCControllerElement *el) { pad_event(g, el); };   // Home opens the sidebar instead of the system's game overlay
            dm_motion_attach(c, 0);   // every controller is player 1: the last one moved drives its six-axis sensor
            pad_read(c.extendedGamepad);
        }
        if (gone) dm_motion_detach(gone, 0);
        if (!any) { dm_pad_set(0, 0, 0, 0, 0); dm_haptics_apple_controller(0, nil); }
        pro_players_changed(gone);
        return;
    }
    NSArray<GCController *> *now = GCController.controllers; char nb[16];
    for (int p = 0; p < DM_PLAYERS; p++) if (g_held[p] && (g_held[p] == gone || ![now containsObject:g_held[p]])) {
        npad_name(p, nb, sizeof nb); LOG("controller '%s' disconnected: player %d (npad %s) is free", pad_name(g_held[p]), p + 1, nb);
        g_held[p].extendedGamepad.valueChangedHandler = nil;
        dm_motion_detach(g_held[p], p);
        dm_haptics_apple_controller(p, nil);
        pad_slot_free(&g_slots, (__bridge const void *)g_held[p]); g_held[p] = nil;
        dm_pad_set_player(p, 0, 0, 0, 0, 0);   // nothing stays pressed
    }
    for (GCController *c in now) if (c.extendedGamepad && c != gone && pad_slot_of(&g_slots, (__bridge const void *)c) < 0) {
        int p = pad_slot_take(&g_slots, (__bridge const void *)c, pad_name(c));
        if (p < 0) { LOG("controller '%s' connected: all %d players are taken, not used", pad_name(c), DM_PLAYERS); continue; }
        g_held[p] = c; pad_keep_system_buttons(c);   // Home opens the sidebar instead of the system's game overlay
        c.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad *g, GCControllerElement *el) { pad_event(g, el); };
        dm_motion_attach(c, p);
        npad_name(p, nb, sizeof nb); LOG("controller '%s' connected: player %d (npad %s)%s", pad_name(c), p + 1, nb, c.motion.hasRotationRate ? ", with motion (gyro)" : "");
        pad_read(c.extendedGamepad);
    }
    dm_pad_players(pad_slot_mask(&g_slots));
    pro_players_changed(gone);
}
// Focus: a window that is no longer key sees no key-up, mouse-up or controller release, so whatever is held when it loses focus (another app, the text box, minimized) would
// stay pressed in the game. The front end releases only what it pressed itself: scripted buttons and sticks have their own path, and the touch is also DM_KEYS / DM_CTL's (hle_hid.c).
// Out of focus a controller's changes are ignored, so back in focus each controller is read as it is now (a button still held, a stick still deflected)
static int g_mouse_down;   // the mouse holds the touch (DmGameView)
static void input_release(void) {
    g_input_on = 0;
    dm_motion_pro_active(0);
    g_btn = 0; g_w = g_a = g_s = g_d = 0; push();
    if (g_mouse_down) { g_mouse_down = 0; dm_touch_set(NULL, 0); }
    if (g_merge) { for (GCController *c in GCController.controllers) if (c.extendedGamepad) { dm_pad_set(0, 0, 0, 0, 0); break; } }
    else for (int p = 0; p < DM_PLAYERS; p++) if (g_held[p]) dm_pad_set_player(p, 0, 0, 0, 0, 0);
}
static void input_resume(void) {
    g_input_on = 1;
    dm_motion_pro_active(1);
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
    dm_motion_pro_start(pro_devices_changed);
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
// - Mods: each folder in ~/Library/Application Support/nxnative/<title ID>/mods is a mod, the game's RomFS files it replaces either in it, in its romfs folder (the layout other
//   Switch tools use) or in Atmosphere's atmosphere/contents/<title ID>/romfs (mod_root). The enabled ones are overlaid on the RomFS at launch in name order, the first one holding a file winning (hle_fs.c DM_ROMFS_OVERLAY, which names them),
//   so a change applies on the next launch. DM_ROMFS_OVERLAY in the environment replaces them.
// - Cheats: this build's cheat file (cheats_host.c), a switch per cheat; the host reads the saved names at launch (DMQuickSettings.cheats.<game>), and the sidebar
//   switches the running set (dm_cheats_set). Code patches are made only at launch. DM_CHEATS / DM_CHEATS_ON in the environment win.
// While the sidebar is up the game sees what it sees when its window loses focus: its input is released (input_release) and its focus state is out of focus (dm_focus_set 2), so a game
// that pauses for the HOME menu pauses; the keyboard goes to the sidebar's controls. The game itself is not suspended, so the filter shows live
static NSString *const g_pfx_title[DM_PFX_N] = {@"Off", @"Sharpen", @"Pixel-perfect", @"CRT", @"CRT-Lottes", @"LCD Grid"};
static NSString *pfx_key(NSString *what) { return [NSString stringWithFormat:@"DMPresentFilter.%@.%s", what, DM_GAME_NAME]; }
static NSString *opt_key(NSString *what) { return [NSString stringWithFormat:@"DMQuickSettings.%@.%s", what, DM_GAME_NAME]; }

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
// A mod's RomFS files: its romfs folder, or the one in the Atmosphere layout a mod is usually downloaded in (atmosphere/contents/<title ID>/romfs,
// contents/<title ID>/romfs or <title ID>/romfs, after the NxNative Launcher's mod manager), or else the mod folder itself
static NSString *mod_root(NSString *name) {
    NSString *p = [mods_dir() stringByAppendingPathComponent:name], *tid = @DM_GAME_ID;
    for (NSString *sub in @[@"romfs", [NSString stringWithFormat:@"atmosphere/contents/%@/romfs", tid], [NSString stringWithFormat:@"contents/%@/romfs", tid],
                            [NSString stringWithFormat:@"%@/romfs", tid]]) {
        NSString *rf = [p stringByAppendingPathComponent:sub]; BOOL dir = NO;
        if ([NSFileManager.defaultManager fileExistsAtPath:rf isDirectory:&dir] && dir) return rf;
    }
    return p;
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
static void qs_toggle(void) { [g_opts toggle:nil]; }
static void qs_fps(void) { [g_opts fpsCounter]; }
static void toast(NSString *msg) { dm_qs_toast((__bridge void *)g_win.contentView, msg.UTF8String); }
// Capture (capture_mac.m): from the sidebar's Capture section, the Capture menu (⇧⌘S, ⇧⌘R) or a controller (front_controller); a toast says where the file went
static NSString *where(NSString *path) {   // a saved file's folder for a toast: its last two folders ("Curse of the Moon › Screenshots")
    NSArray *c = path.stringByDeletingLastPathComponent.pathComponents; NSUInteger n = c.count;
    return n >= 2 ? [NSString stringWithFormat:@"%@ › %@", c[n - 2], c[n - 1]] : path.stringByDeletingLastPathComponent;
}
void front_qs_screenshot(void) {
    capture_screenshot(DM_GAME_NAME, ^(NSString *path, NSString *err) { toast(path ? [@"Screenshot saved to " stringByAppendingString:where(path)] : err); });
}
void front_qs_record(void) {
    if (capture_recording()) { capture_record_stop(); toast(@"Saving the recording…"); return; }
    capture_record_start(DM_GAME_NAME, ^(NSString *path, NSString *err) { toast(path ? [@"Recording saved to " stringByAppendingString:where(path)] : err); if (g_menu_open) dm_qs_refresh(); });
    if (capture_recording()) toast(@"Recording — Shift-Command-R stops");
}
int front_qs_recording(void) { return capture_recording(); }
// Where captures go, for the Capture section: the folder chosen for this game (saved), or none for the default
const char *front_qs_capture_folder(int video) { return capture_folder(video).fileSystemRepresentation; }
int front_qs_capture_custom(void) { return [NSUserDefaults.standardUserDefaults stringForKey:opt_key(@"captureDir")].length > 0; }
void front_qs_capture_folder_set(const char *dir) {
    NSString *d = dir && *dir ? @(dir) : nil;
    if (d) [NSUserDefaults.standardUserDefaults setObject:d forKey:opt_key(@"captureDir")]; else [NSUserDefaults.standardUserDefaults removeObjectForKey:opt_key(@"captureDir")];
    capture_folder_set(d);
}
// While the sidebar is up the game picture moves aside into the window's left part (front.h mtl_present_inset), sliding with it unless Reduce Motion is on
static float g_inset_now, g_inset_to; static NSTimer *g_inset_timer;
static void inset_to(float share) {
    g_inset_to = share; [g_inset_timer invalidate]; g_inset_timer = nil;
    if (NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) { g_inset_now = share; mtl_present_inset(share); return; }
    float from = g_inset_now; double t0 = CACurrentMediaTime();
    g_inset_timer = [NSTimer scheduledTimerWithTimeInterval:1 / 120.0 repeats:YES block:^(NSTimer *t) {
        double u = fmin(1, (CACurrentMediaTime() - t0) / 0.25); u = 1 - pow(1 - u, 3);   // ease out over a quarter second
        g_inset_now = from + (g_inset_to - from) * (float)u; mtl_present_inset(g_inset_now);
        if (u >= 1) { [t invalidate]; g_inset_timer = nil; } }];
}
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
            NSView *gv = g_win.contentView; gv.postsFrameChangedNotifications = YES;
            [NSNotificationCenter.defaultCenter addObserverForName:NSViewFrameDidChangeNotification object:gv queue:nil usingBlock:^(NSNotification *n) {   // a resize while it is up: the picture keeps beside it
                (void)n; if (!g_menu_open || g_inset_timer) return; CGFloat W = gv.bounds.size.width, sw = self.view.frame.size.width;
                g_inset_now = g_inset_to = sw < W ? (float)(sw / W) : 0; mtl_present_inset(g_inset_now); }];
        }
        NSView *gv = g_win.contentView; CGFloat w = MIN(460, gv.bounds.size.width);
        self.view.frame = NSMakeRect(gv.bounds.size.width - w, 0, w, gv.bounds.size.height);
        dm_qs_opened(); dm_qs_refresh();
        [gv addSubview:self.view]; g_menu_open = 1;
        inset_to(w < gv.bounds.size.width ? (float)(w / gv.bounds.size.width) : 0);   // a sidebar as wide as the window covers the game instead
        input_release(); dm_focus_set(2);   // as when the window loses focus: nothing stays held, and a game that pauses for the HOME menu pauses
        LOG("front end: Quick settings open");
    } else {
        [self.view removeFromSuperview]; g_menu_open = 0; inset_to(0); g_pad_quiet = 1; g_assign = -1;
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
    else if (it.action == @selector(record:)) it.title = capture_recording() ? @"Stop Recording" : @"Start Recording";
    else if (it.action == @selector(pickItem:)) it.state = it.tag == mtl_present_filter(NULL) ? NSControlStateValueOn : NSControlStateValueOff;
    return YES;
}
- (void)screenshot:(id)sender { (void)sender; front_qs_screenshot(); }
- (void)record:(id)sender { (void)sender; front_qs_record(); if (g_menu_open) dm_qs_refresh(); }
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
    NSMenu *cm = [[NSMenu alloc] initWithTitle:@"Capture"];   // ⇧⌘S and ⇧⌘R: ⌘ shortcuts never reach the game
    [[bar addItemWithTitle:@"Capture" action:nil keyEquivalent:@""] setSubmenu:cm];
    NSMenuItem *sh = [cm addItemWithTitle:@"Take Screenshot" action:@selector(screenshot:) keyEquivalent:@"s"], *rc = [cm addItemWithTitle:@"Start Recording" action:@selector(record:) keyEquivalent:@"r"];
    for (NSMenuItem *x in @[sh, rc]) { x.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift; x.target = self; }
    g_opts = self; g_menu_toggle = qs_toggle; [self fpsCounter];
}
@end
static void graphics_start(void) {   // main thread, before the guest runs: the saved filter, anisotropic filtering, volume, controls and mods, unless the environment names them
    mods_start(); controls_load();
    capture_folder_set([NSUserDefaults.standardUserDefaults stringForKey:opt_key(@"captureDir")]);
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if (!getenv("DM_ANISO") && [d objectForKey:opt_key(@"aniso")]) mtl_aniso_set((int)[d integerForKey:opt_key(@"aniso")]);   // taken at the game's first sampler: before the guest runs
    if ([d objectForKey:opt_key(@"volume")]) dm_audio_volume_set([d floatForKey:opt_key(@"volume")]);
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
__attribute__((constructor)) static void hud_env(void) { front_hud_env(); }
// NXForge packs apps as org.nxforge.<title ID> (before the rename org.nxnative.<title ID>), and the defaults domain follows the bundle ID:
// once, before anything reads it (cheats_host.c too), copy the saved Quick settings (filter, volume, mods, cheats, FPS counter) from the old ID
__attribute__((constructor)) static void prefs_from_old_id(void) {
    @autoreleasepool {
        NSString *bid = NSBundle.mainBundle.bundleIdentifier, *pre = @"org.nxforge.";
        if (![bid hasPrefix:pre]) return;
        NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
        if ([d persistentDomainForName:bid].count) return;
        NSDictionary *old = [d persistentDomainForName:[@"org.nxnative." stringByAppendingString:[bid substringFromIndex:pre.length]]];
        if (old.count) [d setPersistentDomain:old forName:bid];
    }
}
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
        const char *fs = getenv("DM_FULLSCREEN");   // 1 (or any value but 0): start in fullscreen; 0, the settings window's Window, or unset: a window
        if (fs && strcmp(fs, "0")) dispatch_async(dispatch_get_main_queue(), ^{ [win toggleFullScreen:nil]; });
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
            if (assign_key(e)) return nil;   // a key being assigned in the Controls section
            if (e.keyCode == 53) { if (e.type == NSEventTypeKeyDown && !e.isARepeat) [opts toggle:nil]; return nil; }   // Esc: the Quick settings sidebar (no game button is on it)
            if (g_menu_open) {   // the arrow keys, Return and Space move through the sidebar as a controller does; other keys go to its controls
                int nav = e.keyCode == 126 ? NAV_UP : e.keyCode == 125 ? NAV_DOWN : e.keyCode == 123 ? NAV_LEFT : e.keyCode == 124 ? NAV_RIGHT : e.keyCode == 36 || e.keyCode == 49 || e.keyCode == 76 ? NAV_OK : 0;
                if (!nav) return e;
                if (e.type == NSEventTypeKeyDown) dm_qs_nav(nav);
                return nil;
            }
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
        [nc addObserverForName:NSWindowDidEnterFullScreenNotification object:win queue:nil usingBlock:^(NSNotification *n) { (void)n; g_fullscreen = 1; g_layer.contentsScale = win.backingScaleFactor; screen_match_apply(); }];
        [nc addObserverForName:NSWindowDidExitFullScreenNotification object:win queue:nil usingBlock:^(NSNotification *n) { (void)n; g_fullscreen = 0; g_layer.contentsScale = win.backingScaleFactor; screen_match_apply(); }];
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

// Progress screen of the prepare step (front.h front_progress): a dark view over the game's, the title, a bar and a count, centered; AppKit views, so it draws while the game's thread waits
static NSView *g_prog; static NSTextField *g_prog_title, *g_prog_count; static NSProgressIndicator *g_prog_bar;
static NSTextField *prog_label(NSRect r, CGFloat size, NSFontWeight w, NSColor *c) {
    NSTextField *t = [NSTextField labelWithString:@""]; t.frame = r; t.alignment = NSTextAlignmentCenter; t.textColor = c;
    t.font = [NSFont monospacedDigitSystemFontOfSize:size weight:w]; return t;
}
void front_progress(const char *title, long done, long total) {
    if (!g_layer) return;
    NSString *tt = title ? @(title) : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!tt) { [g_prog removeFromSuperview]; g_prog = nil; return; }
        if (!g_prog) {
            NSView *cv = g_win.contentView;
            g_prog = [[NSView alloc] initWithFrame:cv.bounds]; g_prog.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            g_prog.wantsLayer = YES; g_prog.layer.backgroundColor = [NSColor colorWithWhite:0.06 alpha:0.94].CGColor;
            NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(floor((cv.bounds.size.width - 400) / 2), floor((cv.bounds.size.height - 96) / 2), 400, 96)];
            box.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin;
            g_prog_title = prog_label(NSMakeRect(0, 62, 400, 30), 20, NSFontWeightSemibold, NSColor.whiteColor);
            g_prog_bar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20, 36, 360, 20)];
            g_prog_bar.style = NSProgressIndicatorStyleBar; g_prog_bar.indeterminate = NO; g_prog_bar.minValue = 0;
            g_prog_count = prog_label(NSMakeRect(0, 4, 400, 22), 13, NSFontWeightRegular, [NSColor colorWithWhite:0.72 alpha:1]);
            [box addSubview:g_prog_title]; [box addSubview:g_prog_bar]; [box addSubview:g_prog_count]; [g_prog addSubview:box];
            [cv addSubview:g_prog];
        }
        g_prog_title.stringValue = tt; g_prog_bar.maxValue = total > 0 ? (double)total : 1; g_prog_bar.doubleValue = (double)done;
        g_prog_count.stringValue = [NSString stringWithFormat:@"%@ of %@", [NSNumberFormatter localizedStringFromNumber:@(done) numberStyle:NSNumberFormatterDecimalStyle],
                                    [NSNumberFormatter localizedStringFromNumber:@(total) numberStyle:NSNumberFormatterDecimalStyle]];
    });
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
