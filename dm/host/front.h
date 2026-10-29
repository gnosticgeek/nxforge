// Host front end (Mac: front_mac.m; iOS: dm/ios separately implements the same-named interface).
#pragma once
#include <stdint.h>
#include <stdlib.h>
// Metal reads HUD switches when the first device is made. Called before host preload and again after the launcher applies its settings; explicit environment values win.
static inline void front_hud_env(void) {
    const char *e = getenv("DM_METAL_HUD");
    if (!e || !atoi(e)) return;
    setenv("MTL_HUD_ENABLED", "1", 0);
    // Spatial scaling has no temporal exposure: showing that HUD metric makes the MetalFX rows flicker.
    setenv("MTL_HUD_HIDE_METALFX_METRICS", "1", 0);
}
// Run the guest: with a window the guest runs on its own thread and the main thread belongs to the system UI; without a window it runs directly on the current thread.
void front_run(void (*guest)(void));
// The CAMetalLayer the graphics backend presents frames to (NULL when there is no window)
void *front_metal_layer(void);
// The highest refresh rate of the window's screen in Hz, 0 = not known (Mac front_mac.m; none on iOS, whose screens run at multiples of 60 Hz). Any thread
int front_screen_max_fps(void);
int front_fullscreen(void);   // 1 while the window is in fullscreen (Mac; 0 elsewhere)
// The frame rate the display link paces the game at (60, 30, 120; nvn_mtl.m link_sync): in fullscreen, a screen whose refresh rate is not a multiple of it is switched, while the game runs,
// to a mode of the same size whose rate is, and back when the window leaves fullscreen or that screen (front_mac.m; none on iOS). Called from the present thread
void front_screen_match(int fps);
// Present filter (implemented by the graphics backend, nvn_mtl.m; set by the Mac front end's Graphics menu and panel, or DM_PRESENT_FILTER / DM_PRESENT_FILTER_STRENGTH): how the game picture
// is drawn into the window, taken at every present. Strength 0 to 1. Any thread
enum { DM_PFX_OFF, DM_PFX_SHARPEN, DM_PFX_PIXEL, DM_PFX_CRT, DM_PFX_LOTTES, DM_PFX_LCD, DM_PFX_N };   // in the order they were added: the saved choice is the number
int mtl_present_filter(float *strength);
void mtl_present_filter_set(int mode, float strength);
// Anisotropic filtering floor (nvn_mtl.m; the Mac front end's sidebar, or DM_ANISO): 0 = the game's own, else 2, 4, 8 or 16 taps at least for the game's filtered, mipmapped
// samplers. Taken when the game makes its first sampler, so mtl_aniso_set must come before the guest runs; later calls only log that the change applies at the next launch. Any thread
int mtl_aniso(void);
void mtl_aniso_set(int n);
// Present upscaling (nvn_mtl.m; the Mac front end's Quick settings, or DM_PRESENT_UPSCALE): 1 = MetalFX's spatial scaler where the picture is shown larger than the game renders it,
// 0 = bilinear. Taken at every present; a GPU without the Metal 4 scaler scales bilinearly whatever is chosen. mtl_present_upscale answers the choice. Any thread
int mtl_present_upscale(void);
void mtl_present_upscale_set(int on);
// Present anti-aliasing (nvn_mtl.m; Quick settings per game, or DM_PRESENT_AA): FXAA over the game's finished picture before upscaling and the filter. Taken at every present. Any thread
enum { DM_PAA_OFF, DM_PAA_FXAA, DM_PAA_N };   // the saved choice is the number
int mtl_present_aa(void);
void mtl_present_aa_set(int mode);
// The CRT filters' scanline height (and the LCD grid's cell) in source rows, 1 to 8; 0 = auto (about 240 lines). DM_PRESENT_SCANLINE sets it from the environment
int mtl_present_scanline(void);
void mtl_present_scanline_set(int rows);
// Frames put on screen so far (nvn_mtl.m, NVN and the Vulkan layer alike; frames the display link merged away are not counted): the front ends' frame-rate counters. Any thread
uint64_t mtl_present_count(void);
// Recording (nvn_mtl.m; the Mac front end's video recorder, capture_mac.m): while a recorder is set, every present also draws the frame as it is presented (the filter too) into a texture
// next() hands out (an id<MTLTexture> of the system default device, bridged; NULL skips the frame), on a command buffer of its own as the whole-window screenshot does, and done() gets the same
// texture back with the frame's present time (now_ns) once the GPU has drawn it. NULL stops; done() may still come for frames already drawn. Any thread
typedef struct { void *(*next)(void *ctx); void (*done)(void *ctx, void *tex, uint64_t ns); void *ctx; } mtl_recorder;
void mtl_record_set(const mtl_recorder *r);
// The whole-window screenshot (nvn_mtl.m): at the next present the frame as presented, at the drawable's size, comes to cb on a GPU completion thread (NULL when it could not be drawn)
#ifdef __OBJC__
#include <CoreGraphics/CoreGraphics.h>
void mtl_grab_next_present(void (^cb)(CGImageRef img));
#endif
// The share of the window's width (0 to 0.9) kept free on the right for a panel: the game picture fits and centres in the rest (nvn_mtl.m; the Mac's Quick settings sidebar). Any thread
void mtl_present_inset(float share);
// Host volume (hle_audio.c; the Mac's Quick settings): a gain 0 to 1 on everything the game plays, on top of its own volumes. Any thread
void dm_audio_volume_set(float v);
float dm_audio_volume(void);
// Audio tap (hle_audio.c; the video recorder): the 48 kHz 16-bit PCM of the first output playing, as it goes to the sound card before the host volume, ch channels interleaved. fn runs on the
// real-time audio thread: it must not block or allocate. NULL stops
void dm_audio_tap_set(void (*fn)(void *ctx, const int16_t *pcm, uint32_t frames, int ch), void *ctx);
// Progress screen of the first-start prepare step (nvn_mtl.m warm_prepare: "Preparing shaders" while the pipelines of the prewarm lists are built before the game's first frame):
// title and done of total shown over the game's view (a dark screen, the title, a bar and a count), updated on each call; title NULL hides it. Any thread; the front end switches to its main
// thread and does not block. Nothing is shown without a window
void front_progress(const char *title, long done, long total);
// Text input box (for the software keyboard swkbd): the main thread shows a native input box and the calling thread blocks until the user confirms / cancels.
// All text is UTF-8; max_chars is the maximum character count (0 = unlimited, only a hint for the front end; truncation is done uniformly by the caller hle_swkbd.c in UTF-16 units).
// Confirm returns 1 and writes the result into out (including the terminating 0); cancel returns 0;
// with no window (front_metal_layer() == NULL) nothing is shown and -1 is returned.
int front_text_input(const char *title, const char *sub, const char *guide, const char *initial, int max_chars, char *out, int out_cap);

// Early start of host loading (main.c): reading the NSO / relocation / forced takeover / prefetch start are moved to a background thread, in parallel with the front end (UIKit launch chain, Metal view);
// the dm_main / main called afterwards waits for it to finish. For call timing and preconditions see the comments in main.c (set DM_ROMFS and the other environment variables and the cwd first; arguments identical item by item to those of the later main).
void dm_host_preload_start(int argc, char **argv);

// Touchscreen (implemented by the host's hle_touch.c; called by the iOS / Mac front end): whenever the set of touch points changes (down / move / up / cancel) the whole set is pushed once; n = 0 = all lifted.
// id = finger slot number 0–15 (the lowest free slot on down, unchanged until up; used directly as finger_id); x / y = normalized coordinates [0,1) on the output frame, origin at top left.
// The host converts to the panel coordinates the game reads, 1280x720 (x·1280, y·720), and latches short taps (a down and up between two reads is reported at least once). May be called from any thread.
typedef struct { uint32_t id; float x, y; } dm_touch;
void dm_touch_set(const dm_touch *t, int n);

// Save not written (called by the host's hle_fs.c; the iOS front end provides a strong implementation of the same name that shows the native prompt "Not enough storage. Progress was not saved"; the default weak implementation only logs).
// Timing: when a save write fails (disk full etc.) within one of the game's save transactions (between two Commits), so that this Commit is refused and the previously committed save is unchanged, it is called once per refused transaction;
// the next transaction that succeeds commits as usual, and the front end need not do any recovery. err = the first failing errno (ENOSPC = 28 means out of space). Called on the game thread; the front end switches to the main thread itself and must not block
void front_save_failed(int err);
