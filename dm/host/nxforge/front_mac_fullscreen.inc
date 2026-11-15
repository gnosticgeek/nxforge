// NXForge: included by front_mac.m after DmWinDelegate (it shares that file's statics). Kept out of
// upstream's file so a merge of nxnative meets one #include line. See UPSTREAM.md, Thin fork.
// Full screen without the title bar: macOS's own full screen auto-hides the menu bar and the window's title bar, and shows both again
// while the pointer is at the top of the screen. The green button is up there, so after a click on it the pointer stays where the bars
// come back, and the game's pointer timer only hides a pointer over the game view: the title bar stayed over the game until the mouse
// moved (Ocarina of Time on a MacBook Pro, 2026-11-11). The game window now asks for the menu bar and the Dock hidden in full screen,
// so neither the menu bar nor the title bar comes back; ⌃⌘F, the sidebar's Full screen row (Esc) and ⌘Q work as before.
// DM_FULLSCREEN_MENU_BAR=1 keeps macOS's behaviour (the bars come back at the top of the screen).
@implementation DmWinDelegate (NXForgeFullscreen)
- (NSApplicationPresentationOptions)window:(NSWindow *)w willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)proposed {
    (void)w;
    static int keep = -1;
    if (keep < 0) { const char *e = getenv("DM_FULLSCREEN_MENU_BAR"); keep = e && atoi(e); LOG("front end: full screen %s", keep ? "shows the menu bar and title bar at the top of the screen (DM_FULLSCREEN_MENU_BAR)" : "hides the menu bar, title bar and Dock"); }
    if (keep) return proposed;
    // AppKit refuses AutoHideToolbar without AutoHideMenuBar, and the Hide and AutoHide options of one bar together
    return (proposed & ~(NSApplicationPresentationAutoHideMenuBar | NSApplicationPresentationAutoHideDock | NSApplicationPresentationAutoHideToolbar))
        | NSApplicationPresentationFullScreen | NSApplicationPresentationHideMenuBar | NSApplicationPresentationHideDock;
}
@end
// Borderless full screen (DM_FULLSCREEN_STYLE): macOS's own full screen on a ProMotion screen drops the display link to 80 callbacks a
// second once the game presents on every one of them, which frame interpolation does (Donkey Kong Country Returns HD, 2026-11-14:
// the game ran at 40 fps, and since 0.29.1 interpolation turned itself off there and the game showed 60). A window holds 120 with it.
// So full screen can instead be the game window without its title bar covering its whole screen, with the menu bar and the Dock
// hidden: to macOS (and to the present path's pacing, front_fullscreen) it stays a window, to the player (Quick settings, the
// Window menu) it is full screen. auto (the default) takes it while frame interpolation wants the 120 Hz link
// (mtl_present_interp_active) on a screen of 120 Hz or more, native otherwise (a 60 Hz TV keeps macOS's full screen); borderless
// and native always take that one. The game window is an NXFGameWindow (front_mac.m creates it), whose toggleFullScreen: is where
// the green button, ⌃⌘F and the Window menu, the sidebar's Full screen row and DM_FULLSCREEN's startup request all arrive; leaving
// puts the window's frame, style and the app's presentation options back. The choice is made on each entry, so turning
// interpolation on or off in the sidebar takes effect the next time full screen is entered.
static int g_fs_borderless;   // main thread: the window is in borderless full screen
static NSRect g_fs_frame; static NSWindowStyleMask g_fs_style; static NSApplicationPresentationOptions g_fs_opts;   // what leaving it restores
int front_fullscreen_borderless(void) { return g_fs_borderless; }
static int nxf_fs_style(void) {   // 0 auto, 1 borderless, 2 native
    static int s = -1;
    if (s < 0) { const char *e = getenv("DM_FULLSCREEN_STYLE"); s = e && !strcmp(e, "borderless") ? 1 : e && !strcmp(e, "native") ? 2 : 0;
        if (e && *e && strcmp(e, "auto") && !s) LOG("front end: DM_FULLSCREEN_STYLE=%s is not auto, borderless or native: auto", e); }
    return s;
}
static void nxf_fs_changed(NSWindow *w) {
    screen_refresh(w.screen); if (w.screen) g_layer.contentsScale = w.backingScaleFactor;
    [NSNotificationCenter.defaultCenter postNotificationName:@"NXFBorderlessFullScreenChanged" object:w];   // Quick settings' Full screen row
}
static void nxf_fs_enter(NSWindow *w, int why) {
    NSScreen *scr = w.screen ?: NSScreen.mainScreen;
    static int keep = -1; if (keep < 0) { const char *e = getenv("DM_FULLSCREEN_MENU_BAR"); keep = e && atoi(e); }
    g_fs_frame = w.frame; g_fs_style = w.styleMask; g_fs_opts = NSApp.presentationOptions;
    NSApplicationPresentationOptions o = g_fs_opts & ~(NSApplicationPresentationAutoHideMenuBar | NSApplicationPresentationAutoHideDock | NSApplicationPresentationHideMenuBar | NSApplicationPresentationHideDock);
    NSApp.presentationOptions = o | (keep ? NSApplicationPresentationAutoHideMenuBar | NSApplicationPresentationAutoHideDock : NSApplicationPresentationHideMenuBar | NSApplicationPresentationHideDock);
    g_fs_borderless = 1;
    w.styleMask = NSWindowStyleMaskBorderless;
    [w setFrame:scr.frame display:YES];
    [w makeKeyAndOrderFront:nil];
    LOG("front end: full screen as a borderless window covering the screen (%.0fx%.0f points), %s (DM_FULLSCREEN_STYLE %s)", scr.frame.size.width, scr.frame.size.height,
        keep ? "the menu bar and Dock come back at the screen's edges" : "menu bar and Dock hidden", why == 1 ? "borderless" : "auto: frame interpolation keeps its 120 Hz display link that way");
    nxf_fs_changed(w);
}
static void nxf_fs_leave(NSWindow *w) {
    g_fs_borderless = 0;
    w.styleMask = g_fs_style;
    [w setFrame:g_fs_frame display:YES];
    NSApp.presentationOptions = g_fs_opts;
    [w makeKeyAndOrderFront:nil];
    LOG("front end: left borderless full screen");
    nxf_fs_changed(w);
}
@interface NXFGameWindow : NSWindow
@end
@implementation NXFGameWindow
- (BOOL)canBecomeKeyWindow { return YES; }    // a borderless window is not key or main by default: the game would lose the keyboard
- (BOOL)canBecomeMainWindow { return YES; }
- (void)toggleFullScreen:(id)sender {
    if (g_fs_borderless) { nxf_fs_leave(self); return; }
    int s = nxf_fs_style();
    if (!(self.styleMask & NSWindowStyleMaskFullScreen) && (s == 1 || (s == 0 && mtl_present_interp_active() && front_screen_max_fps() >= 120))) { nxf_fs_enter(self, s); return; }
    [super toggleFullScreen:sender];
}
- (BOOL)validateMenuItem:(NSMenuItem *)item {   // AppKit names the item Enter / Exit Full Screen from the native state only
    if (item.action == @selector(toggleFullScreen:) && g_fs_borderless) { item.title = @"Exit Full Screen"; return YES; }
    return [super validateMenuItem:item];
}
@end
// The game window's delegate from the start: front_mac.m sets one only for DM_FULLSCREEN's startup request, and the
// green button, ⌃⌘F and the sidebar enter full screen through the delegate too
static void nxf_fullscreen_window(NSWindow *win) { static DmWinDelegate *d; if (!win.delegate) { d = [DmWinDelegate new]; win.delegate = d; } }
