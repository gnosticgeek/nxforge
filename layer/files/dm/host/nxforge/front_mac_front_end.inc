// NXForge: included by front_mac_fullscreen.inc (so front_mac.m meets no new line). The hand-off from NXForge's front end into the game.
// A game NXForge's Play starts carries NXFORGE_FRONT_END (the NXForge app's path). Its window then stays see-through until the game has drawn its
// first picture (mtl_present_times, present_filters.inc), so NXForge's launch screen, the game's box turning in its own light, stays in view in
// place of an empty black window; then the window fades in and NXForge is told (the distributed notification org.nxforge.gameShown, its object
// the game app's path) so its launch screen goes in the same moment. A game that draws nothing for 15 s (a first start that builds its shaders
// before its first frame) is shown anyway. DM_FRONT_END_FADE=0 shows the window at once, as before.
static NSWindow *g_nxf_fe_win;
static NSTimer *g_nxf_fe_timer;
static CFAbsoluteTime g_nxf_fe_t0;

static void nxf_front_end_show(const char *why) {
    if (!g_nxf_fe_win) return;
    NSWindow *w = g_nxf_fe_win; g_nxf_fe_win = nil;
    [g_nxf_fe_timer invalidate]; g_nxf_fe_timer = nil;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *c) { c.duration = 0.28; w.animator.alphaValue = 1; } completionHandler:nil];
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"org.nxforge.gameShown" object:NSBundle.mainBundle.bundlePath userInfo:nil deliverImmediately:YES];
    LOG("front end: window shown %.1f s after it opened (%s)", CFAbsoluteTimeGetCurrent() - g_nxf_fe_t0, why);
}

static void nxf_front_end_window(NSWindow *win) {
    const char *fe = getenv("NXFORGE_FRONT_END"), *fade = getenv("DM_FRONT_END_FADE");
    if (!fe || !*fe || (fade && !atoi(fade))) return;
    g_nxf_fe_win = win; g_nxf_fe_t0 = CFAbsoluteTimeGetCurrent();
    win.alphaValue = 0;
    LOG("front end: started from NXForge: the window shows with the game's first frame (DM_FRONT_END_FADE=0: at once)");
    g_nxf_fe_timer = [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *t) {
        (void)t; double ms[2], age = -1;
        mtl_present_times(ms, 0, &age);
        if (age >= 0) nxf_front_end_show("first frame");
        else if (CFAbsoluteTimeGetCurrent() - g_nxf_fe_t0 > 15) nxf_front_end_show("nothing drawn after 15 s");
    }];
}
