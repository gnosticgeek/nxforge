// NXForge: a cheat write that would break a pointer is refused (hle_cheats.c cheat_write; docs/cheats.md, "Pointer guard").
//
// A pointer-chain cheat (5 load, 7 add/sub, 6 store) reaches its value through a static pointer the game fills in once its
// object exists. Before that, at boot, on a title screen or while a save loads, the same static can point at another object,
// and the cheat's store lands inside it. Blazing Chrome's "P1 Lives unlimited" (build 318F9F225A532857, a GameMaker game)
// wrote the high half of the double 5.0 (0x40140000) over the high half of a heap pointer while a quick-save slot restarted
// the game: the game then read through 0x40140000xxxxxxxx and crashed (SIGSEGV at main+0x173a604). A Switch would crash too.
//
// The guard: for each aligned 8-byte word the write touches, when the word holds a pointer into the game's memory now
// (where_get accepts it) and the write would leave something that is not one, nothing is written. The cheat stays on and is
// retried every pass like any failed access, so it takes effect as soon as the static points at the right object, where the
// word holds a value (lives, health, a double) and not a pointer. A write that keeps a pointer a pointer (a cheat that
// redirects one) or that does not change the word goes through. DM_CHEATS_POINTER_GUARD=0 turns the guard off.

static int nxf_ptr_guard_on(void) {
    static int on = -1;
    if (on < 0) { const char *e = getenv("DM_CHEATS_POINTER_GUARD"); on = !(e && e[0] == '0'); }
    return on;
}

// 1 when writing len bytes of val at addr would turn a pointer into the game's memory into something that is not one
static int nxf_write_breaks_pointer(uint64_t addr, uint64_t len, uint64_t val, uint64_t *word_out, uint64_t *old_out) {
    if (!nxf_ptr_guard_on() || !len || len > 8) return 0;
    uint64_t first = addr & ~7ull, last = (addr + len - 1) & ~7ull;
    for (uint64_t a = first; a <= last; a += 8) {
        uint64_t old;
        if (mem_read(a, 8, &old)) continue;   // the word is not readable as a whole: nothing to protect
        uint64_t neu = old;
        for (uint64_t i = 0; i < 8; i++) {
            uint64_t p = a + i;
            if (p < addr || p >= addr + len) continue;
            uint64_t b = (val >> (8 * (p - addr))) & 0xff;
            neu = (neu & ~(0xffull << (8 * i))) | (b << (8 * i));
        }
        if (neu == old) continue;
        where_t w;
        if (where_get(old, 1, &w) == 0 && where_get(neu, 1, &w) != 0) { *word_out = a; *old_out = old; return 1; }
    }
    return 0;
}

// The first refusal of each cheat is logged once with the pointer it kept (later ones are counted on its row like any failed
// access); a handful of cheat slots is plenty for a log line
static void nxf_log_pointer_refusal(cheat_t *c, uint64_t addr, uint64_t word, uint64_t old) {
    static const void *seen[64]; static int nseen;
    for (int i = 0; i < nseen; i++) if (seen[i] == c) return;
    if (nseen < 64) seen[nseen++] = c;
    LOG("[RED] cheat \"%s\": write at guest address 0x%llx refused: it would break the pointer 0x%llx at 0x%llx (the game has not "
        "set up what the cheat looks for yet, or the cheat does not match it); retried every pass, it applies once the word holds a "
        "value (DM_CHEATS_POINTER_GUARD=0 turns this check off)", c->name, (unsigned long long)addr, (unsigned long long)old,
        (unsigned long long)word);
}
