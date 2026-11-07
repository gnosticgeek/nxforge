// NXForge: included by nvn_mtl.m at the place this code stood (it shares that file's statics). Kept out of
// upstream's file so a merge of nxnative meets one #include line. See UPSTREAM.md, Thin fork.
// Present filter (front.h; the Mac's Graphics menu and panel, front_mac.m; DM_PRESENT_FILTER=sharpen|pixel|crt with DM_PRESENT_FILTER_STRENGTH=0 to 1, 0.5 by default): the present pass has
// one fragment function per filter and takes the one set at each present, so a change shows on the next frame and costs no pipeline build then (all are built with the bilinear one).
// Off is the bilinear stretch as before. Sharpen: contrast-adaptive (after AMD's FidelityFX CAS), a cross of the source texels around each sample, weighted less where the neighbourhood
// already has contrast, so edges sharpen without ringing. Pixel: sharp bilinear, each source texel a block of one colour and only the seam between two blocks blended over one output pixel,
// so pixel art at a non-integer scale (720p into a 1898-pixel-high fullscreen) neither blurs nor shimmers. CRT: scanlines (about 240 lines, or a set height in source rows: mtl_present_scanline)
// and an RGB aperture mask on the output columns, brightened by part of what they take away; the scanlines fade out where a line spans under 2.5 output pixels. CRT-Lottes: Timothy Lottes'
// public-domain CRT shader (beams, bloom and a shadow mask on cells of the scanline height). LCD Grid: each cell a square with a dark gap and RGB thirds, like a handheld's screen. The filters work on the stored bytes as the bilinear stretch does (present_raw_src); the whole-window screenshot (grab_present) shows the filter too,
// the raw swapchain screenshots (shot: DM_NVN_SHOT, DM_NVN_SHOT_UI) do not
static const char *const g_pfx_name[DM_PFX_N] = {"off", "sharpen", "pixel", "crt", "lottes", "lcd"};
static id<MTLRenderPipelineState> g_pfx_pso[DM_PFX_N];   // [0] is g_blit_pso
static _Atomic int g_pfx = -1; static _Atomic float g_pfx_k = 0.5f;
// The CRT filter's scanline height in source rows (DM_PRESENT_SCANLINE=1 to 8; 0 = auto, -1 = not read yet). Auto gives about 240 lines whatever the frame's size: a pixel-art game
// draws its art at a low resolution and enlarges it into a 720p or 1080p frame itself (Bloodstained: Curse of the Moon hands over 1280x720), so a line per frame row was a stripe of
// one or two screen pixels, too fine to see, and the filter only darkened the picture and brightened it again
static _Atomic int g_pfx_rows = -1;
int mtl_present_scanline(void) {
    int r = g_pfx_rows;
    if (r >= 0) return r;
    const char *e = getenv("DM_PRESENT_SCANLINE"); int want = 0;
    if (e && *e && strcasecmp(e, "auto")) { char *end; long v = strtol(e, &end, 10); if (end != e && !*end && v >= 0 && v <= 8) want = (int)v; else MLOG("[RED] DM_PRESENT_SCANLINE=%s: must be auto or 0 to 8; using auto", e); }
    int none = -1; atomic_compare_exchange_strong(&g_pfx_rows, &none, want);
    return g_pfx_rows;
}
void mtl_present_scanline_set(int rows) {
    rows = rows < 0 ? 0 : rows > 8 ? 8 : rows;
    if (g_pfx_rows != rows) { g_pfx_rows = rows; if (rows) MLOG("present: CRT scanlines every %d source rows", rows); else MLOG("present: CRT scanlines auto (about 240 lines)"); }
}
static int pfx_mode(void) {   // any thread: the filter now, read from the environment the first time (a front end's mtl_present_filter_set before that wins)
    int m = g_pfx;
    if (m >= 0) return m;
    const char *e = getenv("DM_PRESENT_FILTER"), *k = getenv("DM_PRESENT_FILTER_STRENGTH"); int want = 0;
    if (e && *e) { for (int i = 0; i < DM_PFX_N; i++) if (!strcasecmp(e, g_pfx_name[i])) want = i;
        if (!want && strcasecmp(e, "off") && strcmp(e, "0")) MLOG("[RED] DM_PRESENT_FILTER=%s: not off, sharpen, pixel, crt, lottes or lcd; presenting without a filter", e); }
    if (k && *k) { char *end; float v = strtof(k, &end); if (end != k && !*end && v >= 0 && v <= 1) g_pfx_k = v; else MLOG("[RED] DM_PRESENT_FILTER_STRENGTH=%s: must be 0 to 1; keeping %.2f", k, (double)g_pfx_k); }
    int none = -1;
    if (atomic_compare_exchange_strong(&g_pfx, &none, want) && want) MLOG("present: filter %s, strength %.2f (DM_PRESENT_FILTER)", g_pfx_name[want], (double)g_pfx_k);
    return g_pfx;
}
int mtl_present_filter(float *strength) { int m = pfx_mode(); if (strength) *strength = g_pfx_k; return m; }
void mtl_present_filter_set(int mode, float strength) {
    if (mode < 0 || mode >= DM_PFX_N) mode = 0;
    strength = strength < 0 ? 0 : strength > 1 ? 1 : strength;
    int was = g_pfx; float k0 = g_pfx_k; g_pfx_k = strength; g_pfx = mode;
    if (was != mode || fabsf(k0 - strength) > 0.001f) MLOG("present: filter %s, strength %.2f", g_pfx_name[mode], strength);
}
// Anisotropic filtering floor (front.h mtl_aniso_set; DM_ANISO=2|4|8|16, 0 or unset = the game's own): every filtered, mipmapped sampler the game makes (NVN, GL and Vulkan alike)
// samples at least that many taps along a surface seen at an angle; a game asking for more keeps its own. Samplers without mips, with a nearest minifying filter, depth comparison or
// a min / max reduction keep the game's value: they are lookup tables, pixel art, shadow maps and depth pyramids, where extra taps change the result rather than sharpen it.
// The floor is taken when the first sampler is made (Metal sampler states are immutable and the game holds its own), so a change after that applies at the next launch
static _Atomic int g_aniso = -1;   // -1: not read yet
static _Atomic int g_aniso_latched;
static int aniso_norm(int n) { return n >= 16 ? 16 : n >= 8 ? 8 : n >= 4 ? 4 : n >= 2 ? 2 : 0; }
int mtl_aniso(void) {
    int a = g_aniso;
    if (a >= 0) return a;
    const char *e = getenv("DM_ANISO"); int want = 0;
    if (e && *e) { char *end; long v = strtol(e, &end, 10);
        if (end != e && (!*end || !strcasecmp(end, "x")) && (v == 0 || v == 1 || v == 2 || v == 4 || v == 8 || v == 16)) want = aniso_norm((int)v);
        else MLOG("[RED] DM_ANISO=%s: not 0, 2, 4, 8 or 16; keeping the game's anisotropic filtering", e); }
    int none = -1;
    if (atomic_compare_exchange_strong(&g_aniso, &none, want) && want) MLOG("samplers: anisotropic filtering at least %dx (DM_ANISO)", want);
    return g_aniso;
}
void mtl_aniso_set(int n) {
    n = aniso_norm(n);
    if (g_aniso_latched) { if (n != g_aniso) MLOG("samplers: anisotropic filtering %dx applies at the next launch (keeping %dx)", n, g_aniso); return; }
    if (g_aniso != n) { if (n) MLOG("samplers: anisotropic filtering at least %dx", n); else MLOG("samplers: the game's own anisotropic filtering"); }
    g_aniso = n;
}
unsigned mtl_aniso_pick(float game, int eligible) {
    unsigned g = !(game >= 1) ? 1 : game > 16 ? 16 : (unsigned)game;   // NaN and below 1 → 1
    if (!g_aniso_latched) { mtl_aniso(); g_aniso_latched = 1; }
    unsigned f = (unsigned)g_aniso;
    return eligible && f > g ? f : g;
}
// The filter's parameters (the fragment functions' Crop.fx): strength, the output pixels per source texel on x and y (the viewport over the crop), which sharp bilinear needs,
// and the CRT filter's scanline height in source rows
static void pfx_params(float fx[4], const MTLViewport *vp, NSUInteger cw, NSUInteger ch) {
    int rows = mtl_present_scanline(); if (!rows) rows = (int)fmax(1, floor(ch / 240.0 + 0.5));
    fx[0] = g_pfx_k; fx[1] = cw ? (float)(vp->width / cw) : 1; fx[2] = ch ? (float)(vp->height / ch) : 1; fx[3] = (float)rows;
}
