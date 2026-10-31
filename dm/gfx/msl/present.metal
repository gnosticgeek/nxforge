// The present: the frame drawn into the drawable, cropped (nvn_mtl.m present_pipeline), and NXForge's present filters and anti-aliasing (fx; nvn_mtl.m pfx_params, mtl_present_aa)
#include <metal_stdlib>
using namespace metal;
struct V { float4 p [[position]]; float2 uv; };
vertex V vs(uint id [[vertex_id]]) { float2 uv = float2((id << 1) & 2, id & 2); V o; o.p = float4(uv * float2(2, -2) + float2(-1, 1), 0, 1); o.uv = uv; return o; }
struct Crop { float4 rect; float4 edge; float4 fx; };   // fx: the present filter's strength, output pixels per source texel x / y, scanline height in source rows (pfx_params)
#define UV clamp(in.uv * c.rect.zw + c.rect.xy, c.edge.xy, c.edge.zw)
fragment float4 fs(V in [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]], constant Crop& c [[buffer(0)]]) { return t.sample(s, UV); }
// Sharpen (contrast-adaptive, after FidelityFX CAS): the cross one source texel away; the weight falls where the cross already spans the range, and strength 0 to 1 is CAS's 0 to 1
fragment float4 fs_sharpen(V in [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]], constant Crop& c [[buffer(0)]]) {
  float2 uv = UV, d = 1.0f / float2(t.get_width(), t.get_height());
  float3 m = t.sample(s, uv).rgb, n = t.sample(s, clamp(uv - float2(0, d.y), c.edge.xy, c.edge.zw)).rgb, so = t.sample(s, clamp(uv + float2(0, d.y), c.edge.xy, c.edge.zw)).rgb;
  float3 w = t.sample(s, clamp(uv - float2(d.x, 0), c.edge.xy, c.edge.zw)).rgb, e = t.sample(s, clamp(uv + float2(d.x, 0), c.edge.xy, c.edge.zw)).rgb;
  float3 lo = min(m, min(min(n, so), min(w, e))), hi = max(m, max(max(n, so), max(w, e)));
  float3 amp = sqrt(saturate(min(lo, 1.0f - hi) / max(hi, float3(1e-4f))));
  float3 wt = -amp / mix(8.0f, 5.0f, saturate(c.fx.x));
  return float4(saturate((m + (n + so + w + e) * wt) / (1.0f + 4.0f * wt)), 1);
}
// FXAA (after Timothy Lottes' FXAA 3.11 console pass), the present's anti-aliasing (mtl_present_aa): where the 2x2 diagonal neighbours span a contrast edge, blend along the edge's
// direction, two taps or four, keeping the two-tap blend when the four-tap one leaves the neighbourhood's luma range. Runs on the game's own pixels before any upscaling (aa_encode)
fragment float4 fs_fxaa(V in [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]], constant Crop& c [[buffer(0)]]) {
  float2 uv = UV, d = 1.0f / float2(t.get_width(), t.get_height()); const float3 L = float3(0.299f, 0.587f, 0.114f);
  float4 m = t.sample(s, uv); float lm = dot(m.rgb, L);
  float nw = dot(t.sample(s, clamp(uv + float2(-d.x, -d.y), c.edge.xy, c.edge.zw)).rgb, L), ne = dot(t.sample(s, clamp(uv + float2(d.x, -d.y), c.edge.xy, c.edge.zw)).rgb, L);
  float sw = dot(t.sample(s, clamp(uv + float2(-d.x, d.y), c.edge.xy, c.edge.zw)).rgb, L), se = dot(t.sample(s, clamp(uv + float2(d.x, d.y), c.edge.xy, c.edge.zw)).rgb, L);
  float lo = min(lm, min(min(nw, ne), min(sw, se))), hi = max(lm, max(max(nw, ne), max(sw, se)));
  if (hi - lo < max(0.0312f, hi * 0.125f)) return m;   // no edge worth smoothing: the pixel as it is
  float2 dir = float2((sw + se) - (nw + ne), (nw + sw) - (ne + se));
  float red = max((nw + ne + sw + se) * 0.03125f, 1.0f / 128.0f);
  dir = clamp(dir / (min(abs(dir.x), abs(dir.y)) + red), -8.0f, 8.0f) * d;
  float3 a = 0.5f * (t.sample(s, clamp(uv - dir / 6.0f, c.edge.xy, c.edge.zw)).rgb + t.sample(s, clamp(uv + dir / 6.0f, c.edge.xy, c.edge.zw)).rgb);
  float3 b = 0.5f * a + 0.25f * (t.sample(s, clamp(uv - dir * 0.5f, c.edge.xy, c.edge.zw)).rgb + t.sample(s, clamp(uv + dir * 0.5f, c.edge.xy, c.edge.zw)).rgb);
  float lb = dot(b, L);
  return float4(lb < lo || lb > hi ? a : b, m.a);
}
// Pixel (sharp bilinear): inside a texel the coordinate snaps to its centre, and over the last half output pixel before a seam it moves on linearly to the next one
fragment float4 fs_pixel(V in [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]], constant Crop& c [[buffer(0)]]) {
  float2 sz = float2(t.get_width(), t.get_height()), tx = UV * sz, k = max(abs(c.fx.yz), float2(1.0f));
  float2 f = fract(tx) - 0.5f, r = 0.5f - 0.5f / k;
  float2 g = (f - clamp(f, -r, r)) * k + 0.5f;
  return t.sample(s, clamp((floor(tx) + g) / sz, c.edge.xy, c.edge.zw));
}
// CRT: each scanline (fx.w source rows) lit brightest at its centre and darkest at its edges, and every third output column leaning red, green, blue; strength scales both (the row is taken before UV's clamp to the half-texel edge, which would light the image's first and last half row fully)
fragment float4 fs_crt(V in [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]], constant Crop& c [[buffer(0)]]) {
  float2 uv = UV; float k = saturate(c.fx.x); float3 col = t.sample(s, uv).rgb;
  float row = fract((in.uv.y * c.rect.w + c.rect.y) * t.get_height() / max(c.fx.w, 1.0f)), scan = 0.5f + 0.5f * cos(6.2831853f * (row - 0.5f));
  float vis = smoothstep(1.0f, 2.5f, c.fx.z * max(c.fx.w, 1.0f));   // scanlines fade out where a line spans under 2.5 output pixels: finer ones only make moire (after RetroReplay's)
  col *= mix(1.0f, 0.3f + 0.7f * scan, k * vis);
  uint ph = uint(in.p.x) % 3u; float3 mask = ph == 0u ? float3(1, 0.7f, 0.7f) : ph == 1u ? float3(0.7f, 1, 0.7f) : float3(0.7f, 0.7f, 1);
  col *= mix(float3(1), mask, float3(0.5f * k));
  return float4(saturate(col * (1.0f + 0.35f * k * vis)), 1);
}
// The CRT-Lottes and LCD Grid filters see the picture on a grid of cells fx.w source rows high and wide (the scanline height: about 240 lines by default), so a game that enlarges
// its own pixel art gets one cell per art pixel. A cell's colour is the source texel at its centre, nearest-sampled and clamped to the valid area
static float3 cell_texel(texture2d<float> t, float2 cell, float n, float4 edge) {
  constexpr sampler near(coord::normalized, address::clamp_to_edge, filter::nearest);
  float2 sz = float2(t.get_width(), t.get_height());
  return t.sample(near, clamp((floor(cell) * n + floor(n * 0.5f) + 0.5f) / sz, edge.xy, edge.zw)).rgb;
}
// CRT-Lottes: Timothy Lottes' public-domain CRT shader ("PUBLIC DOMAIN CRT STYLED SCAN-LINE SHADER by Timothy Lottes. Please take and use, change, or whatever."; libretro's
// crt/shaders/crt-lottes.slang), in RetroReplay's Metal port (GameVideo/CRTLottesShader.swift): Gaussian beams over the 3 nearest rows of cells, a wider bloom over 5, and the
// stretched VGA shadow mask (shadowMask 3, maskDark 0.5, maskLight 1.5) on the output pixels; no curvature, so the whole picture shows. Strength mixes it with the plain picture
static float3 lot_lin(float3 c) { return select(pow((c + 0.055f) / 1.055f, 2.4f), c / 12.92f, c <= 0.04045f); }
static float3 lot_srgb(float3 c) { return select(1.055f * pow(c, 0.41666f) - 0.055f, c * 12.92f, c < 0.0031308f); }
static float lot_gauss(float d, float hard) { return exp2(hard * d * d); }
static float3 lot_row(texture2d<float> t, float2 g, float row, int radius, float hard, float dx, float n, float4 edge) {
  float3 col = 0; float tot = 0;
  for (int x = -radius; x <= radius; x++) { float w = lot_gauss(dx + float(x), hard); col += lot_lin(cell_texel(t, g + float2(x, row), n, edge)) * w; tot += w; }
  return col / tot;
}
fragment float4 fs_lottes(V in [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]], constant Crop& c [[buffer(0)]]) {
  float n = max(c.fx.w, 1.0f), k = saturate(c.fx.x); float2 sz = float2(t.get_width(), t.get_height());
  float2 g = (in.uv * c.rect.zw + c.rect.xy) * sz / n, d = 0.5f - fract(g);
  float3 beam = 0, bloom = 0;
  for (int r = -1; r <= 1; r++) beam += lot_row(t, g, float(r), r == 0 ? 2 : 1, -3.0f, d.x, n, c.edge) * lot_gauss(d.y + float(r), -8.0f);
  for (int r = -2; r <= 2; r++) bloom += lot_row(t, g, float(r), abs(r) == 2 ? 2 : 3, -1.5f, d.x, n, c.edge) * lot_gauss(d.y + float(r), -2.0f);
  float ph = fract((in.p.x + in.p.y * 3.0f) * 0.166666666f); float3 mask = 0.5f;
  if (ph < 0.333f) mask.r = 1.5f; else if (ph < 0.666f) mask.g = 1.5f; else mask.b = 1.5f;
  float3 crt = saturate(lot_srgb((beam + bloom * 0.15f) * mask));
  return float4(mix(t.sample(s, UV).rgb, crt, k), 1);
}
// LCD Grid: each cell a lit square with a dark gap of about one output pixel around it and its three thirds leaning red, green, blue, like a handheld's screen; the grid fades
// out where a cell spans under 4 output pixels (it would only make moire there). Strength scales the gap and the subpixels
fragment float4 fs_lcd(V in [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]], constant Crop& c [[buffer(0)]]) {
  float n = max(c.fx.w, 1.0f), k = saturate(c.fx.x); float2 sz = float2(t.get_width(), t.get_height());
  float2 g = (in.uv * c.rect.zw + c.rect.xy) * sz / n, f = fract(g), px = max(abs(c.fx.yz) * n, float2(1.0f));
  float vis = smoothstep(2.0f, 4.0f, min(px.x, px.y)) * k;
  float2 dist = min(f, 1.0f - f) * px; float lit = saturate(min(dist.x, dist.y) / 0.75f);
  float third = floor(f.x * 3.0f); float3 sub = third < 1.0f ? float3(1, 0.6f, 0.6f) : third < 2.0f ? float3(0.6f, 1, 0.6f) : float3(0.6f, 0.6f, 1);
  float3 col = cell_texel(t, g, n, c.edge) * mix(float3(1), sub * mix(0.25f, 1.0f, lit), vis);
  return float4(saturate(col * (1.0f + 0.3f * vis)), 1);
}
