// NXForge: included by front_mac_front_end.inc (so front_mac.m meets no new line). Save battery (the sidebar's General page, on unless turned off;
// DM_BATTERY_SAVER=0 turns it off for a run): while the Mac runs on its battery, a game nobody is playing does not run. It pauses as it does behind
// the sidebar (sound, clock and graphics: qs_pause), without the sidebar,
//   - a few seconds after another app comes to the front, until this one is in front again, and
//   - after ten minutes without a button, key or click, until the next one (a message says so). A movie the game plays does not count as idle.
// On mains power nothing changes: a game left running behind other apps keeps running. A paused game uses next to nothing, where one left on a
// menu draws as much as one being played. What this does not do: lower the frame rate or skip frames of a game that is being played (the Battery
// preset is for that).
#define NXF_BS_AWAY_S 4.0      // another app in front this long: pause (a glance at a notification does not)
#define NXF_BS_IDLE_S 600.0    // no input this long: pause
static int g_nxf_bs_held;      // 0 running; 1 paused because another app is in front; 2 paused because nobody touched it
static double g_nxf_bs_input;  // CACurrentMediaTime of the last button, key or click
__attribute__((weak)) int dm_movie_hz(void);
static BOOL nxf_bs_wanted(void) {
    static int env = -1; if (env < 0) { const char *e = getenv("DM_BATTERY_SAVER"); env = !(e && !atoi(e)); }
    if (!env) return NO;
    id v = [NSUserDefaults.standardUserDefaults objectForKey:opt_key(@"batterySaver")]; if (v && ![v boolValue]) return NO;
    int on_battery; return nxf_battery_percent(&on_battery) >= 0 && on_battery;
}
static void nxf_bs_release(const char *why) {
    if (!g_nxf_bs_held) return;
    g_nxf_bs_held = 0; g_nxf_bs_input = CACurrentMediaTime();
    if (g_paused && !(g_menu_open && (qs_pause_wanted() || g_suspended || g_nxf_sleep_held))) { qs_pause(0); dm_qs_refresh(); }   // the sidebar's own pause stays
    LOG("front end: battery saver: %s, the game runs again", why);
}
static void nxf_bs_hold(int kind) {
    if (g_nxf_bs_held || g_paused || !g_win || g_win.miniaturized || !nxf_bs_wanted()) return;   // already stopped by the sidebar or a minimized window: nothing to add
    g_nxf_bs_held = kind; qs_pause(1); dm_qs_refresh();
    LOG("front end: battery saver: game paused on the battery (%s)", kind == 1 ? "another app is in front" : "no input for ten minutes");
    if (kind == 2) dm_qs_toast_long((__bridge void *)g_win.contentView, "Paused to save the battery. Press any button to carry on", 3600);
}
// Any button, key or click (front_mac_pad_nav.inc pad_event, and the monitor below)
static void nxf_bs_touch(void) {
    g_nxf_bs_input = CACurrentMediaTime();
    if (g_nxf_bs_held == 2) { nxf_bs_release("a button"); if (g_win) dm_qs_toast_long((__bridge void *)g_win.contentView, "Carrying on", 1.5); }
}
static void nxf_battery_saver_init(void) {
    static int done; if (done) return; done = 1;
    int ob; if (nxf_battery_percent(&ob) < 0) return;   // no battery: nothing to save
    g_nxf_bs_input = CACurrentMediaTime();
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserverForName:NSApplicationDidResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { (void)n;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NXF_BS_AWAY_S * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (!NSApp.active) nxf_bs_hold(1); }); }];
    [nc addObserverForName:NSApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { (void)n;
        if (g_nxf_bs_held == 1) nxf_bs_release("in front again"); }];
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown | NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskScrollWheel handler:^NSEvent *(NSEvent *e) { nxf_bs_touch(); return e; }];
    [NSTimer scheduledTimerWithTimeInterval:20 repeats:YES block:^(NSTimer *t) { (void)t;
        if (g_nxf_bs_held) { if (!nxf_bs_wanted()) nxf_bs_release("on mains power, or turned off"); return; }   // plugged in: it runs again
        if (g_paused || !NSApp.active || (dm_movie_hz && dm_movie_hz() > 0)) { g_nxf_bs_input = CACurrentMediaTime(); return; }
        if (CACurrentMediaTime() - g_nxf_bs_input >= NXF_BS_IDLE_S) nxf_bs_hold(2);
    }];
}
