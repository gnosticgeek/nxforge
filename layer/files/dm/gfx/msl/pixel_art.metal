// NXForge: Pixel art (nvn_mtl.m nxforge/pixel_art.inc): finding the art's own pixel grid in the game's picture, taking the art back to its own size, and MMPX's 2x enlargement.
// px_edges marks where the colour changes between neighbouring texels along sampled rows (the target's first nr rows) and columns (the next nr rows), for the grid finder
// (pixel_grid.h). px_restore takes one texel from the centre of each art pixel (nearest, so the colours stay exact). px_mmpx is MMPX (Morgan McGuire and Mara Gagiu, "MMPX
// Style-Preserving Pixel Art Magnification", JCGT 2021; reference code MIT licensed): each art pixel becomes 2x2, and where neighbours of one colour run on a diagonal or a 2:1
// slope the corners take that colour, so outlines and curves stay one colour per pixel instead of blurring. It compares colours exactly, which the restored art keeps.
#include <metal_stdlib>
using namespace metal;
struct V { float4 p [[position]]; float2 uv; };
vertex V px_vs(uint id [[vertex_id]]) { float2 uv = float2((id << 1) & 2, id & 2); V o; o.p = float4(uv * float2(2, -2) + float2(-1, 1), 0, 1); o.uv = uv; return o; }
// crop: the game picture's valid rectangle (x, y, w, h); nr: sampled rows and columns. ax / ay: per axis the grid's offset, scale, the art pixel at texel 0, and the crop's origin
struct PxC { int4 crop; int4 nr; float4 ax; float4 ay; };

static bool px_diff(float4 a, float4 b) { float3 d = abs(a.rgb - b.rgb); return max(d.r, max(d.g, d.b)) > 0.03f; }
fragment float px_edges(V in [[stage_in]], texture2d<float> t [[texture(0)]], constant PxC& c [[buffer(0)]]) {
  int i = int(in.p.x), row = int(in.p.y), nr = c.nr.x, cx = c.crop.x, cy = c.crop.y, cw = c.crop.z, ch = c.crop.w;
  if (row < nr) {   // along row y: texel i against i + 1
    if (i + 1 >= cw) return 0;
    int y = cy + (row * ch + ch / 2) / nr;
    return px_diff(t.read(uint2(cx + i, y)), t.read(uint2(cx + i + 1, y))) ? 1 : 0;
  }
  if (i + 1 >= ch) return 0;   // down column x: texel i against i + 1
  int x = cx + ((row - nr) * cw + cw / 2) / nr;
  return px_diff(t.read(uint2(x, cy + i)), t.read(uint2(x, cy + i + 1))) ? 1 : 0;
}
// Art pixel (i, j) of the target: the game's texel at that art pixel's centre, o + (a0 + i + 0.5) s, kept inside the crop
fragment float4 px_restore(V in [[stage_in]], texture2d<float> t [[texture(0)]], constant PxC& c [[buffer(0)]]) {
  float2 k = floor(in.p.xy);
  float u = c.ax.x + (c.ax.z + k.x + 0.5f) * c.ax.y, v = c.ay.x + (c.ay.z + k.y + 0.5f) * c.ay.y;
  int x = clamp(int(floor(u)), 0, c.crop.z - 1), y = clamp(int(floor(v)), 0, c.crop.w - 1);
  return t.read(uint2(c.crop.x + x, c.crop.y + y));
}

// MMPX, after the reference implementation (mmpx.cpp). Colours compare on RGB (a swapchain's alpha is not the picture's)
static bool eq(float4 a, float4 b) { return all(a.rgb == b.rgb); }
static bool ne(float4 a, float4 b) { return !eq(a, b); }
static bool all_eq2(float4 b, float4 a0, float4 a1) { return eq(b, a0) && eq(b, a1); }
static bool all_eq3(float4 b, float4 a0, float4 a1, float4 a2) { return eq(b, a0) && eq(b, a1) && eq(b, a2); }
static bool all_eq4(float4 b, float4 a0, float4 a1, float4 a2, float4 a3) { return eq(b, a0) && eq(b, a1) && eq(b, a2) && eq(b, a3); }
static bool any_eq3(float4 b, float4 a0, float4 a1, float4 a2) { return eq(b, a0) || eq(b, a1) || eq(b, a2); }
static bool none_eq2(float4 b, float4 a0, float4 a1) { return ne(b, a0) && ne(b, a1); }
static bool none_eq4(float4 b, float4 a0, float4 a1, float4 a2, float4 a3) { return ne(b, a0) && ne(b, a1) && ne(b, a2) && ne(b, a3); }
static float luma(float4 c) { return c.r + c.g + c.b; }
fragment float4 px_mmpx(V in [[stage_in]], texture2d<float> t [[texture(0)]]) {
  int2 o = int2(floor(in.p.xy)); int sx = o.x >> 1, sy = o.y >> 1;
  int w = int(t.get_width()), h = int(t.get_height());
#define AT(x, y) t.read(uint2(clamp(x, 0, w - 1), clamp(y, 0, h - 1)))
  float4 A = AT(sx - 1, sy - 1), B = AT(sx, sy - 1), C = AT(sx + 1, sy - 1);
  float4 D = AT(sx - 1, sy), E = AT(sx, sy), F = AT(sx + 1, sy);
  float4 G = AT(sx - 1, sy + 1), H = AT(sx, sy + 1), I = AT(sx + 1, sy + 1);
  float4 J = E, K = E, L = E, M = E;
  if (ne(A, E) || ne(B, E) || ne(C, E) || ne(D, E) || ne(F, E) || ne(G, E) || ne(H, E) || ne(I, E)) {
    float4 P = AT(sx, sy - 2), S = AT(sx, sy + 2), Q = AT(sx - 2, sy), R = AT(sx + 2, sy);
    float Bl = luma(B), Dl = luma(D), El = luma(E), Fl = luma(F), Hl = luma(H);
    // 1:1 slopes
    if ((eq(D, B) && ne(D, H) && ne(D, F)) && (El >= Dl || eq(E, A)) && any_eq3(E, A, C, G) && ((El < Dl) || ne(A, D) || ne(E, P) || ne(E, Q))) J = D;
    if ((eq(B, F) && ne(B, D) && ne(B, H)) && (El >= Bl || eq(E, C)) && any_eq3(E, A, C, I) && ((El < Bl) || ne(C, B) || ne(E, P) || ne(E, R))) K = B;
    if ((eq(H, D) && ne(H, F) && ne(H, B)) && (El >= Hl || eq(E, G)) && any_eq3(E, A, G, I) && ((El < Hl) || ne(G, H) || ne(E, S) || ne(E, Q))) L = H;
    if ((eq(F, H) && ne(F, B) && ne(F, D)) && (El >= Fl || eq(E, I)) && any_eq3(E, C, G, I) && ((El < Fl) || ne(I, H) || ne(E, R) || ne(E, S))) M = F;
    // Intersections
    if ((ne(E, F) && all_eq4(E, C, I, D, Q) && all_eq2(F, B, H)) && ne(F, AT(sx + 3, sy))) { K = F; M = F; }
    if ((ne(E, D) && all_eq4(E, A, G, F, R) && all_eq2(D, B, H)) && ne(D, AT(sx - 3, sy))) { J = D; L = D; }
    if ((ne(E, H) && all_eq4(E, G, I, B, P) && all_eq2(H, D, F)) && ne(H, AT(sx, sy + 3))) { L = H; M = H; }
    if ((ne(E, B) && all_eq4(E, A, C, H, S) && all_eq2(B, D, F)) && ne(B, AT(sx, sy - 3))) { J = B; K = B; }
    // Triangle tips
    if (Bl < El && all_eq4(E, G, H, I, S) && none_eq4(E, A, D, C, F)) { J = B; K = B; }
    if (Hl < El && all_eq4(E, A, B, C, P) && none_eq4(E, D, G, I, F)) { L = H; M = H; }
    if (Fl < El && all_eq4(E, A, D, G, Q) && none_eq4(E, B, C, I, H)) { K = F; M = F; }
    if (Dl < El && all_eq4(E, C, F, I, R) && none_eq4(E, B, A, G, H)) { J = D; L = D; }
    // 2:1 slopes
    if (ne(H, B)) {
      if (ne(H, A) && ne(H, E) && ne(H, C)) {
        if (all_eq3(H, G, F, R) && none_eq2(H, D, AT(sx + 2, sy - 1))) L = M;
        if (all_eq3(H, I, D, Q) && none_eq2(H, F, AT(sx - 2, sy - 1))) M = L;
      }
      if (ne(B, I) && ne(B, G) && ne(B, E)) {
        if (all_eq3(B, A, F, R) && none_eq2(B, D, AT(sx + 2, sy + 1))) J = K;
        if (all_eq3(B, C, D, Q) && none_eq2(B, F, AT(sx - 2, sy + 1))) K = J;
      }
    }
    if (ne(F, D)) {
      if (ne(D, I) && ne(D, E) && ne(D, C)) {
        if (all_eq3(D, A, H, S) && none_eq2(D, B, AT(sx + 1, sy + 2))) J = L;
        if (all_eq3(D, G, B, P) && none_eq2(D, H, AT(sx + 1, sy - 2))) L = J;
      }
      if (ne(F, E) && ne(F, A) && ne(F, G)) {
        if (all_eq3(F, C, H, S) && none_eq2(F, B, AT(sx - 1, sy + 2))) K = M;
        if (all_eq3(F, I, B, P) && none_eq2(F, H, AT(sx - 1, sy - 2))) M = K;
      }
    }
  }
#undef AT
  bool right = o.x & 1, down = o.y & 1;
  return down ? (right ? M : L) : (right ? K : J);
}
