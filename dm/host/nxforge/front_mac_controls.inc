// NXForge: included by front_mac.m at the place this code stood (it shares that file's statics). Kept out of
// upstream's file so a merge of nxnative meets one #include line. See UPSTREAM.md, Thin fork.
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
