// NXForge: a variable-refresh screen (ProMotion) keeps its own mode in fullscreen when its rate is already a multiple of the game's (120 Hz for 60 and 30 fps).
// Upstream switches it to a fixed 60 Hz mode there (front_screen_match, issues #347/#348) because its display link at 60 Hz missed targets on a ProMotion screen
// in fullscreen. NXForge does not use the display link in fullscreen: the present thread takes its own drawables (pacing mode 0, nvn_mtl.m link_sync), so the
// reason does not hold, and the fixed 60 Hz mode cost frames. Mario Kart World on an M4 Pro (16 Nov 2026), races at 12-14 ms of GPU: every full screen session
// dropped 40-97 frames of each 300 at fixed 60 Hz, where a frame a moment late waits a whole 16.7 ms refresh; at the screen's own 120 Hz it waits at most 8.3 ms.
// DM_SCREEN_MATCH=1 switches as upstream does (for comparing), 0 keeps every screen's rate (upstream's switch). The game's own rate is still matched on a fixed-rate
// screen that is not a multiple (144 Hz → 120 Hz), as before.
static int nxf_screen_keeps_vrr(void) {
    static int keep = -1;
    if (keep < 0) {
        const char *e = getenv("DM_SCREEN_MATCH"); keep = !(e && !strcmp(e, "1"));
        LOG("front end: a variable-refresh screen %s in fullscreen (%s)", keep ? "keeps its own refresh rate" : "switches to a fixed-rate mode at a multiple of the game's rate",
            keep ? "NXForge default; DM_SCREEN_MATCH=1 switches it as upstream does" : "DM_SCREEN_MATCH=1");
    }
    return keep;
}
