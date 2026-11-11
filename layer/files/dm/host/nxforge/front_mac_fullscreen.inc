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
// The game window's delegate from the start: front_mac.m sets one only for DM_FULLSCREEN's startup request, and the
// green button, ⌃⌘F and the sidebar enter full screen through the delegate too
static void nxf_fullscreen_window(NSWindow *win) { static DmWinDelegate *d; if (!win.delegate) { d = [DmWinDelegate new]; win.delegate = d; } }
