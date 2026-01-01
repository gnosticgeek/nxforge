// NXForge: frame interpolation through the display-link callback (frame_interp.inc), offscreen drawables and no window: 60 fps frames on a 120 Hz link, each frame an
// in-between picture on one tick and the held frame on the next. Then what 0.28.3 changed: a callback on another thread (CA runs deferred display links from the thread that
// flushes a window change) and the first second after the drawable changes size present the game's frames only, and a rescue in mode 1 is not ended by the 120 Hz link it asks for.
// 0.29.1: a link that calls back only about 80 times a second turns them off at that drawable size
#include "../nvn/nvn_mtl.m"
@interface FakeLinkUpdate : NSObject
@property id<CAMetalDrawable> drawable;
@property CFTimeInterval targetPresentationTimestamp;
@end
@implementation FakeLinkUpdate
@end
static CAMetalLayer *g_test_layer;
void *front_metal_layer(void) { return (__bridge void *)g_test_layer; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t *g_mod; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int checks, failed;
#define CHECK(name, ok) do { int pass = !!(ok); checks++; failed += !pass; printf("%s: %s\n", name, pass ? "PASS" : "FAIL"); } while (0)
enum { W = 1920, H = 1080 };
static tex_t source(unsigned serial) {
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:W height:H mipmapped:NO];
    d.storageMode = MTLStorageModePrivate; d.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    id<MTLTexture> mt = [g_dev newTextureWithDescriptor:d];
    tex_t t = {.magic=MAGIC('T','E','X',0), .serial=serial};
    t.d.width = W; t.d.height = H; t.d.depth = t.d.levels = t.d.samples = 1;
    t.d.target = NVN_TEXTURE_TARGET_2D; t.d.format = NVN_FORMAT_RGBA8;
    serial_put(t.serial, mt); res_add(mt); res_commit(); return t;
}
static double g_t;
static NvMetalDisplayLinkDelegate *g_dl;
static void tick(void) {
    @autoreleasepool { FakeLinkUpdate *u = [FakeLinkUpdate new]; u.drawable = [g_test_layer nextDrawable]; g_t += 1.0 / 120; u.targetPresentationTimestamp = g_t;
    [g_dl metalDisplayLink:(CAMetalDisplayLink *)(id)u needsUpdate:(CAMetalDisplayLinkUpdate *)u]; }
}
static tex_t g_a, g_b;
static void frames(int n) { for (int i = 0; i < n; i++) { present_enqueue(i & 1 ? &g_b : &g_a, 1. / 60, NULL, 0, NULL); tick(); tick(); } }
static void *other_thread(void *arg) { (void)arg; @autoreleasepool { frames(10); } return NULL; }
static int drain(void) {
    pthread_mutex_lock(&g_pq_mu); struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts); ts.tv_sec += 5;
    while (g_pq_inflight && pthread_cond_timedwait(&g_pq_cv, &g_pq_mu, &ts) != ETIMEDOUT) {}
    int left = g_pq_inflight; pthread_mutex_unlock(&g_pq_mu); return left;
}
int main(void) { @autoreleasepool {
    alarm(60); setvbuf(stdout, NULL, _IONBF, 0);
    setenv("DM_PRESENT_HZ", "0", 1); setenv("DM_PRESENT_INTERP", "on", 1);
    mtl_init();
    g_test_layer = [CAMetalLayer layer]; g_test_layer.device = g_dev; g_test_layer.pixelFormat = MTLPixelFormatBGRA8Unorm; g_test_layer.framebufferOnly = NO;
    g_test_layer.drawableSize = CGSizeMake(2560, 1440); [g_q4 addResidencySet:g_test_layer.residencySet];
    mtl_present_layer(2560, 1440);
    // Display-link mode at 120 Hz without a link thread; this thread stands in for the link's (the name nxf_fi_callback_ok looks for)
    g_dm_present_link = 1; g_link_mode = 2; g_link_started = 1; g_link_owns_layer = 1; g_dl = [NvMetalDisplayLinkDelegate new];
    pthread_setname_np("nvn-present-link");
    g_t = CACurrentMediaTime(); g_a = source(92001); g_b = source(92002);
    char name[160];

    frames(4); uint64_t m0 = g_fi_mid_n;
    CHECK("no in-between picture in the first second at a drawable size", m0 == 0);
    usleep(1100000); frames(30); uint64_t m1 = g_fi_mid_n;
    snprintf(name, sizeof name, "then one for each 60 fps frame (%llu of 30)", (unsigned long long)m1); CHECK(name, m1 >= 29);

    pthread_t th; pthread_create(&th, NULL, other_thread, NULL); pthread_join(th, NULL);
    snprintf(name, sizeof name, "callbacks on another thread draw none (%llu)", (unsigned long long)(g_fi_mid_n - m1)); CHECK(name, g_fi_mid_n == m1);

    g_test_layer.drawableSize = CGSizeMake(3024, 1898); mtl_present_layer(3024, 1898);
    frames(10);
    snprintf(name, sizeof name, "a new drawable size pauses them (%llu)", (unsigned long long)(g_fi_mid_n - m1)); CHECK(name, g_fi_mid_n == m1);
    usleep(1100000); frames(10);
    CHECK("and they come back once it has kept its size for a second", g_fi_mid_n >= m1 + 9);
    CHECK("every present completed", drain() == 0);

    // A link that calls back 80 times a second (full screen at latency 2, 0.29.1): interpolation turns off at that size, and comes back at a new size
    usleep(1100000); uint64_t m2 = g_fi_mid_n;
    for (int i = 0; i < 120; i++) { present_enqueue(i & 1 ? &g_b : &g_a, 1. / 60, NULL, 0, NULL); tick(); usleep(12500); tick(); usleep(12500); }
    uint64_t m3 = g_fi_mid_n;
    snprintf(name, sizeof name, "a link at 80 a second turns them off (%llu in-between pictures, then %d)", (unsigned long long)(m3 - m2), g_fi_slow); CHECK(name, g_fi_slow && m3 - m2 < 100);
    frames(10); CHECK("and they stay off at that size", g_fi_mid_n == m3);
    g_test_layer.drawableSize = CGSizeMake(2560, 1440); mtl_present_layer(2560, 1440);
    frames(2); usleep(1100000); frames(10);
    CHECK("a new size tries them again", g_fi_mid_n >= m3 + 9);
    CHECK("every present completed after that", drain() == 0);

    // A rescue of mode 1 (link_sync): the 120 Hz link that interpolation asks for does not end it
    g_rescue_mode = 1; g_rescue_back_at = now_ns() + 3000000000ull; link_sync();
    CHECK("a rescue holds while interpolation wants the 120 Hz link", g_rescue_mode == 1);
    g_rescue_mode = 0;
    printf("frame interpolation: %d checks, %d failed\n", checks, failed); return failed != 0;
} }
