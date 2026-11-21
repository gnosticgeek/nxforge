// NXForge: Border fill (nvn_mtl.m nxforge/border_fill.inc): what the window shows around a picture that does not fill it (a 16:9 game on a 16:10 screen, a Pixel-perfect
// picture, the room beside the sidebar) in place of black bars. bf_down averages the picture (or the game's banner art) into a small texture, a 4x4 box of bilinear taps over
// each of its pixels' footprints, so no detail survives to alias; bf_fill stretches that texture over the whole window (aspect fill, a little enlarged), blurs it once more with
// a 3x3 Gaussian and dims it, so the picture drawn over it afterwards keeps the eye. Into an extended linear sRGB drawable (EDR highlights) the fill is decoded to linear.
#include <metal_stdlib>
using namespace metal;
struct V { float4 p [[position]]; float2 uv; };
vertex V bf_vs(uint id [[vertex_id]]) { float2 uv = float2((id << 1) & 2, id & 2); V o; o.p = float4(uv * float2(2, -2) + float2(-1, 1), 0, 1); o.uv = uv; return o; }
// rect: the source's crop in its uv (origin, size; a negative height reads it bottom-up). a: bf_down: one tap's step in source uv (xy); bf_fill: the share of the small
// texture the window shows (xy), the dim (z), 1 when the target is linear (w)
struct BfC { float4 rect; float4 a; };
fragment float4 bf_down(V in [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]], constant BfC& c [[buffer(0)]]) {
  float2 base = c.rect.xy + in.uv * c.rect.zw; float3 sum = float3(0);
  float2 lo = min(c.rect.xy, c.rect.xy + c.rect.zw), hi = max(c.rect.xy, c.rect.xy + c.rect.zw);
  for (int j = 0; j < 4; j++) for (int i = 0; i < 4; i++) sum += t.sample(s, clamp(base + (float2(i, j) - 1.5f) * c.a.xy, lo, hi)).rgb;
  return float4(saturate(sum / 16.0f), 1);
}
fragment float4 bf_fill(V in [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]], constant BfC& c [[buffer(0)]]) {
  float2 uv = (in.uv - 0.5f) * c.a.xy + 0.5f, d = 1.0f / float2(t.get_width(), t.get_height());
  const float w[3] = {0.25f, 0.5f, 0.25f}; float3 sum = float3(0);
  for (int j = 0; j < 3; j++) for (int i = 0; i < 3; i++) sum += w[i] * w[j] * t.sample(s, uv + float2(i - 1, j - 1) * d * 1.5f).rgb;
  float3 g = saturate(sum) * c.a.z;
  if (c.a.w > 0.5f) g = select(pow((g + 0.055f) / 1.055f, 2.4f), g / 12.92f, g <= 0.04045f);
  return float4(g, 1);
}
