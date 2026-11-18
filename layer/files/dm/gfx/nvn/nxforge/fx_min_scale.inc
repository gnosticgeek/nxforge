// NXForge: the MetalFX spatial scaler only where it enlarges the picture by at least DM_FX_MIN_SCALE (1.4 by default; 1 = wherever it is larger, upstream's rule).
// MetalFX costs 0.8-1.45 ms of GPU a present on an M4 Pro (Mario Kart World, 2560x1440 → 3024x1701 in full screen on the built-in screen, "present command buffer
// GPU time over 600 presents through MetalFX": p50 0.81 ms in a race on 16 Nov 2026, 1.30-1.45 ms in Tom's evening sessions), the bilinear pass 0.24 ms. Ocarina of Time, 2292x1440 → 3024x1898 (1.32x):
// 0.83-1.19 ms. Enlargements that small gain little sharpness, and in a game at the edge of its 16.7 ms that millisecond decides whether a frame is late. Games that
// render 720p or 1080p (1.75x and more to a MacBook's screen) keep it
static int nxf_fx_scale_ok(NSUInteger cw, NSUInteger ch, NSUInteger w, NSUInteger h) {
    static double min = -1;
    if (min < 0) { const char *e = getenv("DM_FX_MIN_SCALE"); double v = e && *e ? atof(e) : 1.4; min = v >= 1 && v <= 8 ? v : 1.4; }
    double k = fmax((double)w / cw, (double)h / ch);
    static int said; int ok = k >= min - 1e-6;
    if (!ok && !said) { said = 1; MLOG("present upscaling: %lux%lu → %lux%lu is only %.2fx, under %.2fx: bilinear, MetalFX's GPU time saved (DM_FX_MIN_SCALE=1 uses MetalFX for any enlargement)",
                                       (unsigned long)cw, (unsigned long)ch, (unsigned long)w, (unsigned long)h, k, min); }
    return ok;
}
