// NXForge's Game Boy Advance player: the window a converted GBA game runs in. The machine, sound, saves, save states
// and cheats are the host library's (nxgba.h, gba/host/src/lib.rs); this file is the Mac side of it: the window and
// its Metal picture, the keyboard and controllers, the sound device, and NXForge's own in-game sidebar
// (layer/files/dm/host/quick_settings_mac.swift), which is the same file the Switch player builds. The sidebar talks
// to its player through the C calls in quick_settings_mac.h; they are implemented here for a GBA game.
//
// The app bundle holds the game (Contents/Resources/gba/game.gba, game.dylib: scripts/gba_build.py); the save, save
// snapshots, cheats and screenshots live where a Switch game's do, ~/Library/Application Support/nxnative/<title ID>.
//
// NXGBA_SNAPSHOT=<file.png> runs without showing anything: the game runs NXGBA_SNAPSHOT_FRAMES frames (600) with the
// keys in NXGBA_SNAPSHOT_INPUT, then the window's picture (the Metal pass drawn into a texture, the sidebar over it
// when NXGBA_SNAPSHOT_SIDEBAR names a page number) is written to the file and the player quits.
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <GameController/GameController.h>
#import <AudioToolbox/AudioToolbox.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <stdatomic.h>
#include <sys/clonefile.h>
#include <sys/stat.h>
#include "nxgba.h"
#include "quick_settings_mac.h"

#define LOG(...) do { fprintf(stderr, "nxgba: " __VA_ARGS__); fputc('\n', stderr); } while (0)
enum { GW = 240, GH = 160 };

static NxGba *g;
static pthread_mutex_t g_mu = PTHREAD_MUTEX_INITIALIZER;   // the machine: the game thread holds it for a frame
static NSString *g_name, *g_id, *g_root, *g_code;
static NSWindow *g_win;
static NSView *g_view, *g_side;
static int g_open, g_peek, g_open_by_pad, g_snapshot;
static _Atomic int g_paused, g_quit, g_fast;
static _Atomic uint32_t g_keys_kb, g_keys_pad;
// the picture's settings (front.h), read by the game thread at every frame
static _Atomic int g_filter, g_scan, g_scale, g_border, g_pixel = DM_PIXEL_AUTO, g_aa, g_upscale, g_edr, g_edr_strength = 50, g_interp, g_aniso, g_colour;
static _Atomic float g_strength = 0.5f, g_inset;
static _Atomic int g_dw = 960, g_dh = 640;
static _Atomic uint64_t g_presents;
static double g_times[254]; static int g_times_n, g_times_at; static double g_last_present; static pthread_mutex_t g_times_mu = PTHREAD_MUTEX_INITIALIZER;

static double now_s(void) { static mach_timebase_info_data_t tb; if (!tb.denom) mach_timebase_info(&tb); return (double)mach_absolute_time() * tb.numer / tb.denom * 1e-9; }
static NSString *opt_key(NSString *what) { return [NSString stringWithFormat:@"DMQuickSettings.%@.%@", what, g_name]; }
static NSString *pfx_key(NSString *what) { return [NSString stringWithFormat:@"DMPresentFilter.%@.%@", what, g_name]; }
static BOOL opt_bool(NSString *what, BOOL def) { id v = [NSUserDefaults.standardUserDefaults objectForKey:opt_key(what)]; return v ? [v boolValue] : def; }
static void toast(NSString *msg) { if (g_snapshot && !g_side) return; dm_qs_toast((__bridge void *)g_view, msg.UTF8String); }

// ---- the picture settings (front.h) ----
int mtl_present_filter(float *k) { if (k) *k = g_strength; return g_filter; }
void mtl_present_filter_set(int mode, float k) { g_filter = mode; g_strength = k; }
int mtl_aniso(void) { return g_aniso; }
void mtl_aniso_set(int n) { g_aniso = n; }
int mtl_present_upscale(void) { return g_upscale; }
void mtl_present_upscale_set(int on) { g_upscale = on; }
int mtl_present_aa(void) { return g_aa; }
void mtl_present_aa_set(int m) { g_aa = m; }
int mtl_present_edr(void) { return g_edr; }
void mtl_present_edr_set(int on) { g_edr = on; }
int mtl_present_edr_strength(void) { return g_edr_strength; }
void mtl_present_edr_strength_set(int s) { g_edr_strength = s; }
float mtl_present_edr_headroom(void) { return 1; }
int mtl_present_interp(void) { return g_interp; }
void mtl_present_interp_set(int m) { g_interp = m; }
int mtl_present_interp_active(void) { return 0; }
int mtl_present_pixel(void) { return g_pixel; }
void mtl_present_pixel_set(int m) { g_pixel = m; }
int mtl_present_pixel_active(void) { return g_pixel == DM_PIXEL_OFF ? DM_PIXEL_OFF : DM_PIXEL_SHARP; }
int mtl_present_pixel_grid(float *w, float *h, float *s) { if (w) *w = GW; if (h) *h = GH; if (s) *s = 1; return g_pixel != DM_PIXEL_OFF; }
int mtl_present_scanline(void) { return g_scan; }
void mtl_present_scanline_set(int rows) { g_scan = rows; }
int mtl_present_scale(void) { return g_scale; }
void mtl_present_scale_set(int m) { g_scale = m; }
int mtl_present_border(void) { return g_border; }
void mtl_present_border_set(int m) { g_border = m; }
void mtl_present_inset(float share) { g_inset = share; }
uint64_t mtl_present_count(void) { return g_presents; }
int mtl_present_times(double *ms, int max, double *age) {
    pthread_mutex_lock(&g_times_mu);
    int n = g_times_n < max ? g_times_n : max;
    for (int i = 0; i < n; i++) ms[i] = g_times[(g_times_at - n + i + 254 * 2) % 254];
    if (age) *age = g_last_present > 0 ? (now_s() - g_last_present) * 1e3 : -1;
    pthread_mutex_unlock(&g_times_mu);
    return n;
}
static void present_counted(void) {
    double t = now_s();
    pthread_mutex_lock(&g_times_mu);
    if (g_last_present > 0) { g_times[g_times_at] = (t - g_last_present) * 1e3; g_times_at = (g_times_at + 1) % 254; if (g_times_n < 254) g_times_n++; }
    g_last_present = t;
    pthread_mutex_unlock(&g_times_mu);
    g_presents++;
}

// ---- Metal: the 240 x 160 picture into the window ----
static NSString *const kShader = @
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"struct U { float4 pic; float4 a; float4 b; };\n"   // pic: the picture's corners in clip space; a: its size in pixels, CRT strength, scanline rows; b: pass, filter, sharp
"struct V { float4 pos [[position]]; float2 uv; };\n"
"vertex V vs(uint vid [[vertex_id]], constant U &u [[buffer(0)]]) {\n"
"  float2 c = float2(vid & 1, vid >> 1); V o;\n"
"  o.pos = u.b.x < 0.5 ? float4(c * 2 - 1, 0, 1) : float4(mix(u.pic.xy, u.pic.zw, c), 0, 1);\n"
"  o.uv = float2(c.x, 1 - c.y); return o; }\n"
"fragment float4 fs(V in [[stage_in]], constant U &u [[buffer(0)]], texture2d<float> t [[texture(0)]], sampler lin [[sampler(0)]]) {\n"
"  const float2 src = float2(240, 160);\n"
"  if (u.b.x < 0.5) {\n"   // around the picture: the picture itself, blurred and dimmed
"    float3 s = float3(0);\n"
"    for (int y = -3; y <= 3; y++) for (int x = -3; x <= 3; x++) s += t.sample(lin, in.uv * 0.7 + 0.15 + float2(x, y) * float2(0.02, 0.03)).rgb;\n"
"    return float4(s / 49 * 0.3, 1); }\n"
"  float2 p = in.uv * src, i = floor(p), f = p - i, uv = in.uv;\n"
"  if (u.b.z > 0.5) {\n"   // sharp: whole game pixels, blended only across the one screen pixel where two meet
"    float2 scale = max(u.a.xy / src, float2(1));\n"
"    float2 r = 0.5 - 0.5 / scale, d = f - 0.5;\n"
"    uv = (i + (d - clamp(d, -r, r)) * scale + 0.5) / src; }\n"
"  float3 c = t.sample(lin, uv).rgb;\n"
"  int filter = int(u.b.y + 0.5); float k = u.a.z;\n"
"  if (filter == 3 || filter == 4) {\n"   // CRT: scanlines over the game's rows and a three-colour mask over the screen's pixels
"    float rows = u.a.w > 0.5 ? u.a.w : 1.0;\n"
"    float line = 0.5 - 0.5 * cos(6.2831853 * fract(p.y / rows));\n"
"    float3 mask = float3(0.72); int m = int(in.pos.x) % 3; mask[m] = 1.18;\n"
"    float3 crt = pow(c, float3(1.12)) * mix(0.42, 1.12, line) * mask * 1.22;\n"
"    c = mix(c, crt, k);\n"
"  } else if (filter == 5) {\n"   // LCD: the dark grid between the handheld screen's pixels
"    float2 e = smoothstep(float2(0), float2(0.18), f) * smoothstep(float2(0), float2(0.18), 1 - f);\n"
"    c *= mix(1.0, e.x * e.y * 1.08, k); }\n"
"  return float4(c, 1); }\n";

typedef struct { float pic[4], a[4], b[4]; } Uniforms;
static id<MTLDevice> g_dev; static id<MTLCommandQueue> g_queue; static id<MTLRenderPipelineState> g_pipe; static id<MTLTexture> g_tex, g_off; static id<MTLSamplerState> g_lin;
static CAMetalLayer *g_layer;
static uint8_t g_rgba[GW * GH * 4];

static BOOL metal_start(void) {
    g_dev = MTLCreateSystemDefaultDevice(); if (!g_dev) return NO;
    g_queue = [g_dev newCommandQueue];
    NSError *err = nil; id<MTLLibrary> lib = [g_dev newLibraryWithSource:kShader options:nil error:&err];
    if (!lib) { LOG("the picture's shader did not compile: %s", err.localizedDescription.UTF8String); return NO; }
    MTLRenderPipelineDescriptor *d = [MTLRenderPipelineDescriptor new];
    d.vertexFunction = [lib newFunctionWithName:@"vs"]; d.fragmentFunction = [lib newFunctionWithName:@"fs"]; d.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    g_pipe = [g_dev newRenderPipelineStateWithDescriptor:d error:&err]; if (!g_pipe) return NO;
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:GW height:GH mipmapped:NO];
    g_tex = [g_dev newTextureWithDescriptor:td];
    MTLSamplerDescriptor *sd = [MTLSamplerDescriptor new]; sd.minFilter = sd.magFilter = MTLSamplerMinMagFilterLinear; sd.sAddressMode = sd.tAddressMode = MTLSamplerAddressModeClampToEdge;
    g_lin = [g_dev newSamplerStateWithDescriptor:sd];
    return YES;
}
// Where the picture goes in a W x H target (pixels), by the Picture size setting, left of the sidebar's share
static void picture_rect(double W, double H, double *x, double *y, double *w, double *h) {
    double aw = W * (1 - g_inset), s = fmin(aw / GW, H / GH);
    if (g_scale == DM_PSCALE_INTEGER) s = fmax(floor(s), 1);
    *w = GW * s; *h = GH * s;
    if (g_scale == DM_PSCALE_STRETCH) { *w = aw; *h = H; }
    *x = floor((aw - *w) / 2); *y = floor((H - *h) / 2);
}
static void draw_into(id<MTLCommandBuffer> cb, id<MTLTexture> target) {
    double W = target.width, H = target.height, x, y, w, h; picture_rect(W, H, &x, &y, &w, &h);
    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor new];
    rp.colorAttachments[0].texture = target; rp.colorAttachments[0].loadAction = MTLLoadActionClear; rp.colorAttachments[0].storeAction = MTLStoreActionStore;
    rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
    [e setRenderPipelineState:g_pipe]; [e setFragmentTexture:g_tex atIndex:0]; [e setFragmentSamplerState:g_lin atIndex:0];
    Uniforms u = {{(float)(x / W * 2 - 1), (float)(1 - (y + h) / H * 2), (float)((x + w) / W * 2 - 1), (float)(1 - y / H * 2)},
                  {(float)w, (float)h, g_strength, (float)g_scan}, {0, (float)g_filter, g_pixel != DM_PIXEL_OFF, 0}};
    if (g_border != DM_PBORDER_OFF && (w < W - 1 || h < H - 1)) {
        [e setVertexBytes:&u length:sizeof u atIndex:0]; [e setFragmentBytes:&u length:sizeof u atIndex:0];
        [e drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    }
    u.b[0] = 1;
    [e setVertexBytes:&u length:sizeof u atIndex:0]; [e setFragmentBytes:&u length:sizeof u atIndex:0];
    [e drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [e endEncoding];
}
static void present(void) {   // the game thread
    [g_tex replaceRegion:MTLRegionMake2D(0, 0, GW, GH) mipmapLevel:0 withBytes:g_rgba bytesPerRow:GW * 4];
    if (g_snapshot) { present_counted(); return; }
    @autoreleasepool {
        CGSize want = CGSizeMake(g_dw, g_dh);
        if (!CGSizeEqualToSize(g_layer.drawableSize, want)) g_layer.drawableSize = want;
        id<CAMetalDrawable> dr = [g_layer nextDrawable]; if (!dr) return;
        id<MTLCommandBuffer> cb = [g_queue commandBuffer];
        draw_into(cb, dr.texture);
        [cb presentDrawable:dr]; [cb commit];
    }
    present_counted();
}
// The window's picture as it would be presented, w x h pixels (BGRA): the same pass, into a texture
static NSData *picture_pixels(int w, int h) {
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:w height:h mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead; td.storageMode = MTLStorageModeShared;
    g_off = [g_dev newTextureWithDescriptor:td];
    id<MTLCommandBuffer> cb = [g_queue commandBuffer]; draw_into(cb, g_off); [cb commit]; [cb waitUntilCompleted];
    NSMutableData *d = [NSMutableData dataWithLength:(NSUInteger)w * h * 4];
    [g_off getBytes:d.mutableBytes bytesPerRow:w * 4 fromRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0];
    return d;
}
static CGImageRef image_from(NSData *d, int w, int h, BOOL bgra) {
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGDataProviderRef p = CGDataProviderCreateWithCFData((__bridge CFDataRef)d);
    CGImageRef img = CGImageCreate(w, h, 8, 32, w * 4, cs, (bgra ? kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst : kCGBitmapByteOrder32Big | kCGImageAlphaNoneSkipLast), p, NULL, false, kCGRenderingIntentDefault);
    CGDataProviderRelease(p); CGColorSpaceRelease(cs);
    return img;
}
static BOOL png_write(CGImageRef img, NSString *path) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:img];
    return [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}

// ---- sound ----
static AudioUnit g_au;
static OSStatus audio_cb(void *ctx, AudioUnitRenderActionFlags *fl, const AudioTimeStamp *ts, UInt32 bus, UInt32 n, AudioBufferList *io) {
    (void)ctx; (void)fl; (void)ts; (void)bus;
    nxgba_audio_render(g, io->mBuffers[0].mData, (int32_t)n, 48000);
    return noErr;
}
static void audio_apply(void) {   // the volume and the Sound switches, as saved
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    float v = [d objectForKey:opt_key(@"volume")] ? [d floatForKey:opt_key(@"volume")] : 1;
    if ([d boolForKey:opt_key(@"muted")]) v = 0;
    if (g_open && !g_peek && [d boolForKey:opt_key(@"duckOpen")]) v *= 0.25f;
    nxgba_audio_set(g, opt_bool(@"gbaEnhanced", YES), opt_bool(@"gbaBass", NO), opt_bool(@"gbaWide", NO), v);
}
static void audio_start(void) {
    AudioComponentDescription cd = {kAudioUnitType_Output, kAudioUnitSubType_DefaultOutput, kAudioUnitManufacturer_Apple, 0, 0};
    AudioComponent c = AudioComponentFindNext(NULL, &cd);
    if (!c || AudioComponentInstanceNew(c, &g_au) != noErr) { LOG("no sound device"); return; }
    AudioStreamBasicDescription f = {48000, kAudioFormatLinearPCM, kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, 8, 1, 8, 2, 32, 0};
    AudioUnitSetProperty(g_au, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &f, sizeof f);
    AURenderCallbackStruct cb = {audio_cb, NULL};
    AudioUnitSetProperty(g_au, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &cb, sizeof cb);
    if (AudioUnitInitialize(g_au) != noErr || AudioOutputUnitStart(g_au) != noErr) { LOG("the sound device did not start"); g_au = NULL; return; }
    nxgba_audio_consumer(g, 1);
}

// ---- the game thread ----
static NSString *g_script;   // NXGBA_SNAPSHOT_INPUT: "frame:keys frame:keys …" (keys as the letters of A B S(elect) T(start) R L U D < >, or - for none)
static uint32_t script_keys(uint64_t frame) {
    static NSArray<NSArray *> *steps;
    if (!steps) { NSMutableArray *a = [NSMutableArray array];
        for (NSString *s in [g_script componentsSeparatedByString:@" "]) { NSArray *kv = [s componentsSeparatedByString:@":"]; if (kv.count == 2) [a addObject:kv]; }
        steps = a; }
    uint32_t k = 0;
    for (NSArray *kv in steps) {
        if ((uint64_t)[kv[0] longLongValue] > frame) break;
        k = 0; NSString *s = kv[1];
        for (NSUInteger i = 0; i < s.length; i++) switch ([s characterAtIndex:i]) {
            case 'A': k |= NXGBA_A; break; case 'B': k |= NXGBA_B; break; case 'S': k |= NXGBA_SELECT; break; case 'T': k |= NXGBA_START; break;
            case 'R': k |= NXGBA_R; break; case 'L': k |= NXGBA_L; break; case 'U': k |= NXGBA_UP; break; case 'D': k |= NXGBA_DOWN; break;
            case '<': k |= NXGBA_LEFT; break; case '>': k |= NXGBA_RIGHT; break; }
    }
    return k;
}
static _Atomic uint64_t g_frames;
static void *game_thread(void *ctx) {
    (void)ctx; pthread_setname_np("nxgba game");
    const double period = 1.0 / 59.7275;
    double next = now_s();
    while (!g_quit) {
        if (!g_paused) {
            int n = g_fast ? 4 : 1;
            pthread_mutex_lock(&g_mu);
            for (int i = 0; i < n; i++) {
                nxgba_keys(g, g_script ? script_keys(g_frames) : (g_open && !g_peek ? 0 : g_keys_kb | g_keys_pad));
                nxgba_run_frame(g); g_frames++;
            }
            nxgba_rgba(g, g_rgba, (uint32_t)g_colour);
            pthread_mutex_unlock(&g_mu);
        }
        present();
        if (g_snapshot) { if (g_paused) usleep(2000); continue; }   // as fast as it goes: nobody is watching
        // 59.73 frames a second, leaning a little on how much sound is waiting so the device never runs dry or behind
        double lean = 0;
        if (g_au && !g_paused) { double fill = nxgba_audio_fill(g), want = nxgba_audio_target(); lean = fmax(-1, fmin(1, (fill - want) / want)) * 0.006; }
        next += period * (1 + lean);
        double t = now_s();
        if (next < t - period * 4) next = t;
        if (next > t) { struct timespec ts = {0, (long)((next - t) * 1e9)}; nanosleep(&ts, NULL); }
    }
    return NULL;
}

// ---- cheats: <root>/cheats/<game code>.txt, the switches beside it ----
static NSString *cheats_dir(void) { return [g_root stringByAppendingPathComponent:@"cheats"]; }
static NSString *cheats_file(void) { return [cheats_dir() stringByAppendingFormat:@"/%@.txt", g_code]; }
static int g_cheats_found;
static void cheats_load(void) {
    NSString *text = [NSString stringWithContentsOfFile:cheats_file() encoding:NSUTF8StringEncoding error:nil] ?: [NSString stringWithContentsOfFile:cheats_file() encoding:NSISOLatin1StringEncoding error:nil];
    g_cheats_found = text != nil;
    NSArray *on = [[NSString stringWithContentsOfFile:[cheats_file() stringByAppendingString:@".enabled"] encoding:NSUTF8StringEncoding error:nil] componentsSeparatedByString:@"\n"] ?: @[];
    pthread_mutex_lock(&g_mu);
    int n = nxgba_cheats_load(g, (text ?: @"").UTF8String);
    for (int i = 0; i < n; i++) nxgba_cheat_set(g, i, [on containsObject:@(nxgba_cheat_text(g, i, 0))]);
    pthread_mutex_unlock(&g_mu);
}
static void cheats_keep(void) {
    NSMutableArray *on = [NSMutableArray array];
    pthread_mutex_lock(&g_mu);
    for (int i = 0, n = nxgba_cheat_count(g); i < n; i++) if (nxgba_cheat_on(g, i)) [on addObject:@(nxgba_cheat_text(g, i, 0))];
    pthread_mutex_unlock(&g_mu);
    [[on componentsJoinedByString:@"\n"] writeToFile:[cheats_file() stringByAppendingString:@".enabled"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
static const char *keep(NSString *s) { static NSString *held[8]; static int at; held[at = (at + 1) % 8] = s ?: @""; return held[at].UTF8String; }
int dm_cheats_found(void) { return g_cheats_found; }
int dm_cheats_ncheats(void) { return nxgba_cheat_count(g); }
const char *dm_cheats_build(void) { return keep(g_code); }
const char *dm_cheats_version(void) { return ""; }
const char *dm_cheats_dir_path(void) { return keep(cheats_dir()); }
int dm_cheats_nothers(void) { return 0; }
const char *dm_cheat_name_at(int i) { pthread_mutex_lock(&g_mu); NSString *s = @(nxgba_cheat_text(g, i, 0)); pthread_mutex_unlock(&g_mu); return keep(s); }
const char *dm_cheat_why_at(int i) { pthread_mutex_lock(&g_mu); NSString *s = @(nxgba_cheat_text(g, i, 1)); pthread_mutex_unlock(&g_mu); return keep(s); }
const char *dm_cheat_note_at(int i) { (void)i; return ""; }
int dm_cheat_kind_at(int i) { return *dm_cheat_why_at(i) ? 2 : 0; }
int dm_cheat_on_at(int i) { return nxgba_cheat_on(g, i); }
int dm_cheat_flags_at(int i) { (void)i; return 0; }
const char *dm_cheat_section_at(int i) { (void)i; return ""; }
void dm_cheat_toggle(int i) { pthread_mutex_lock(&g_mu); nxgba_cheat_set(g, i, !nxgba_cheat_on(g, i)); pthread_mutex_unlock(&g_mu); cheats_keep(); }
void dm_cheats_reload(void) { cheats_load(); }
int dm_cheats_master(void) { return 1; }
void dm_cheats_master_set(int on) { (void)on; }
int dm_cheats_safe(void) { return 0; }
void dm_cheats_safe_restore(void) {}

// ---- the save, save states, reset ----
static NSString *save_dir(void) { return [g_root stringByAppendingPathComponent:@"save"]; }
int dm_fs_clone_committed(const char *dir, const char *to) {   // the sidebar's save backups and slots: the cartridge save, written out first
    pthread_mutex_lock(&g_mu); nxgba_save_flush(g); pthread_mutex_unlock(&g_mu);
    return clonefile(dir, to, 0);
}
static void state_do(int slot, int load) {
    pthread_mutex_lock(&g_mu);
    int ok = load ? nxgba_state_load(g, slot) : nxgba_state_save(g, slot);
    if (ok && load) nxgba_rgba(g, g_rgba, (uint32_t)g_colour);
    pthread_mutex_unlock(&g_mu);
    toast(load ? (ok ? [NSString stringWithFormat:@"State %d loaded", slot] : [NSString stringWithFormat:@"State %d is empty", slot])
               : (ok ? [NSString stringWithFormat:@"State %d saved (kept until you quit the game)", slot] : @"The state could not be saved"));
    if (g_open) dm_qs_refresh();
}
int front_qs_gba(void) { return 1; }
int front_qs_gba_state(int slot, int op) {
    if (op == 0) { pthread_mutex_lock(&g_mu); int has = nxgba_state_has(g, slot); pthread_mutex_unlock(&g_mu); return has; }
    state_do(slot, op == 2); return 1;
}
static NSString *const kGbaOpt[] = {@"gbaEnhanced", @"gbaBass", @"gbaWide", @"gbaColour"};
int front_qs_gba_opt(int which) { return which >= 0 && which < 4 ? opt_bool(kGbaOpt[which], which == 0) : 0; }
void front_qs_gba_opt_set(int which, int on) {
    if (which < 0 || which > 3) return;
    [NSUserDefaults.standardUserDefaults setBool:on != 0 forKey:opt_key(kGbaOpt[which])];
    if (which == 3) { g_colour = on != 0; front_qs_live_changed(); } else audio_apply();
}
const char *front_qs_gba_sound(void) { pthread_mutex_lock(&g_mu); NSString *s = @(nxgba_text(g, 4)); pthread_mutex_unlock(&g_mu); return keep(s); }

// ---- the sidebar's player side (quick_settings_mac.h) ----
static NSString *capture_dir(int video) {
    NSString *own = [NSUserDefaults.standardUserDefaults stringForKey:opt_key(@"captureDir")];
    const char *gf = getenv("DM_GAME_FOLDER");
    NSString *base = own.length ? own : gf && *gf ? @(gf) : g_root;
    return own.length ? own : [base stringByAppendingPathComponent:video ? @"Recordings" : @"Screenshots"];
}
void front_qs_screenshot(void) {
    NSString *dir = capture_dir(0); [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"yyyy-MM-dd 'at' HH.mm.ss";
    NSString *path = [dir stringByAppendingFormat:@"/%@ %@.png", [g_name stringByReplacingOccurrencesOfString:@"/" withString:@"-"], [f stringFromDate:NSDate.date]];
    float inset = g_inset; g_inset = 0; int sc = g_scale; g_scale = DM_PSCALE_FIT;
    NSData *d = picture_pixels(GW * 6, GH * 6); g_inset = inset; g_scale = sc;
    CGImageRef img = image_from(d, GW * 6, GH * 6, YES); BOOL ok = png_write(img, path); CGImageRelease(img);
    toast(ok ? [NSString stringWithFormat:@"Screenshot saved to %@ › %@", dir.stringByDeletingLastPathComponent.lastPathComponent, dir.lastPathComponent] : @"The screenshot could not be saved");
    dm_qs_captures_changed();
}
void front_qs_record(void) { toast(@"Recording is not in Game Boy Advance games yet"); }
int front_qs_recording(void) { return 0; }
int front_qs_replay(void) { return 0; }
void front_qs_replay_set(int on) { if (on) toast(@"Instant replay is not in Game Boy Advance games yet"); }
void front_qs_replay_save(void) { toast(@"Instant replay is not in Game Boy Advance games yet"); }
int front_qs_can_restart(void) { return 1; }
void front_qs_restart(void) { pthread_mutex_lock(&g_mu); nxgba_reset(g); pthread_mutex_unlock(&g_mu); toast(@"Game restarted"); }
const char *front_qs_capture_folder(int video) { return keep(capture_dir(video)); }
int front_qs_capture_custom(void) { return [NSUserDefaults.standardUserDefaults stringForKey:opt_key(@"captureDir")].length > 0; }
void front_qs_capture_folder_set(const char *dir) {
    if (dir && *dir) [NSUserDefaults.standardUserDefaults setObject:@(dir) forKey:opt_key(@"captureDir")]; else [NSUserDefaults.standardUserDefaults removeObjectForKey:opt_key(@"captureDir")];
}
void front_qs_assign(int action, int pad) { (void)action; (void)pad; }
int front_qs_assigning(void) { return -1; }
void front_qs_controls_reload(void) {}
static GCController *pad_now(void) { for (GCController *c in GCController.controllers) if (c.extendedGamepad) return c; return nil; }
int front_qs_player(int p, char *name, int cap) {
    GCController *c = p == 0 ? pad_now() : nil; if (!c) return 0;
    if (name && cap > 0) snprintf(name, (size_t)cap, "%s", (c.vendorName ?: @"Controller").UTF8String);
    return 2;
}
int front_qs_player_swap(int a, int b) { (void)a; (void)b; return 0; }
static void set_paused(int on) { g_paused = on; if (g_au) { if (on) AudioOutputUnitStop(g_au); else AudioOutputUnitStart(g_au); } }
int front_qs_paused(void) { return g_paused; }
static void sidebar_toggle(void);
void front_qs_pause_set(int on) { [NSUserDefaults.standardUserDefaults setBool:on != 0 forKey:opt_key(@"pauseOpen")]; if (g_open && !g_peek) set_paused(on != 0); }
void front_qs_suspend(void) { if (!g_open) sidebar_toggle(); set_paused(1); }
void front_qs_volume_apply(void) { audio_apply(); }
int front_qs_fullscreen(void) { return (g_win.styleMask & NSWindowStyleMaskFullScreen) != 0; }
void front_qs_fullscreen_toggle(void) { [g_win toggleFullScreen:nil]; }
const char *front_qs_settings_path(void) { return ""; }
const char *front_qs_defaults_path(void) { return ""; }
int front_qs_defaults_exist(void) { return 0; }
void front_qs_defaults_save(void) { toast(@"My defaults are not in Game Boy Advance games yet"); }
void front_qs_defaults_use(void) {}
const char *front_qs_title_id(void) { return keep(g_id); }
void front_qs_toast_text(const char *msg) { toast(@(msg)); }
void front_qs_settings_reapply(void);
void front_qs_live_changed(void) {}   // a paused game's picture is drawn again at every refresh as it is

// The saved settings put to work: at launch, and after the sidebar put several back at once
static void settings_apply(void) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    g_pixel = [d objectForKey:opt_key(@"pixel")] ? (int)[d integerForKey:opt_key(@"pixel")] : DM_PIXEL_AUTO;
    g_scale = [d objectForKey:opt_key(@"scale")] ? (int)[d integerForKey:opt_key(@"scale")] : DM_PSCALE_FIT;
    g_border = (int)[d integerForKey:opt_key(@"border")];
    int m = (int)[d integerForKey:pfx_key(@"mode")]; if (m != DM_PFX_CRT) m = DM_PFX_OFF;
    g_filter = m; g_strength = [d objectForKey:pfx_key(@"strength")] ? [d floatForKey:pfx_key(@"strength")] : 0.5f;
    g_scan = (int)[d integerForKey:pfx_key(@"scanline")];
    g_colour = opt_bool(@"gbaColour", NO);
    audio_apply();
}
void front_qs_settings_reapply(void) { settings_apply(); }

// The frame-rate counter: the frames shown in the last half second, in the corner the sidebar chose
static NSTextField *g_fps_label; static NSTimer *g_fps_timer;
static void fps_counter(void) {
    BOOL on = opt_bool(@"fps", NO);
    [g_fps_timer invalidate]; g_fps_timer = nil;
    if (!on) { [g_fps_label removeFromSuperview]; g_fps_label = nil; return; }
    if (!g_fps_label) {
        g_fps_label = [NSTextField labelWithString:@""]; g_fps_label.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightSemibold];
        g_fps_label.textColor = NSColor.whiteColor; g_fps_label.drawsBackground = YES; g_fps_label.backgroundColor = [NSColor colorWithWhite:0 alpha:0.55];
        [g_view addSubview:g_fps_label];
    }
    __block uint64_t n0 = g_presents; __block double t0 = now_s();
    void (^tick)(NSTimer *) = ^(NSTimer *t) {
        (void)t; double t1 = now_s(); uint64_t n1 = g_presents;
        g_fps_label.stringValue = [NSString stringWithFormat:@" %.0f fps ", (double)(n1 - n0) / fmax(t1 - t0, 1e-3)]; n0 = n1; t0 = t1;
        [g_fps_label sizeToFit];
        int c = (int)MIN(MAX([NSUserDefaults.standardUserDefaults integerForKey:opt_key(@"fpsPos")], 0), 3); NSSize s = g_fps_label.frame.size, b = g_view.bounds.size;
        CGFloat w = b.width * (1 - g_inset);
        [g_fps_label setFrameOrigin:NSMakePoint(c & 1 ? w - s.width - 10 : 10, c & 2 ? 10 : b.height - s.height - 10)];
    };
    g_fps_timer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:tick]; tick(nil);
}

// The sidebar: made at the first opening, 460 points down the window's right; the picture moves aside for it
static void inset_for(BOOL open) { CGFloat W = g_view.bounds.size.width, w = MIN(460, W); g_inset = open && w < W ? (float)(w / W) : 0; }
static void sidebar_close(void) { if (g_open) sidebar_toggle(); }
static void sidebar_toggle(void) {
    if (!g_open) {
        if (!g_side) {
            NSString *mods = [g_root stringByAppendingPathComponent:@"mods"];
            g_side = (__bridge_transfer NSView *)dm_qs_make(g_name.UTF8String, mods.fileSystemRepresentation, NULL, sidebar_close, fps_counter);
            g_side.autoresizingMask = NSViewMinXMargin | NSViewHeightSizable;
        }
        CGFloat W = g_view.bounds.size.width, w = MIN(460, W);
        g_side.frame = NSMakeRect(W - w, 0, w, g_view.bounds.size.height);
        dm_qs_opened(g_open_by_pad); dm_qs_refresh();
        [g_view addSubview:g_side]; g_open = 1; inset_for(YES);
        g_keys_kb = 0; audio_apply();
        if (opt_bool(@"pauseOpen", YES)) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 80 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ if (g_open && !g_peek) { set_paused(1); dm_qs_refresh(); } });
    } else {
        set_paused(0);
        if (g_peek) { g_peek = 0; g_side.alphaValue = 1; dm_qs_peeked(0); }
        [g_side removeFromSuperview]; g_open = 0; inset_for(NO); audio_apply();
        [g_win makeFirstResponder:g_view];
    }
}
void front_qs_peek(int on) {
    if (!g_open || (on != 0) == g_peek) return;
    g_peek = on != 0; g_side.animator.alphaValue = on ? 0 : 1; inset_for(!on); audio_apply();
    set_paused(!on && opt_bool(@"pauseOpen", YES));
    dm_qs_peeked(on);
}

// ---- keyboard and controller ----
static uint32_t key_bit(unsigned short code) {
    switch (code) {
        case 123: case 0: return NXGBA_LEFT; case 124: case 2: return NXGBA_RIGHT; case 126: case 13: return NXGBA_UP; case 125: case 1: return NXGBA_DOWN;
        case 38: case 7: return NXGBA_A;   // J, X
        case 40: case 6: return NXGBA_B;   // K, Z
        case 12: return NXGBA_L; case 14: return NXGBA_R;   // Q, E
        case 36: return NXGBA_START; case 48: case 51: return NXGBA_SELECT;   // Return; Tab, Delete
    }
    return 0;
}
static BOOL typing(void) { return [g_win.firstResponder isKindOfClass:NSTextView.class]; }   // the cheats' search field
static NSEvent *key_event(NSEvent *e) {
    BOOL down = e.type == NSEventTypeKeyDown; unsigned short c = e.keyCode;
    if (e.modifierFlags & NSEventModifierFlagCommand) return e;   // the menus' shortcuts
    if (g_open) {
        if (typing() && c != 53) return e;
        if (c == 35) { if (!e.isARepeat) front_qs_peek(down); return nil; }   // P held: a peek
        if (!down) return nil;
        int cmd = c == 126 ? 1 : c == 125 ? 2 : c == 123 ? 3 : c == 124 ? 4 : c == 36 || c == 49 ? 5 : c == 53 ? 6 : c == 48 ? (e.modifierFlags & NSEventModifierFlagShift ? 7 : 8) : 0;
        if (cmd) { g_open_by_pad = 0; dm_qs_input(0, NULL, NULL, NULL, NULL); dm_qs_nav(cmd); }
        return nil;
    }
    if (c == 53) { if (down && !e.isARepeat) { g_open_by_pad = 0; sidebar_toggle(); } return nil; }
    if (c == 49) { g_fast = down; return nil; }   // Space held: four times the speed
    uint32_t b = key_bit(c); if (!b) return e;
    if (down) g_keys_kb |= b; else g_keys_kb &= ~b;
    return nil;
}
static void pad_poll(void) {   // main thread, 120 times a second
    static uint32_t was; static double held_since, last_rep;
    GCExtendedGamepad *p = pad_now().extendedGamepad;
    uint32_t k = 0, nav = 0;
    if (p) {
        float x = p.leftThumbstick.xAxis.value, y = p.leftThumbstick.yAxis.value;
        if (p.buttonB.pressed) k |= NXGBA_A;   // the right face button, where the handheld's A is
        if (p.buttonA.pressed) k |= NXGBA_B;
        if (p.leftShoulder.pressed || p.leftTrigger.pressed) k |= NXGBA_L;
        if (p.rightShoulder.pressed || p.rightTrigger.pressed) k |= NXGBA_R;
        if (p.buttonMenu.pressed) k |= NXGBA_START;
        if (p.buttonOptions.pressed) k |= NXGBA_SELECT;
        if (p.dpad.left.pressed || x < -0.5f) k |= NXGBA_LEFT;
        if (p.dpad.right.pressed || x > 0.5f) k |= NXGBA_RIGHT;
        if (p.dpad.up.pressed || y > 0.5f) k |= NXGBA_UP;
        if (p.dpad.down.pressed || y < -0.5f) k |= NXGBA_DOWN;
        if (p.leftThumbstickButton.pressed || p.buttonHome.pressed) nav |= 1 << 16;   // the sidebar
        if (p.buttonY.pressed) nav |= 1 << 17;                                        // the top face button: peek
        if (!g_open) g_fast = p.rightThumbstickButton.pressed || (g_fast && !p);
    }
    uint32_t all = k | nav, pressed = all & ~was; was = all;
    if (!g_open) { g_keys_pad = k; if (pressed & (1 << 16)) { g_open_by_pad = 1; sidebar_toggle(); } return; }
    g_keys_pad = 0;
    if (pressed & (1 << 16)) { sidebar_toggle(); return; }
    if ((all ^ (all & ~(1u << 17))) != 0 || g_peek) { int on = (all >> 17) & 1; if (on != g_peek) front_qs_peek(on); }
    if (pressed) dm_qs_input(1, "b.circle", "a.circle", "l1.rectangle.roundedbottom", "r1.rectangle.roundedbottom");
    double t = now_s(); uint32_t dirs = k & (NXGBA_UP | NXGBA_DOWN | NXGBA_LEFT | NXGBA_RIGHT), go = pressed;
    if (dirs && !(pressed & dirs)) { if (t - held_since > 0.4 && t - last_rep > 0.09) { go |= dirs; last_rep = t; } } else held_since = t;
    if (go & NXGBA_UP) dm_qs_nav(1); else if (go & NXGBA_DOWN) dm_qs_nav(2); else if (go & NXGBA_LEFT) dm_qs_nav(3); else if (go & NXGBA_RIGHT) dm_qs_nav(4);
    if (pressed & NXGBA_A) dm_qs_nav(5); else if (pressed & (NXGBA_B | NXGBA_START)) dm_qs_nav(6);
    if (pressed & NXGBA_L) dm_qs_nav(7); else if (pressed & NXGBA_R) dm_qs_nav(8);
}

// ---- the window ----
@interface GameView : NSView
@end
@implementation GameView
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)wantsUpdateLayer { return YES; }
- (CALayer *)makeBackingLayer { g_layer = [CAMetalLayer layer]; g_layer.device = g_dev; g_layer.pixelFormat = MTLPixelFormatBGRA8Unorm; g_layer.framebufferOnly = YES; g_layer.backgroundColor = NSColor.blackColor.CGColor; return g_layer; }
- (void)sized { NSSize s = [self convertSizeToBacking:self.bounds.size]; g_dw = MAX((int)s.width, 1); g_dh = MAX((int)s.height, 1); if (g_open && !g_peek) inset_for(YES); }
- (void)setFrameSize:(NSSize)s { [super setFrameSize:s]; [self sized]; }
- (void)viewDidChangeBackingProperties { [super viewDidChangeBackingProperties]; g_layer.contentsScale = self.window.backingScaleFactor; [self sized]; }
- (void)keyDown:(NSEvent *)e { (void)e; }
- (void)keyUp:(NSEvent *)e { (void)e; }
@end
@interface OffscreenWindow : NSWindow
@end
@implementation OffscreenWindow
- (NSRect)constrainFrameRect:(NSRect)r toScreen:(NSScreen *)s { (void)s; return r; }
@end

@interface App : NSObject <NSApplicationDelegate, NSWindowDelegate>
@end
@implementation App
- (void)state:(NSMenuItem *)it { state_do((int)(it.tag % 10), it.tag >= 10); }
- (void)sidebar:(id)s { (void)s; g_open_by_pad = 0; sidebar_toggle(); }
- (void)shot:(id)s { (void)s; front_qs_screenshot(); }
- (void)restart:(id)s { (void)s; front_qs_restart(); }
- (void)full:(id)s { (void)s; front_qs_fullscreen_toggle(); }
- (void)windowDidResignKey:(NSNotification *)n { (void)n; g_keys_kb = 0; g_fast = 0; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)a { (void)a; return YES; }
- (void)applicationWillTerminate:(NSNotification *)n {
    (void)n; static int done; if (done) return; done = 1;
    g_quit = 1; set_paused(0); if (g_au) { AudioOutputUnitStop(g_au); }
    pthread_mutex_lock(&g_mu);
    nxgba_info i; nxgba_get_info(g, &i);
    // what this run did, for NXForge's Port details page
    NSDictionary *run = @{@"frames": @(i.frames), @"nativeBlocks": @(i.native_blocks), @"fallbackSteps": @(i.fallback_steps), @"missesRom": @(i.misses_rom), @"missesRam": @(i.misses_ram),
                          @"blocks": @(i.blocks), @"ended": @((long long)NSDate.date.timeIntervalSince1970)};
    [[NSJSONSerialization dataWithJSONObject:run options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[g_root stringByAppendingPathComponent:@"last-run.json"] atomically:YES];
    nxgba_close(g);   // writes the save, and the entry points this run found that the conversion missed
    pthread_mutex_unlock(&g_mu);
}
@end

static void menus(App *app) {
    NSMenu *bar = [NSMenu new];
    NSMenu *am = [NSMenu new]; NSMenuItem *ai = [bar addItemWithTitle:@"" action:nil keyEquivalent:@""]; ai.submenu = am;
    [am addItemWithTitle:[@"Hide " stringByAppendingString:g_name] action:@selector(hide:) keyEquivalent:@"h"];
    [am addItemWithTitle:[@"Quit " stringByAppendingString:g_name] action:@selector(terminate:) keyEquivalent:@"q"];
    NSMenu *gm = [[NSMenu alloc] initWithTitle:@"Game"]; NSMenuItem *gi = [bar addItemWithTitle:@"Game" action:nil keyEquivalent:@""]; gi.submenu = gm;
    NSMenuItem *it;
    it = [gm addItemWithTitle:@"Sidebar" action:@selector(sidebar:) keyEquivalent:@"g"]; it.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift; it.target = app;
    it = [gm addItemWithTitle:@"Screenshot" action:@selector(shot:) keyEquivalent:@"s"]; it.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift; it.target = app;
    it = [gm addItemWithTitle:@"Full Screen" action:@selector(full:) keyEquivalent:@"f"]; it.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl; it.target = app;
    [gm addItem:NSMenuItem.separatorItem];
    for (int load = 0; load < 2; load++) for (int n = 1; n <= 3; n++) {
        it = [gm addItemWithTitle:[NSString stringWithFormat:load ? @"Load State %d" : @"Save State %d", n] action:@selector(state:) keyEquivalent:[NSString stringWithFormat:@"%d", n]];
        it.keyEquivalentModifierMask = NSEventModifierFlagCommand | (load ? NSEventModifierFlagOption : 0); it.tag = load * 10 + n; it.target = app;
    }
    [gm addItem:NSMenuItem.separatorItem];
    it = [gm addItemWithTitle:@"Restart Game" action:@selector(restart:) keyEquivalent:@"r"]; it.target = app;
    NSApp.mainMenu = bar;
}

// NXGBA_SNAPSHOT: the window's picture with the sidebar over it, into a PNG, and quit
static void snapshot(NSString *out, uint64_t frames) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        while (g_frames < frames) usleep(5000);
        dispatch_async(dispatch_get_main_queue(), ^{
            const char *page = getenv("NXGBA_SNAPSHOT_SIDEBAR");
            if (getenv("NXGBA_SNAPSHOT_STATE")) { state_do(1, 0); }
            if (page) { [NSUserDefaults.standardUserDefaults setInteger:atoi(page) forKey:[@"DMQuickSettings.page." stringByAppendingString:g_name]]; sidebar_toggle(); }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSSize sz = g_view.bounds.size; int w = (int)sz.width * 2, h = (int)sz.height * 2;
                NSData *d = picture_pixels(w, h); CGImageRef pic = image_from(d, w, h, YES);
                NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                         colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
                rep.size = sz;
                NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
                [NSGraphicsContext saveGraphicsState]; NSGraphicsContext.currentContext = gc;
                CGContextDrawImage(gc.CGContext, CGRectMake(0, 0, sz.width, sz.height), pic);
                [NSGraphicsContext restoreGraphicsState]; CGImageRelease(pic);
                if (g_open) {
                    NSBitmapImageRep *side = [g_side bitmapImageRepForCachingDisplayInRect:g_side.bounds]; [g_side cacheDisplayInRect:g_side.bounds toBitmapImageRep:side];
                    [NSGraphicsContext saveGraphicsState]; NSGraphicsContext.currentContext = gc;
                    [side drawInRect:g_side.frame fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:NO hints:nil];
                    [NSGraphicsContext restoreGraphicsState];
                }
                BOOL ok = [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:out atomically:YES];
                pthread_mutex_lock(&g_mu); nxgba_info i; nxgba_get_info(g, &i); pthread_mutex_unlock(&g_mu);
                printf("{\"snapshot\": %s, \"frames\": %llu, \"native_blocks\": %llu, \"fallback_steps\": %llu, \"paused\": %d, \"state\": %d}\n", ok ? "true" : "false",
                       (unsigned long long)i.frames, (unsigned long long)i.native_blocks, (unsigned long long)i.fallback_steps, (int)g_paused, front_qs_gba_state(1, 0));
                [NSApp terminate:nil];
            });
        });
    });
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        NSBundle *b = NSBundle.mainBundle; NSDictionary *info = b.infoDictionary ?: @{};
        const char *e;
        NSString *res = [b.resourcePath stringByAppendingPathComponent:@"gba"];
        NSString *rom = (e = getenv("NXGBA_ROM")) ? @(e) : argc > 1 ? @(argv[1]) : [res stringByAppendingPathComponent:@"game.gba"];
        NSString *lib = (e = getenv("NXGBA_LIB")) ? @(e) : argc > 2 ? @(argv[2]) : [res stringByAppendingPathComponent:@"game.dylib"];
        g_name = (e = getenv("NXGBA_NAME")) ? @(e) : info[@"CFBundleName"] ?: rom.lastPathComponent.stringByDeletingPathExtension;
        g_id = (e = getenv("NXGBA_ID")) ? @(e) : info[@"NXForgeTitleID"] ?: @"0BA0000000000000";
        NSString *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject.path;
        g_root = (e = getenv("DM_ROOT")) && *e ? @(e) : [support stringByAppendingFormat:@"/nxnative/%@", g_id];
        NSString *sd = (e = getenv("DM_SAVE")) && *e ? @(e) : save_dir();
        for (NSString *d in @[sd, cheats_dir()]) [NSFileManager.defaultManager createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
        setenv("DM_SAVE", sd.fileSystemRepresentation, 1);   // the sidebar's save backups read it
        setenv("DM_GAME_ID", g_id.UTF8String, 0);
        if (![NSFileManager.defaultManager fileExistsAtPath:lib]) { LOG("no translation at %s: the game runs interpreted", lib.fileSystemRepresentation); lib = nil; }
        char err[512] = "";
        g = nxgba_open(rom.fileSystemRepresentation, lib.fileSystemRepresentation, [sd stringByAppendingPathComponent:@"game.sav"].fileSystemRepresentation, err, sizeof err);
        if (!g) {
            LOG("%s", err);
            if (!getenv("NXGBA_SNAPSHOT")) { [NSApplication sharedApplication]; NSAlert *a = [NSAlert new]; a.messageText = [g_name stringByAppendingString:@" could not start"]; a.informativeText = @(err); [a runModal]; }
            return 1;
        }
        g_code = @(nxgba_text(g, 1)); if (!g_code.length) g_code = @"GAME";
        if ((e = getenv("NXGBA_SNAPSHOT_INPUT"))) g_script = @(e);
        g_snapshot = getenv("NXGBA_SNAPSHOT") != NULL;

        NSApplication *app = [NSApplication sharedApplication]; App *del = [App new]; app.delegate = del;
        [app setActivationPolicy:g_snapshot ? NSApplicationActivationPolicyProhibited : NSApplicationActivationPolicyRegular];
        if (!metal_start()) { LOG("Metal is not available"); return 1; }
        NSRect r = NSMakeRect(0, 0, 1200, 800);
        NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
        g_win = g_snapshot ? [[OffscreenWindow alloc] initWithContentRect:r styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO]
                           : [[NSWindow alloc] initWithContentRect:r styleMask:style backing:NSBackingStoreBuffered defer:NO];
        g_win.title = g_name; g_win.delegate = del; g_win.releasedWhenClosed = NO; g_win.minSize = NSMakeSize(480, 320); g_win.backgroundColor = NSColor.blackColor;
        g_win.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary; g_win.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        g_view = [[GameView alloc] initWithFrame:r]; g_view.wantsLayer = YES; g_win.contentView = g_view;
        settings_apply(); cheats_load();
        if (g_snapshot) { [g_win setFrameOrigin:NSMakePoint(-30000, -30000)]; }
        else {
            menus(del); [g_win center]; [g_win setFrameAutosaveName:[@"NXGBA." stringByAppendingString:g_id]];
            [g_win makeKeyAndOrderFront:nil]; [g_win makeFirstResponder:g_view]; [app activateIgnoringOtherApps:YES];
            [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown | NSEventMaskKeyUp handler:^NSEvent *(NSEvent *ev) { return key_event(ev); }];
            [NSTimer scheduledTimerWithTimeInterval:1 / 120.0 repeats:YES block:^(NSTimer *t) { (void)t; pad_poll(); }];
            audio_start(); audio_apply(); fps_counter();
        }
        pthread_t th; pthread_create(&th, NULL, game_thread, NULL);
        if (g_snapshot) snapshot(@(getenv("NXGBA_SNAPSHOT")), (e = getenv("NXGBA_SNAPSHOT_FRAMES")) ? strtoull(e, NULL, 10) : 600);
        [app run];
    }
    return 0;
}
