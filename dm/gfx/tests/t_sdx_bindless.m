// Store lookahead and bindless readers (nvn_mtl.m mtl_sub_index / sdx_decide): an attachment cleared in full before its next read is not written back, and a reader the index
// cannot name (a handle in a uniform buffer, a pool array, raw global memory) or a read through another descriptor of the attachment's storage keeps the store.
// Index-level checks: command lists are walked as at a submit and a pass end is decided at a chosen operation; nothing is drawn.
#include "../nvn/nvn_mtl.m"
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t *g_mod; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int fail, count;
#define EXPECT(name, want, got) do { uint64_t w = (want), g = (got); count++; printf("%-78s expected %llu → got %llu %s\n", name, (unsigned long long)w, (unsigned long long)g, w == g ? "✓" : "✗"); fail += w != g; } while (0)
typedef struct { uint8_t *p; size_t n; } chain;
static chain chain_new(void) { chain c = {0}; if (posix_memalign((void **)&c.p, getpagesize(), 65536)) abort(); memset(c.p, 0, 65536); return c; }
static const uint8_t *emit(chain *c, unsigned op, const void *a, size_t n) { size_t z = (8 + n + 7) & ~7ull; op_hdr h = {op, (uint32_t)z}; const uint8_t *at = c->p + c->n; memcpy(c->p + c->n, &h, 8); if (n) memcpy(c->p + c->n + 8, a, n); c->n += z; return at; }
static void end(chain *c) { emit(c, OP_END, NULL, 0); }
static uint8_t g_mem[1 << 16];
static tex_t tex(int k) { static uint64_t s = 9000; tex_t t = {.magic = MAGIC('T', 'E', 'X', 0), .serial = s++}; t.d.width = t.d.height = 8; t.d.depth = t.d.samples = 1; t.d.levels = 1; t.d.target = NVN_TEXTURE_TARGET_2D; t.d.format = NVN_FORMAT_RGBA8;
    t.mem = g_mem + 4096 * k; t.L.size = 4096; return t; }   // k: its storage, 4 KB each; two textures of one k are two descriptors of one memory
static int reg(const tex_t *t) { static int id = 1300; view_t v = {0}; mtl_reg_tex(id, t, &v); return id++; }
static const uint8_t *set_rt(chain *c, const tex_t *a) { p_set_rt r = {.n = 1}; r.color[0] = a; return emit(c, OP_SET_RT, &r, sizeof r); }
static const uint8_t *clear(chain *c) { p_clear_color x = {.index = 0, .mask = 15, .rgba = {0, 0, 0, 1}}; return emit(c, OP_CLEAR_COLOR, &x, sizeof x); }
static const uint8_t *drw(chain *c) { p_draw d = {NVN_DRAW_PRIMITIVE_TRIANGLES, 0, 3}; return emit(c, OP_DRAW, &d, sizeof d); }
static void bind_prog(chain *c, prog_t *p) { p_bind_program b = {p, 3}; emit(c, OP_BIND_PROGRAM, &b, sizeof b); }
static void bind_tex(chain *c, int slot, int id) { p_bind_handles b = {.stage = 1, .first = slot, .n = 1}; b.h[0] = (uint64_t)id; emit(c, OP_BIND_TEX, &b, sizeof b); }
static NvProg *g_pkeep[16]; static int g_npkeep;
static prog_t *prog(uint8_t kind, uint8_t flag) {   // a pixel shader with one binding of that kind (0: none); flag 1 sets rf.bindless, 2 rf.dyn
    static prog_t pg[16]; static int n; prog_t *p = &pg[n]; p->serial = 7000 + n++;
    NvProg *o = [NvProg new]; o->sh[0] = [NvShader new]; o->sh[0]->stage = 0; o->sh[1] = [NvShader new]; o->sh[1]->stage = 1;
    if (kind) { o->sh[1]->rf.nb = 1; o->sh[1]->rf.b[0] = (nvn_rbind){.kind = kind, .reg = 0, .n = kind == NVN_RB_TEXA ? 4 : 0}; }
    o->sh[1]->rf.bindless = flag == 1; o->sh[1]->rf.dyn = flag == 2;
    g_pkeep[g_npkeep++] = o; serial_put(p->serial, o); return p;
}
// Index chain c as one submission, then decide the pass that ends at op `at` with attachment a: 2 redundant, else the reason it is needed (sd_need's why)
static int decide(chain *c, const uint8_t *at, const tex_t *a) {
    memset(&R, 0, sizeof R); S.prog = S.cprog = NULL; memset(S.tex, 0, sizeof S.tex); memset(S.img, 0, sizeof S.img);
    uint64_t h = (uint64_t)c->p; mtl_sub_index(&h, 1);
    if (!g_sdx_ok) return -1;
    uint32_t seq = 0; while (seq < g_sdx_nop && g_sdx_op[seq] != at) seq++;
    if (seq == g_sdx_nop) return -2;
    g_exec_cur = at; g_exec_seq = seq + 1;
    g_nsd = 1; memset(g_sd, 0, sizeof g_sd); g_sd[0].ser = a->serial; g_sd[0].idx = 0;
    uint8_t st[SD_ATT_MAX]; if (!sdx_decide(st)) return -3;
    g_nsd = 0; return st[0] == 2 ? 2 : st[0] >> 2;
}
int main(void) { @autoreleasepool {
    setenv("DM_NVN_PSO_MTL4", "0", 1);
    mtl_init(); g_dev = MTLCreateSystemDefaultDevice(); if (!g_dev) { printf("t_sdx_bindless: no Metal device, skipped\n"); return 0; }
    EXPECT("store lookahead on by default (DM_NVN_TBDR unset)", 1, sdx_on());
    prog_t *plain = prog(0, 0), *texu = prog(NVN_RB_TEXU, 1), *gmem = prog(NVN_RB_GMEM, 0), *texp = prog(NVN_RB_TEXP, 0), *texa = prog(NVN_RB_TEXA, 0), *slot = prog(NVN_RB_TEX, 0), *flagged = prog(0, 1);
    tex_t A = tex(0), B = tex(1), Aview = tex(0), C = tex(2); int idA = reg(&A), idAv = reg(&Aview), idC = reg(&C);
    // pass A (draw) -> pass B with <prog> drawing -> pass A cleared in full: the store of the first pass is redundant only when nothing between reads A
    struct { const char *name; prog_t *p; int bind_slot, bind_id, want; } cs[] = {
        {"plain draw between: A's store is redundant", plain, -1, 0, 2},
        {"A bound to a texture slot the shader samples: needed (a draw reads it)", slot, 0, 0, 1},
        {"another descriptor of A's storage sampled: needed (alias read)", slot, 0, 1, 1},
        {"an unrelated texture sampled: redundant", slot, 0, 2, 2},
        {"a handle in a uniform buffer (TEXU): needed (bindless reader)", texu, -1, 0, 7},
        {"a shader flagged bindless with no TEXU binding: needed (bindless reader)", flagged, -1, 0, 7},
        {"raw global memory (GMEM): needed (bindless reader)", gmem, -1, 0, 7},
        {"a texture pool array (TEXP): needed (bindless reader)", texp, -1, 0, 7},
        {"a c2 slot array (TEXA) with A on a slot: needed (every slot counts)", texa, 5, 0, 1},
        {"a c2 slot array (TEXA) with an unrelated texture on a slot: redundant", texa, 5, 2, 2},
    };
    for (unsigned i = 0; i < sizeof cs / sizeof *cs; i++) {
        chain c = chain_new(); bind_prog(&c, plain); set_rt(&c, &A); const uint8_t *last = drw(&c);
        set_rt(&c, &B); if (cs[i].bind_slot >= 0) bind_tex(&c, cs[i].bind_slot, cs[i].bind_id == 0 ? idA : cs[i].bind_id == 1 ? idAv : idC); bind_prog(&c, cs[i].p); drw(&c);
        set_rt(&c, &A); clear(&c); drw(&c); end(&c);
        EXPECT(cs[i].name, cs[i].want, decide(&c, last, &A));
    }
    { chain c = chain_new(); bind_prog(&c, plain); set_rt(&c, &A); const uint8_t *last = drw(&c); set_rt(&c, &A); clear(&c); drw(&c); bind_prog(&c, texu); set_rt(&c, &B); drw(&c); end(&c);
      EXPECT("a bindless reader after A is cleared: redundant (the clear comes first)", 2, decide(&c, last, &A)); }
    { chain c = chain_new(); bind_prog(&c, plain); set_rt(&c, &A); const uint8_t *last = drw(&c); set_rt(&c, &B); bind_prog(&c, texu); drw(&c); end(&c);
      EXPECT("a bindless reader and no later touch of A: needed", 7, decide(&c, last, &A)); }
    { chain c = chain_new(); set_rt(&c, &A); const uint8_t *last = drw(&c); set_rt(&c, &B); drw(&c); set_rt(&c, &A); clear(&c); end(&c);
      EXPECT("a draw with no program bound: needed (it may read anything)", 7, decide(&c, last, &A)); }
    printf("t_sdx_bindless: %d checks, %d failed\n", count, fail);
    return fail != 0;
} }
