// Cheats in the host (cheats.h, docs/cheats.md): finds this build's cheat file, writes the enabled cheats' code patches into main's text while the loader still has it writable
// (Mac; the iOS app's code pages are signed and stay as they are), and runs the enabled cheats once per presented frame.
//   DM_CHEATS=<folder>   where the cheat files are; default ~/Library/Application Support/nxnative/<title ID>/cheats (the Mac front end's folder, beside mods). Off when it has no file for this build.
//                        The file is <build ID>.md or .txt (the first 16 hex digits, Atmosphere's name), or any .md whose front matter names this game and build
//   DM_CHEATS_ON=all | <name>;<name>...   the cheats to enable (master codes always run); unset: the ones marked ```dmnt on
// Code patches: a cheat made only of type 0 stores. Its stores into main's text are made once at load, before any guest code runs (a running page cannot be made writable),
// and only where the word is the game's own (not a rewriter site: a B into the patch area) and the new words pass code_word_ok; at run time the VM leaves text it already holds alone
// and refuses other text writes. Everything else (data, pointers, conditions, keys) runs in the VM each frame.
#include "dm.h"
#include "cheats.h"
#include "dm_input.h"
#include <ctype.h>
#include <dirent.h>
#include <strings.h>
#include <stdatomic.h>
#include <sys/stat.h>
#include <unistd.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>

static dm_cheat_file g_file;
static uint8_t *g_on;              // per cheat of g_file
static dm_cheat_vm g_vm;
static _Atomic int g_live;         // the VM has a program
static pthread_mutex_t g_mu = PTHREAD_MUTEX_INITIALIZER;
static int g_inited;

static char *slurp_text(const char *path, size_t *n) {
    FILE *f = fopen(path, "rb"); if (!f) return NULL;
    struct stat st; if (fstat(fileno(f), &st) || st.st_size > (1 << 20)) { fclose(f); return NULL; }
    char *b = malloc((size_t)st.st_size + 1); *n = fread(b, 1, (size_t)st.st_size, f); b[*n] = 0; fclose(f); return b;
}
static int try_file(const char *path, const char *bid) {
    size_t n; char *t = slurp_text(path, &n); if (!t) return 0;
    dm_cheat_file f; int r = dm_cheats_parse(t, n, &f); free(t);
    if (r < 0 || !dm_cheats_match(&f, DM_GAME_ID, bid)) { dm_cheats_free(&f); return 0; }
    g_file = f;
    LOG("cheats: %s: %u cheats for %s build %.16s%s%s", path, f.n, DM_GAME_ID, bid, f.err[0] ? "; left out: " : "", f.err);
    return 1;
}
static int find_file(const char *dir, const char *bid) {
    char p[1024], b16[17]; snprintf(b16, sizeof b16, "%.16s", bid);
    for (int up = 0; up < 2; up++) {
        for (int i = 0; b16[i]; i++) b16[i] = up ? (char)toupper((unsigned char)b16[i]) : (char)tolower((unsigned char)b16[i]);
        snprintf(p, sizeof p, "%s/%s.md", dir, b16); if (try_file(p, bid)) return 1;
        snprintf(p, sizeof p, "%s/%s.txt", dir, b16); if (try_file(p, bid)) return 1;
    }
    DIR *d = opendir(dir); if (!d) return 0;   // a file named some other way: its front matter must name this game and build
    struct dirent *e; int ok = 0;
    while (!ok && (e = readdir(d))) {
        size_t l = strlen(e->d_name);
        if (l > 3 && !strcasecmp(e->d_name + l - 3, ".md")) {
            snprintf(p, sizeof p, "%s/%s", dir, e->d_name);
            size_t n; char *t = slurp_text(p, &n); if (!t) continue;
            dm_cheat_file f; int r = dm_cheats_parse(t, n, &f); free(t);
            int named = f.title_id[0] && f.build_id[0]; dm_cheats_free(&f);
            if (r > 0 && named) ok = try_file(p, bid);
        }
    }
    closedir(d); return ok;
}
static void choose(void) {
    const char *on = getenv("DM_CHEATS_ON");
    g_on = calloc(g_file.n ? g_file.n : 1, 1);
    for (unsigned i = 0; i < g_file.n; i++) {
        const dm_cheat *c = &g_file.c[i];
        if (!on) g_on[i] = (uint8_t)c->default_on;
        else if (!strcmp(on, "all")) g_on[i] = 1;
        else for (const char *s = on; *s;) {   // names separated by ';'
            const char *e = strchr(s, ';'); size_t n = e ? (size_t)(e - s) : strlen(s);
            if (n == strlen(c->name) && !strncmp(s, c->name, n)) g_on[i] = 1;
            s += n + (e ? 1 : 0);
        }
        if (g_on[i] || c->master) LOG("cheats: %s%s", c->master ? "master code: " : "on: ", c->name);
    }
}
static void cheats_init(const char *bid) {   // bid: main's build ID (the loader calls before main counts in g_nmod, so dm_main_build() is still empty there)
    if (g_inited) return;
    g_inited = 1;
    const char *dir = getenv("DM_CHEATS"); char def[1024];
    if (!dir) { const char *h = getenv("HOME"); if (!h) return; snprintf(def, sizeof def, "%s/Library/Application Support/nxnative/%s/cheats", h, DM_GAME_ID); dir = def; }
    if (!bid[0]) { if (getenv("DM_CHEATS")) LOG("[RED] cheats: main has no build ID (an older build output): no cheats"); return; }
    if (!find_file(dir, bid)) { if (getenv("DM_CHEATS")) LOG("cheats: no file in %s for %s build %.16s", dir, DM_GAME_ID, bid); return; }
    choose();
}

// ---- Code patches
// A word the rewriter changed: a B whose target is outside the text (into the patch area). The spin-wait copies (sites.tsv W rows) are not seen here: a patch inside one does nothing
static int rewritten(const module_t *m, uint64_t off) {
    uint32_t w; memcpy(&w, m->base + off, 4);
    if ((w & 0xFC000000u) != 0x14000000u) return 0;
    int64_t t = (int64_t)off + ((int64_t)(int32_t)(w << 6) >> 4);
    return t < 0 || (uint64_t)t >= m->text_end;
}
// New code may not use what the rewriter takes care of (patch_nso.py): svc, system registers (tpidr_el0, tpidrro_el0, cntpct_el0), x18, sub sp from a register
static int code_word_ok(uint32_t w) {
    unsigned rd = w & 31, rn = w >> 5 & 31, rm = w >> 16 & 31, rt2 = w >> 10 & 31, cls = w >> 25 & 0xF;
    if ((w & 0xFFE0001Fu) == 0xD4000001u) return 0;                      // svc
    if ((w & 0xFFD00000u) == 0xD5100000u) return 0;                      // mrs / msr (register)
    if ((cls & 0xE) == 0x8) {                                            // data processing, immediate
        if (rd == 18) return 0;
        int movw = (w >> 23 & 7) == 5, adr = (w >> 24 & 0x1F) == 0x10;
        return movw || adr || rn != 18;
    }
    if ((cls & 0xE) == 0xA) {                                            // branches and system
        if ((w >> 25 & 0x3F) == 0x1A || (w >> 25 & 0x3F) == 0x1B) return rd != 18;   // cbz / cbnz / tbz / tbnz
        if ((w >> 25 & 0x7F) == 0x6B) return rn != 18;                  // br / blr / ret
        return 1;
    }
    if ((cls & 0x5) == 0x4) {                                            // loads and stores
        if (rn == 18) return 0;
        if (!(w >> 26 & 1) && (rd == 18 || ((w >> 27 & 7) == 5 && rt2 == 18))) return 0;   // general registers (not SIMD): Rt, and Rt2 of a pair
        if ((w >> 27 & 7) == 7 && !(w >> 24 & 3) && (w >> 21 & 1) && (w >> 10 & 3) == 2 && rm == 18) return 0;   // register offset
        return 1;
    }
    if ((cls & 0x7) == 0x5) {                                            // data processing, register
        if ((w & 0x7FE00000u) == 0x4B200000u && rd == 31) return 0;     // add / sub (extended register) to sp: the rewriter's sp alignment
        return rd != 18 && rn != 18 && rm != 18 && (!((w >> 24 & 0x1F) == 0x1B) || rt2 != 18);
    }
    return 1;   // SIMD and FP: their general-register moves are not checked
}
static int code_only(const dm_cheat *c) {
    for (unsigned i = 0; i < c->nops;) {
        uint32_t w = c->ops[i]; unsigned wd = w >> 24 & 0xF;
        if (w >> 28 != 0 || (w >> 16 & 0xF) != 0 || !(wd == 1 || wd == 2 || wd == 4 || wd == 8)) return 0;
        i += 2 + (wd == 8 ? 2 : 1);
        if (i > c->nops) return 0;
    }
    return 1;
}
// Loader (map_image, Mac): main is copied in and its text not yet sealed
void cheats_patch_code(module_t *m) {
    if (strcmp(m->name, "main")) return;
    cheats_init(m->build_id);
    for (unsigned k = 0; k < g_file.n; k++) {
        const dm_cheat *c = &g_file.c[k];
        if (!(g_on[k] || c->master) || !code_only(c)) continue;
        for (unsigned i = 0; i < c->nops;) {   // whole type 0 stores (code_only)
            uint32_t w = c->ops[i]; unsigned wd = w >> 24 & 0xF, mem = w >> 20 & 0xF;
            uint64_t off = (uint64_t)(w & 0xFF) << 32 | c->ops[i + 1], v = wd == 8 ? (uint64_t)c->ops[i + 2] << 32 | c->ops[i + 3] : c->ops[i + 2];
            i += 2 + (wd == 8 ? 2 : 1);
            if (mem != 0 || off >= m->text_end) continue;   // data: the VM writes it each frame
            if ((off & 3) || (wd != 4 && wd != 8) || off + wd > m->text_end) { LOG("[RED] cheats: %s: main+%#llx: code patches are whole instructions", c->name, (unsigned long long)off); continue; }
            int ok = 1;
            for (unsigned j = 0; j < wd / 4; j++) {
                uint32_t nw = (uint32_t)(v >> (32 * j));
                if (rewritten(m, off + 4 * j)) { LOG("[RED] cheats: %s: main+%#llx is a rewriter site; left as it is", c->name, (unsigned long long)(off + 4 * j)); ok = 0; }
                else if (!code_word_ok(nw)) { LOG("[RED] cheats: %s: main+%#llx: %08x uses svc, a system register, x18 or sub sp; left as it is", c->name, (unsigned long long)(off + 4 * j), nw); ok = 0; }
            }
            if (!ok) continue;
            memcpy(m->base + off, &v, wd);
            LOG("cheats: %s: main+%#llx patched", c->name, (unsigned long long)off);
        }
    }
}

// ---- Run time
static int mem_read(void *ctx, uint64_t a, void *buf, size_t n) {
    (void)ctx; mach_vm_size_t got = 0;
    return mach_vm_read_overwrite(mach_task_self(), a, n, (mach_vm_address_t)(uintptr_t)buf, &got) != KERN_SUCCESS || got != n;
}
static int mem_write(void *ctx, uint64_t a, const void *buf, size_t n) {
    (void)ctx;
    for (int i = 0; i < g_nmod; i++) {   // module text: only what the loader already patched to these bytes
        const module_t *m = &g_mod[i]; uint64_t b = (uint64_t)(uintptr_t)m->base;
        if (a + n > b && a < b + m->text_end) {
            uint8_t cur[8]; if (mem_read(NULL, a, cur, n)) return -1;
            if (!memcmp(cur, buf, n)) return 0;
            static _Atomic int said; if (!atomic_exchange(&said, 1)) LOG("[RED] cheats: a write into %s's code at +%#llx while it runs is refused (code patches are made at load)", m->name, (unsigned long long)(a - b));
            return -1;
        }
    }
    uint8_t probe[8]; if (mem_read(NULL, a, probe, n)) return -1;   // mapped at all (a write to an unmapped address would crash; mach_vm_write cannot write a page the dirty tracking holds read-only)
    dm_guest_write_prepare((void *)(uintptr_t)a, n);
    return mach_vm_write(mach_task_self(), a, (vm_offset_t)buf, (mach_msg_type_number_t)n) != KERN_SUCCESS;
}
static uint64_t keys(void *ctx) { (void)ctx; uint64_t dm_input_held(void); return dm_input_held(); }
static void say(void *ctx, const char *s) { (void)ctx; LOG("%s", s); }

// Every present (hle_os.c dm_guest_frame_tick)
void cheats_frame(void) {
    static _Atomic int tried;
    if (!atomic_load_explicit(&g_live, memory_order_acquire)) {
        if (atomic_exchange(&tried, 1)) return;
        cheats_init(dm_main_build());
        if (!g_file.n) return;
        if (dm_cheat_vm_load(&g_vm, &g_file, g_on) < 0) { LOG("[RED] cheats: the enabled cheats are longer than 0x400 words together (Atmosphere's limit): none run"); return; }
        if (!g_vm.nprog) return;
        atomic_store_explicit(&g_live, 1, memory_order_release);
    }
    if (pthread_mutex_trylock(&g_mu)) return;
    dm_cheat_env env = { .read = mem_read, .write = mem_write, .keys_held = keys, .log = say };
    for (int i = 0; i < g_nmod; i++) if (!strcmp(g_mod[i].name, "main")) { env.r.main_base = (uint64_t)(uintptr_t)g_mod[i].base; env.r.main_size = g_mod[i].size; }
    void svc_cheat_regions(uint64_t *heap, uint64_t *heap_size, uint64_t *alias, uint64_t *alias_size, uint64_t *aslr, uint64_t *aslr_size);
    svc_cheat_regions(&env.r.heap_base, &env.r.heap_size, &env.r.alias_base, &env.r.alias_size, &env.r.aslr_base, &env.r.aslr_size);
    if (!g_vm.bad) dm_cheat_vm_run(&g_vm, &env);
    pthread_mutex_unlock(&g_mu);
}
