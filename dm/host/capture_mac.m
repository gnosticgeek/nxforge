// Screenshots and video of the game as it is presented, the present filter included and the sidebar left out (front.h mtl_record_set: the present thread draws each frame once more into
// a texture handed out here). Screenshots: PNG, 16:9 at the window's height in pixels (720 at least). Video: H.264 with AAC sound in a QuickTime movie, 1920x1080 at the game's frame rate,
// the sound from the first audio output (front.h dm_audio_tap_set) before the host volume. Where (capture_folder): a folder the player chose, else Screenshots / Recordings in the game folder
// (DM_GAME_FOLDER, which the app's launcher sets), else ~/Pictures/NxNative / ~/Movies/NxNative. Writing files there needs no permission
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <Metal/Metal.h>
#import <AppKit/AppKit.h>
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
    return [base.path stringByAppendingPathComponent:@"NxNative"];
}
static NSString *capture_path(int video, const char *game, NSString *ext) {
    NSString *dir = capture_folder(video);
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"yyyy-MM-dd 'at' HH.mm.ss";
    NSString *name = [[NSString stringWithFormat:@"%s %@", game, [f stringFromDate:NSDate.date]] stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    NSString *p = [[dir stringByAppendingPathComponent:name] stringByAppendingPathExtension:ext];
    for (int i = 2; [NSFileManager.defaultManager fileExistsAtPath:p]; i++) p = [[dir stringByAppendingPathComponent:[name stringByAppendingFormat:@" %d", i]] stringByAppendingPathExtension:ext];
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
    if (r.adaptor.pixelBufferPool) CVPixelBufferPoolCreatePixelBuffer(NULL, r.adaptor.pixelBufferPool, &pb);
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
    if (CVMetalTextureCacheCreate(NULL, NULL, dev, NULL, &c)) return nil;
    r.cache = c; return r;
}
static void rec_attach(DmRecording *r) { mtl_recorder m = {rec_next, rec_done, (__bridge void *)r}; mtl_record_set(&m); }

void capture_screenshot(const char *game, void (^done)(NSString *, NSString *)) {
    if (g_rec) { done(nil, @"A recording is in progress; stop it first"); return; }
    CGFloat hgt = NSApp.keyWindow ? NSApp.keyWindow.contentView.bounds.size.height * NSApp.keyWindow.backingScaleFactor : 1080;
    size_t h = (size_t)MAX(720, (long)hgt) & ~1ul, w = (size_t)(h * 16 / 9) & ~1ul;
    DmRecording *r = rec_new(w, h); if (!r) { done(nil, @"The screenshot could not be set up"); return; }
    r.single = YES; NSString *path = capture_path(0, game, @"png"); g_rec = r;
    r.shot = ^(CVPixelBufferRef pb) {
        mtl_record_set(NULL);
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
        if (g_rec == r && r.shot) { mtl_record_set(NULL); g_rec = nil; done(nil, @"The game has not drawn a frame"); } });
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
    mtl_record_set(NULL); dm_audio_tap_set(NULL, NULL);
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
