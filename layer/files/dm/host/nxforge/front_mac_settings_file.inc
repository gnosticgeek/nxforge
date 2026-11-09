// NXForge: included by nxforge/front_mac_quick_settings.inc (it shares front_mac.m's statics). See UPSTREAM.md, Thin fork.
// The settings file: this game's sidebar settings as plain text, "name = value" a line, beside the game ("NXForge settings.txt" in the game folder, DM_GAME_FOLDER), else in
// <DM_ROOT>/nxforge-settings.txt. The user defaults stay where the settings are read from; the file mirrors them and wins at launch, so an edit made with the game closed applies.
// A setting left at its default is written as a comment line ("# fps = off"); deleting a line puts it back to the default. Every change the sidebar (or a menu) makes rewrites
// the file within half a second; an edit made while the game runs is read when the sidebar next opens. DM_SETTINGS_FILE=0 turns the file off.
// My defaults (the sidebar's General page): the same format, in ~/Library/Application Support/NXForge/Sidebar defaults.txt, with only the settings that make sense in every game
// (graphics, sound, the counter, pausing and the controls; not mods, frame times or the capture folder). A game without a settings file of its own starts from it.
enum { SF_BOOL, SF_PICK, SF_PERCENT, SF_FRACTION, SF_TEXT, SF_LIST };
typedef struct { const char *name; const char *key; int pfx; int type; const char *const *picks; int npicks; int carry; const char *def; } sf_entry;
static const char *const sf_filter[] = {"off", "sharpen", "pixel", "crt", "lottes", "lcd"};   // DM_PFX_* in order
static const char *const sf_lines[] = {"auto", "1", "2", "3", "4", "5", "6", "7", "8"};
static const char *const sf_aa[] = {"off", "fxaa"};
static const char *const sf_size[] = {"fit", "stretch", "pixel-perfect"};   // DM_PSCALE_*
static const char *const sf_interp[] = {"off", "on", "auto"};   // front.h mtl_present_interp
static const char *const sf_corner[] = {"top-left", "top-right", "bottom-left", "bottom-right"};
// key: the user defaults key's middle part (pfx: DMPresentFilter.<key>.<game>, else DMQuickSettings.<key>.<game>); aniso and upscale are handled by name
static const sf_entry g_sf[] = {
    {"filter", "mode", 1, SF_PICK, sf_filter, 6, 1, "off"},
    {"crt_strength", "strength", 1, SF_PERCENT, NULL, 0, 1, "50"},
    {"crt_line_size", "scanline", 1, SF_PICK, sf_lines, 9, 1, "auto"},
    {"anti_aliasing", "aa", 0, SF_PICK, sf_aa, 2, 1, "off"},
    {"anisotropic_filtering", "aniso", 0, SF_TEXT, NULL, 0, 1, "16"},
    {"metalfx_upscaling", "upscale", 0, SF_BOOL, NULL, 0, 1, "on"},
    {"hdr_highlights", "edr", 0, SF_BOOL, NULL, 0, 1, "off"},
    {"hdr_strength", "edrStrength", 0, SF_PERCENT, NULL, 0, 1, "50"},
    {"picture_size", "scale", 0, SF_PICK, sf_size, 3, 1, "fit"},
    {"volume", "volume", 0, SF_PERCENT, NULL, 0, 1, "100"},
    {"muted", "muted", 0, SF_BOOL, NULL, 0, 1, "off"},
    {"pause_while_open", "pauseOpen", 0, SF_BOOL, NULL, 0, 1, "on"},
    {"quieter_while_open", "duckOpen", 0, SF_BOOL, NULL, 0, 1, "off"},
    {"fps_counter", "fps", 0, SF_BOOL, NULL, 0, 1, "off"},
    {"fps_corner", "fpsPos", 0, SF_PICK, sf_corner, 4, 1, "top-left"},
    {"fps_milliseconds", "fpsMs", 0, SF_BOOL, NULL, 0, 1, "off"},
    {"frame_interpolation", "interp", 0, SF_PICK, sf_interp, 3, 1, "off"},
    {"record_frame_times", "frameTimes", 0, SF_BOOL, NULL, 0, 0, "off"},
    {"mods_on", "mods", 0, SF_LIST, NULL, 0, 0, ""},
    {"mod_order", "modOrder", 0, SF_LIST, NULL, 0, 0, ""},
    {"capture_folder", "captureDir", 0, SF_TEXT, NULL, 0, 0, ""},
};
enum { SF_N = sizeof g_sf / sizeof g_sf[0] };
static const char *const sf_action[] = {"a", "b", "x", "y", "left_stick_press", "right_stick_press", "l", "r", "zl", "zr", "plus", "minus", "dpad_left", "dpad_up", "dpad_right",
                                        "dpad_down", "stick_up", "stick_left", "stick_down", "stick_right", "shake"};   // the Controls page's actions (ACT_*), as file names
_Static_assert(sizeof sf_action / sizeof sf_action[0] == ACT_N, "one file name per action");
// Key names (US layout key codes), for the file and for a swapped key's label; a code without a name is written "key 50"
static const struct { unsigned short code; const char *name; } g_sf_keys[] = {
    {0, "A"}, {1, "S"}, {2, "D"}, {3, "F"}, {4, "H"}, {5, "G"}, {6, "Z"}, {7, "X"}, {8, "C"}, {9, "V"}, {11, "B"}, {12, "Q"}, {13, "W"}, {14, "E"}, {15, "R"}, {16, "Y"}, {17, "T"},
    {18, "1"}, {19, "2"}, {20, "3"}, {21, "4"}, {22, "6"}, {23, "5"}, {24, "="}, {25, "9"}, {26, "7"}, {27, "-"}, {28, "8"}, {29, "0"}, {30, "]"}, {31, "O"}, {32, "U"}, {33, "["},
    {34, "I"}, {35, "P"}, {36, "Return"}, {37, "L"}, {38, "J"}, {39, "'"}, {40, "K"}, {41, ";"}, {42, "\\"}, {43, ","}, {44, "/"}, {45, "N"}, {46, "M"}, {47, "."}, {48, "Tab"},
    {49, "Space"}, {50, "`"}, {51, "Delete"}, {76, "Enter"}, {123, "←"}, {124, "→"}, {125, "↓"}, {126, "↑"},
};
static NSString *sf_key_name(unsigned short code) {
    if (code == KEY_NONE) return @"none";
    for (size_t i = 0; i < sizeof g_sf_keys / sizeof g_sf_keys[0]; i++) if (g_sf_keys[i].code == code) return @(g_sf_keys[i].name);
    return [NSString stringWithFormat:@"key %u", code];
}
static int sf_key_code(NSString *s) {   // -1: not a key name
    if ([s caseInsensitiveCompare:@"none"] == NSOrderedSame) return KEY_NONE;
    for (size_t i = 0; i < sizeof g_sf_keys / sizeof g_sf_keys[0]; i++) if ([s caseInsensitiveCompare:@(g_sf_keys[i].name)] == NSOrderedSame) return g_sf_keys[i].code;
    NSArray *w = [s componentsSeparatedByString:@" "];
    if (w.count == 2 && [w[0] caseInsensitiveCompare:@"key"] == NSOrderedSame && [w[1] intValue] >= 0 && [w[1] intValue] < 0xffff) return [w[1] intValue];
    return -1;
}
static NSString *sf_dkey(const sf_entry *e) { return e->pfx ? pfx_key(@(e->key)) : !strcmp(e->key, "upscale") ? @"launcher.DM_PRESENT_UPSCALE" : opt_key(@(e->key)); }

static NSString *settings_file_path(void) {
    const char *off = getenv("DM_SETTINGS_FILE"); if (off && !strcmp(off, "0")) return nil;
    const char *g = getenv("DM_GAME_FOLDER"), *r = getenv("DM_ROOT");
    if (g && *g) return [@(g) stringByAppendingPathComponent:@"NXForge settings.txt"];
    if (r && *r) return [@(r) stringByAppendingPathComponent:@"nxforge-settings.txt"];
    return nil;
}
static NSString *defaults_file_path(void) {
    NSURL *u = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return u ? [u.path stringByAppendingPathComponent:@"NXForge/Sidebar defaults.txt"] : nil;
}

// One entry's value as the file writes it; nil when it is not saved (the default applies)
static NSString *sf_value(const sf_entry *e) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults; NSString *k = sf_dkey(e); id v = [d objectForKey:k];
    if (!v) return nil;
    if (!strcmp(e->key, "upscale")) return [v isEqual:@"off"] ? @"off" : @"on";
    if (!strcmp(e->key, "aniso")) { int n = [v intValue]; return n ? [NSString stringWithFormat:@"%d", n] : @"game"; }
    switch (e->type) {
        case SF_BOOL: return [v boolValue] ? @"on" : @"off";
        case SF_PICK: { int i = [v intValue]; return i >= 0 && i < e->npicks ? @(e->picks[i]) : nil; }
        case SF_PERCENT: return [NSString stringWithFormat:@"%d", (int)lround([v doubleValue] * 100)];
        case SF_TEXT: return [v isKindOfClass:NSString.class] ? v : [v description];
        case SF_LIST: return [v isKindOfClass:NSArray.class] ? [v componentsJoinedByString:@" | "] : nil;
    }
    return nil;
}
// Put a file value into the user defaults; NO when the value does not fit the entry (it is then left out, and logged)
static BOOL sf_set(const sf_entry *e, NSString *s) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults; NSString *k = sf_dkey(e), *l = s.lowercaseString;
    BOOL on = [l isEqualToString:@"on"] || [l isEqualToString:@"yes"] || [l isEqualToString:@"true"] || [l isEqualToString:@"1"];
    BOOL off = [l isEqualToString:@"off"] || [l isEqualToString:@"no"] || [l isEqualToString:@"false"] || [l isEqualToString:@"0"];
    if (!strcmp(e->key, "upscale")) { if (on) [d removeObjectForKey:k]; else if (off) [d setObject:@"off" forKey:k]; else return NO; return YES; }
    if (!strcmp(e->key, "aniso")) {
        int n = [l isEqualToString:@"game"] ? 0 : [l stringByReplacingOccurrencesOfString:@"x" withString:@""].intValue;
        if (n != 0 && n != 2 && n != 4 && n != 8 && n != 16) return NO;
        [d setInteger:n forKey:k]; return YES;
    }
    switch (e->type) {
        case SF_BOOL: if (!on && !off) return NO; [d setBool:on forKey:k]; return YES;
        case SF_PICK: for (int i = 0; i < e->npicks; i++) if ([l isEqualToString:@(e->picks[i])]) { [d setInteger:i forKey:k]; return YES; } return NO;
        case SF_PERCENT: { NSScanner *sc = [NSScanner scannerWithString:l]; double v; if (![sc scanDouble:&v] || v < 0 || v > 100) return NO;
                           if (e->pfx) [d setFloat:(float)(v / 100) forKey:k]; else [d setDouble:v / 100 forKey:k]; return YES; }
        case SF_TEXT: if (!s.length) [d removeObjectForKey:k]; else [d setObject:s forKey:k]; return YES;
        case SF_LIST: { NSMutableArray *a = [NSMutableArray array];
                        for (NSString *x in [s componentsSeparatedByString:@"|"]) { NSString *t = [x stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]; if (t.length) [a addObject:t]; }
                        [d setObject:a forKey:k]; return YES; }
    }
    return NO;
}

static int g_sf_loading;            // the file is being read into the user defaults: their change notifications do not write it back
static NSDate *g_sf_written;        // the file's modification date after this run last wrote it (or read it)
static NSDate *sf_mtime(NSString *p) { return [[NSFileManager.defaultManager attributesOfItemAtPath:p error:nil] fileModificationDate]; }

// Read a settings file into the user defaults. carry_only: the defaults file (only the settings every game shares, and a missing line leaves a setting as it is); else this game's
// file, where a missing line puts the setting back to its default. Returns whether the file was there
static BOOL settings_file_read(NSString *path, int carry_only) {
    NSString *text = path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
    if (!text) return NO;
    NSMutableDictionary<NSString *, NSString *> *kv = [NSMutableDictionary dictionary];
    for (NSString *raw in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *ln = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (!ln.length || [ln hasPrefix:@"#"]) continue;
        NSRange eq = [ln rangeOfString:@"="]; if (eq.location == NSNotFound) { LOG("[RED] settings file %s: no '=' in \"%s\"; line skipped", path.lastPathComponent.UTF8String, ln.UTF8String); continue; }
        NSString *k = [[ln substringToIndex:eq.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].lowercaseString;
        kv[k] = [[ln substringFromIndex:eq.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    }
    g_sf_loading++;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    for (int i = 0; i < SF_N; i++) {
        const sf_entry *e = &g_sf[i];
        if (carry_only && !e->carry) continue;
        NSString *v = kv[@(e->name)];
        if (!v) { if (!carry_only) [d removeObjectForKey:sf_dkey(e)]; continue; }
        if (!sf_set(e, v)) LOG("[RED] settings file %s: %s = %s is not a value it takes; the setting keeps its default", path.lastPathComponent.UTF8String, e->name, v.UTF8String);
    }
    // Controls: keyboard.<action> = key name, controller.<action> = a GameController button name ("Button B"); only the actions that differ from the defaults are written
    NSMutableDictionary *keys = [NSMutableDictionary dictionary], *keyNames = [NSMutableDictionary dictionary], *pad = [NSMutableDictionary dictionary], *padNames = [NSMutableDictionary dictionary];
    int any_keys = 0, any_pad = 0;
    for (int i = 0; i < ACT_N; i++) {
        NSString *kv1 = kv[[@"keyboard." stringByAppendingString:@(sf_action[i])]];
        if (kv1) { int c = sf_key_code(kv1);
            if (c < 0) LOG("[RED] settings file %s: keyboard.%s = %s is not a key name; the key keeps its default", path.lastPathComponent.UTF8String, sf_action[i], kv1.UTF8String);
            else { keys[@(i).stringValue] = @(c); keyNames[@(i).stringValue] = c == KEY_NONE ? @"Not set" : sf_key_name((unsigned short)c); any_keys = 1; } }
        NSString *pv = i < PAD_N ? kv[[@"controller." stringByAppendingString:@(sf_action[i])]] : nil;
        if (pv) { BOOL none = [pv caseInsensitiveCompare:@"none"] == NSOrderedSame; pad[@(i).stringValue] = none ? @"" : pv; padNames[@(i).stringValue] = none ? @"Not set" : pv; any_pad = 1; }
    }
    if (any_keys || !carry_only) { if (any_keys) { [d setObject:keys forKey:opt_key(@"keys")]; [d setObject:keyNames forKey:opt_key(@"keyNames")]; } else { [d removeObjectForKey:opt_key(@"keys")]; [d removeObjectForKey:opt_key(@"keyNames")]; } }
    if (any_pad || !carry_only) { if (any_pad) { [d setObject:pad forKey:opt_key(@"pad")]; [d setObject:padNames forKey:opt_key(@"padNames")]; } else { [d removeObjectForKey:opt_key(@"pad")]; [d removeObjectForKey:opt_key(@"padNames")]; } }
    g_sf_loading--;
    LOG("front end: settings read from %s", path.fileSystemRepresentation);
    return YES;
}
static void settings_file_write_to(NSString *path, int carry_only) {
    if (!path) return;
    NSMutableString *t = [NSMutableString string];
    if (carry_only) [t appendString:@"# NXForge Sidebar: my defaults. A game without a settings file of its own starts from these.\n"];
    else [t appendFormat:@"# NXForge Sidebar settings for %s (%s)\n", DM_GAME_NAME, DM_GAME_ID];
    [t appendString:@"# One setting a line: name = value. A line starting with # is the default, unused; remove the # to change it, delete a line to go back to the default.\n"
                    @"# Edit it with the game closed, or open the game's sidebar after saving here: the sidebar reads it again when it opens.\n"];
    int group = -1;
    for (int i = 0; i < SF_N; i++) {
        const sf_entry *e = &g_sf[i];
        if (carry_only && !e->carry) continue;
        static const char *const groups[] = {"Graphics", "Sound and pausing", "Performance", "Mods and capture"};
        int gr = i < 7 ? 0 : i < 11 ? 1 : i < 15 ? 2 : 3;
        if (gr != group) { [t appendFormat:@"\n# %s\n", groups[gr]]; group = gr; }
        NSString *v = sf_value(e), *choices = @"";
        if (e->type == SF_PICK) { NSMutableArray *a = [NSMutableArray array]; for (int j = 0; j < e->npicks; j++) [a addObject:@(e->picks[j])]; choices = [NSString stringWithFormat:@"   (%@)", [a componentsJoinedByString:@", "]]; }
        if (!strcmp(e->key, "mode")) choices = @"   (off, crt)";
        if (!strcmp(e->key, "aniso")) choices = @"   (game, 2, 4, 8, 16)";
        if (e->type == SF_PERCENT) choices = @"   (0 to 100)";
        if (e->type == SF_BOOL) choices = @"   (on, off)";
        if (e->type == SF_LIST) choices = @"   (folder names, separated by |)";
        if (v) [t appendFormat:@"%s = %@\n", e->name, v]; else [t appendFormat:@"# %s = %s%@\n", e->name, e->def, choices];
    }
    [t appendString:@"\n# Controls: keyboard.<button> = a key (A to Z, 0 to 9, Return, Tab, Space, Delete, ←, →, ↑, ↓, none), controller.<button> = a controller button (Button A, Left Shoulder, …)\n"];
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSDictionary *keys = [d dictionaryForKey:opt_key(@"keys")], *pad = [d dictionaryForKey:opt_key(@"pad")];
    for (int i = 0; i < ACT_N; i++) {
        NSNumber *n = keys[@(i).stringValue];
        if (n) [t appendFormat:@"keyboard.%s = %@\n", sf_action[i], sf_key_name(n.unsignedShortValue)]; else [t appendFormat:@"# keyboard.%s = %@\n", sf_action[i], sf_key_name(g_key_default[i])];
    }
    for (int i = 0; i < PAD_N; i++) {
        NSString *p = pad[@(i).stringValue];
        if (p) [t appendFormat:@"controller.%s = %@\n", sf_action[i], p.length ? p : @"none"]; else [t appendFormat:@"# controller.%s = %@\n", sf_action[i], pad_default(i)];
    }
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *old = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if ([old isEqualToString:t]) { if (!carry_only) g_sf_written = sf_mtime(path); return; }
    NSError *err = nil;
    if (![t writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err]) { LOG("[RED] settings file: cannot write %s: %s", path.fileSystemRepresentation, err.localizedDescription.UTF8String); return; }
    if (!carry_only) g_sf_written = sf_mtime(path);
}
static void settings_file_write(void) { settings_file_write_to(settings_file_path(), 0); }
// Rewrite the file half a second after the last change to the user defaults (a slider sends many)
static void settings_file_watch(void) {
    static int on; if (on || !settings_file_path()) return; on = 1;
    static NSTimer *t;
    [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        (void)n; if (g_sf_loading) return;
        [t invalidate]; t = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer *x) { (void)x; t = nil; settings_file_write(); }];
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationWillTerminateNotification object:nil queue:nil usingBlock:^(NSNotification *n) { (void)n; if (t) { [t invalidate]; t = nil; settings_file_write(); } }];
}
// At launch, before any setting is read: this game's file (or, when it has none yet, my defaults), then the file written as the settings now are
static void settings_file_start(void) {
    NSString *p = settings_file_path(); if (!p) return;
    if (!settings_file_read(p, 0)) settings_file_read(defaults_file_path(), 1);
    settings_file_write(); settings_file_watch();
}
// Whether the file changed since this run wrote it (an edit while the game runs): the sidebar reads it again when it opens
static BOOL settings_file_changed(void) {
    NSString *p = settings_file_path(); NSDate *m = p ? sf_mtime(p) : nil;
    return m && g_sf_written && ![m isEqualToDate:g_sf_written];
}
