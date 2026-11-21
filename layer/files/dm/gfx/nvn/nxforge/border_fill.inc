// NXForge: included by present_filters.inc (it shares nvn_mtl.m's statics). See UPSTREAM.md, Thin fork.
// Border fill (front.h mtl_present_border; the Mac sidebar's Graphics page, or DM_PRESENT_BORDER=off|glow|art): what the window shows around a picture that does not fill it,
// in place of black bars. Glow is the game's own picture, blurred and dimmed, so the colours of the scene run on to the screen's edges; Art is the game's banner art (the
// app's Resources/dm/banner, handed over by the front end: mtl_present_border_art), blurred and dimmed the same way, and Glow where the game has no art. Only the window's
// present draws it (screenshots and recordings keep the picture alone), and only while the picture leaves room: a picture that fills the window costs nothing.
// Two small passes a present: the picture averaged into a 96x54 texture (border_fill.metal bf_down), then that texture stretched over the window before the picture is drawn
// (bf_fill, in the present's own pass). About 0.05 ms of GPU on an M4 Pro.
#import <ImageIO/ImageIO.h>
enum { BF_W = 96, BF_H = 54 };
typedef struct { float rect[4], a[4]; } bf_consts;
static _Atomic int g_bf = -1;
static id<MTLTexture> g_bf_small, g_bf_art; static id<MTLBuffer> g_bf_buf; static id<MTL4ArgumentTable> g_bf_args;
static id<MTLRenderPipelineState> g_bf_down, g_bf_fill; static MTLPixelFormat g_bf_fill_pf;
static pthread_mutex_t g_bf_mu = PTHREAD_MUTEX_INITIALIZER; static char *g_bf_art_path; static int g_bf_art_new;   // the front end's art, taken by the present thread
int mtl_present_border(void) {
    int b = g_bf;
    if (b >= 0) return b;
    const char *e = getenv("DM_PRESENT_BORDER"); int want = DM_PBORDER_OFF;
    if (e && *e) { if (!strcasecmp(e, "glow") || !strcasecmp(e, "blur")) want = DM_PBORDER_GLOW; else if (!strcasecmp(e, "art")) want = DM_PBORDER_ART;
                   else if (strcasecmp(e, "off") && strcmp(e, "0")) MLOG("[RED] DM_PRESENT_BORDER=%s: must be off, glow or art; using off", e); }
    int none = -1; atomic_compare_exchange_strong(&g_bf, &none, want);
    return g_bf;
}
void mtl_present_border_set(int mode) {
    mode = mode < 0 || mode >= DM_PBORDER_N ? DM_PBORDER_OFF : mode;
    if (atomic_exchange(&g_bf, mode) != mode) MLOG("present: border fill %s", mode == DM_PBORDER_GLOW ? "glow" : mode == DM_PBORDER_ART ? "art" : "off");
}
void mtl_present_border_art(const char *path) {   // any thread: an image file (JPEG or PNG), NULL for none
    if (path && !*path) path = NULL;
    pthread_mutex_lock(&g_bf_mu);
    if ((!path && g_bf_art_path) || (path && (!g_bf_art_path || strcmp(path, g_bf_art_path)))) { free(g_bf_art_path); g_bf_art_path = path ? strdup(path) : NULL; g_bf_art_new = 1; }   // the same file again is not read again
    pthread_mutex_unlock(&g_bf_mu);
}
static id<MTLRenderPipelineState> bf_pso(id<MTLLibrary> lib, NSString *fs, MTLPixelFormat pf) {
    MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new]; NSError *e = nil;
    pd.vertexFunction = [lib newFunctionWithName:@"bf_vs"]; pd.fragmentFunction = [lib newFunctionWithName:fs]; pd.colorAttachments[0].pixelFormat = pf;
    id<MTLRenderPipelineState> p = pd.fragmentFunction ? [g_dev newRenderPipelineStateWithDescriptor:pd error:&e] : nil;
    if (!p) NXF_RED_ONCE(9, "present: border fill's %s pipeline failed (%s); black bars", fs.UTF8String, e ? e.localizedDescription.UTF8String : "no function");
    return p;
}
static int bf_ready(MTLPixelFormat dst_pf) {
    static id<MTLLibrary> lib; static int failed;
    if (failed) return 0;
    if (!lib) {
        NSError *e = nil; lib = host_lib("border_fill", &e);
        MTL4ArgumentTableDescriptor *ad = [MTL4ArgumentTableDescriptor new]; ad.maxTextureBindCount = 1; ad.maxSamplerStateBindCount = 1; ad.maxBufferBindCount = 1;
        g_bf_args = lib ? [g_dev newArgumentTableWithDescriptor:ad error:&e] : nil;
        g_bf_down = lib ? bf_pso(lib, @"bf_down", MTLPixelFormatRGBA8Unorm) : nil;
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:BF_W height:BF_H mipmapped:NO];
        td.storageMode = MTLStorageModePrivate; td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        g_bf_small = g_bf_down ? [g_dev newTextureWithDescriptor:td] : nil;
        g_bf_buf = g_bf_small ? [g_dev newBufferWithLength:2 * sizeof(bf_consts) options:MTLResourceStorageModeShared] : nil;
        if (!lib || !g_bf_args || !g_bf_down || !g_bf_small || !g_bf_buf) {
            failed = 1; NXF_RED_ONCE(10, "present: border fill could not be set up (%s); black bars", e ? e.localizedDescription.UTF8String : "a pipeline, texture or buffer failed"); return 0; }
        g_bf_small.label = @"border fill"; res_add(g_bf_small); res_add(g_bf_buf); res_commit();
    }
    if (g_bf_fill_pf != dst_pf || !g_bf_fill) { g_bf_fill = bf_pso(lib, @"bf_fill", dst_pf); g_bf_fill_pf = dst_pf; if (!g_bf_fill) return 0; }
    return 1;
}
// The front end's art as a texture at most 512 wide (present thread; the file is read once per change)
static void bf_art_take(void) {
    pthread_mutex_lock(&g_bf_mu); int fresh = g_bf_art_new; g_bf_art_new = 0; char *path = fresh && g_bf_art_path ? strdup(g_bf_art_path) : NULL; pthread_mutex_unlock(&g_bf_mu);
    if (!fresh) return;
    if (g_bf_art) { pthread_mutex_lock(&g_pq_mu); while (g_pq_inflight) pthread_cond_wait(&g_pq_cv, &g_pq_mu); pthread_mutex_unlock(&g_pq_mu); res_remove(g_bf_art); g_bf_art = nil; res_commit(); }
    if (!path) return;
    @autoreleasepool {
        CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:@(path)], NULL);
        NSDictionary *opt = @{(id)kCGImageSourceCreateThumbnailFromImageAlways: @YES, (id)kCGImageSourceThumbnailMaxPixelSize: @512, (id)kCGImageSourceCreateThumbnailWithTransform: @YES};
        CGImageRef img = src ? CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opt) : NULL;
        size_t w = img ? CGImageGetWidth(img) : 0, h = img ? CGImageGetHeight(img) : 0;
        uint8_t *px = w && h ? calloc(w * h, 4) : NULL;
        if (px) {
            CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            CGContextRef cg = CGBitmapContextCreate(px, w, h, 8, w * 4, cs, (CGBitmapInfo)kCGImageAlphaNoneSkipLast | kCGBitmapByteOrder32Big);
            if (cg) {
                CGContextDrawImage(cg, CGRectMake(0, 0, w, h), img); CGContextRelease(cg);
                MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:w height:h mipmapped:NO];
                td.storageMode = MTLStorageModeShared; td.usage = MTLTextureUsageShaderRead;
                id<MTLTexture> t = [g_dev newTextureWithDescriptor:td];
                if (t) { [t replaceRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0 withBytes:px bytesPerRow:w * 4]; t.label = @"border fill art"; res_add(t); res_commit(); g_bf_art = t; }
            }
            CGColorSpaceRelease(cs);
        }
        if (g_bf_art) MLOG("present: border fill art %zux%zu from %s", w, h, path); else MLOG("present: border fill: no picture could be read from %s; Art shows the glow", path);
        free(px); if (img) CGImageRelease(img); if (src) CFRelease(src);
    }
    free(path);
}
// Before the present's own pass (present_encode_m4, the window's present with a picture that leaves room): the small texture drawn from the picture (tex, its crop fr in
// texels, flipped when the window image is stored bottom-up) or from the art. Returns whether the fill is ready to be drawn; *aspect is the small texture's content's shape
static int nxf_bf_prepare(id<MTL4CommandBuffer> cb, id<MTLTexture> tex, const double fr[4], int flipped, MTLPixelFormat dst_pf, double pic_aspect, double *aspect) {
    int mode = mtl_present_border();
    if (mode == DM_PBORDER_OFF || !bf_ready(dst_pf)) return 0;
    bf_art_take();
    id<MTLTexture> src = mode == DM_PBORDER_ART && g_bf_art ? g_bf_art : tex;
    bf_consts *c = (bf_consts *)g_bf_buf.contents;
    if (src == tex) {
        double tw = tex.width, th = tex.height;
        c->rect[0] = (float)(fr[0] / tw); c->rect[1] = (float)(fr[1] / th); c->rect[2] = (float)(fr[2] / tw); c->rect[3] = (float)(fr[3] / th);
        if (flipped) { c->rect[1] += c->rect[3]; c->rect[3] = -c->rect[3]; }
        *aspect = pic_aspect;
    } else { c->rect[0] = c->rect[1] = 0; c->rect[2] = c->rect[3] = 1; *aspect = (double)src.width / (double)src.height; }
    c->a[0] = c->rect[2] / BF_W / 4; c->a[1] = c->rect[3] / BF_H / 4; c->a[2] = c->a[3] = 0;
    MTL4RenderPassDescriptor *rp = [MTL4RenderPassDescriptor new];
    rp.colorAttachments[0].texture = g_bf_small; rp.colorAttachments[0].loadAction = MTLLoadActionDontCare; rp.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTL4RenderCommandEncoder> en = [cb renderCommandEncoderWithDescriptor:rp];
    if (!en) { NXF_RED_ONCE(11, "present: border fill: no render encoder"); return 0; }
    [en barrierAfterQueueStages:MTLStageAll beforeStages:MTLStageAll visibilityOptions:resource_vis()];
    [en setArgumentTable:g_bf_args atStages:MTLRenderStageFragment];
    [g_bf_args setTexture:src.gpuResourceID atIndex:0]; [g_bf_args setSamplerState:g_blit_samp.gpuResourceID atIndex:0]; [g_bf_args setAddress:g_bf_buf.gpuAddress atIndex:0];
    [en setViewport:(MTLViewport){0, 0, BF_W, BF_H, 0, 1}]; [en setRenderPipelineState:g_bf_down];
    [en drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    m4_end(en);
    static int once; if (!once++) MLOG("present: border fill drawn around the picture (%s)", src == tex ? "glow: the picture, blurred" : "the game's art, blurred");
    return 1;
}
// In the present's own pass, before the picture: the small texture over the whole drawable (dw x dh), then the pass's own argument table back in place
static void nxf_bf_fill(id<MTL4RenderCommandEncoder> en, double dw, double dh, double aspect, MTLPixelFormat dst_pf) {
    bf_consts *c = (bf_consts *)g_bf_buf.contents + 1;
    double da = dh > 0 ? dw / dh : 1, zoom = 0.92;   // a little enlarged, so the small texture's clamped edge stays outside the window
    c->rect[0] = c->rect[1] = 0; c->rect[2] = c->rect[3] = 1;
    c->a[0] = (float)((da > aspect ? 1 : da / aspect) * zoom); c->a[1] = (float)((da > aspect ? aspect / da : 1) * zoom);
    c->a[2] = 0.38f; c->a[3] = dst_pf == MTLPixelFormatRGBA16Float ? 1 : 0;
    [en setArgumentTable:g_bf_args atStages:MTLRenderStageFragment];
    [g_bf_args setTexture:g_bf_small.gpuResourceID atIndex:0]; [g_bf_args setSamplerState:g_blit_samp.gpuResourceID atIndex:0];
    [g_bf_args setAddress:g_bf_buf.gpuAddress + sizeof(bf_consts) atIndex:0];
    [en setViewport:(MTLViewport){0, 0, dw, dh, 0, 1}]; [en setRenderPipelineState:g_bf_fill];
    [en drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [en setArgumentTable:g_present_args atStages:MTLRenderStageFragment];
}
