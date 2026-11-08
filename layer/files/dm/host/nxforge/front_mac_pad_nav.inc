// NXForge: included by front_mac.m at the place this code stood (it shares that file's statics). Kept out of
// upstream's file so a merge of nxnative meets one #include line. See UPSTREAM.md, Thin fork.
// The sidebar with a controller (after RetroReplay's pause menu): the D-pad or left stick moves the selection, left / right change its value, A (the right face button) activates it,
// B (the bottom one), + or Home close the sidebar, L / R turn the page; a held direction repeats. quick_settings_mac.swift dm_qs_nav keeps the selection
enum { NAV_UP = 1, NAV_DOWN, NAV_LEFT, NAV_RIGHT, NAV_OK, NAV_BACK, NAV_PREV, NAV_NEXT };
static uint32_t g_nav_prev; static NSTimer *g_nav_rep;
// The sidebar's button legend shows this controller's own glyphs (its elements' SF Symbols: an Xbox pad's B where a Nintendo pad has A) for the buttons pad_nav reads
static void pad_glyphs(GCExtendedGamepad *g) {
    static const void *last;   // only compared: a new controller (or the first) sends its glyphs
    if (last == (__bridge const void *)g) { dm_qs_input(1, NULL, NULL, NULL, NULL); return; }
    last = (__bridge const void *)g;
    dm_qs_input(1, g.buttonB.sfSymbolsName.UTF8String, g.buttonA.sfSymbolsName.UTF8String, g.leftShoulder.sfSymbolsName.UTF8String, g.rightShoulder.sfSymbolsName.UTF8String);
}
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
    if (pressed && g_menu_open) pad_glyphs(g);
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
    if (now && !held && g_menu_toggle) { held = YES; g_nav_prev = ~0u; g_open_by_pad = 1; g_menu_toggle(); g_open_by_pad = 0; if (g_menu_open) pad_glyphs(g); return; }   // every button counts as held, so the opening press does not also act in the sidebar
    held = now;
    pad_read(g);
}
