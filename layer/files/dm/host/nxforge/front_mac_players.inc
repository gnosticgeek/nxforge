// NXForge: included by front_mac_front_end.inc (so front_mac.m meets no new line). Players (the sidebar's Controls page): who is player 1, 2, 3 and 4, by the
// controllers' names, and Make player 1, which trades two players' controllers. The slot table (pad_slots.h) gives a controller its player by the order and the
// names of what connected, so with two controllers the one that happened to connect first is player 1 until both are unplugged; here the players choose.
// A trade moves everything that follows the player: the buttons and sticks (released for a moment on both), a GameController pad's motion and rumble, and
// the rumble sink of a pad read over HID or Bluetooth. Original Joy-Cons read from their HID reports keep their player (pad_jc1_mac.h holds it per Joy-Con:
// they join in the order their first buttons are pressed, so pressing in the order wanted does the same). Not with DM_PAD_MERGE, where every controller is player 1.
static int nxf_player_is_jc1(const void *o) { for (jc1_pad *d = g_jc1_pads; d; d = d->next) if (d == o) return 1; return 0; }
static int nxf_player_is_s2(const void *o) { for (s2_pad *d = dm_switch2_pads(); d; d = d->next) if (d == o) return 1; return 0; }
// What the sidebar shows for player p (0-based): 0 nobody; 1 a controller that can trade places; 2 one that cannot (Joy-Cons, or the keyboard as a player of its own)
int front_qs_player(int p, char *name, int cap) {
    if (name && cap > 0) name[0] = 0;
    if (g_merge || p < 0 || p >= DM_PLAYERS || !g_slots.owner[p]) return 0;
    if (name) snprintf(name, cap, "%s", g_slots.last[p][0] ? g_slots.last[p] : "Controller");
    return g_held[p] || nxf_player_is_s2(g_slots.owner[p]) || (!nxf_player_is_jc1(g_slots.owner[p]) && strcmp(g_slots.last[p], "keyboard")) ? 1 : 2;
}
// Trade players a and b (one of them may be free: the controller moves there). 1: done
int front_qs_player_swap(int a, int b) {
    char na[64], nb[64];
    int ka = front_qs_player(a, na, sizeof na), kb = front_qs_player(b, nb, sizeof nb);
    if (a == b || a < 0 || b < 0 || a >= DM_PLAYERS || b >= DM_PLAYERS || ka == 2 || kb == 2 || (!ka && !kb)) return 0;
    int pl[2] = {a, b};
    for (int i = 0; i < 2; i++) {   // nothing stays pressed, and nothing of the old player stays attached
        int p = pl[i];
        dm_pad_set_player(p, 0, 0, 0, 0, 0);
        if (g_held[p]) dm_motion_detach(g_held[p], p);
        dm_haptics_apple_controller(p, nil); dm_haptics_apple_set_sink(p, NULL); dm_motion_clear_hid(p);
    }
    for (hid_pad *d = g_hidpads; d; d = d->next) if (d == g_slots.owner[a] || d == g_slots.owner[b]) d->sink = 0;   // hidpad_read sets its player's sink again
    const void *o = g_slots.owner[a]; g_slots.owner[a] = g_slots.owner[b]; g_slots.owner[b] = o;
    char t[64]; memcpy(t, g_slots.last[a], sizeof t); memcpy(g_slots.last[a], g_slots.last[b], sizeof t); memcpy(g_slots.last[b], t, sizeof t);
    GCController *c = g_held[a]; g_held[a] = g_held[b]; g_held[b] = c;
    for (int i = 0; i < 2; i++) {
        int p = pl[i];
        if (g_held[p]) dm_motion_attach(g_held[p], p);   // its rumble follows at its next report (pad_read: dm_haptics_apple_controller)
        else if (nxf_player_is_s2(g_slots.owner[p])) dm_haptics_apple_set_sink(p, dm_switch2_rumble);
    }
    dm_pad_players(pad_slot_mask(&g_slots)); pads_motion_changed(nil);
    LOG("front end: players traded: player %d is '%s' now, player %d '%s'", a + 1, kb ? nb : "free", b + 1, ka ? na : "free");
    return 1;
}
