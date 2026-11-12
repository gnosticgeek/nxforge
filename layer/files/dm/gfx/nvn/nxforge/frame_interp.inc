// NXForge: included by present_filters.inc (it shares nvn_mtl.m's statics). See UPSTREAM.md, Thin fork.
// Frame interpolation to 120 fps (front.h mtl_present_interp; the Mac sidebar's FPS section, or DM_PRESENT_INTERP=off|on|auto): a 60 fps game on a 120 Hz screen gets an in-between
// picture on every other refresh. The display link runs at 120 Hz (pacing mode 2, the game still steps at 60). When frame N arrives its tick shows a picture halfway between N-1
// and N, and the next tick shows N itself (held one refresh, about 8 ms more latency). The in-between picture comes from the two finished pictures alone, so it works for every game:
// motion is estimated on a quarter-size luma pyramid (symmetric block matching from the midpoint, coarse to fine, then a vector median), and each pixel takes the average of N-1
// sampled half a step back and N half a step forward. A pixel the same in both frames (the HUD, a still scene) is kept as is; where the two samples disagree (something uncovered)
// it leans on N. Off for games that step at 30 or 120, while the game holds a frame for its present interval, and for screenshots and recordings (they keep the game's frames).
// Auto turns it on where the window's screen runs at 120 Hz or more. Wobble around fine moving edges and HUD over moving scenery is the known cost of the estimate.
enum { FI_OFF, FI_NEW, FI_HELD };
static _Atomic int g_fi = -1;   // 0 off, 1 on, 2 auto; -1 not read yet
static int g_fi_phase;          // display-link callback thread: what the present being encoded is (FI_NEW: a game frame, FI_HELD: the frame held back after its in-between)
static int g_fi_made_mid;       // the last FI_NEW present drew an in-between picture (so the real frame waits for the next tick)
static id<MTLTexture> g_fi_prev, g_fi_cur, g_fi_out, g_fi_lum[4], g_fi_flow[4], g_fi_vm;
static int g_fi_have_prev;
static id<MTL4ArgumentTable> g_fi_args;
static id<MTLRenderPipelineState> g_fi_pso_lum, g_fi_pso_down, g_fi_pso_top, g_fi_pso_flow, g_fi_pso_vm, g_fi_pso_mix, g_fi_pso_copy; static MTLPixelFormat g_fi_pf;
static uint64_t g_fi_mid_n, g_fi_skip_n;
__attribute__((weak)) int front_screen_max_fps(void); int mtl_link_rate(void); int nvn_vsync_hz(void);
static const char *const g_fi_name[3] = {"off", "on", "auto"};
static void fi_env(void) {
    if (g_fi >= 0) return;
    const char *e = getenv("DM_PRESENT_INTERP"); int want = 0;
    if (e && *e) { if (!strcasecmp(e, "on") || !strcmp(e, "1")) want = 1; else if (!strcasecmp(e, "auto")) want = 2; else if (strcasecmp(e, "off") && strcmp(e, "0")) MLOG("[RED] DM_PRESENT_INTERP=%s: off, on or auto; keeping off", e); }
    int none = -1; if (atomic_compare_exchange_strong(&g_fi, &none, want) && want) MLOG("present: frame interpolation %s (DM_PRESENT_INTERP)", g_fi_name[want]);
}
int mtl_present_interp(void) { fi_env(); return g_fi; }
void mtl_present_interp_set(int mode) {
    fi_env(); if (mode < 0 || mode > 2) mode = 0;
    if (atomic_exchange(&g_fi, mode) != mode) MLOG("present: frame interpolation %s", g_fi_name[mode]);
}
// Whether the display link should run at 120 Hz for it (link_sync): on, or auto on a screen of 120 Hz or more
static int nxf_fi_wants_link(void) { int m = mtl_present_interp(); return m == 1 || (m == 2 && front_screen_max_fps() >= 120); }
int mtl_present_interp_active(void) { return nxf_fi_wants_link(); }

static const char *const g_fi_src =
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"struct V { float4 p [[position]]; float2 uv; };\n"
"vertex V fi_vs(uint i [[vertex_id]]) { float2 q = float2((i << 1) & 2, i & 2); V o; o.p = float4(q * 2 - 1, 0, 1); o.uv = float2(q.x, 1 - q.y); return o; }\n"
"static float lum(float4 c) { return dot(c.rgb, float3(0.299, 0.587, 0.114)); }\n"
"static float mx3(float3 v) { return max(v.x, max(v.y, v.z)); }\n"
// quarter-size luma of both frames: four bilinear taps cover the 4x4 block
"fragment float4 fi_lum(V in [[stage_in]], texture2d<float> P [[texture(0)]], texture2d<float> C [[texture(1)]], sampler s [[sampler(0)]]) {\n"
"  float2 t = 1.0 / float2(P.get_width(), P.get_height()); float a = 0, b = 0;\n"
"  for (int k = 0; k < 4; k++) { float2 u = in.uv + float2((k & 1) ? 1 : -1, (k & 2) ? 1 : -1) * t; a += lum(P.sample(s, u)); b += lum(C.sample(s, u)); }\n"
"  return float4(a * 0.25, b * 0.25, 0, 1);\n"
"}\n"
"fragment float4 fi_down(V in [[stage_in]], texture2d<float> L [[texture(0)]], sampler s [[sampler(0)]]) {\n"
"  float2 t = 0.5 / float2(L.get_width(), L.get_height()); float4 r = 0;\n"
"  for (int k = 0; k < 4; k++) r += L.sample(s, in.uv + float2((k & 1) ? 1 : -1, (k & 2) ? 1 : -1) * t);\n"
"  return r * 0.25;\n"
"}\n"
// matching cost of motion v (uv units, previous -> current) seen from the midpoint: 3x3 patch, previous half a step back, current half a step forward
"static float cost(texture2d<float> L, sampler s, float2 uv, float2 v, float2 t) {\n"
"  float c = 0;\n"
"  for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) { float2 o = float2(x, y) * t; c += abs(L.sample(s, uv - v * 0.5 + o).r - L.sample(s, uv + v * 0.5 + o).g); }\n"
"  return c * (1.0 / 9);\n"
"}\n"
"static float4 search(texture2d<float> L, sampler s, float2 uv, float2 v0, int R) {\n"
"  float2 t = 1.0 / float2(L.get_width(), L.get_height());\n"
"  float best = cost(L, s, uv, float2(0), t) * 0.9 - 0.001, c; float2 bv = float2(0);\n"   // a still pixel wins ties: the HUD and still scenery keep zero motion
"  for (int y = -R; y <= R; y++) for (int x = -R; x <= R; x++) { float2 v = v0 + float2(x, y) * t; c = cost(L, s, uv, v, t) + 0.0015 * length(float2(x, y)); if (c < best) { best = c; bv = v; } }\n"
"  return float4(bv, best, 1);\n"
"}\n"
"fragment float4 fi_top(V in [[stage_in]], texture2d<float> L [[texture(0)]], sampler s [[sampler(0)]]) { return search(L, s, in.uv, float2(0), 4); }\n"
"fragment float4 fi_flow(V in [[stage_in]], texture2d<float> L [[texture(0)]], texture2d<float> F [[texture(1)]], sampler s [[sampler(0)]]) { return search(L, s, in.uv, F.sample(s, in.uv).xy, 2); }\n"
// vector median: of the 3x3 neighbours' motions, the one that matches best here
"fragment float4 fi_vm(V in [[stage_in]], texture2d<float> L [[texture(0)]], texture2d<float> F [[texture(1)]], sampler s [[sampler(0)]]) {\n"
"  float2 t = 1.0 / float2(L.get_width(), L.get_height()); float4 r = F.sample(s, in.uv); float best = 1e9; float2 bv = r.xy;\n"
"  for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) { float2 v = F.sample(s, in.uv + float2(x, y) * t).xy; float c = cost(L, s, in.uv, v, t); if (c < best) { best = c; bv = v; } }\n"
"  return float4(bv, best, 1);\n"
"}\n"
"fragment float4 fi_mix(V in [[stage_in]], texture2d<float> P [[texture(0)]], texture2d<float> C [[texture(1)]], texture2d<float> F [[texture(2)]], sampler s [[sampler(0)]]) {\n"
"  float2 v = F.sample(s, in.uv).xy; uint2 px = uint2(in.p.xy);\n"
"  float4 p0 = P.read(px), c0 = C.read(px);\n"
"  if (mx3(abs(p0.rgb - c0.rgb)) < 0.008) return c0;\n"
"  float4 a = P.sample(s, in.uv - v * 0.5), b = C.sample(s, in.uv + v * 0.5);\n"
"  float w = 0.5 + 0.5 * smoothstep(0.08, 0.25, mx3(abs(a.rgb - b.rgb)));\n"
"  return mix(a, b, w);\n"
"}\n"
"fragment float4 fi_copy(V in [[stage_in]], texture2d<float> T [[texture(0)]]) { return T.read(uint2(in.p.xy)); }\n";

static id<MTLRenderPipelineState> fi_pso(id<MTLLibrary> lib, NSString *fs, MTLPixelFormat pf) {
    MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new]; NSError *e = nil;
    pd.vertexFunction = [lib newFunctionWithName:@"fi_vs"]; pd.fragmentFunction = [lib newFunctionWithName:fs]; pd.colorAttachments[0].pixelFormat = pf;
    id<MTLRenderPipelineState> p = [g_dev newRenderPipelineStateWithDescriptor:pd error:&e];
    if (!p) MLOG("[RED] frame interpolation: pipeline %s failed (%s)", fs.UTF8String, e ? e.localizedDescription.UTF8String : "no function");
    return p;
}
// Pipelines (once) and the pictures' format-dependent ones (when the game picture's format changes); 0 when something failed
static int fi_ready(MTLPixelFormat pf) {
    static id<MTLLibrary> lib; static int failed;
    if (failed) return 0;
    if (!lib) {
        NSError *e = nil; NSString *src = [NSString stringWithUTF8String:g_fi_src]; if (src) lib = [g_dev newLibraryWithSource:src options:nil error:&e];
        MTL4ArgumentTableDescriptor *ad = [MTL4ArgumentTableDescriptor new]; ad.maxTextureBindCount = 3; ad.maxSamplerStateBindCount = 1; ad.maxBufferBindCount = 1;
        g_fi_args = lib ? [g_dev newArgumentTableWithDescriptor:ad error:&e] : nil;
        if (lib) { g_fi_pso_lum = fi_pso(lib, @"fi_lum", MTLPixelFormatRG16Float); g_fi_pso_down = fi_pso(lib, @"fi_down", MTLPixelFormatRG16Float);
                   g_fi_pso_top = fi_pso(lib, @"fi_top", MTLPixelFormatRGBA16Float); g_fi_pso_flow = fi_pso(lib, @"fi_flow", MTLPixelFormatRGBA16Float); g_fi_pso_vm = fi_pso(lib, @"fi_vm", MTLPixelFormatRGBA16Float); }
        if (!lib || !g_fi_args || !g_fi_pso_lum || !g_fi_pso_down || !g_fi_pso_top || !g_fi_pso_flow || !g_fi_pso_vm) {
            failed = 1; MLOG("[RED] frame interpolation: its shaders did not build (%s); presenting the game's frames only", e ? e.localizedDescription.UTF8String : "a pipeline failed"); return 0; }
    }
    if (g_fi_pf != pf || !g_fi_pso_mix) {
        g_fi_pso_mix = fi_pso(lib, @"fi_mix", pf); g_fi_pso_copy = fi_pso(lib, @"fi_copy", pf); g_fi_pf = pf;
        if (!g_fi_pso_mix || !g_fi_pso_copy) { g_fi_pso_mix = nil; return 0; }
    }
    return 1;
}
static id<MTLTexture> fi_tex(MTLPixelFormat pf, NSUInteger w, NSUInteger h, NSString *label) {
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pf width:MAX(w, 1) height:MAX(h, 1) mipmapped:NO];
    td.storageMode = MTLStorageModePrivate; td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    id<MTLTexture> t = [g_dev newTextureWithDescriptor:td]; t.label = label; if (t) res_add(t);
    return t;
}
static void fi_free(void) {
    res_remove(g_fi_prev); res_remove(g_fi_cur); res_remove(g_fi_out); res_remove(g_fi_vm); g_fi_prev = g_fi_cur = g_fi_out = g_fi_vm = nil;
    for (int i = 0; i < 4; i++) { res_remove(g_fi_lum[i]); res_remove(g_fi_flow[i]); g_fi_lum[i] = g_fi_flow[i] = nil; }
    g_fi_have_prev = 0;
}
// The textures for a game picture of w x h in format pf; a change waits for presents still reading the old ones
static int fi_textures(MTLPixelFormat pf, NSUInteger w, NSUInteger h) {
    if (g_fi_cur && g_fi_cur.width == w && g_fi_cur.height == h && g_fi_cur.pixelFormat == pf) return 1;
    if (g_fi_cur) { pthread_mutex_lock(&g_pq_mu); while (g_pq_inflight) pthread_cond_wait(&g_pq_cv, &g_pq_mu); pthread_mutex_unlock(&g_pq_mu); }
    fi_free();
    g_fi_prev = fi_tex(pf, w, h, @"interp previous"); g_fi_cur = fi_tex(pf, w, h, @"interp current"); g_fi_out = fi_tex(pf, w, h, @"interp in-between");
    NSUInteger lw = (w + 3) / 4, lh = (h + 3) / 4;
    for (int i = 0; i < 4; i++) { g_fi_lum[i] = fi_tex(MTLPixelFormatRG16Float, lw >> i, lh >> i, @"interp luma"); g_fi_flow[i] = fi_tex(MTLPixelFormatRGBA16Float, lw >> i, lh >> i, @"interp motion"); }
    g_fi_vm = fi_tex(MTLPixelFormatRGBA16Float, lw, lh, @"interp motion median");
    int ok = g_fi_prev && g_fi_cur && g_fi_out && g_fi_vm; for (int i = 0; i < 4; i++) ok = ok && g_fi_lum[i] && g_fi_flow[i];
    if (!ok) { fi_free(); NXF_RED_ONCE(3, "frame interpolation: cannot create its textures for %lux%lu; presenting the game's frames only", (unsigned long)w, (unsigned long)h); return 0; }
    res_commit();
    MLOG("frame interpolation: %lux%lu pictures (format %lu), motion estimated at %lux%lu", (unsigned long)w, (unsigned long)h, (unsigned long)pf, (unsigned long)lw, (unsigned long)lh);
    return 1;
}
// One full-target pass: dst drawn by pso from up to three textures
static void fi_pass(id<MTL4CommandBuffer> cb, id<MTLTexture> dst, id<MTLRenderPipelineState> pso, id<MTLTexture> t0, id<MTLTexture> t1, id<MTLTexture> t2) {
    MTL4RenderPassDescriptor *rp = [MTL4RenderPassDescriptor new];
    rp.colorAttachments[0].texture = dst; rp.colorAttachments[0].loadAction = MTLLoadActionDontCare; rp.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTL4RenderCommandEncoder> en = [cb renderCommandEncoderWithDescriptor:rp];
    if (!en) return;
    [en barrierAfterQueueStages:MTLStageAll beforeStages:MTLStageAll visibilityOptions:resource_vis()];   // after the frame's work and the pass before
    [en setArgumentTable:g_fi_args atStages:MTLRenderStageFragment];
    if (t0) [g_fi_args setTexture:t0.gpuResourceID atIndex:0];
    if (t1) [g_fi_args setTexture:t1.gpuResourceID atIndex:1];
    if (t2) [g_fi_args setTexture:t2.gpuResourceID atIndex:2];
    [g_fi_args setSamplerState:g_blit_samp.gpuResourceID atIndex:0];
    [en setViewport:(MTLViewport){0, 0, dst.width, dst.height, 0, 1}]; [en setRenderPipelineState:pso];
    [en drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    m4_end(en);
}
// The present's source (present_encode_m4, the window's present only). FI_NEW: the game's frame is copied (it may be reused once this present is done) and, with the frame before,
// the in-between picture is drawn and shown instead (g_fi_made_mid); FI_HELD: the copy, shown on the next tick; FI_OFF: the game's texture as before, and the history is dropped
static id<MTLTexture> nxf_fi_source(id<MTL4CommandBuffer> cb, id<MTLTexture> raw) {
    g_fi_made_mid = 0;
    if (g_fi_phase == FI_OFF) { g_fi_have_prev = 0; return raw; }
    if (g_fi_phase == FI_HELD) return raw;
    if (!fi_ready(raw.pixelFormat) || !fi_textures(raw.pixelFormat, raw.width, raw.height)) { g_fi_have_prev = 0; return raw; }
    id<MTLTexture> t = g_fi_prev; g_fi_prev = g_fi_cur; g_fi_cur = t;
    fi_pass(cb, g_fi_cur, g_fi_pso_copy, raw, nil, nil);
    if (!g_fi_have_prev) { g_fi_have_prev = 1; return g_fi_cur; }
    fi_pass(cb, g_fi_lum[0], g_fi_pso_lum, g_fi_prev, g_fi_cur, nil);
    for (int i = 1; i < 4; i++) fi_pass(cb, g_fi_lum[i], g_fi_pso_down, g_fi_lum[i - 1], nil, nil);
    fi_pass(cb, g_fi_flow[3], g_fi_pso_top, g_fi_lum[3], nil, nil);
    for (int i = 2; i >= 0; i--) fi_pass(cb, g_fi_flow[i], g_fi_pso_flow, g_fi_lum[i], g_fi_flow[i + 1], nil);
    fi_pass(cb, g_fi_vm, g_fi_pso_vm, g_fi_lum[0], g_fi_flow[0], nil);
    fi_pass(cb, g_fi_out, g_fi_pso_mix, g_fi_prev, g_fi_cur, g_fi_vm);
    g_fi_made_mid = 1;
    if (!(++g_fi_mid_n % 600)) MLOG("frame interpolation: %llu in-between pictures, %llu game frames shown without one", (unsigned long long)g_fi_mid_n, (unsigned long long)g_fi_skip_n);
    return g_fi_out;
}
