// NXForge: pixel art (nxforge/pixel_art.inc, pixel_grid.h, msl/pixel_art.metal). The grid finder on counts made up here (even, uneven and bordered enlargements, chunky art,
// noise, a flat screen); then on the GPU: the finder on a 320x180 picture enlarged 6x into 1920x1080, the art taken back to its own grid and presented at 2x exactly, an uneven
// 3.2x enlargement coming out even, MMPX keeping the art's colours on a diagonal, and auto turning on by itself
#include "../nvn/nvn_mtl.m"
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t *g_mod; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int checks, failed;
#define CHECK(name, ok) do { int pass = !!(ok); checks++; failed += !pass; printf("%s: %s\n", name, pass ? "PASS" : "FAIL"); } while (0)

// ---- the finder on made-up counts: art of aw pixels enlarged into len texels at scale s from offset o (outside the art: one more colour), changes counted over 96 lines
static uint32_t g_h[4096];
static void counts(int len, int aw, double s, double o, int chunk, int noise) {
    memset(g_h, 0, sizeof g_h); srand(7);
    static int art[4096];
    for (int line = 0; line < 96; line++) {
        for (int i = 0; i < 4096; i++) art[i] = i % chunk ? art[i - 1] : rand() % 4;
        int prev = -1;
        for (int x = 0; x < len; x++) {
            int k = (int)floor((x + 0.5 - o) / s), c = noise ? rand() % 4 : k < 0 || k >= aw ? 9 : art[k];
            if (x && c != prev) g_h[x - 1]++;
            prev = c;
        }
    }
}
static void finder_cases(void) {
    pxg_axis a; char name[160]; int r;
    counts(1920, 320, 6, 0, 1, 0); r = pxg_find(g_h, 1920, NULL, &a);
    snprintf(name, sizeof name, "320 art pixels in 1920: scale 6 (%.3f), 320 across (%d)", a.s, a.n); CHECK(name, r == 1 && fabs(a.s - 6) < 1e-9 && a.n == 320);
    counts(1280, 400, 3.2, 0, 1, 0); r = pxg_find(g_h, 1280, NULL, &a);
    snprintf(name, sizeof name, "400 in 1280, blocks of 3 and 4: scale 3.2 (%.3f)", a.s); CHECK(name, r == 1 && fabs(a.s - 3.2) < 1e-9 && a.n == 400);
    counts(1280, 400, 3, 40, 1, 0); r = pxg_find(g_h, 1280, NULL, &a);
    snprintf(name, sizeof name, "3x with a 40-texel border: scale 3 offset 1 (%.2f, %.2f)", a.s, a.o); CHECK(name, r == 1 && fabs(a.s - 3) < 1e-9 && fabs(a.o - 1) < 1e-9);
    counts(1920, 320, 6, 0, 2, 0); r = pxg_find(g_h, 1920, NULL, &a);
    snprintf(name, sizeof name, "art in 2x2 blocks only: the coarser grid, 12 (%.2f)", a.s); CHECK(name, r == 1 && fabs(a.s - 12) < 1e-9);
    pxg_axis keep = {6, 0, 0, 320, 1}; r = pxg_find(g_h, 1920, &keep, &a);
    snprintf(name, sizeof name, "  but the grid in use (6) is kept (%.2f)", a.s); CHECK(name, r == 1 && fabs(a.s - 6) < 1e-9);
    counts(1920, 0, 1, 0, 1, 1); r = pxg_find(g_h, 1920, NULL, &a);
    CHECK("a picture drawn at full resolution (noise): no grid", r == 0);
    memset(g_h, 0, sizeof g_h); g_h[100] = 10; r = pxg_find(g_h, 1920, NULL, &a);
    CHECK("a nearly flat screen: too little to tell", r == -1);
}

// ---- on the GPU
enum { AW = 320, AH = 180, S = 6, W = AW * S, H = AH * S };
static uint8_t g_art[AH][AW][4];
static id<MTLTexture> picture(int w, int h, double sx, double sy) {   // the art enlarged into w x h by repeating pixels at scale sx, sy (nearest, as a game does)
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:w height:h mipmapped:NO];
    d.storageMode = MTLStorageModeShared; d.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> t = [g_dev newTextureWithDescriptor:d]; uint8_t *p = malloc((size_t)w * h * 4);
    for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
        int ax = (int)floor((x + 0.5) / sx), ay = (int)floor((y + 0.5) / sy);
        memcpy(p + ((size_t)y * w + x) * 4, g_art[ay < AH ? ay : AH - 1][ax < AW ? ax : AW - 1], 4);
    }
    [t replaceRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0 withBytes:p bytesPerRow:w * 4]; free(p);
    res_add(t); res_commit(); return t;
}
static id<MTLTexture> target(int w, int h) {
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:w height:h mipmapped:NO];
    d.storageMode = MTLStorageModeShared; d.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    id<MTLTexture> t = [g_dev newTextureWithDescriptor:d]; res_add(t); res_commit(); return t;
}
static int window_present(id<MTLTexture> src, id<MTLTexture> out) {   // the window's present path (the finder runs there), waited for
    id<MTL4CommandAllocator> al = [g_dev newCommandAllocator]; id<MTL4CommandBuffer> cb = [g_dev newCommandBuffer]; id<MTLSharedEvent> ev = [g_dev newSharedEvent];
    [cb beginCommandBufferWithAllocator:al]; int kind = present_encode_m4(cb, src, out, NULL, g_present_uv[0], &g_fx_present); [cb endCommandBuffer];
    [g_q4 commit:&cb count:1]; [g_q4 signalEvent:ev value:1];
    return kind && [ev waitUntilSignaledValue:1 timeoutMS:10000];
}
// How many of out's pixels differ from the art enlarged k times (each art pixel a k x k block); out's size is the art's times k
static long art_mismatch(id<MTLTexture> out, int k) {
    int w = (int)out.width, h = (int)out.height; uint8_t *p = malloc((size_t)w * h * 4); long bad = 0;
    [out getBytes:p bytesPerRow:w * 4 fromRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0];
    for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) if (memcmp(p + ((size_t)y * w + x) * 4, g_art[y / k][x / k], 3)) bad++;
    free(p); return bad;
}
static void finder_settle(id<MTLTexture> src, id<MTLTexture> out, int presents) { for (int i = 0; i < presents; i++) window_present(src, out); usleep(300000); }
int main(void) { @autoreleasepool {
    alarm(120); setvbuf(stdout, NULL, _IONBF, 0);
    finder_cases();
    setenv("DM_PRESENT_UPSCALE", "metalfx", 1);   // MetalFX wanted: pixel art must leave it out
    mtl_init();
    mtl_present_layer(W, H);
    srand(11); for (int y = 0; y < AH; y++) for (int x = 0; x < AW; x++) { g_art[y][x][0] = (uint8_t)(rand() % 6 * 51); g_art[y][x][1] = (uint8_t)(rand() % 6 * 51); g_art[y][x][2] = (uint8_t)(rand() % 6 * 51); g_art[y][x][3] = 255; }
    id<MTLTexture> big = picture(W, H, S, S), out = target(AW * 2, AH * 2);
    char name[200]; float aw = 0, ah = 0, sc = 0;

    mtl_present_pixel_set(DM_PIXEL_AUTO);
    finder_settle(big, out, PX_EVERY * 3);
    CHECK("auto: off until the grid has held a while", mtl_present_pixel_active() == DM_PIXEL_OFF);
    int got = mtl_present_pixel_grid(&aw, &ah, &sc);
    snprintf(name, sizeof name, "the finder: art 320x180 at 6 texels per pixel (%d: %.1fx%.1f at %.2f)", got, aw, ah, sc); CHECK(name, got && fabsf(aw - AW) < 0.01f && fabsf(ah - AH) < 0.01f && fabsf(sc - S) < 0.01f);
    finder_settle(big, out, PX_EVERY * (PX_LATCH + 2));
    CHECK("auto turns sharp pixels on by itself", mtl_present_pixel_active() == DM_PIXEL_SHARP);
    CHECK("which pauses frame interpolation", !nxf_fi_wants_link());

    int kind = present_offscreen_wait(big, NULL, out);
    CHECK("no MetalFX while pixel art is on", kind == PRESENT_STANDARD);
    snprintf(name, sizeof name, "1920x1080 of 6x art shown at 640x360: the art at exactly 2x (%ld pixels off)", art_mismatch(out, 2)); CHECK(name, art_mismatch(out, 2) == 0);

    // An uneven enlargement: 320 into 1024 is 3.2 (blocks of 3 and 4); taken back to the art and shown at 2x, every art pixel is 2x2
    mtl_present_layer(1024, 576); id<MTLTexture> uneven = picture(1024, 576, 3.2, 3.2);
    finder_settle(uneven, out, PX_EVERY * 3);
    got = mtl_present_pixel_grid(&aw, &ah, &sc);
    snprintf(name, sizeof name, "3.2x found (%.2f)", sc); CHECK(name, got && fabsf(sc - 3.2f) < 0.01f);
    present_offscreen_wait(uneven, NULL, out);
    snprintf(name, sizeof name, "  and shown even, at exactly 2x (%ld pixels off)", art_mismatch(out, 2)); CHECK(name, art_mismatch(out, 2) == 0);

    // Off: the plain present (MetalFX again), and nothing taken back
    mtl_present_pixel_set(DM_PIXEL_OFF);
    CHECK("off: MetalFX again", present_offscreen_wait(uneven, NULL, out) == PRESENT_METALFX || !mtl_present_upscale());

    // MMPX: a one-pixel diagonal of one colour on another; Smooth edges at 2x keeps only the art's two colours and fills the stair's corners
    mtl_present_layer(W, H);
    for (int y = 0; y < AH; y++) for (int x = 0; x < AW; x++) { uint8_t v = x == y || x == y + 1 ? 255 : 0; g_art[y][x][0] = v; g_art[y][x][1] = v; g_art[y][x][2] = v; g_art[y][x][3] = 255; }
    id<MTLTexture> diag = picture(W, H, S, S);
    mtl_present_pixel_set(DM_PIXEL_SMOOTH);
    finder_settle(diag, out, PX_EVERY * 3);
    present_offscreen_wait(diag, NULL, out);
    uint8_t *p = malloc(AW * 2 * AH * 2 * 4); [out getBytes:p bytesPerRow:AW * 2 * 4 fromRegion:MTLRegionMake2D(0, 0, AW * 2, AH * 2) mipmapLevel:0];
    long other = 0, changed = 0;
    for (int y = 0; y < AH * 2; y++) for (int x = 0; x < AW * 2; x++) { uint8_t v = p[((size_t)y * AW * 2 + x) * 4]; other += v != 0 && v != 255; changed += (v == 255) != (g_art[y / 2][x / 2][0] == 255); }
    free(p);
    snprintf(name, sizeof name, "MMPX keeps the art's colours (%ld other values)", other); CHECK(name, other == 0);
    snprintf(name, sizeof name, "  and smooths the diagonal (%ld pixels differ from plain 2x)", changed); CHECK(name, changed > 0);
    printf("pixel art: %d checks, %d failed\n", checks, failed); return failed != 0;
} }
