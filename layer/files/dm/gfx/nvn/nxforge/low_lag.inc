// NXForge: included by nvn_mtl.m above link_sync (it shares its statics). The glue of low_lag.h: direct presents in a window while the game has headroom.
// DM_LOW_LAG=0 turns it off (DM_LOW_LAG_TEST=<frames> makes a direct run end after that many, to test the way back); DM_PRESENT_LINK and DM_PRESENT_LATENCY, which choose the pacing themselves, do too. Mac only.
#include "low_lag.h"
static nxf_low_lag g_ll; static _Atomic int g_ll_direct;
static int nxf_ll_on(void) {
    static int on = -1;
    if (on < 0) { const char *e = getenv("DM_LOW_LAG"); on = TARGET_OS_OSX && !(e && !strcmp(e, "0")) && !g_present_link_env && !g_present_latency; if (TARGET_OS_OSX) MLOG("low lag: %s", on ? "direct presents in a window while the game has headroom (DM_LOW_LAG=0 turns it off)" : "off (DM_LOW_LAG=0, DM_PRESENT_LINK or DM_PRESENT_LATENCY)"); }
    return on;
}
// Once per present, on the game's presenting thread (hle_nvn.c nvnQueuePresentTexture). start_ns: when the frame started (its first acquire returned); k: vsyncs it is held for
void mtl_low_lag_tick(uint64_t start_ns, int k) {
    if (!start_ns || !nxf_ll_on()) return;
    static uint64_t prev, cpu_prev;
    const double v = 1e9 / 60.0;
    uint64_t cpu = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID);
    if (prev && start_ns > prev) {
        double gpu = 0; uint64_t f = atomic_load(&g_cur_frame);
        for (uint64_t i = f; i-- > 0 && f - i <= 8;) { double g = mtl_gpu_ms(i); if (g >= 0) { gpu = g * 1e6 / v; break; } }
        static int test = -1; if (test < 0) { const char *e = getenv("DM_LOW_LAG_TEST"); test = e ? atoi(e) : 0; }   // a test's fall back: after this many direct frames the next ones count as late
        if (test > 0 && g_ll.direct && g_ll.calm >= test) prev = start_ns - (uint64_t)((k + 1) * v);
        int was = g_ll.direct, wait = g_ll.wait_next, now = nxf_low_lag_next(&g_ll, (start_ns - prev) / v, gpu, cpu > cpu_prev ? (cpu - cpu_prev) / v : 0, k);
        if (now != was) {
            atomic_store(&g_ll_direct, now);
            dm_fstep_settle();   // the frames around the switch are not what the scene costs (nvn_fstep.h settle)
            if (now) MLOG("low lag: direct presents (%d frames on time with GPU and CPU under %.2f of a vsync; frame %llu, time %llu)", NXF_LL_RUN, NXF_LL_ENTER, (unsigned long long)f, (unsigned long long)g_ll.ins);
            else MLOG("low lag: back to the display link (%d late frames within %d; frame %llu, after %d direct frames; next try in %d frames)", NXF_LL_BAD, NXF_LL_WIN, (unsigned long long)f, g_ll.calm, wait ? wait : NXF_LL_WAIT0);
        }
    }
    prev = start_ns; cpu_prev = cpu;
}
// The trim (low_lag.h): on the present thread, before a direct present takes its drawable. wait_ns: what the present before it waited for its drawable
static int nxf_ll_trim_drop(uint64_t wait_ns) {
    static nxf_ll_trim t;
    if (!nxf_ll_on() || !atomic_load(&g_ll_direct)) { t.run = 0; return 0; }   // fullscreen too: its presents are direct whatever the policy says, and the policy still says whether the game has headroom
    if (!nxf_ll_trim_next(&t, wait_ns / 1e6)) return 0;
    MLOG("low lag: one present dropped to empty the layer's queue (the last %d waited %.1f ms or more for their drawable; %llu so far)", NXF_LL_TRIM_RUN, NXF_LL_TRIM_MS, (unsigned long long)t.total);
    return 1;
}
static int nxf_low_lag_direct(void) { return nxf_ll_on() && atomic_load(&g_ll_direct); }
