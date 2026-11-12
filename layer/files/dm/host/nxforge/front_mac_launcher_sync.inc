// NXForge: included by nxforge/front_mac_quick_settings.inc (it shares front_mac.m's statics). See UPSTREAM.md, Thin fork.
// The settings the game's settings window (dm/mac/Launcher.swift, rows from dm/games/settings.tsv) and the sidebar both show: anti-aliasing, HDR highlights and its strength, and
// frame interpolation. The sidebar keeps them as before (DMQuickSettings.<what>.<game>, and the settings file); the window keeps launcher.<VAR> strings, which launcher.c and the
// window put into the environment at launch. Two stores, kept equal here:
//   - the host mirrors each sidebar value into launcher.<VAR> (removed at the default, as the window does), and notes what it wrote in nxforge.mirror.<VAR>
//   - at launch, a launcher.<VAR> that differs from that note was changed in the window since: the sidebar takes it (and the settings file follows)
// So the window shows what the sidebar last chose, a choice made in the window reaches the sidebar, and a Restart game (the same environment again) keeps a sidebar change made in
// the run before. The environment decides only where the launch environment or an env file set the variable (env_fixed); the window's own variables are not fixed.
// Upscaling has one store (launcher.DM_PRESENT_UPSCALE) and needs no mirror; its fixed rule is the same.

static int env_list_has(const char *list, const char *var) {   // a space-separated list of names (DM_ENV_LAUNCH_KEYS, DM_ENV_FILE_KEYS)
    size_t n = strlen(var);
    for (const char *p = list; p && *p;) {
        while (*p == ' ') p++;
        const char *e = strchr(p, ' '); size_t len = e ? (size_t)(e - p) : strlen(p);
        if (len == n && !strncmp(p, var, n)) return 1;
        if (!e) break; p = e;
    }
    return 0;
}
// The launch environment or an env file set this variable, so it wins over every saved choice; not when the settings window (or launcher.c's saved choices) set it.
// Without DM_ENV_LAUNCH_KEYS the host was not started by the app's launcher (a bench, a test), and a variable set is fixed
static int env_fixed(const char *var) {
    if (!getenv(var)) return 0;
    const char *l = getenv("DM_ENV_LAUNCH_KEYS");
    return !l || env_list_has(l, var) || env_list_has(getenv("DM_ENV_FILE_KEYS"), var);
}

enum { LW_BOOL, LW_PICK, LW_FRACTION };   // a fraction: the window's slider writes "0.50"
typedef struct { const char *var; const char *what; int kind; const char *const *picks; int npicks; const char *def; } lw_entry;
static const char *const lw_aa[] = {"off", "fxaa"};           // DM_PAA_*, as DM_PRESENT_AA takes them
static const char *const lw_interp[] = {"off", "on", "auto"};  // mtl_present_interp, as DM_PRESENT_INTERP takes them
static const lw_entry g_lw[] = {
    {"DM_PRESENT_AA", "aa", LW_PICK, lw_aa, 2, "off"},
    {"DM_PRESENT_EDR", "edr", LW_BOOL, NULL, 0, "0"},
    {"DM_PRESENT_EDR_STRENGTH", "edrStrength", LW_FRACTION, NULL, 0, "0.50"},
    {"DM_PRESENT_INTERP", "interp", LW_PICK, lw_interp, 3, "off"},
};
enum { LW_N = sizeof g_lw / sizeof g_lw[0] };

// The sidebar's value as the window writes it
static NSString *lw_current(const lw_entry *e) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults; id v = [d objectForKey:opt_key(@(e->what))];
    if (!v) return @(e->def);
    switch (e->kind) {
        case LW_BOOL: return [v boolValue] ? @"1" : @"0";
        case LW_PICK: { int i = [v intValue]; return i >= 0 && i < e->npicks ? @(e->picks[i]) : @(e->def); }
        case LW_FRACTION: return [NSString stringWithFormat:@"%.2f", [v doubleValue]];
    }
    return @(e->def);
}
// A window value into the sidebar's store; NO when this build's sidebar does not take it
static BOOL lw_take(const lw_entry *e, NSString *s) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults; NSString *k = opt_key(@(e->what));
    switch (e->kind) {
        case LW_BOOL: if (![s isEqualToString:@"1"] && ![s isEqualToString:@"0"]) return NO; [d setBool:[s isEqualToString:@"1"] forKey:k]; return YES;
        case LW_PICK: for (int i = 0; i < e->npicks; i++) if ([s isEqualToString:@(e->picks[i])]) { [d setInteger:i forKey:k]; return YES; } return NO;
        case LW_FRACTION: { NSScanner *sc = [NSScanner scannerWithString:s]; double v; if (![sc scanDouble:&v] || !sc.atEnd || v < 0 || v > 1) return NO; [d setDouble:v forKey:k]; return YES; }
    }
    return NO;
}
// adopt: at launch, take what the window changed; then mirror the sidebar's values into the window's store
static void launcher_sync(int adopt) {
    static int busy; if (busy) return; busy = 1;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    for (int i = 0; i < LW_N; i++) {
        const lw_entry *e = &g_lw[i];
        if (env_fixed(e->var)) continue;   // env.txt or the launch environment: not a choice to keep
        NSString *lk = [@"launcher." stringByAppendingString:@(e->var)], *mk = [@"nxforge.mirror." stringByAppendingString:@(e->var)];
        NSString *l = [d stringForKey:lk] ?: @(e->def), *m = [d stringForKey:mk] ?: @(e->def);
        if (e->kind == LW_FRACTION) { NSScanner *sc = [NSScanner scannerWithString:l]; double v; if ([sc scanDouble:&v] && sc.atEnd) l = [NSString stringWithFormat:@"%.2f", v]; }   // "0.5" is "0.50"
        if (adopt && ![l isEqualToString:m]) {
            if (lw_take(e, l)) LOG("front end: %s=%s from the settings window (was %s)", e->var, l.UTF8String, m.UTF8String);
            else LOG("[RED] front end: the settings window's %s=%s is not a value the sidebar takes; kept %s", e->var, l.UTF8String, lw_current(e).UTF8String);
        }
        NSString *c = lw_current(e);
        if ([c isEqualToString:@(e->def)]) { if ([d objectForKey:lk]) [d removeObjectForKey:lk]; }
        else if (![[d stringForKey:lk] isEqualToString:c]) [d setObject:c forKey:lk];
        if (![[d stringForKey:mk] isEqualToString:c]) [d setObject:c forKey:mk];
    }
    busy = 0;
}
// A sidebar change (or a settings file read while the game runs) reaches the window's store at once
static void launcher_sync_watch(void) {
    static int on; if (on) return; on = 1;
    [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { (void)n; launcher_sync(0); }];
}
