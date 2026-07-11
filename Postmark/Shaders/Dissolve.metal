#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// ────────────────────────────────────────────────────────────────────────────
// Grain dissolve — the signature Postmark transition.
// Pixels quantize into visible grains that glint, shrink, drift upward on a
// breeze and die. Two variants: rect-masked (everything outside the
// viewfinder) and texture-masked (everything that is not the Vision subject).
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

    // Rigid per-grain drift: up and sideways on a randomized breeze.
    float rise = local * local * (70.0 + 130.0 * rnd);
    float wind = sin(rnd * 6.28318) * (18.0 + 30.0 * rnd2) * local;
    float2 offset = float2(wind, -rise);

    // Shrink grain content toward its center as it dies.
    float2 center = (cell + 0.5) * cellSize;
    float shrink = 1.0 - 0.8 * local;
    g.samplePos = center + (position - offset - center) / max(shrink, 0.06);

    // If the shrunken sample escapes this grain's cell, the grain is gone there.
    float2 rel = (g.samplePos / cellSize) - cell;
    float inCell = step(0.0, rel.x) * step(rel.x, 1.0) * step(0.0, rel.y) * step(rel.y, 1.0);

    g.alpha = (1.0 - smoothstep(0.30, 0.92, local)) * inCell;
    // A brief glint as the grain lets go — like mica catching light.
    g.glint = smoothstep(0.04, 0.16, local) * (1.0 - smoothstep(0.16, 0.45, local))
              * pow(rnd2, 3.5) * 2.2;
    return g;
}

/// Signed distance to a rounded rect (negative inside).
static inline float sdRoundRect(float2 p, float2 center, float2 halfSize, float radius) {
    float2 q = abs(p - center) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

/// The die-cut's waste: everything the mask calls background dissolves in a
/// grain wave radiating OUTWARD from the sticker's box — the press cuts,
/// the waste shatters off the cut line and drifts away. One-shot and
/// forward-only: switches never reverse it.
///
/// `size` is the content size in points, passed explicitly: for a
/// layerEffect, `.boundingRect` reports raster bounds expanded by
/// maxSampleOffset while `position` stays in content coordinates —
/// normalizing by the padded rect shifts the mask.
/// `origin` is the content rect's origin in the layer's coordinate space:
/// `position` carries the raw view's content offset, so every mask sample
/// must subtract it — sampling at position/size shifts the matte by the
/// content inset and strands un-dissolvable waste on the subject's far side.
/// `box` = sticker coverage rect (x, y, w, h) in content points.
[[ stitchable ]] half4 grainDissolveWaste(
    float2 position,
    SwiftUI::Layer layer,
    float2 size,
    float2 origin,
    texture2d<half> mask,
    float4 box,
    float progress,
    float cellSize
) {
    if (progress <= 0.0) { return layer.sample(position); }

    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = (position - origin) / size;
    half m = mask.sample(s, uv).a;

    // Kept pixels ride the matte's continuous alpha. They sit beneath the
    // bordered sticker overlay while the wave runs, then fade at its tail —
    // the overlay is about to settle away from this position, and nothing
    // may remain behind it.
    if (m > 0.5) {
        half fade = half(1.0 - smoothstep(0.8, 0.97, progress));
        return layer.sample(position) * m * fade;
    }

    float2 boxCenter = box.xy + box.zw * 0.5;
    float2 half_ = box.zw * 0.5;
    float sd = max(sdRoundRect(position, boxCenter, half_, 8.0), 0.0);
    // Normalize the wave by the waste's own extent — the farthest content
    // corner from the cut line — so the front spends the full window
    // crossing whatever waste actually exists, however large the sticker.
    // Corners live in the same (layer) space as `position` and `box`.
    float maxDist = max(
        max(sdRoundRect(origin, boxCenter, half_, 8.0),
            sdRoundRect(origin + float2(size.x, 0.0), boxCenter, half_, 8.0)),
        max(sdRoundRect(origin + float2(0.0, size.y), boxCenter, half_, 8.0),
            sdRoundRect(origin + size, boxCenter, half_, 8.0)));
    maxDist = max(maxDist, 1.0);

    float2 cell = floor(position / cellSize);
    float rnd = hash21(cell + 7.3);
    // Wide spread + strong per-grain stagger: the front visibly TRAVELS
    // outward from the cut line instead of melting all at once.
    float delay = clamp(sd / maxDist, 0.0, 1.0) * 0.85 + rnd * 0.22;
    float local = clamp((progress * 1.65 - delay) / 0.42, 0.0, 1.0);

    if (local <= 0.0) { return layer.sample(position); }
    if (local >= 1.0) { return half4(0.0); }

    GrainSample g = grainMotion(position, cell, cellSize, local);
    // Never resurrect subject pixels while sampling for a dying grain.
    float2 suv = (g.samplePos - origin) / size;
    half sm = mask.sample(s, suv).a;
    half4 c = layer.sample(g.samplePos) * half(1.0 - float(sm > 0.5));
    c.rgb += half3(g.glint) * c.a;
    c *= half(g.alpha);
    return c;
}

/// Everything outside the viewfinder rounded-rect dissolves, edge-out.
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

    // The wave travels outward from the viewfinder edge; per-grain jitter
    // keeps the front ragged but legible.
    float maxDist = length(bounds.zw) * 0.42;
    float2 cell = floor(position / cellSize);
    float rnd = hash21(cell + 13.1);
    float delay = clamp(sd / maxDist, 0.0, 1.0) * 0.62 + rnd * 0.10;
    float local = clamp((progress * 1.75 - delay) / 0.42, 0.0, 1.0);

    if (local <= 0.0) { return layer.sample(position); }
    if (local >= 1.0) { return half4(0.0); }

    GrainSample g = grainMotion(position, cell, cellSize, local);
    half4 c = layer.sample(g.samplePos);
    c.rgb += half3(g.glint) * c.a;
    c *= half(g.alpha);
    return c;
}

