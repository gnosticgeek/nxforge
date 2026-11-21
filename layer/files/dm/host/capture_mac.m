// Screenshots and video of the game as it is presented, the present filter included and the sidebar left out (front.h mtl_record_set: the present thread draws each frame once more into
// a texture handed out here). Screenshots: PNG, 16:9 at the window's height in pixels (720 at least). Video: H.264 with AAC sound in a QuickTime movie, 1920x1080 at the game's frame rate,
// the sound from the first audio output (front.h dm_audio_tap_set) before the host volume. Where (capture_folder): a folder the player chose, else Screenshots / Recordings in the game folder
// (DM_GAME_FOLDER, which the app's launcher sets), else ~/Pictures/NXForge / ~/Movies/NXForge. Writing files there needs no permission
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <Metal/Metal.h>
#import <AppKit/AppKit.h>
#import <VideoToolbox/VideoToolbox.h>
#include "dm.h"
#include "front.h"
#include "capture_mac.h"
#include <stdatomic.h>

static NSString *g_folder;   // the player's choice (capture_folder_set), nil: the default
void capture_folder_set(NSString *dir) { g_folder = dir.length ? [dir copy] : nil; }
NSString *capture_folder(int video) {
    if (g_folder) return g_folder;
    const char *g = getenv("DM_GAME_FOLDER");
    if (g && *g) return [@(g) stringByAppendingPathComponent:video ? @"Recordings" : @"Screenshots"];
    NSURL *base = [NSFileManager.defaultManager URLsForDirectory:video ? NSMoviesDirectory : NSPicturesDirectory inDomains:NSUserDomainMask].firstObject;
    return [(base.path ?: NSHomeDirectory()) stringByAppendingPathComponent:@"NXForge"];   // no Pictures / Movies folder: the home folder
}
static NSString *with_ext(NSString *s, NSString *ext) { return [s stringByAppendingPathExtension:ext] ?: s; }   // nil only for an extension it cannot add
static NSString *capture_path(int video, const char *game, NSString *ext) {
    NSString *dir = capture_folder(video) ?: NSHomeDirectory();   // never nil, which clang-tidy cannot see through capture_folder
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"yyyy-MM-dd 'at' HH.mm.ss";
    NSString *name = [[NSString stringWithFormat:@"%s %@", game, [f stringFromDate:NSDate.date]] stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    NSString *p = with_ext([dir stringByAppendingPathComponent:name], ext);
    for (int i = 2; [NSFileManager.defaultManager fileExistsAtPath:p]; i++) p = with_ext([dir stringByAppendingPathComponent:[name stringByAppendingFormat:@" %d", i]], ext);
    return p;
}

// One recording: a pool of IOSurface pixel buffers the present draws into (as Metal textures), an AVAssetWriter with a video and an audio input, a serial queue that feeds it,
// and a ring of the tapped PCM the queue drains
#define RING (48000 * 2 * 4)   // 4 s of 48 kHz stereo
@interface DmRecording : NSObject {
@public
    int16_t ring[RING]; _Atomic uint64_t wpos; uint64_t rpos; _Atomic int ch; _Atomic uint64_t audio_t0;   // ring of interleaved samples (written by the audio thread), its channels and the time of its first sample
}
@property AVAssetWriter *writer; @property AVAssetWriterInput *video, *audio; @property AVAssetWriterInputPixelBufferAdaptor *adaptor;
@property CVMetalTextureCacheRef cache; @property NSMutableDictionary<NSValue *, id> *inflight; @property dispatch_queue_t q; @property dispatch_source_t timer;
@property uint64_t t0, last, audio_frames; @property BOOL started, stopping, single; @property size_t w, h; @property (copy) void (^done)(NSString *, NSString *); @property NSString *path;
@property CMAudioFormatDescriptionRef afmt; @property (copy) void (^shot)(CVPixelBufferRef);
@end
@implementation DmRecording
- (void)dealloc { if (_cache) CFRelease(_cache); if (_afmt) CFRelease(_afmt); }
@end
static DmRecording *g_rec;   // the recording or one-shot screenshot in progress (main thread sets it; the callbacks hold their own reference)

static void *rec_next(void *ctx) {   // present thread: a texture to draw this frame into, or NULL to skip it (no buffer free, or still writing the last ones)
    DmRecording *r = (__bridge DmRecording *)ctx;
    @synchronized (r) { if (r.stopping || r.inflight.count >= 3 || (r.single && r.inflight.count)) return NULL; }
    CVPixelBufferRef pb = NULL;
    CVPixelBufferPoolRef pool = r.adaptor.pixelBufferPool;   // read once: the adaptor makes it when the writer starts, and the property is nullable
    if (pool) CVPixelBufferPoolCreatePixelBuffer(NULL, pool, &pb);
    else { NSDictionary *a = @{(id)kCVPixelBufferMetalCompatibilityKey: @YES, (id)kCVPixelBufferIOSurfacePropertiesKey: @{}};
           CVPixelBufferCreate(NULL, r.w, r.h, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)a, &pb); }
    if (!pb) return NULL;
    CVMetalTextureRef ct = NULL;
    CVMetalTextureCacheCreateTextureFromImage(NULL, r.cache, pb, NULL, MTLPixelFormatBGRA8Unorm, r.w, r.h, 0, &ct);
    id<MTLTexture> tex = ct ? CVMetalTextureGetTexture(ct) : nil;
    if (!tex) { if (ct) CFRelease(ct); CVPixelBufferRelease(pb); return NULL; }
    @synchronized (r) { r.inflight[[NSValue valueWithPointer:(__bridge void *)tex]] = @[(__bridge_transfer id)pb, (__bridge_transfer id)ct, tex]; }   // keeps all three alive until rec_done
    return (__bridge void *)tex;
}
static void rec_done(void *ctx, void *texp, uint64_t ns) {   // GPU completion thread: the frame is drawn; the queue writes it
    DmRecording *r = (__bridge DmRecording *)ctx; NSValue *k = [NSValue valueWithPointer:texp]; NSArray *keep;
    @synchronized (r) { keep = r.inflight[k]; [r.inflight removeObjectForKey:k]; }
    if (!keep) return;
    dispatch_async(r.q, ^{
        CVPixelBufferRef pb = (__bridge CVPixelBufferRef)keep[0];
        if (r.shot) { void (^s)(CVPixelBufferRef) = r.shot; r.shot = nil; s(pb); return; }
        if (r.stopping) return;
        if (!r.started) { r.t0 = ns; [r.writer startSessionAtSourceTime:kCMTimeZero]; r.started = YES; }
        if (ns <= r.last || !r.video.readyForMoreMediaData) return;   // a frame the encoder cannot take now is dropped, not queued: the game must not wait for the file
        r.last = ns;
        [r.adaptor appendPixelBuffer:pb withPresentationTime:CMTimeMake((int64_t)(ns - r.t0), 1000000000)];
    });
}
static void rec_tap(void *ctx, const int16_t *pcm, uint32_t frames, int ch) {   // real-time audio thread: copy into the ring, nothing else
    DmRecording *r = (__bridge DmRecording *)ctx;
    uint64_t t = now_ns(), z = 0; atomic_compare_exchange_strong(&r->audio_t0, &z, t);
    int want = 0; atomic_compare_exchange_strong(&r->ch, &want, ch); if (atomic_load(&r->ch) != ch) return;
    uint64_t w = atomic_load_explicit(&r->wpos, memory_order_relaxed), n = (uint64_t)frames * ch;
    if (n > RING / 2) return;
    for (uint64_t i = 0; i < n; i++) r->ring[(w + i) % RING] = pcm[i];
    atomic_store_explicit(&r->wpos, w + n, memory_order_release);
}
static void rec_drain(DmRecording *r) {   // the queue: the PCM tapped so far into the audio input, timed from the first sample (its place against the video's first frame)
    uint64_t w = atomic_load_explicit(&r->wpos, memory_order_acquire); int ch = atomic_load(&r->ch);
    if (!r.started || !ch || w == r->rpos) return;
    if (w - r->rpos > RING) r->rpos = w - RING;   // fell behind by more than the ring: the oldest is gone
    uint64_t n = w - r->rpos; size_t frames = n / ch;
    if (!r.afmt) {
        AudioStreamBasicDescription d = {.mSampleRate = 48000, .mFormatID = kAudioFormatLinearPCM, .mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                                         .mBytesPerPacket = 2u * ch, .mFramesPerPacket = 1, .mBytesPerFrame = 2u * ch, .mChannelsPerFrame = (UInt32)ch, .mBitsPerChannel = 16};
        CMAudioFormatDescriptionRef f = NULL; CMAudioFormatDescriptionCreate(NULL, &d, 0, NULL, 0, NULL, NULL, &f); r.afmt = f;
    }
    int64_t start = (int64_t)atomic_load(&r->audio_t0) - (int64_t)r.t0;   // ns from the first video frame to the first sample
    int64_t pts = start + (int64_t)(r.audio_frames * 1000000000ull / 48000);
    size_t count = frames * ch, bytes = count * 2, at = r->rpos % RING, first = MIN(count, RING - at); CMBlockBufferRef bb = NULL;
    int16_t *mem = malloc(bytes); if (!mem) return;
    memcpy(mem, r->ring + at, first * 2); memcpy(mem + first, r->ring, (count - first) * 2);   // the ring wraps at most once
    if (CMBlockBufferCreateWithMemoryBlock(NULL, mem, bytes, kCFAllocatorMalloc, NULL, 0, bytes, 0, &bb)) { free(mem); return; }
    r->rpos += frames * ch; r.audio_frames += frames;
    if (pts < 0 || !r.audio.readyForMoreMediaData) { CFRelease(bb); return; }   // sound from before the first frame, or the encoder busy: dropped
    CMSampleBufferRef sb = NULL;
    CMAudioSampleBufferCreateReadyWithPacketDescriptions(NULL, bb, r.afmt, (CMItemCount)frames, CMTimeMake(pts, 1000000000), NULL, &sb);
    if (sb) { [r.audio appendSampleBuffer:sb]; CFRelease(sb); }
    CFRelease(bb);
}

static DmRecording *rec_new(size_t w, size_t h) {
    DmRecording *r = [DmRecording new]; r.w = w; r.h = h; r.inflight = [NSMutableDictionary dictionary];
    r.q = dispatch_queue_create("nxnative.capture", DISPATCH_QUEUE_SERIAL);
    CVMetalTextureCacheRef c = NULL; id<MTLDevice> dev = MTLCreateSystemDefaultDevice();   // the device the graphics backend draws with (nvn_mtl.m takes the system default too)
    if (!dev || CVMetalTextureCacheCreate(NULL, NULL, dev, NULL, &c)) return nil;
    r.cache = c; return r;
}
static void replay_attach(int audio);
// The recorder (and with audio the sound tap) is free again: the replay buffer takes it back when Instant replay is on
static void rec_release(int audio) { mtl_record_set(NULL); if (audio) dm_audio_tap_set(NULL, NULL); replay_attach(audio); }
static void rec_attach(DmRecording *r) { mtl_recorder m = {rec_next, rec_done, (__bridge void *)r}; mtl_record_set(&m); }

void capture_screenshot(const char *game, void (^done)(NSString *, NSString *)) {
    if (g_rec) { done(nil, @"A recording is in progress; stop it first"); return; }
    CGFloat hgt = NSApp.keyWindow ? NSApp.keyWindow.contentView.bounds.size.height * NSApp.keyWindow.backingScaleFactor : 1080;
    size_t h = (size_t)MAX(720, (long)hgt) & ~1ul, w = (size_t)(h * 16 / 9) & ~1ul;
    DmRecording *r = rec_new(w, h); if (!r) { done(nil, @"The screenshot could not be set up"); return; }
    r.single = YES; NSString *path = capture_path(0, game, @"png"); g_rec = r;
    r.shot = ^(CVPixelBufferRef pb) {
        rec_release(0);
        CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
        CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGContextRef cg = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pb), CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb), 8, CVPixelBufferGetBytesPerRow(pb), cs,
                                                kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
        CGImageRef img = cg ? CGBitmapContextCreateImage(cg) : NULL;
        CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
        NSData *png = img ? [[[NSBitmapImageRep alloc] initWithCGImage:img] representationUsingType:NSBitmapImageFileTypePNG properties:@{}] : nil;
        BOOL ok = [png writeToFile:path atomically:YES];
        CGImageRelease(img); CGContextRelease(cg); CGColorSpaceRelease(cs);
        dispatch_async(dispatch_get_main_queue(), ^{ g_rec = nil; LOG("capture: screenshot %s%s", path.UTF8String, ok ? "" : " could not be written"); done(ok ? path : nil, ok ? nil : @"The screenshot could not be saved"); });
    };
    rec_attach(r);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{   // no present in 2 s (the game is paused or minimized): give up
        if (g_rec == r && r.shot) { rec_release(0); g_rec = nil; done(nil, @"The game has not drawn a frame"); } });
}

int capture_recording(void) { return g_rec && !g_rec.single; }
void capture_record_start(const char *game, void (^done)(NSString *, NSString *)) {
    if (g_rec) { done(nil, @"A capture is already in progress"); return; }
    DmRecording *r = rec_new(1920, 1080); NSError *e = nil; NSString *path = capture_path(1, game, @"mov");
    r.writer = r ? [AVAssetWriter assetWriterWithURL:[NSURL fileURLWithPath:path] fileType:AVFileTypeQuickTimeMovie error:&e] : nil;
    if (!r.writer) { done(nil, [NSString stringWithFormat:@"The recording could not start: %@", e.localizedDescription ?: @"no writer"]); return; }
    r.video = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{AVVideoCodecKey: AVVideoCodecTypeH264, AVVideoWidthKey: @1920, AVVideoHeightKey: @1080,
                                                                                                    AVVideoCompressionPropertiesKey: @{AVVideoAverageBitRateKey: @(16000000)}}];
    r.audio = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:@{AVFormatIDKey: @(kAudioFormatMPEG4AAC), AVSampleRateKey: @48000, AVNumberOfChannelsKey: @2, AVEncoderBitRateKey: @192000}];
    r.video.expectsMediaDataInRealTime = r.audio.expectsMediaDataInRealTime = YES;
    r.adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:r.video sourcePixelBufferAttributes:@{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA), (id)kCVPixelBufferWidthKey: @1920, (id)kCVPixelBufferHeightKey: @1080,
        (id)kCVPixelBufferMetalCompatibilityKey: @YES, (id)kCVPixelBufferIOSurfacePropertiesKey: @{}}];
    [r.writer addInput:r.video]; [r.writer addInput:r.audio];
    if (![r.writer startWriting]) { done(nil, [NSString stringWithFormat:@"The recording could not start: %@", r.writer.error.localizedDescription]); return; }
    r.path = path; r.done = done; g_rec = r;
    r.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, r.q);
    dispatch_source_set_timer(r.timer, DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC, 10 * NSEC_PER_MSEC);
    __weak DmRecording *wr = r; dispatch_source_set_event_handler(r.timer, ^{ DmRecording *x = wr; if (x && !x.stopping) rec_drain(x); });
    dispatch_resume(r.timer);
    dm_audio_tap_set(rec_tap, (__bridge void *)r);
    rec_attach(r);
    LOG("capture: recording to %s", path.UTF8String);
}
void capture_record_stop(void) {
    DmRecording *r = g_rec; if (!r || r.single) return;
    rec_release(1);
    dispatch_async(r.q, ^{
        rec_drain(r); r.stopping = YES; dispatch_source_cancel(r.timer);
        if (!r.started) { [r.writer cancelWriting]; dispatch_async(dispatch_get_main_queue(), ^{ g_rec = nil; r.done(nil, @"The game drew no frame while recording"); }); return; }
        [r.video markAsFinished]; [r.audio markAsFinished];
        [r.writer finishWritingWithCompletionHandler:^{
            BOOL ok = r.writer.status == AVAssetWriterStatusCompleted;
            LOG("capture: recording %s %s", r.path.UTF8String, ok ? "saved" : r.writer.error.localizedDescription.UTF8String);
            dispatch_async(dispatch_get_main_queue(), ^{ g_rec = nil; r.done(ok ? r.path : nil, ok ? nil : [NSString stringWithFormat:@"The recording could not be saved: %@", r.writer.error.localizedDescription]); });
        }];
    });
}

// ---- Instant replay (NXForge) ----
// While it is on, every presented frame is also drawn at 1920x1080 (the recorder's path, mtl_record_set) and encoded to H.264 by the Mac's hardware encoder, and the encoded
// frames of the last RP_SECS seconds stay in memory (about 45 MB at 12 Mbit/s) beside the sound of the same time as PCM (6 MB). Nothing is written until the player saves:
// then the frames from the first key frame of the last 30 s go into a QuickTime movie as they are (no second encode), with the sound as AAC, in the Recordings folder.
// A key frame every second, no frame reordering (so a frame's place in the file is its present time). A screenshot or a recording has the recorder meanwhile, and the
// buffer misses that stretch; frames a paused game does not present leave a gap that plays as a held frame. Off, none of this runs.
#define RP_SECS 30
#define RP_KEEP_NS ((uint64_t)(RP_SECS + 2) * 1000000000ull)
#define RP_PCM (48000 * 2 * (RP_SECS + 2))   // stereo; more channels keep proportionally less
@interface DmReplay : NSObject {
@public
    int16_t *pcm; _Atomic uint64_t wpos; _Atomic int ch; _Atomic uint64_t heard_ns;   // ring of interleaved samples, its channels, and the time just after its newest sample
}
@property VTCompressionSessionRef vt; @property CVMetalTextureCacheRef cache; @property CVPixelBufferPoolRef pool; @property NSMutableDictionary<NSValue *, id> *inflight;
@property NSMutableArray *frames; @property dispatch_queue_t q; @property uint64_t last; @property BOOL saving, off;
@end
@implementation DmReplay
- (void)dealloc { if (_vt) { VTCompressionSessionInvalidate(_vt); CFRelease(_vt); } if (_cache) CFRelease(_cache); if (_pool) CVPixelBufferPoolRelease(_pool); free(pcm); }
@end
static DmReplay *g_replay;   // main thread sets it; the recorder's callbacks reach it through their ctx, and a replay turned off is kept (g_replay_old) so a late callback finds it
static NSMutableArray *g_replay_old;

static void *rp_next(void *ctx) {   // present thread
    DmReplay *r = (__bridge DmReplay *)ctx;
    @synchronized (r) { if (r.off || r.inflight.count >= 3) return NULL; }
    CVPixelBufferRef pb = NULL; CVPixelBufferPoolCreatePixelBuffer(NULL, r.pool, &pb); if (!pb) return NULL;
    CVMetalTextureRef ct = NULL;
    CVMetalTextureCacheCreateTextureFromImage(NULL, r.cache, pb, NULL, MTLPixelFormatBGRA8Unorm, 1920, 1080, 0, &ct);
    id<MTLTexture> tex = ct ? CVMetalTextureGetTexture(ct) : nil;
    if (!tex) { if (ct) CFRelease(ct); CVPixelBufferRelease(pb); return NULL; }
    @synchronized (r) { r.inflight[[NSValue valueWithPointer:(__bridge void *)tex]] = @[(__bridge_transfer id)pb, (__bridge_transfer id)ct, tex]; }
    return (__bridge void *)tex;
}
static BOOL rp_key(CMSampleBufferRef sb) {
    CFArrayRef a = CMSampleBufferGetSampleAttachmentsArray(sb, false); if (!a || !CFArrayGetCount(a)) return YES;
    CFDictionaryRef d = CFArrayGetValueAtIndex(a, 0); CFBooleanRef ns = CFDictionaryGetValue(d, kCMSampleAttachmentKey_NotSync);
    return !ns || !CFBooleanGetValue(ns);
}
static uint64_t rp_ns(CMSampleBufferRef sb) { CMTime t = CMSampleBufferGetPresentationTimeStamp(sb); return (uint64_t)CMTimeConvertScale(t, 1000000000, kCMTimeRoundingMethod_Default).value; }
static void rp_done(void *ctx, void *texp, uint64_t ns) {   // GPU completion thread
    DmReplay *r = (__bridge DmReplay *)ctx; NSValue *k = [NSValue valueWithPointer:texp]; NSArray *keep;
    @synchronized (r) { keep = r.inflight[k]; [r.inflight removeObjectForKey:k]; }
    if (!keep) return;
    dispatch_async(r.q, ^{
        if (r.off || ns <= r.last) return;
        r.last = ns;
        VTCompressionSessionEncodeFrameWithOutputHandler(r.vt, (__bridge CVPixelBufferRef)keep[0], CMTimeMake((int64_t)ns, 1000000000), kCMTimeInvalid, NULL, NULL,
            ^(OSStatus st, VTEncodeInfoFlags fl, CMSampleBufferRef sb) {
                (void)fl; if (st || !sb || !CMSampleBufferDataIsReady(sb)) return;
                @synchronized (r.frames) {
                    [r.frames addObject:(__bridge id)sb];
                    uint64_t newest = rp_ns(sb);
                    // the oldest go a second at a time: up to the key frame after them, so the buffer always starts on one
                    while (r.frames.count > 2) {
                        NSUInteger nk = NSNotFound;
                        for (NSUInteger i = 1; i < r.frames.count; i++) if (rp_key((__bridge CMSampleBufferRef)r.frames[i])) { nk = i; break; }
                        if (nk == NSNotFound || newest - rp_ns((__bridge CMSampleBufferRef)r.frames[nk]) < RP_KEEP_NS) break;
                        [r.frames removeObjectsInRange:NSMakeRange(0, nk)];
                    }
                }
            });
    });
}
static void rp_tap(void *ctx, const int16_t *pcm, uint32_t frames, int ch) {   // real-time audio thread
    DmReplay *r = (__bridge DmReplay *)ctx;
    int want = 0; atomic_compare_exchange_strong(&r->ch, &want, ch); if (atomic_load(&r->ch) != ch) return;
    uint64_t w = atomic_load_explicit(&r->wpos, memory_order_relaxed), n = (uint64_t)frames * ch;
    if (n > RP_PCM / 2) return;
    for (uint64_t i = 0; i < n; i++) r->pcm[(w + i) % RP_PCM] = pcm[i];
    atomic_store_explicit(&r->wpos, w + n, memory_order_release);
    atomic_store_explicit(&r->heard_ns, now_ns(), memory_order_release);
}
static void replay_attach(int audio) {
    DmReplay *r = g_replay; if (!r) return;
    mtl_recorder m = {rp_next, rp_done, (__bridge void *)r}; mtl_record_set(&m);
    if (audio) dm_audio_tap_set(rp_tap, (__bridge void *)r);
}
int capture_replay_on(void) { return g_replay != nil; }
int capture_replay_set(int on) {
    if (!on) {
        DmReplay *r = g_replay; if (!r) return 0;
        g_replay = nil; r.off = YES;
        if (!g_replay_old) g_replay_old = [NSMutableArray array];
        [g_replay_old addObject:r];   // a frame or a block of sound already on its way still finds it; its buffers are emptied below
        if (!g_rec) { mtl_record_set(NULL); dm_audio_tap_set(NULL, NULL); } else if (g_rec.single) dm_audio_tap_set(NULL, NULL);
        dispatch_async(r.q, ^{ VTCompressionSessionCompleteFrames(r.vt, kCMTimeInvalid); @synchronized (r.frames) { [r.frames removeAllObjects]; } });
        LOG("capture: instant replay off");
        return 0;
    }
    if (g_replay) return 1;
    DmReplay *r = [DmReplay new]; r.inflight = [NSMutableDictionary dictionary]; r.frames = [NSMutableArray array];
    r.q = dispatch_queue_create("nxforge.replay", DISPATCH_QUEUE_SERIAL);
    r->pcm = calloc(RP_PCM, sizeof(int16_t));
    CVMetalTextureCacheRef c = NULL; id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    if (!r->pcm || !dev || CVMetalTextureCacheCreate(NULL, NULL, dev, NULL, &c)) { LOG("[RED] capture: instant replay could not be set up (texture cache)"); return 0; }
    r.cache = c;
    NSDictionary *pa = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA), (id)kCVPixelBufferWidthKey: @1920, (id)kCVPixelBufferHeightKey: @1080,
                         (id)kCVPixelBufferMetalCompatibilityKey: @YES, (id)kCVPixelBufferIOSurfacePropertiesKey: @{}};
    CVPixelBufferPoolRef pool = NULL; CVPixelBufferPoolCreate(NULL, NULL, (__bridge CFDictionaryRef)pa, &pool); r.pool = pool;
    VTCompressionSessionRef vt = NULL;
    OSStatus st = VTCompressionSessionCreate(NULL, 1920, 1080, kCMVideoCodecType_H264, NULL, NULL, NULL, NULL, NULL, &vt);
    if (st || !vt || !pool) { LOG("[RED] capture: instant replay could not be set up (encoder: %d)", (int)st); return 0; }
    r.vt = vt;
    VTSessionSetProperty(vt, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    VTSessionSetProperty(vt, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);
    VTSessionSetProperty(vt, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_High_AutoLevel);
    VTSessionSetProperty(vt, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFTypeRef)@(12000000));
    VTSessionSetProperty(vt, kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, (__bridge CFTypeRef)@(1));
    VTCompressionSessionPrepareToEncodeFrames(vt);
    g_replay = r;
    if (!g_rec) replay_attach(1); else if (g_rec.single) dm_audio_tap_set(rp_tap, (__bridge void *)r);   // a recording in progress keeps both until it stops (rec_release)
    LOG("capture: instant replay on: the last %d s are kept in memory (H.264 1920x1080, 12 Mbit/s)", RP_SECS);
    return 1;
}
// Wait for an input of a writer that is not fed in real time (at most 5 s)
static BOOL rp_ready(AVAssetWriterInput *in) { for (int i = 0; i < 2500 && !in.readyForMoreMediaData; i++) usleep(2000); return in.readyForMoreMediaData; }
void capture_replay_save(const char *game, void (^done)(NSString *, NSString *)) {
    DmReplay *r = g_replay;
    if (!r) { done(nil, @"Instant replay is off: turn it on in the Capture page"); return; }
    if (r.saving) { done(nil, @"The last replay is still being saved"); return; }
    r.saving = YES; NSString *path = capture_path(1, game, @"mov");
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        void (^end)(NSString *, NSString *) = ^(NSString *p, NSString *err) { dispatch_async(dispatch_get_main_queue(), ^{ r.saving = NO; done(p, err); }); };
        NSArray *all; @synchronized (r.frames) { all = [r.frames copy]; }
        if (all.count < 2) { end(nil, @"Nothing to save yet: the replay keeps what you play from now on"); return; }
        uint64_t newest = rp_ns((__bridge CMSampleBufferRef)all.lastObject); NSUInteger from = 0;   // the buffer starts on a key frame
        for (NSUInteger i = 0; i < all.count; i++) {
            CMSampleBufferRef sb = (__bridge CMSampleBufferRef)all[i];
            if (rp_key(sb) && newest - rp_ns(sb) <= (uint64_t)RP_SECS * 1000000000ull) { from = i; break; }
        }
        CMSampleBufferRef first = (__bridge CMSampleBufferRef)all[from]; uint64_t t0 = rp_ns(first);
        NSError *e = nil; AVAssetWriter *w = [AVAssetWriter assetWriterWithURL:[NSURL fileURLWithPath:path] fileType:AVFileTypeQuickTimeMovie error:&e];
        if (!w) { end(nil, [NSString stringWithFormat:@"The replay could not be saved: %@", e.localizedDescription ?: @"no writer"]); return; }
        AVAssetWriterInput *vi = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:nil sourceFormatHint:CMSampleBufferGetFormatDescription(first)];
        [w addInput:vi];
        // The sound of the same stretch, counted back from the newest sample heard
        int ch = atomic_load(&r->ch); uint64_t wpos = atomic_load_explicit(&r->wpos, memory_order_acquire), heard = atomic_load_explicit(&r->heard_ns, memory_order_acquire);
        AVAssetWriterInput *ai = nil; int16_t *mem = NULL; size_t frames = 0; uint64_t a0 = 0;
        if (ch > 0 && wpos && heard > t0) {
            uint64_t have = MIN(wpos, (uint64_t)RP_PCM) / ch, want = (heard - t0) * 48000 / 1000000000ull;
            frames = (size_t)MIN(have, want); a0 = heard - (uint64_t)frames * 1000000000ull / 48000;
            uint64_t over = heard > newest ? (heard - newest) * 48000 / 1000000000ull : 0;   // sound after the last frame kept (the game ran on while this started): left out
            size_t count = frames * ch; mem = frames > over ? malloc(count * 2) : NULL;
            if (mem) {
                uint64_t start = wpos - count; for (size_t i = 0; i < count; i++) mem[i] = r->pcm[(start + i) % RP_PCM];
                frames -= (size_t)over;
                ai = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:@{AVFormatIDKey: @(kAudioFormatMPEG4AAC), AVSampleRateKey: @48000, AVNumberOfChannelsKey: @2, AVEncoderBitRateKey: @192000}];
                [w addInput:ai];
            }
        }
        if (![w startWriting]) { free(mem); end(nil, [NSString stringWithFormat:@"The replay could not be saved: %@", w.error.localizedDescription]); return; }
        [w startSessionAtSourceTime:CMTimeMake((int64_t)t0, 1000000000)];
        // Sound and picture go in side by side, a second of sound ahead of each frame's time: a writer that is not fed in real time holds one input back
        // (readyForMoreMediaData) until the other has caught up, so the whole picture first would wait for sound that never came
        CMAudioFormatDescriptionRef f = NULL; __block size_t at = 0;
        if (ai) {
            AudioStreamBasicDescription d = {.mSampleRate = 48000, .mFormatID = kAudioFormatLinearPCM, .mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                                             .mBytesPerPacket = 2u * ch, .mFramesPerPacket = 1, .mBytesPerFrame = 2u * ch, .mChannelsPerFrame = (UInt32)ch, .mBitsPerChannel = 16};
            CMAudioFormatDescriptionCreate(NULL, &d, 0, NULL, 0, NULL, NULL, &f);
        }
        BOOL (^sound_to)(uint64_t) = ^BOOL(uint64_t until) {   // the sound up to a time (a second past it at most), in blocks of half a second
            while (ai && f && at < frames && a0 + (uint64_t)at * 1000000000ull / 48000 <= until) {
                size_t n = MIN((size_t)24000, frames - at), bytes = n * ch * 2; CMBlockBufferRef bb = NULL; CMSampleBufferRef sb = NULL;
                if (CMBlockBufferCreateWithMemoryBlock(NULL, NULL, bytes, NULL, NULL, 0, bytes, kCMBlockBufferAssureMemoryNowFlag, &bb)) return NO;
                CMBlockBufferReplaceDataBytes(mem + at * ch, bb, 0, bytes);
                CMAudioSampleBufferCreateReadyWithPacketDescriptions(NULL, bb, f, (CMItemCount)n, CMTimeMake((int64_t)(a0 + (uint64_t)at * 1000000000ull / 48000), 1000000000), NULL, &sb);
                BOOL good = sb && rp_ready(ai) && [ai appendSampleBuffer:sb];
                if (sb) CFRelease(sb);
                CFRelease(bb);
                if (!good) return NO;
                at += n;
            }
            return YES;
        };
        BOOL ok = YES; const char *stopped = NULL;
        for (NSUInteger i = from; ok && i < all.count; i++) {
            CMSampleBufferRef sb = (__bridge CMSampleBufferRef)all[i];
            if (!sound_to(rp_ns(sb) + 500000000ull)) { ok = NO; stopped = "the sound was not taken"; break; }
            if (!rp_ready(vi)) { ok = NO; stopped = "the writer did not take the picture in time"; break; }
            if (![vi appendSampleBuffer:sb]) { ok = NO; stopped = "a frame was refused"; }
        }
        if (ok && !sound_to(UINT64_MAX)) { ok = NO; stopped = "the sound was not taken"; }
        [vi markAsFinished]; [ai markAsFinished];
        if (f) CFRelease(f);
        free(mem);
        double secs = (newest - t0) / 1e9;
        [w finishWritingWithCompletionHandler:^{
            BOOL good = ok && w.status == AVAssetWriterStatusCompleted;
            LOG("capture: replay of the last %.0f s %s %s", secs, path.UTF8String, good ? "saved" : (w.error.localizedDescription.UTF8String ?: stopped ?: "could not be written"));
            if (!good) [NSFileManager.defaultManager removeItemAtPath:path error:nil];
            end(good ? path : nil, good ? nil : [NSString stringWithFormat:@"The replay could not be saved: %@", w.error.localizedDescription ?: @"the file could not be written"]);
        }];
    });
}
