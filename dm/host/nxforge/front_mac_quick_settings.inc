// NXForge: included by front_mac.m at the place this code stood (it shares that file's statics). Kept out of
// upstream's file so a merge of nxnative meets one #include line. See UPSTREAM.md, Thin fork.
// Quick settings: a sidebar over the right of the game picture (Esc, ⇧⌘G or the Graphics menu opens it; Esc, its close button or Resume game closes it), fullscreen too. The sidebar itself is
// SwiftUI (quick_settings_mac.swift: the system's controls on a Liquid Glass panel); this side opens and closes it, draws the frame-rate counter and loads the mods at launch. Kept per game in the
// user defaults (the app bundle's own domain; the keys name the game for a bare dmhost); a setting the environment names wins over its saved value and is not saved.
// - Graphics & shaders: the present filter (front.h mtl_present_filter_set, nvn_mtl.m), from the next frame, so the game runs on behind the sidebar and shows the change at once.
//   DM_PRESENT_FILTER / DM_PRESENT_FILTER_STRENGTH / DM_PRESENT_SCANLINE in the environment.
// - Performance: a frame-rate counter in a corner of the game picture, the frames put on screen in the last second (nvn_mtl.m mtl_present_count, as on the iPhone). DM_SHOW_FPS=0 / 1.
// - Mods: each folder in ~/Library/Application Support/nxnative/<title ID>/mods is a mod, the game's RomFS files it replaces either in it, in its romfs folder (the layout other
//   Switch tools use) or in Atmosphere's atmosphere/contents/<title ID>/romfs (mod_root). The enabled ones are overlaid on the RomFS at launch in name order, the first one holding a file winning (hle_fs.c DM_ROMFS_OVERLAY, which names them),
//   so a change applies on the next launch. DM_ROMFS_OVERLAY in the environment replaces them.
// - Cheats: this build's Atmosphère cheat file (hle_cheats.c), a switch per cheat, the same rows as the Cheats menu; the host keeps the toggles beside the file (<build ID>.enabled).
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
    if (!d) return r;   // no Application Support folder: no mods
    for (NSString *n in [NSFileManager.defaultManager contentsOfDirectoryAtPath:d error:nil] ?: @[]) {
        BOOL dir = NO;
        if (![n hasPrefix:@"."] && [NSFileManager.defaultManager fileExistsAtPath:[d stringByAppendingPathComponent:n] isDirectory:&dir] && dir) [r addObject:n];
    }
    r = [[r sortedArrayUsingSelector:@selector(localizedStandardCompare:)] mutableCopy];
    // the load order the sidebar's Mods page set (modOrder: names, first loads first); a mod it has not placed yet comes after those, in name order
    NSArray *order = [NSUserDefaults.standardUserDefaults arrayForKey:opt_key(@"modOrder")] ?: @[]; NSMutableArray *o = [NSMutableArray array];
    for (NSString *n in order) if ([n isKindOfClass:NSString.class] && [r containsObject:n] && ![o containsObject:n]) [o addObject:n];
    for (NSString *n in r) if (![o containsObject:n]) [o addObject:n];
    return o;
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
static NSArray<NSString *> *g_mods_run_order;   // the same, in the order they were overlaid
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
    g_mods_run = on; g_mods_run_order = [mods_list() filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *n, NSDictionary *b) { (void)b; return [on containsObject:n]; }]];
    if (!roots.count) return;
    setenv("DM_ROMFS_OVERLAY", [roots componentsJoinedByString:@":"].fileSystemRepresentation, 1);
    LOG("front end: %lu mod%s over the RomFS (Quick settings): %s", (unsigned long)roots.count, roots.count == 1 ? "" : "s", [on.allObjects componentsJoinedByString:@", "].UTF8String);
}

#include "front_mac_settings_file.inc"

@interface DmSettings : NSObject
@property NSView *view; @property NSMutableArray<NSMenuItem *> *items; @property NSTextField *fpsLabel; @property NSTimer *fpsTimer; @property uint64_t fpsN0; @property double fpsT0;
- (void)toggle:(id)sender; - (void)fpsCounter;
@end
static DmSettings *g_opts;
static void qs_close(void) { if (g_menu_open) [g_opts toggle:nil]; }
// Record frame times (Quick settings › Performance, from the next launch; after NX2Apple's FrameTimes.swift, MIT): the host's per-frame timing rows (hle_nvn.c DM_NVN_TSV,
// timing rows only) go to a new file per launch in the game folder's "Frame times" (DM_GAME_FOLDER), else <DM_ROOT>/frame-times (Application Support/nxnative/<title ID>),
// named like the captures. DM_FRAME_TIMES=1 / 0 turns it on or off for one run without saving; a DM_NVN_TSV the environment sets wins over both. scripts/bench.py's
// percentiles, and the NXForge Converter's Builds page sums the newest recording up the same way
static void frame_times_begin(void) {
    if (getenv("DM_NVN_TSV")) return;
    const char *e = getenv("DM_FRAME_TIMES");
    if (!(e ? atoi(e) != 0 : [NSUserDefaults.standardUserDefaults boolForKey:opt_key(@"frameTimes")])) return;
    const char *g = getenv("DM_GAME_FOLDER"), *root = getenv("DM_ROOT");
    NSString *dir = g && *g ? [@(g) stringByAppendingPathComponent:@"Frame times"] : root && *root ? [@(root) stringByAppendingPathComponent:@"frame-times"] : nil;
    if (!dir || ![NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil]) { LOG("[RED] front end: no folder for frame times (DM_GAME_FOLDER and DM_ROOT unset or not writable)"); return; }
    NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"yyyy-MM-dd 'at' HH.mm.ss";
    NSString *name = [[NSString stringWithFormat:@"%s %@.tsv", DM_GAME_NAME, [f stringFromDate:NSDate.date]] stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    NSString *path = [dir stringByAppendingPathComponent:name];
    setenv("DM_NVN_TSV", path.fileSystemRepresentation, 1); setenv("DM_NVN_TSV_CALLS", "0", 0);
    LOG("front end: recording frame times to %s", path.fileSystemRepresentation);
}
static void qs_toggle(void) { [g_opts toggle:nil]; }
static void qs_fps(void) { [g_opts fpsCounter]; }
static void toast(NSString *msg) { dm_qs_toast((__bridge void *)g_win.contentView, msg.UTF8String); }
// Capture (capture_mac.m): from the sidebar's Capture section, the Capture menu (⇧⌘S, ⇧⌘R) or a controller (front_controller); a toast says where the file went
static NSString *where(NSString *path) {   // a saved file's folder for a toast: its last two folders ("Curse of the Moon › Screenshots")
    NSArray *c = path.stringByDeletingLastPathComponent.pathComponents; NSUInteger n = c.count;
    return n >= 2 ? [NSString stringWithFormat:@"%@ › %@", c[n - 2], c[n - 1]] : path.stringByDeletingLastPathComponent;
}
static int g_paused;
static void qs_pause(int on);
void front_qs_screenshot(void) {
    int was = g_paused; if (was) qs_pause(0);   // the screenshot is the next frame presented: a paused game presents none
    capture_screenshot(DM_GAME_NAME, ^(NSString *path, NSString *err) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (was && g_menu_open) qs_pause(1); dm_qs_captures_changed(); });
        toast(path ? [@"Screenshot saved to " stringByAppendingString:where(path)] : err); });
}
void front_qs_record(void) {
    if (capture_recording()) { capture_record_stop(); toast(@"Saving the recording…"); return; }
    capture_record_start(DM_GAME_NAME, ^(NSString *path, NSString *err) { toast(path ? [@"Recording saved to " stringByAppendingString:where(path)] : err); if (g_menu_open) { dm_qs_refresh(); dm_qs_captures_changed(); } });
    if (capture_recording()) toast(@"Recording — Shift-Command-R stops");
}
int front_qs_recording(void) { return capture_recording(); }
// Restart game (Quick settings, for the settings that apply at the next launch): the app's launcher (dm/mac/launcher.c) names a file in DM_LAUNCHER_RESTART; the host makes it
// and quits as ⌘Q does, and the launcher, finding the file, starts the host again with the same environment. A bare dmhost has no launcher and no restart
int front_qs_can_restart(void) { const char *e = getenv("DM_LAUNCHER_RESTART"); return e && *e; }
void front_qs_restart(void) {
    const char *rf = getenv("DM_LAUNCHER_RESTART"); if (!rf || !*rf) return;
    int fd = open(rf, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) { LOG("[RED] front end: Restart game: cannot write %s: %s", rf, strerror(errno)); toast(@"Restart did not work: quit and open the game again"); return; }
    close(fd); LOG("front end: Restart game (Quick settings)"); qs_pause(0); [NSApp terminate:nil];
}
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
// Pause while open (the sidebar's General page, on unless turned off): once the picture has slid aside, the game stops as when the window is minimized: its sound (dm_audio_suspend),
// its clock (guest_clock_freeze_for, reason 3: the sidebar) and its graphics (dm_gfx_suspend: a submit or present waits). Closing the sidebar, quitting or a screenshot taken from
// it starts it again first. Un-minimizing the window resumes sound and graphics (front_mac.m), so while the sidebar is up they are stopped again after it
static BOOL qs_pause_wanted(void) { id v = [NSUserDefaults.standardUserDefaults objectForKey:opt_key(@"pauseOpen")]; return v ? [v boolValue] : YES; }
static void qs_pause(int on) {
    if (on == g_paused) return;
    static int observed;
    if (!observed) { observed = 1;   // after front_mac.m's own observers: those resume, this stops again
        [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidDeminiaturizeNotification object:g_win queue:nil usingBlock:^(NSNotification *n) { (void)n; if (g_paused) { dm_audio_suspend(1); dm_gfx_suspend(1); } }];
        [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationWillTerminateNotification object:nil queue:nil usingBlock:^(NSNotification *n) { (void)n; qs_pause(0); }];
    }
    g_paused = on;
    if (on) { dm_audio_suspend(1); guest_clock_freeze_for(3, 1); dm_gfx_suspend(1); LOG("front end: game paused while Quick settings is open"); }
    else { if (!g_win.miniaturized) { dm_gfx_suspend(0); dm_audio_suspend(0); } guest_clock_freeze_for(3, 0); LOG("front end: game resumed"); }
}
int front_qs_paused(void) { return g_paused; }
void front_qs_pause_set(int on) {   // the General page's switch, while the sidebar is up: applies at once
    [NSUserDefaults.standardUserDefaults setBool:on != 0 forKey:opt_key(@"pauseOpen")];
    if (g_menu_open) qs_pause(on != 0);
}
// Quieter while open: the game's sound at a quarter of its volume while the sidebar is up and the game is not paused
static void qs_volume_apply(void) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    float v = [d objectForKey:opt_key(@"volume")] ? [d floatForKey:opt_key(@"volume")] : 1;
    if ([d boolForKey:opt_key(@"muted")]) v = 0;
    if (g_menu_open && [d boolForKey:opt_key(@"duckOpen")]) v *= 0.25f;
    dm_audio_volume_set(v);
}
void front_qs_volume_apply(void) { qs_volume_apply(); }
// Full screen from the Display section
int front_qs_fullscreen(void) { return g_fullscreen; }
void front_qs_fullscreen_toggle(void) { [g_win toggleFullScreen:nil]; }
// Where this game's settings file is ("" when there is none: DM_SETTINGS_FILE=0 or no folder), and my defaults
const char *front_qs_settings_path(void) { NSString *p = settings_file_path(); return p ? p.fileSystemRepresentation : ""; }
const char *front_qs_defaults_path(void) { NSString *p = defaults_file_path(); return p ? p.fileSystemRepresentation : ""; }
int front_qs_defaults_exist(void) { NSString *p = defaults_file_path(); return p && [NSFileManager.defaultManager fileExistsAtPath:p]; }
static void settings_apply(int start);
void front_qs_defaults_save(void) { settings_file_write_to(defaults_file_path(), 1); toast(@"Saved as my defaults for every game"); }
void front_qs_defaults_use(void) {
    if (!settings_file_read(defaults_file_path(), 1)) { toast(@"No defaults saved yet"); return; }
    settings_apply(0); settings_file_write(); toast(@"My defaults applied to this game");
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
        NSTextField *l = [NSTextField labelWithString:@"-- FPS · --.- ms"]; l.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightSemibold]; l.textColor = NSColor.whiteColor;
        NSShadow *sh = [NSShadow new]; sh.shadowColor = [NSColor colorWithWhite:0 alpha:0.8]; sh.shadowBlurRadius = 2; sh.shadowOffset = NSMakeSize(0, -1); l.shadow = sh;
        if (self.view.superview) [gv addSubview:l positioned:NSWindowBelow relativeTo:self.view]; else [gv addSubview:l];
        self.fpsLabel = l; self.fpsN0 = mtl_present_count(); self.fpsT0 = CACurrentMediaTime();
        __weak DmSettings *me = self;
        self.fpsTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) {
            (void)t; DmSettings *s = me; if (!s) return;
            uint64_t n = mtl_present_count(); double now = CACurrentMediaTime();
            double fps = (n - s.fpsN0) / (now - s.fpsT0);
            if (now - s.fpsT0 < 1.5) s.fpsLabel.stringValue = [NSUserDefaults.standardUserDefaults boolForKey:opt_key(@"fpsMs")] && fps > 0   // a longer span was a stall (minimized): no reading
                ? [NSString stringWithFormat:@"%.0f FPS · %.1f ms", fps, 1000 / fps] : [NSString stringWithFormat:@"%.0f FPS", fps];
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
            NSString *run = g_mods_run ? [g_mods_run_order componentsJoinedByString:@"\n"] : nil;   // in load order
            self.view = (__bridge_transfer NSView *)dm_qs_make(DM_GAME_NAME, mods_dir().fileSystemRepresentation, run.UTF8String, qs_close, qs_fps);
            self.view.autoresizingMask = NSViewMinXMargin | NSViewHeightSizable;
            NSView *gv = g_win.contentView; gv.postsFrameChangedNotifications = YES;
            [NSNotificationCenter.defaultCenter addObserverForName:NSViewFrameDidChangeNotification object:gv queue:nil usingBlock:^(NSNotification *n) {   // a resize while it is up: the picture keeps beside it
                (void)n; if (!g_menu_open || g_inset_timer) return; CGFloat W = gv.bounds.size.width, sw = self.view.frame.size.width;
                g_inset_now = g_inset_to = sw < W ? (float)(sw / W) : 0; mtl_present_inset(g_inset_now); }];
        }
        NSView *gv = g_win.contentView; CGFloat w = MIN(460, gv.bounds.size.width);
        self.view.frame = NSMakeRect(gv.bounds.size.width - w, 0, w, gv.bounds.size.height);
        if (settings_file_changed() && settings_file_read(settings_file_path(), 0)) { settings_apply(0); settings_file_write(); toast(@"Settings file read again"); }   // edited while the game ran
        dm_qs_opened(g_open_by_pad); dm_qs_refresh();
        [gv addSubview:self.view]; g_menu_open = 1;
        inset_to(w < gv.bounds.size.width ? (float)(w / gv.bounds.size.width) : 0);   // a sidebar as wide as the window covers the game instead
        input_release(); dm_focus_set(2);   // as when the window loses focus: nothing stays held, and a game that pauses for the HOME menu pauses
        qs_volume_apply();
        if (qs_pause_wanted()) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ if (g_menu_open && qs_pause_wanted()) { qs_pause(1); dm_qs_refresh(); } });   // once the picture has slid aside
        LOG("front end: Quick settings open");
    } else {
        qs_pause(0);
        [self.view removeFromSuperview]; g_menu_open = 0; inset_to(0); g_pad_quiet = 1; g_assign = -1; qs_volume_apply();
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
        if (i != DM_PFX_OFF && i != DM_PFX_CRT) continue;   // the player picks off or CRT; the others stay for DM_PRESENT_FILTER
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
// The saved settings put to work: at launch (start: also the mods, the capture folder and anisotropic filtering, which take effect only then), and after the settings file or
// my defaults were read while the game runs. A setting the environment names wins over its saved value
static void settings_apply(int start) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if (start) {
        mods_start();
        capture_folder_set([d stringForKey:opt_key(@"captureDir")]);
        // Anisotropic filtering: 16x unless this game's saved choice says otherwise (the Mac has the GPU time to spare; "Game default" is saved as 0). Taken at the game's first sampler: before the guest runs
        if (!getenv("DM_ANISO")) mtl_aniso_set([d objectForKey:opt_key(@"aniso")] ? (int)[d integerForKey:opt_key(@"aniso")] : 16);
    } else if (!getenv("DM_ANISO")) mtl_aniso_set([d objectForKey:opt_key(@"aniso")] ? (int)[d integerForKey:opt_key(@"aniso")] : 16);   // logs that it applies at the next launch
    controls_load();
    // Upscaling: MetalFX unless the settings window's saved choice (launcher.DM_PRESENT_UPSCALE, which Quick settings writes too) says off; the window and env.txt set it in the environment
    if (!getenv("DM_PRESENT_UPSCALE")) { NSString *u = [d stringForKey:@"launcher.DM_PRESENT_UPSCALE"]; mtl_present_upscale_set(u ? [u isEqualToString:@"metalfx"] : 1); }
    if (!getenv("DM_PRESENT_AA")) mtl_present_aa_set([d objectForKey:opt_key(@"aa")] ? (int)[d integerForKey:opt_key(@"aa")] : DM_PAA_OFF);
    if (!getenv("DM_PRESENT_SCALE")) mtl_present_scale_set([d objectForKey:opt_key(@"scale")] ? (int)[d integerForKey:opt_key(@"scale")] : DM_PSCALE_FIT);
    qs_volume_apply();
    if (!getenv("DM_PRESENT_SCANLINE")) mtl_present_scanline_set([d objectForKey:pfx_key(@"scanline")] ? (int)[d integerForKey:pfx_key(@"scanline")] : 0);
    if (!start && g_opts) [g_opts fpsCounter];
    if (getenv("DM_PRESENT_FILTER")) return;
    if (![d objectForKey:pfx_key(@"mode")]) { if (!start) mtl_present_filter_set(DM_PFX_OFF, 0.5f); return; }
    int m = (int)[d integerForKey:pfx_key(@"mode")]; if (m != DM_PFX_CRT) m = DM_PFX_OFF;   // a choice saved before Sharpen, Pixel-perfect, CRT-Lottes and LCD Grid left the menus: off
    float k = [d objectForKey:pfx_key(@"strength")] ? [d floatForKey:pfx_key(@"strength")] : 0.5f;
    mtl_present_filter_set(m, k); LOG("front end: present filter from the saved choice for this game (Quick settings)");
}
static void graphics_start(void) {   // main thread, before the guest runs: the settings file, then the saved filter, anisotropic filtering, upscaling, anti-aliasing, volume, controls and mods
    settings_file_start();
    settings_apply(1);
}
const char *front_qs_title_id(void) { return DM_GAME_ID; }   // the save backups' manifest and the mods' Atmosphere folders
void front_qs_toast_text(const char *msg) { toast(@(msg)); }   // the sidebar's own toasts (a save backed up, a capture copied)
