// NXForge: included by nvn_mtl.m just before present_encode_m4 (it shares that file's statics, fx_state among them). See UPSTREAM.md, Thin fork.
// Pixel art (front.h mtl_present_pixel; the Mac sidebar's Graphics page and the settings window, or DM_PIXEL_ART=off|sharp|smooth|auto): crisp, even pixels for 2D games.
//   - While it is on, the present uses sharp bilinear scaling (present.metal fs_pixel) in place of the plain stretch, and leaves out what blurs or shifts pixel art: MetalFX,
//     FXAA, frame interpolation and EDR highlights (each keeps its saved choice and comes back when pixel art is off). The CRT filters still apply, on the art's own rows.
//   - The art's own grid: a 2D game draws its art small (320x180, 400x240) and enlarges it into its 720p or 1080p picture itself, sometimes unevenly (400 into 1280 is blocks
//     of 3 and 4 texels). Every PX_EVERY presents the window's present marks where the colour changes along PX_NR rows and columns (pixel_art.metal px_edges); a shared
//     texture read back PX_EVERY presents later gives the counts, and pixel_grid.h finds the scale and offset whose seams take them. While a grid holds, the present first takes
//     the art back to its own size (px_restore: one texel from each art pixel's centre), so every art pixel comes out the same size on screen, Pixel-perfect picture size
//     counts the art's pixels (a 180-row game fills 1800 rows of a 1898-row screen at 10x, not 1440 at 2x of 720p), and the CRT filters' auto line size is one art row.
//     A picture with no grid (a menu drawn at full resolution, a game that scales smoothly) is drawn as it is, sharply scaled. DM_PIXEL_GRID=WxH fixes the art's size, off
//     never restores, auto (the default) finds it.
//   - Smooth edges: the restored art goes through MMPX (pixel_art.metal px_mmpx) at 2x, and again at 4x where an art pixel spans 6 screen pixels or more, before the sharp scaling:
//     diagonals and curves get stepped corners in the art's own colours instead of square blocks.
//   - Auto: off until the finder has seen a grid at PX_LATCH checks in a row (about a second of a 2D game), then sharp for the rest of the run.
// Screenshots and recordings get the same picture (their fx_state has its own textures). The finder runs on the window's present only.
#include "pixel_grid.h"
enum { PX_NR = 96, PX_EVERY = 6, PX_LATCH = 8 };
static const char *const g_px_name[DM_PIXEL_N] = {"off", "sharp", "smooth", "auto"};
static _Atomic int g_px = -1;      // the mode chosen (DM_PIXEL_*); -1: not read yet
static _Atomic int g_px_found;     // auto: pixel art seen steadily this run
typedef struct { int ok, cw, ch, streak; pxg_axis x, y; } px_grid;
static px_grid g_pxg;              // the grid now, for the picture of cw x ch (under g_px_mu)
static pthread_mutex_t g_px_mu = PTHREAD_MUTEX_INITIALIZER;
static void px_env(void) {
    if (g_px >= 0) return;
    const char *e = getenv("DM_PIXEL_ART"); int want = DM_PIXEL_OFF;
    if (e && *e) {
        int k = -1;
        for (int i = 0; i < DM_PIXEL_N; i++) if (!strcasecmp(e, g_px_name[i])) k = i;
        if (!strcasecmp(e, "on") || !strcmp(e, "1")) k = DM_PIXEL_SHARP; else if (!strcmp(e, "0")) k = DM_PIXEL_OFF;
        if (k < 0) MLOG("[RED] DM_PIXEL_ART=%s: off, sharp, smooth or auto; keeping off", e); else want = k;
    }
    int none = -1; if (atomic_compare_exchange_strong(&g_px, &none, want) && want) MLOG("present: pixel art %s (DM_PIXEL_ART)", g_px_name[want]);
}
int mtl_present_pixel(void) { px_env(); return g_px; }
void mtl_present_pixel_set(int mode) {
    px_env(); if (mode < 0 || mode >= DM_PIXEL_N) mode = DM_PIXEL_OFF;
    if (atomic_exchange(&g_px, mode) != mode) MLOG("present: pixel art %s", g_px_name[mode]);
}
int mtl_present_pixel_active(void) { int m = mtl_present_pixel(); return m == DM_PIXEL_AUTO ? (g_px_found ? DM_PIXEL_SHARP : DM_PIXEL_OFF) : m; }
static int nxf_px_active(void) { return mtl_present_pixel_active() != DM_PIXEL_OFF; }
// DM_PIXEL_GRID: -1 off, 0 auto, else the art's width and height
static int g_px_fix_w, g_px_fix_h;
static void px_grid_env_read(void) {
    const char *e = getenv("DM_PIXEL_GRID"); int w = 0, h = 0; char x;
    if (!e || !*e || !strcasecmp(e, "auto")) return;
    if (!strcasecmp(e, "off") || !strcmp(e, "0")) { g_px_fix_w = -1; MLOG("present: pixel art's own grid not looked for (DM_PIXEL_GRID=off)"); return; }
    if (sscanf(e, "%d%c%d", &w, &x, &h) == 3 && (x == 'x' || x == 'X') && w >= 16 && h >= 16 && w <= 4096 && h <= 4096) { g_px_fix_w = w; g_px_fix_h = h; MLOG("present: pixel art drawn at %dx%d (DM_PIXEL_GRID)", w, h); return; }
    MLOG("[RED] DM_PIXEL_GRID=%s: auto, off or <width>x<height> (320x180); looking for it", e);
}
static void px_grid_env(void) { static pthread_once_t once = PTHREAD_ONCE_INIT; pthread_once(&once, px_grid_env_read); }
int mtl_present_pixel_grid(float *art_w, float *art_h, float *scale) {
    pthread_mutex_lock(&g_px_mu); px_grid g = g_pxg; pthread_mutex_unlock(&g_px_mu);
    if (!g.ok) return 0;
    if (art_w) *art_w = (float)(g.cw / g.x.s);
    if (art_h) *art_h = (float)(g.ch / g.y.s);
    if (scale) *scale = (float)g.y.s;
    return 1;
}
// The art's size over the picture while pixel art is on and a grid holds (Pixel-perfect picture size counts these pixels; present_filters.inc nxf_present_scale_fit)
static int nxf_px_art_size(double *w, double *h) {
    if (!nxf_px_active()) return 0;
    pthread_mutex_lock(&g_px_mu); px_grid g = g_pxg; pthread_mutex_unlock(&g_px_mu);
    if (!g.ok) return 0;
    *w = g.cw / g.x.s; *h = g.ch / g.y.s; return 1;
}
// A finished count (a queue of its own, off the present thread): the grid follows it. hx: changes along rows over cw texels, hy: down columns over ch texels
static void px_take(uint32_t *hx, int cw, uint32_t *hy, int ch) {
    pthread_mutex_lock(&g_px_mu); px_grid was = g_pxg; pthread_mutex_unlock(&g_px_mu);
    int had = was.ok && was.cw == cw && was.ch == ch;
    pxg_axis ax, ay; int fx = pxg_find(hx, cw, had ? &was.x : NULL, &ax), fy = pxg_find(hy, ch, had ? &was.y : NULL, &ay);
    free(hx); free(hy);
    if (fx < 0 && fy < 0) return;   // too little on screen to tell (a fade to black): as it was
    px_grid g = was;
    if (fx == 1 && fy == 1 && ax.s / ay.s > 0.5 && ax.s / ay.s < 2) { g.ok = 1; g.cw = cw; g.ch = ch; g.x = ax; g.y = ay; g.streak++; }
    else if (fx == 0 || fy == 0) { g.ok = 0; g.streak = 0; }
    else return;   // one axis found, the other too little to tell
    pthread_mutex_lock(&g_px_mu); g_pxg = g; pthread_mutex_unlock(&g_px_mu);
    if (g.ok && (!had || fabs(g.x.s - was.x.s) > 1e-6 || fabs(g.y.s - was.y.s) > 1e-6))
        MLOG("present: pixel art drawn at %.0fx%.0f, %.2f x %.2f texels per art pixel (offset %.1f, %.1f) in the %dx%d picture", cw / ax.s, ch / ay.s, ax.s, ay.s, ax.o, ay.o, cw, ch);
    else if (!g.ok && was.ok) MLOG("present: no pixel-art grid in the picture now; drawing it as it is");
    if (g.ok && g.streak >= PX_LATCH && !g_px_found && mtl_present_pixel() == DM_PIXEL_AUTO) { g_px_found = 1; MLOG("present: pixel art found; auto turns sharp pixels on for this run"); }
}
// Pipelines (the library once; the passes into the game picture's format when it changes) and the argument table; 0 when they did not build
static id<MTL4ArgumentTable> g_px_args;
static id<MTLRenderPipelineState> g_px_edges, g_px_restore, g_px_mmpx; static MTLPixelFormat g_px_pf;
static id<MTLRenderPipelineState> px_pso(id<MTLLibrary> lib, NSString *fs, MTLPixelFormat pf) {
    MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new]; NSError *e = nil;
    pd.vertexFunction = [lib newFunctionWithName:@"px_vs"]; pd.fragmentFunction = [lib newFunctionWithName:fs]; pd.colorAttachments[0].pixelFormat = pf;
    id<MTLRenderPipelineState> p = pd.fragmentFunction ? [g_dev newRenderPipelineStateWithDescriptor:pd error:&e] : nil;
    if (!p) NXF_RED_ONCE(4, "present: pixel art's %s pipeline failed (%s); drawing the picture as it is", fs.UTF8String, e ? e.localizedDescription.UTF8String : "no function");
    return p;
}
static int px_ready(MTLPixelFormat pf) {
    static id<MTLLibrary> lib; static int failed;
    if (failed) return 0;
    if (!lib) {
        NSError *e = nil; lib = host_lib("pixel_art", &e);
        MTL4ArgumentTableDescriptor *ad = [MTL4ArgumentTableDescriptor new]; ad.maxTextureBindCount = 1; ad.maxBufferBindCount = 1;
        g_px_args = lib ? [g_dev newArgumentTableWithDescriptor:ad error:&e] : nil;
        g_px_edges = lib ? px_pso(lib, @"px_edges", MTLPixelFormatR8Unorm) : nil;
        if (!lib || !g_px_args || !g_px_edges) { failed = 1; NXF_RED_ONCE(5, "present: pixel art's shaders did not build (%s); sharp scaling only", e ? e.localizedDescription.UTF8String : "a pipeline failed"); return 0; }
    }
    if (g_px_pf != pf || !g_px_restore || !g_px_mmpx) {
        g_px_restore = px_pso(lib, @"px_restore", pf); g_px_mmpx = px_pso(lib, @"px_mmpx", pf); g_px_pf = pf;
        if (!g_px_restore || !g_px_mmpx) { g_px_restore = nil; return 0; }
    }
    return 1;
}
// One pass: dst's top-left w x h drawn by pso from src, with the constants at buf + off (none: off < 0)
static void px_pass(id<MTL4CommandBuffer> cb, id<MTLTexture> dst, NSUInteger w, NSUInteger h, id<MTLRenderPipelineState> pso, id<MTLTexture> src, id<MTLBuffer> buf, long off) {
    MTL4RenderPassDescriptor *rp = [MTL4RenderPassDescriptor new];
    rp.colorAttachments[0].texture = dst; rp.colorAttachments[0].loadAction = MTLLoadActionDontCare; rp.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTL4RenderCommandEncoder> en = [cb renderCommandEncoderWithDescriptor:rp];
    if (!en) { NXF_RED_ONCE(6, "present: pixel art: no render encoder"); return; }
    [en barrierAfterQueueStages:MTLStageAll beforeStages:MTLStageAll visibilityOptions:resource_vis()];   // after the frame's work and the pass before
    [en setArgumentTable:g_px_args atStages:MTLRenderStageFragment];
    [g_px_args setTexture:src.gpuResourceID atIndex:0];
    if (off >= 0) [g_px_args setAddress:buf.gpuAddress + (uint64_t)off atIndex:0];
    [en setViewport:(MTLViewport){0, 0, (double)w, (double)h, 0, 1}]; [en setRenderPipelineState:pso];
    [en drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    m4_end(en);
}
// fx->px[i] as a w x h texture of format pf; a new size waits for the presents still reading the old one (remake_wait, the window's), as aa_encode does
static id<MTLTexture> px_tex(fx_state *fx, int i, MTLPixelFormat pf, NSUInteger w, NSUInteger h, int remake_wait) {
    id<MTLTexture> t = fx->px[i];
    if (t && t.width == w && t.height == h && t.pixelFormat == pf) return t;
    if (remake_wait && t) { pthread_mutex_lock(&g_pq_mu); while (g_pq_inflight) pthread_cond_wait(&g_pq_cv, &g_pq_mu); pthread_mutex_unlock(&g_pq_mu); }
    res_remove(t); fx->px[i] = nil;
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pf width:MAX(w, 1) height:MAX(h, 1) mipmapped:NO];
    td.storageMode = MTLStorageModePrivate; td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    t = [g_dev newTextureWithDescriptor:td];
    if (!t) { NXF_RED_ONCE(7, "present: pixel art: cannot create a %lux%lu texture; drawing the picture as it is", (unsigned long)w, (unsigned long)h); return nil; }
    t.label = i ? @"pixel art enlarged" : @"pixel art"; res_add(t); res_commit(); fx->px[i] = t;
    return t;
}
// The constants (pixel_art.metal PxC), at uvb + PX_C_OFF: after the present pass's crop, filter, anti-aliasing and EDR constants (28 floats)
typedef struct { int32_t crop[4], nr[4]; float ax[4], ay[4]; } px_consts;
#define PX_C_OFF (28 * sizeof(float))
// The finder's side of the window's present: every PX_EVERY presents, read the count drawn PX_EVERY presents ago and draw this picture's
static id<MTLTexture> g_px_mask[2]; static int g_px_mask_w[2], g_px_mask_cw[2], g_px_mask_ch[2]; static uint64_t g_px_n;
static void px_detect(id<MTL4CommandBuffer> cb, id<MTLTexture> tex, const NSUInteger r[4], id<MTLBuffer> uvb) {
    int cw = (int)r[2], ch = (int)r[3];
    if (g_px_fix_w) {   // DM_PIXEL_GRID: the size given, or no grid
        px_grid g = {0};
        if (g_px_fix_w > 0) { g.ok = 1; g.cw = cw; g.ch = ch; g.streak = PX_LATCH; g.x.s = (double)cw / g_px_fix_w; g.y.s = (double)ch / g_px_fix_h; pxg_fill(&g.x, cw); pxg_fill(&g.y, ch); }
        pthread_mutex_lock(&g_px_mu); g_pxg = g; pthread_mutex_unlock(&g_px_mu);
        if (g.ok && !g_px_found) g_px_found = 1;
        return;
    }
    if (++g_px_n % PX_EVERY || cw < 16 || ch < 16) return;
    int k = (int)(g_px_n / PX_EVERY) & 1, j = k ^ 1;
    static dispatch_queue_t q; if (!q) q = dispatch_queue_create("nxforge.pixel-grid", DISPATCH_QUEUE_SERIAL);
    if (g_px_mask_cw[j]) {   // drawn PX_EVERY presents ago, long done
        int w = g_px_mask_w[j], mcw = g_px_mask_cw[j], mch = g_px_mask_ch[j];
        uint8_t *m = malloc((size_t)w * 2 * PX_NR); uint32_t *hx = calloc((size_t)mcw, 4), *hy = calloc((size_t)mch, 4);
        if (m && hx && hy) {
            [g_px_mask[j] getBytes:m bytesPerRow:(NSUInteger)w fromRegion:MTLRegionMake2D(0, 0, (NSUInteger)w, 2 * PX_NR) mipmapLevel:0];
            for (int row = 0; row < PX_NR; row++) { const uint8_t *p = m + (size_t)row * w; for (int x = 0; x < mcw; x++) hx[x] += p[x] > 127; }
            for (int row = PX_NR; row < 2 * PX_NR; row++) { const uint8_t *p = m + (size_t)row * w; for (int y = 0; y < mch; y++) hy[y] += p[y] > 127; }
            dispatch_async(q, ^{ px_take(hx, mcw, hy, mch); });
        } else { free(hx); free(hy); }
        free(m); g_px_mask_cw[j] = 0;
    }
    int w = cw > ch ? cw : ch;
    if (!g_px_mask[k] || g_px_mask_w[k] < w) {
        res_remove(g_px_mask[k]); g_px_mask[k] = nil;   // only this present draws into it, and the one before was read: no present still uses it
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm width:(NSUInteger)w height:2 * PX_NR mipmapped:NO];
        td.storageMode = MTLStorageModeShared; td.usage = MTLTextureUsageRenderTarget;
        g_px_mask[k] = [g_dev newTextureWithDescriptor:td];
        if (!g_px_mask[k]) { NXF_RED_ONCE(8, "present: pixel art: cannot create the grid finder's texture"); return; }
        g_px_mask[k].label = @"pixel art grid finder"; res_add(g_px_mask[k]); res_commit(); g_px_mask_w[k] = w;
    }
    px_pass(cb, g_px_mask[k], (NSUInteger)w, 2 * PX_NR, g_px_edges, tex, uvb, (long)PX_C_OFF);
    g_px_mask_cw[k] = cw; g_px_mask_ch[k] = ch;
}
// The present's pixel-art passes (present_encode_m4): tex's crop r, shown in vp. Returns the texture the present pass draws in place of tex, with fr its crop in that
// texture's texels (fractional: the picture's edges can cut through an art pixel), or nil (tex as it is). window: the window's present, which also runs the grid finder.
// t_px_rows (present_filters.inc) becomes the texture rows per art row, for the CRT filters' auto line size
static id<MTLTexture> px_encode(fx_state *fx, id<MTL4CommandBuffer> cb, id<MTLTexture> tex, const NSUInteger r[4], MTLViewport vp, id<MTLBuffer> uvb, int window, double fr[4]) {
    if (!px_ready(tex.pixelFormat)) return nil;
    px_consts *c = (px_consts *)((uint8_t *)uvb.contents + PX_C_OFF);
    memset(c, 0, sizeof *c);
    c->crop[0] = (int32_t)r[0]; c->crop[1] = (int32_t)r[1]; c->crop[2] = (int32_t)r[2]; c->crop[3] = (int32_t)r[3]; c->nr[0] = PX_NR;
    if (window) px_detect(cb, tex, r, uvb);
    int act = mtl_present_pixel_active();
    if (act == DM_PIXEL_OFF || g_px_fix_w < 0) return nil;
    pthread_mutex_lock(&g_px_mu); px_grid g = g_pxg; pthread_mutex_unlock(&g_px_mu);
    if (!g.ok || g.cw != (int)r[2] || g.ch != (int)r[3] || g.x.n < 2 || g.y.n < 2) return nil;
    c->ax[0] = (float)g.x.o; c->ax[1] = (float)g.x.s; c->ax[2] = (float)g.x.a0;
    c->ay[0] = (float)g.y.o; c->ay[1] = (float)g.y.s; c->ay[2] = (float)g.y.a0;
    NSUInteger nx = (NSUInteger)g.x.n, ny = (NSUInteger)g.y.n; int m = 1;
    id<MTLTexture> out = px_tex(fx, 0, tex.pixelFormat, nx, ny, window);
    if (!out) return nil;
    px_pass(cb, out, nx, ny, g_px_restore, tex, uvb, (long)PX_C_OFF);
    if (act == DM_PIXEL_SMOOTH) {
        double screen = fmin(vp.width * g.x.s / r[2], vp.height * g.y.s / r[3]);   // screen pixels per art pixel
        for (int i = 1; i <= (screen >= 6 ? 2 : 1); i++) {
            id<MTLTexture> big = px_tex(fx, i, tex.pixelFormat, out.width * 2, out.height * 2, window);
            if (!big) break;
            px_pass(cb, big, big.width, big.height, g_px_mmpx, out, nil, -1);
            out = big; m *= 2;
        }
    }
    fr[0] = m * (-g.x.o / g.x.s - g.x.a0); fr[1] = m * (-g.y.o / g.y.s - g.y.a0); fr[2] = m * r[2] / g.x.s; fr[3] = m * r[3] / g.y.s;
    t_px_rows = m;
    return out;
}
static id<MTLTexture> nxf_px_encode(fx_state *fx, id<MTL4CommandBuffer> cb, id<MTLTexture> tex, const NSUInteger r[4], MTLViewport vp, id<MTLBuffer> uvb, int window, double fr[4]) {
    static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;   // one argument table: the window's present and a screenshot's take turns
    t_px_rows = 0;
    if (mtl_present_pixel() == DM_PIXEL_OFF || !uvb || uvb.length < PX_C_OFF + sizeof(px_consts)) return nil;
    px_grid_env();
    if (g_px_fix_w < 0 && !window) return nil;   // DM_PIXEL_GRID=off: nothing to restore
    pthread_mutex_lock(&mu);
    id<MTLTexture> out = px_encode(fx, cb, tex, r, vp, uvb, window, fr);
    pthread_mutex_unlock(&mu);
    return out;
}
