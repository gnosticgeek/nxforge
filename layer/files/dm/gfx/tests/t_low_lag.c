// NXForge: unit tests of the direct-present policy (nvn/nxforge/low_lag.h). Frames are simulated in vsyncs
#include "../nvn/nxforge/low_lag.h"
#include <stdio.h>

static int fail, checks;
static void check(int ok, const char *what) { checks++; fail += !ok; printf("%-86s %s\n", what, ok ? "✓" : "✗"); }
static int feed(nxf_ll_trim *t, int n, double wait_ms) { int d = 0; for (int i = 0; i < n; i++) d += nxf_ll_trim_next(t, wait_ms); return d; }
static void run(nxf_low_lag *s, int n, double shown, double gpu, double cpu, int k) { for (int i = 0; i < n; i++) nxf_low_lag_next(s, shown, gpu, cpu, k); }

int main(void) {
    {   nxf_low_lag s = {0};
        run(&s, NXF_LL_RUN - 1, 1.0, 0.03, 0.02, 1); check(!s.direct, "a light game: the link for the first frames");
        run(&s, 1, 1.0, 0.03, 0.02, 1); check(s.direct && s.ins == 1, "a light game: direct after the run on time with headroom");
        run(&s, 20000, 1.0, 0.03, 0.02, 1); check(s.direct && s.outs == 0, "a light game: it stays direct");
        run(&s, 2, 1.5, 0.03, 0.02, 1); run(&s, 200, 1.0, 0.03, 0.02, 1); run(&s, 2, 1.5, 0.03, 0.02, 1);
        check(s.direct, "two late frames, then two more a window later, keep it direct");
        run(&s, 1, 40.0, 0.03, 0.02, 1); run(&s, 10, 1.6, 0.9, 0.5, 1); check(s.direct, "a stall (a load, a pause) and the late frames after it are not judged");
    }
    {   nxf_low_lag s = {0};
        run(&s, 2000, 1.1, 1.01, 0.06, 1); check(!s.direct && !s.ins, "a GPU-bound game (Ocarina of Time in the field) never leaves the link");
        run(&s, 2000, 1.0, 0.80, 0.06, 1); check(!s.direct, "on time at 0.8 vsyncs of GPU time is not headroom");
        run(&s, 2000, 1.0, 0.10, 0.70, 1); check(!s.direct, "nor is 0.7 vsyncs of CPU time on the presenting thread");
        run(&s, 170, 1.0, 0.1, 0.1, 1); run(&s, 1, 1.0, 0.9, 0.1, 1); run(&s, 170, 1.0, 0.1, 0.1, 1); check(!s.direct, "one heavy frame starts the run again");
    }
    {   nxf_low_lag s = {0};   // a menu, then a scene the game cannot hold direct
        run(&s, NXF_LL_RUN, 1.0, 0.05, 0.05, 1); check(s.direct, "menu: direct");
        run(&s, NXF_LL_GRACE, 1.5, 0.9, 0.1, 1); check(s.direct, "the frames after the switch are not judged");
        run(&s, 3, 1.5, 0.9, 0.1, 1); check(!s.direct && s.outs == 1 && s.wait == NXF_LL_WAIT0, "three late frames: back to the link, 10 s before the next try");
        run(&s, 400, 1.0, 0.05, 0.05, 1); check(!s.direct, "a light scene again: not before the wait is over");
        run(&s, 300, 1.0, 0.05, 0.05, 1); check(s.direct && s.ins == 2, "then direct again");
        run(&s, NXF_LL_GRACE + 3, 1.5, 0.9, 0.1, 1); check(!s.direct && s.wait == 2 * NXF_LL_WAIT0, "a direct run that did not last doubles the wait");
        for (int i = 0; i < 8; i++) { run(&s, s.wait + NXF_LL_RUN, 1.0, 0.05, 0.05, 1); run(&s, NXF_LL_GRACE + 3, 1.5, 0.9, 0.1, 1); }
        check(!s.direct && s.wait == NXF_LL_WAIT_MAX, "the wait stops at 80 s");
        run(&s, s.wait + NXF_LL_RUN, 1.0, 0.05, 0.05, 1); run(&s, NXF_LL_CALM + NXF_LL_GRACE, 1.0, 0.05, 0.05, 1); run(&s, 3, 1.5, 0.9, 0.1, 1);
        check(!s.direct && s.wait == NXF_LL_WAIT0, "a direct run of a minute brings the wait back to 10 s");
    }
    {   nxf_low_lag s = {0};   // a 30 fps game: each frame held two vsyncs
        run(&s, NXF_LL_RUN, 2.0, 0.4, 0.3, 2); check(s.direct, "30 fps with headroom: direct");
        run(&s, 1000, 2.0, 0.4, 0.3, 2); check(s.direct && !s.outs, "30 fps: frames shown two vsyncs are on time");
        run(&s, NXF_LL_GRACE + 3, 3.0, 0.4, 0.3, 2); check(!s.direct, "30 fps: frames shown three vsyncs are late");
    }
    {   nxf_ll_trim t = {0}; int drops = 0;   // the trim
        drops += feed(&t, 600, 0.1); check(!drops, "trim: a queue that is not full drops nothing");
        drops += feed(&t, NXF_LL_TRIM_RUN - 1, 16.6); check(!drops, "trim: a full queue is left for half a second");
        drops += nxf_ll_trim_next(&t, 16.6); check(drops == 1, "trim: then one present is dropped");
        drops += feed(&t, NXF_LL_TRIM_RUN, 11.0); check(drops == 2, "trim: still full half a second later: another");
        drops += feed(&t, 2000, 0.1); check(drops == 2, "trim: empty now, no more");
        drops += feed(&t, 20, 9.0); drops += nxf_ll_trim_next(&t, 0.2); drops += feed(&t, 20, 9.0);
        check(drops == 2, "trim: one present without a wait starts the count again");
        nxf_ll_trim u = {0}; drops = 0;
        drops += feed(&u, 3000, 16.6); check(drops == NXF_LL_TRIM_MAX, "trim: a game that keeps the queue full is dropped six frames, then left alone");
        drops += feed(&u, NXF_LL_TRIM_WIN, 16.6); check(drops > NXF_LL_TRIM_MAX && drops <= 2 * NXF_LL_TRIM_MAX, "trim: and tried again a minute later");
    }
    printf("%d checks, %d failed\n", checks, fail);
    return fail != 0;
}
