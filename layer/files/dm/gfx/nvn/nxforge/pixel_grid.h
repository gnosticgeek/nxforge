// NXForge: the pixel-art grid finder (pixel_art.inc), plain C so it is tested without a GPU (dm/gfx/tests/t_pixel_art.m).
// A 2D game draws its art at a low resolution (320x180, 400x240, 426x240) and enlarges it into the 720p or 1080p picture it hands over, usually by repeating each art pixel, sometimes
// unevenly (400 into 1280 is 3.2: blocks of 3 and 4). Along one axis, the colour changes between neighbouring texels then fall only on the art pixels' seams. The finder takes how often
// the colour changes between texel x and x + 1 (h[x], counted over sampled rows or columns) and looks for the scale s (texels per art pixel, 2 to 16) and offset o whose seams take
// almost all of them. Art pixel k covers the picture's [o + k s, o + (k + 1) s) (texel x is [x, x + 1)); texel x belongs to art pixel floor((x + 0.5 - o) / s).
// Among the grids that explain the changes, a coarser one wins when it is a real multiple (1.5x the scale or more): a finer grid (half the scale) has every seam of the true one and
// explains them too. Between close scales the higher share wins, and on a tie the whole scale: where the changes sit in a band (a line of text, the HUD, the ground), an uneven
// scale near the true one (720 / 234 = 3.08 next to 3) puts them all on its seams as well. A grid in use is kept while it still explains them, so a scene whose art happens to sit
// on a coarser grid (big 2x2 blocks only) does not flip the scale back and forth. Uneven scales within PXG_NEAR_WHOLE of a whole one are not candidates: a picture with two layers on
// 3x grids of different offsets (a scrolling line of text over the HUD) has no one grid, and 720 / 241 = 2.99 would otherwise put both on its seams. For the same reason an
// uneven grid needs changes at PXG_UNEVEN_COVER of its seams: Curse of the Moon's intro text (a few lines scrolled off the 3x grid) fitted 2.80 and 3.20 down the picture.
#ifndef NXF_PIXEL_GRID_H
#define NXF_PIXEL_GRID_H
#include <math.h>
#include <stdint.h>

typedef struct { double s, o; int a0, n; double score; } pxg_axis;   // scale, offset, the art pixel at texel 0, art pixels covering the axis, share of the changes on its seams

enum { PXG_MIN_CHANGES = 48 };       // fewer changes than this say nothing (a dark or flat screen)
#define PXG_ACCEPT 0.95              // a new grid must put this share of the changes on its seams
#define PXG_KEEP 0.90                // the grid in use stays while it puts this share there
#define PXG_MULTIPLE 1.5           // a grid this many times coarser than another is a multiple of it (2x2 art blocks), not a near miss
#define PXG_TIE 0.01               // shares closer than this are a tie
#define PXG_UNEVEN_COVER 0.30      // an uneven grid needs changes at this share of its seams (whole ones are told by their offset alone)
#define PXG_NEAR_WHOLE 0.15        // an uneven scale this close to a whole one is not looked at (real ones: 3.2, 2.25, 4.5, 4.8)
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
// The share of grid (s, o)'s seams inside the axis that have any changes at all
static inline double pxg_cover(const uint32_t *h, int len, double s, double o) {
    int seams = 0, hit = 0;
    for (int k = (int)floor((0.5 - o) / s) + 1;; k++) {
        int x = (int)ceil(k * s + o - 0.5 - 1e-9);
        if (x >= len) break;
        if (x >= 1) { seams++; hit += h[x - 1] != 0; }
    }
    return seams ? (double)hit / seams : 0;
}
static inline void pxg_fill(pxg_axis *a, int len) {   // a0 and n for a's scale and offset over len texels
    a->a0 = (int)floor((0.5 - a->o) / a->s);
    int last = (int)floor((len - 0.5 - a->o) / a->s);
    a->n = last - a->a0 + 1;
}
// Whether scale s with share sc beats best: a real multiple of it (coarser) wins, a real fraction loses; between close scales the higher share (by PXG_TIE), then the whole scale
static inline int pxg_better(double s, double sc, int whole, const pxg_axis *best) {
    if (best->s <= 0 || s >= best->s * PXG_MULTIPLE - 1e-9) return 1;
    if (s * PXG_MULTIPLE <= best->s + 1e-9) return 0;
    if (fabs(sc - best->score) > PXG_TIE) return sc > best->score;
    return whole && fabs(best->s - floor(best->s + 0.5)) >= 1e-9;
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
            if (s * PXG_MULTIPLE < best.s - 1e-9) continue;   // a real multiple finer than the best: it cannot beat it
            int whole = fabs(s - floor(s + 0.5)) < 1e-9;
            if (!whole && fabs(s - floor(s + 0.5)) < PXG_NEAR_WHOLE) continue;   // 720 / 241 = 2.99: a whole grid with an offset is that art; near-whole ones fit two misaligned 3x layers
            double step = pass || whole ? 1.0 : 0.5;   // a whole scale has whole offsets; an uneven one may sit between texels
            int n_o = (int)ceil(s / step - 1e-9);   // offsets 0, step, ... below s (counted whole: clang-tidy bugprone-float-loop-counter)
            for (int oi = 0; oi < n_o; oi++) {
                double o = oi * step, sc = pxg_score(h, len, s, o, total);
                if (sc < PXG_ACCEPT) continue;
                if (!whole && pxg_cover(h, len, s, o) < PXG_UNEVEN_COVER) continue;   // a few lines of text fit an uneven grid by chance
                if (pxg_better(s, sc, whole, &best)) { best.s = s; best.o = o; best.score = sc; }
            }
        }
    }
    if (best.s < PXG_S_MIN) return 0;
    pxg_fill(&best, len); *out = best; return 1;
}
#endif
