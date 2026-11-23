// The screen t_vi_display tells hle_vi.c of (its own file, to win over hle_vi.c's weak front_display_pixels): 0 x 0 for not known
int g_w, g_h;
int front_display_pixels(int *w, int *h) { if (!g_w) return 0; *w = g_w; *h = g_h; return 1; }
// what else hle_vi.c calls, which these checks do not reach: no frames, no EDR
#include <stdint.h>
uint64_t dm_nvn_frame_count(void) { return 0; }
void front_screen_edr(float *potential, float *current) { *potential = *current = 1; }
float front_launch_edr_potential(void) { return 1; }
void mtl_present_layer(uint32_t w, uint32_t h) { (void)w; (void)h; }   // the present takes a sized layer's shape (nvn_mtl.m): no present here
// the frame history (nn::vi::ListFrameHistory) hle_vi.c keeps at each present: no presents and a still clock here
uint64_t now_ns(void) { return 0; }
uint64_t guest_ns(void) { return 0; }
void mtl_present_progress(uint64_t *queued, uint64_t *done) { *queued = *done = 0; }
double mtl_presented_time(uint64_t n) { (void)n; return 0; }
// the HDR answers hle_vi.c gives (nvn/hdr.c, upstream PR #3009): these checks reach none, so HDR off and the default paper white
int dm_hdr_paper_white(void) { return 203; }
int dm_hdr_answer(uint16_t *peak) { if (peak) *peak = 0; return 0; }
void dm_hdr_meta_set(int which, int a, int b) { (void)which; (void)a; (void)b; }
