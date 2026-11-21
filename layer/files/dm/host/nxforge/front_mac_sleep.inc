// NXForge: included by front_mac_front_end.inc (so front_mac.m meets no new line). Laptop-safe play: when the Mac is about to sleep (the lid closes,
// Sleep, an empty battery's forced sleep), its screens sleep, or the battery is nearly empty, the game's committed save is copied to a save snapshot
// ("Before the Mac slept", quick_settings_mac.swift dm_qs_safety_copy: only when the game saved since the last copy) and the game pauses with the
// sidebar up, whatever Pause the game says. So the lid opens on a paused game and a message, not on a game that ran on while the screen was still
// dark, and a battery that dies mid-session costs no more than the game's own last save. At 10 % on the battery a message asks for the charger; at
// 4 % the copy is made and the game pauses. Once per discharge each. DM_SLEEP_SAFE=0 turns all of it off.
#include <IOKit/ps/IOPSKeys.h>
static int g_nxf_sleep_held, g_nxf_batt_warned, g_nxf_batt_held;

static int nxf_battery_percent(int *on_battery) {   // -1: no battery (a desktop Mac)
    *on_battery = 0; int pct = -1;
    CFTypeRef info = IOPSCopyPowerSourcesInfo(); if (!info) return -1;
    CFArrayRef list = IOPSCopyPowerSourcesList(info);
    for (CFIndex i = 0; list && i < CFArrayGetCount(list); i++) {
        CFDictionaryRef d = IOPSGetPowerSourceDescription(info, CFArrayGetValueAtIndex(list, i)); if (!d) continue;
        CFStringRef type = CFDictionaryGetValue(d, CFSTR(kIOPSTypeKey));
        if (!type || !CFEqual(type, CFSTR(kIOPSInternalBatteryType))) continue;
        CFNumberRef cur = CFDictionaryGetValue(d, CFSTR(kIOPSCurrentCapacityKey)), max = CFDictionaryGetValue(d, CFSTR(kIOPSMaxCapacityKey));
        CFStringRef state = CFDictionaryGetValue(d, CFSTR(kIOPSPowerSourceStateKey));
        int c = 0, m = 0; if (cur) CFNumberGetValue(cur, kCFNumberIntType, &c); if (max) CFNumberGetValue(max, kCFNumberIntType, &m);
        if (m > 0) pct = c * 100 / m;
        *on_battery = state && CFEqual(state, CFSTR(kIOPSBatteryPowerValue));
    }
    if (list) CFRelease(list);
    CFRelease(info); return pct;
}

// The copy, then the pause with the sidebar up. why: for the log. Returns the copy's result (1 made, 0 nothing new since the last, -1 failed or no save yet)
static int nxf_sleep_hold(const char *why) {
    int copied = dm_qs_safety_copy();
    if (g_opts && g_win) {
        if (!g_menu_open) qs_toggle();
        if (g_menu_open && !g_paused) { qs_pause(1); dm_qs_refresh(); }   // at once: the Mac may be asleep before the picture has slid aside
    }
    LOG("front end: %s: game paused with the sidebar up, save %s", why, copied > 0 ? "copied to a snapshot" : copied == 0 ? "unchanged since its last copy" : "not copied (nothing saved yet, or the copy failed)");
    return copied;
}

static void nxf_sleep_init(void) {
    static int done; if (done) return; done = 1;
    const char *e = getenv("DM_SLEEP_SAFE"); if (e && !atoi(e)) { LOG("front end: DM_SLEEP_SAFE=0: no pause or save copy before sleep or on a low battery"); return; }
    NSNotificationCenter *ws = NSWorkspace.sharedWorkspace.notificationCenter;
    void (^held)(NSNotification *) = ^(NSNotification *n) {
        if (g_nxf_sleep_held) return;
        g_nxf_sleep_held = 1; nxf_sleep_hold([n.name isEqualToString:NSWorkspaceWillSleepNotification] ? "the Mac is going to sleep" : "the screens went to sleep");
    };
    [ws addObserverForName:NSWorkspaceWillSleepNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:held];
    [ws addObserverForName:NSWorkspaceScreensDidSleepNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:held];
    void (^woke)(NSNotification *) = ^(NSNotification *n) {
        (void)n; if (!g_nxf_sleep_held) return;
        g_nxf_sleep_held = 0;
        if (g_win) dm_qs_toast_long((__bridge void *)g_win.contentView, "Paused while the Mac slept. Resume when you are ready", 6);
        LOG("front end: awake again; the game stays paused until Resume");
    };
    [ws addObserverForName:NSWorkspaceDidWakeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:woke];
    [ws addObserverForName:NSWorkspaceScreensDidWakeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:woke];
    int ob; if (nxf_battery_percent(&ob) < 0) return;   // no battery: nothing to watch
    [NSTimer scheduledTimerWithTimeInterval:30 repeats:YES block:^(NSTimer *t) {
        (void)t; int on_battery, pct = nxf_battery_percent(&on_battery);
        if (!on_battery || pct < 0) { g_nxf_batt_warned = g_nxf_batt_held = 0; return; }
        if (pct <= 4 && !g_nxf_batt_held) {
            g_nxf_batt_held = g_nxf_batt_warned = 1;
            int copied = nxf_sleep_hold("battery nearly empty");
            if (g_win) dm_qs_toast_long((__bridge void *)g_win.contentView, copied >= 0 ? "Battery nearly empty: the game is paused and its save is copied. Plug in to carry on"
                                                                                       : "Battery nearly empty: the game is paused. Plug in to carry on", 8);
        } else if (pct <= 10 && !g_nxf_batt_warned) {
            g_nxf_batt_warned = 1;
            if (g_win) dm_qs_toast_long((__bridge void *)g_win.contentView, [NSString stringWithFormat:@"Battery at %d %%: plug in, or save soon", pct].UTF8String, 6);
            LOG("front end: battery at %d %%: the player is told", pct);
        }
    }];
}
