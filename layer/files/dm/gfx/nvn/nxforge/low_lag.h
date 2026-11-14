// NXForge: direct presents in a window while the game has headroom (pure function; unit test tests/t_low_lag.c; the glue is in nvn_mtl.m below link_latency, the per-frame
// call in hle_nvn.c nvnQueuePresentTexture). In a window the display link calls back about 50 ms before its target display time (nvn_mtl.m link_latency), so a frame a game
// presents is on screen 66 ms later; a present thread that takes its own drawables (pacing mode 0, what fullscreen on a Mac already does) shows it after 35 ms.
// Measured on an M4 Pro, macOS 27.2, 120 Hz screen, game present to on screen (DM_NVN_TSV @pres_at_ms − @call_ms), p50:
//   Bloodstained: Curse of the Moon (GPU 0.5 ms a frame): link 66.5 ms, 120 Hz link 49.8 ms, mode 0 34.9 ms; every on-screen interval 16.67 ms in all three.
//   Ocarina of Time standing in the field (GPU 16.8 ms, 3,080 draws): link 66 ms at 54.3 fps with 10% of the intervals over 20 ms; mode 0 41 ms at 46.2 fps with 60%.
// So mode 0 is right for a game with headroom and wrong for one at the edge of its frame, where the link's queue is what keeps the frames even (upstream's reason for the link).
// The policy: after NXF_LL_RUN frames in a row on time, each with GPU and thread CPU time of at most NXF_LL_ENTER vsyncs, presents go direct. Direct ends when NXF_LL_BAD
// frames within NXF_LL_WIN were late (shown a quarter vsync longer than their hold); the next try waits NXF_LL_WAIT0 frames, twice as long after each direct run that
// lasted less than NXF_LL_CALM frames (up to NXF_LL_WAIT_MAX), so a game that goes back and forth between a light and a heavy scene does not switch every few seconds.
// GPU time is not judged while direct: a game that waits for its drawable there has the wait in its GPU time. A stall (a pause, a covered window, a load) is not a late
// frame, and the NXF_LL_GRACE frames after it or after a switch are not judged.
// The trim: mode 0 shows a frame after 35 ms only while the layer's queue of drawables is empty. The game is paced by its own 60 Hz clock, not the screen's, so once it has
// run a frame ahead (the frames queued for the link at the switch, a hitch on the screen's side) the queue stays full: every nextDrawable then waits for the screen to
// let one go, and the lag is 60 ms (one queued) or 80 ms (two), as with the link (Switch Sports Resort after a switch: 80 ms, nextDrawable waiting 16.6 ms a frame).
// A queue that is full for NXF_LL_TRIM_RUN presents in a row is emptied by one frame: that present is dropped, so the picture before it stays one refresh longer, once.
// At most NXF_LL_TRIM_MAX drops within NXF_LL_TRIM_WIN presents; a game that fills the queue faster than that is left alone for as long.
#pragma once
#include <stdint.h>

#define NXF_LL_ENTER 0.55
#define NXF_LL_RUN 180
#define NXF_LL_LATE 0.25
#define NXF_LL_BAD 3
#define NXF_LL_WIN 60
#define NXF_LL_GRACE 30
#define NXF_LL_STALL 8.0
#define NXF_LL_WAIT0 600
#define NXF_LL_WAIT_MAX 4800
#define NXF_LL_CALM 3600

#define NXF_LL_TRIM_MS 4.0
#define NXF_LL_TRIM_RUN 30
#define NXF_LL_TRIM_MAX 6
#define NXF_LL_TRIM_WIN 3600

typedef struct { int run, drops, win, rest; uint64_t total; } nxf_ll_trim;
// Before each direct present, with the time the present before it waited for its drawable (ms). Returns 1 when this present is to be dropped
static inline int nxf_ll_trim_next(nxf_ll_trim *t, double wait_ms) {
    if (t->rest > 0) { if (!--t->rest) t->drops = t->win = t->run = 0; return 0; }
    if (t->drops && ++t->win >= NXF_LL_TRIM_WIN) t->drops = t->win = 0;
    t->run = wait_ms >= NXF_LL_TRIM_MS ? t->run + 1 : 0;
    if (t->run < NXF_LL_TRIM_RUN) return 0;
    t->run = 0; t->total++;
    if (++t->drops >= NXF_LL_TRIM_MAX) t->rest = NXF_LL_TRIM_WIN;
    return 1;
}

typedef struct {
    int direct;             // 1 = the present thread takes its own drawables
    int run;                // link: frames in a row with headroom
    int wait, wait_next;    // link: frames before the next try; what the wait will be after the next fall back
    int grace;              // frames left that are not judged
    int bad, win;           // direct: late frames in the current window, frames the window has run
    int calm;               // direct: frames since it started
    uint64_t ins, outs;     // statistics for the log
} nxf_low_lag;

// Once per frame. shown: real time since the previous frame's start, in vsyncs; gpu, cpu: the frame's GPU time and the presenting thread's CPU time, in vsyncs
// (gpu 0 = none finished yet); k: vsyncs the frame was held for (the present interval). Returns s->direct
static inline int nxf_low_lag_next(nxf_low_lag *s, double shown, double gpu, double cpu, int k) {
    if (k < 1) k = 1;
    if (!s->wait_next) s->wait_next = NXF_LL_WAIT0;
    if (shown >= NXF_LL_STALL * k) { s->grace = NXF_LL_GRACE; s->run = 0; return s->direct; }
    if (s->grace > 0) { s->grace--; return s->direct; }
    int late = shown > k + NXF_LL_LATE;
    if (!s->direct) {
        if (s->wait > 0) s->wait--;
        s->run = !late && gpu <= NXF_LL_ENTER && cpu <= NXF_LL_ENTER ? s->run + 1 : 0;
        if (s->run >= NXF_LL_RUN && !s->wait) { s->direct = 1; s->ins++; s->run = 0; s->bad = s->win = s->calm = 0; s->grace = NXF_LL_GRACE; }
        return s->direct;
    }
    s->calm++;
    if (s->calm == NXF_LL_CALM) s->wait_next = NXF_LL_WAIT0;
    if (s->bad && ++s->win >= NXF_LL_WIN) s->bad = s->win = 0;
    if (late && ++s->bad >= NXF_LL_BAD) {
        s->direct = 0; s->outs++; s->run = 0; s->grace = NXF_LL_GRACE;
        s->wait = s->wait_next;
        if (s->calm < NXF_LL_CALM) s->wait_next = s->wait_next * 2 < NXF_LL_WAIT_MAX ? s->wait_next * 2 : NXF_LL_WAIT_MAX;
    }
    return s->direct;
}
