#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// ────────────────────────────────────────────────────────────────────────────
// Grain dissolve — the signature Postmark transition.
// Pixels quantize into small grains that glint, shrink, drift upward and die.
// Two variants: rect-masked (everything outside the viewfinder) and
// texture-masked (everything that is not the Vision subject).
// ────────────────────────────────────────────────────────────────────────────

static inline float hash21(float2 p) {
    p = fract(p * float2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

struct GrainSample {
    float2 samplePos;
    float alpha;
    float glint;
};

/// Shared grain math. `local` is this grain's 0→1 death progress.
static inline GrainSample grainMotion(float2 position, float2 cell, float cellSize, float local) {
    GrainSample g;
    float rnd  = hash21(cell);
    float rnd2 = hash21(cell + 71.7);

    // Rigid per-grain drift: up and slightly windblown sideways.
    float rise = local * local * (44.0 + 66.0 * rnd);
    float wind = sin(rnd * 6.28318) * 26.0 * local;
    float2 offset = float2(wind, -rise);

    // Shrink grain content toward its center as it dies.
    float2 center = (cell + 0.5) * cellSize;
    float shrink = 1.0 - 0.75 * local;
    g.samplePos = center + (position - offset - center) / max(shrink, 0.08);

    // If the shrunken sample escapes this grain's cell, the grain is gone there.
    float2 rel = (g.samplePos / cellSize) - cell;
    float inCell = step(0.0, rel.x) * step(rel.x, 1.0) * step(0.0, rel.y) * step(rel.y, 1.0);

    g.alpha = (1.0 - smoothstep(0.55, 1.0, local)) * inCell;
    // A brief glint as the grain lets go — like mica catching light.
    g.glint = smoothstep(0.02, 0.18, local) * (1.0 - smoothstep(0.18, 0.5, local))
              * pow(rnd2, 6.0) * 1.6;
    return g;
}

/// Signed distance to a rounded rect (negative inside).
static inline float sdRoundRect(float2 p, float2 center, float2 halfSize, float radius) {
    float2 q = abs(p - center) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

/// Everything outside the viewfinder rounded-rect dissolves.
/// vfRect = (x, y, w, h) in view points; progress 0→1.
[[ stitchable ]] half4 grainDissolveRect(
    float2 position,
    SwiftUI::Layer layer,
    float4 bounds,
    float4 vfRect,
    float vfCorner,
    float progress,
    float cellSize
) {
    float2 vfCenter = vfRect.xy + vfRect.zw * 0.5;
    float sd = sdRoundRect(position, vfCenter, vfRect.zw * 0.5, vfCorner);

    // Inside the viewfinder: untouched, always.
    if (sd <= 0.0) { return layer.sample(position); }

    // Distance-based wave: grains at the viewfinder edge go first.
    float maxDist = length(bounds.zw) * 0.55;
    float2 cell = floor(position / cellSize);
    float rnd = hash21(cell + 13.1);
    float delay = clamp(sd / maxDist, 0.0, 1.0) * 0.48 + rnd * 0.22;
    float local = clamp((progress * 1.7 - delay) / 0.5, 0.0, 1.0);

    if (local <= 0.0) { return layer.sample(position); }
    if (local >= 1.0) { return half4(0.0); }

    GrainSample g = grainMotion(position, cell, cellSize, local);
    half4 c = layer.sample(g.samplePos);
    c.rgb += half3(g.glint) * c.a;
    c *= half(g.alpha);
    return c;
}

/// Everything the mask calls background (mask alpha < 0.5) dissolves.
/// Used to lift the Vision subject out of the crop. Mask is sampled in
/// normalized coordinates over `bounds`.
[[ stitchable ]] half4 grainDissolveMask(
    float2 position,
    SwiftUI::Layer layer,
    float4 bounds,
    texture2d<half> mask,
    float progress,
    float cellSize
) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = (position - bounds.xy) / bounds.zw;
    half m = mask.sample(s, uv).a;

    if (m > 0.5) { return layer.sample(position); }

    // Wave sweeps top → bottom with per-grain jitter.
    float2 cell = floor(position / cellSize);
    float rnd = hash21(cell + 5.7);
    float delay = uv.y * 0.35 + rnd * 0.3;
    float local = clamp((progress * 1.65 - delay) / 0.5, 0.0, 1.0);

    if (local <= 0.0) { return layer.sample(position); }
    if (local >= 1.0) { return half4(0.0); }

    GrainSample g = grainMotion(position, cell, cellSize, local);
    // Never resurrect subject pixels while sampling for a dying grain.
    float2 suv = (g.samplePos - bounds.xy) / bounds.zw;
    half sm = mask.sample(s, suv).a;
    half4 c = layer.sample(g.samplePos) * half(1.0 - float(sm > 0.5));
    c.rgb += half3(g.glint) * c.a;
    c *= half(g.alpha);
    return c;
}
