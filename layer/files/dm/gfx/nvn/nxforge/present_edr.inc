// NXForge: included by present_filters.inc (it shares nvn_mtl.m's statics). See UPSTREAM.md, Thin fork.
// EDR highlights (front.h mtl_present_edr; the Mac sidebar's Graphics section, or DM_PRESENT_EDR=on|off with DM_PRESENT_EDR_STRENGTH=0 to 100, 50 by default): on a screen with
// extended dynamic range (a MacBook Pro's Liquid Retina XDR, a Pro Display XDR, an HDR monitor) the window's layer becomes RGBA16Float in extended linear sRGB, and the present pass
// (present.metal edr_out) decodes the game's SDR picture to linear light and lifts its brightest parts above SDR white: the sun, lava, coins and specular glints glow while the rest
// keeps its look. It is an estimate from the finished SDR picture (an inverse tone map), not the game's own light, so white HUD text brightens too; strength sets how far.
// The peak is 1 + (headroom - 1) x strength, with the screen's potential headroom capped at 4x SDR white (NSScreen's maximumPotentialExtendedDynamicRangeColorComponentValue, read on
// the main thread every 2 s), so an SDR screen gets peak 1: the same picture as before. The knee is linear 0.6 (sRGB about 0.8). Off, the layer goes back to BGRA8Unorm.
static _Atomic int g_edr = -1, g_edr_k = -1;   // -1: not read yet
static _Atomic float g_edr_head = 1.0f;          // the screen's potential EDR headroom, 1 = SDR
static void edr_env(void) {
    if (g_edr >= 0) return;
    const char *e = getenv("DM_PRESENT_EDR"), *k = getenv("DM_PRESENT_EDR_STRENGTH"); int want = 0, kk = 50;
    if (e && *e) { if (!strcasecmp(e, "on") || !strcmp(e, "1")) want = 1; else if (strcasecmp(e, "off") && strcmp(e, "0")) MLOG("[RED] DM_PRESENT_EDR=%s: on or off; keeping off", e); }
    if (k && *k) { char *end; long v = strtol(k, &end, 10); if (end != k && !*end && v >= 0 && v <= 100) kk = (int)v; else MLOG("[RED] DM_PRESENT_EDR_STRENGTH=%s: must be 0 to 100; keeping 50", k); }
    int none = -1; atomic_compare_exchange_strong(&g_edr_k, &none, kk);
    none = -1; if (atomic_compare_exchange_strong(&g_edr, &none, want) && want) MLOG("present: EDR highlights on, strength %d (DM_PRESENT_EDR)", (int)g_edr_k);
}
int mtl_present_edr(void) { edr_env(); return g_edr; }
void mtl_present_edr_set(int on) {
    edr_env(); on = !!on;
    if (atomic_exchange(&g_edr, on) != on) MLOG("present: EDR highlights %s", on ? "on" : "off");
}
int mtl_present_edr_strength(void) { edr_env(); return g_edr_k; }
void mtl_present_edr_strength_set(int k) { edr_env(); k = k < 0 ? 0 : k > 100 ? 100 : k; atomic_store(&g_edr_k, k); }
float mtl_present_edr_headroom(void) { return g_edr_head; }
// Present thread: the layer's format and colour space follow the choice (a drawable already handed out keeps its format; the pass takes the destination's format, present_pipeline)
static void nxf_edr_layer(CAMetalLayer *layer) {
#if TARGET_OS_OSX
    static uint64_t n; static _Atomic int asking;
    if (!(n++ % 120) && !atomic_exchange(&asking, 1)) dispatch_async(dispatch_get_main_queue(), ^{   // NSScreen on the main thread
        id s = [NSClassFromString(@"NSScreen") valueForKey:@"mainScreen"]; float h = 1;
        if (s && [s respondsToSelector:NSSelectorFromString(@"maximumPotentialExtendedDynamicRangeColorComponentValue")]) h = [[s valueForKey:@"maximumPotentialExtendedDynamicRangeColorComponentValue"] floatValue];
        if (fabsf(h - g_edr_head) > 0.01f) MLOG("present: screen EDR headroom %.2fx SDR white", (double)h);
        g_edr_head = h < 1 ? 1 : h; asking = 0; });
    int on = mtl_present_edr(), is = layer.pixelFormat == MTLPixelFormatRGBA16Float;
    if (on == is) return;
    if (on) {
        CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearSRGB);
        layer.pixelFormat = MTLPixelFormatRGBA16Float; layer.colorspace = cs; layer.wantsExtendedDynamicRangeContent = YES;
        CGColorSpaceRelease(cs);
    } else { layer.wantsExtendedDynamicRangeContent = NO; layer.colorspace = NULL; layer.pixelFormat = MTLPixelFormatBGRA8Unorm; }
    MLOG("present: window layer %s", on ? "RGBA16Float, extended linear sRGB (EDR)" : "BGRA8Unorm (SDR)");
#else
    (void)layer;
#endif
}
// The pass's hdr constants (Crop.hdr): only a pass into RGBA16Float reads them
static void nxf_edr_params(float *p, MTLPixelFormat f) {
    float head = fminf(g_edr_head, 4.0f), k = (g_edr_k < 0 ? 50 : g_edr_k) / 100.0f;
    p[0] = f == MTLPixelFormatRGBA16Float ? 1.0f + (head - 1.0f) * k : 1.0f; p[1] = 0.6f; p[2] = p[3] = 0;
}
