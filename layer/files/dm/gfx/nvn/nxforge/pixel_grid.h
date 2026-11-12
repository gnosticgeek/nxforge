// NXForge: the pixel-art grid finder (pixel_art.inc), plain C so it is tested without a GPU (dm/gfx/tests/t_pixel_art.m).
// A 2D game draws its art at a low resolution (320x180, 400x240, 426x240) and enlarges it into the 720p or 1080p picture it hands over, usually by repeating each art pixel, sometimes
// unevenly (400 into 1280 is 3.2: blocks of 3 and 4). Along one axis, the colour changes between neighbouring texels then fall only on the art pixels' seams. The finder takes how often
// the colour changes between texel x and x + 1 (h[x], counted over sampled rows or columns) and looks for the scale s (texels per art pixel, 2 to 16) and offset o whose seams take
// almost all of them. Art pixel k covers the picture's [o + k s, o + (k + 1) s) (texel x is [x, x + 1)); texel x belongs to art pixel floor((x + 0.5 - o) / s).
// Among the grids that explain the changes, the coarsest wins: a finer grid (half the scale) has every seam of the true one and explains them too. A grid in use is kept while it
// still explains them, so a scene whose art happens to sit on a coarser grid (big 2x2 blocks only) does not flip the scale back and forth.
#ifndef NXF_PIXEL_GRID_H
#define NXF_PIXEL_GRID_H
#include <math.h>
#include <stdint.h>

typedef struct { double s, o; int a0, n; double score; } pxg_axis;   // scale, offset, the art pixel at texel 0, art pixels covering the axis, share of the changes on its seams

enum { PXG_MIN_CHANGES = 48 };       // fewer changes than this say nothing (a dark or flat screen)
#define PXG_ACCEPT 0.95              // a new grid must put this share of the changes on its seams
#define PXG_KEEP 0.90                // the grid in use stays while it puts this share there
#define PXG_S_MIN 2.0
#define PXG_S_MAX 16.0

// The share of the changes that fall on the seams of grid (s, o); total: the sum of h[0 .. len - 2]
static inline double pxg_score(const uint32_t *h, int len, double s, double o, uint64_t total) {
    if (!total || s < 1) return 0;
    uint64_t on = 0;
    // seam k lies between texels x - 1 and x, where x is the first texel of art pixel k: x = ceil(k s + o - 0.5)
    for (int k = (int)floor((0.5 - o) / s) + 1;; k++) {
        double xs = k * s + o - 0.5; int x = (int)ceil(xs - 1e-9);
        if (x >= len) break;
        if (x >= 1) on += h[x - 1];
    }
    return (double)on / (double)total;
}
static inline void pxg_fill(pxg_axis *a, int len) {   // a0 and n for a's scale and offset over len texels
    a->a0 = (int)floor((0.5 - a->o) / a->s);
    int last = (int)floor((len - 0.5 - a->o) / a->s);
    a->n = last - a->a0 + 1;
}
// Returns 1 with *out set when a grid explains the changes, 0 when none does, -1 when there are too few changes to tell (*out untouched). keep: the grid in use, or NULL
static inline int pxg_find(const uint32_t *h, int len, const pxg_axis *keep, pxg_axis *out) {
    if (len < 8) return -1;
    uint64_t total = 0;
    for (int x = 0; x + 1 < len; x++) total += h[x];
    if (total < PXG_MIN_CHANGES) return -1;
    if (keep && keep->s >= PXG_S_MIN) {
        double sc = pxg_score(h, len, keep->s, keep->o, total);
        if (sc >= PXG_KEEP) { *out = *keep; out->score = sc; pxg_fill(out, len); return 1; }
    }
    pxg_axis best = {0, 0, 0, 0, 0};
    // Candidates: the art filling the axis (s = len / W for every whole W), and whole scales with any whole offset (art with a border)
    int w_lo = (int)ceil(len / PXG_S_MAX), w_hi = (int)floor(len / PXG_S_MIN);
    for (int pass = 0; pass < 2; pass++) {
        int lo = pass ? 2 : w_lo, hi = pass ? (int)PXG_S_MAX : w_hi;
        for (int i = lo; i <= hi; i++) {
            double s = pass ? (double)i : (double)len / i;
            if (s < best.s - 1e-9) continue;   // the coarsest wins: a finer one cannot beat it
            double step = pass || fabs(s - floor(s + 0.5)) < 1e-9 ? 1.0 : 0.5;   // a whole scale has whole offsets; an uneven one may sit between texels
            for (double o = 0; o < s - 1e-9; o += step) {
                double sc = pxg_score(h, len, s, o, total);
                if (sc < PXG_ACCEPT) continue;
                if (s > best.s + 1e-9 || sc > best.score) { best.s = s; best.o = o; best.score = sc; }
            }
        }
    }
    if (best.s < PXG_S_MIN) return 0;
    pxg_fill(&best, len); *out = best; return 1;
}
#endif
