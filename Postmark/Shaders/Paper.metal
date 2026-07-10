#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// Paper grain — procedural speckle + fibers so stamp paper and album pages
// never render as flat hex fills. Subtle by design: visible on close look,
// felt more than seen.

static inline float phash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static inline float vnoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = phash(i);
    float b = phash(i + float2(1, 0));
    float c = phash(i + float2(0, 1));
    float d = phash(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

[[ stitchable ]] half4 paperGrain(
    float2 position,
    half4 color,
    float seed,
    float strength
) {
    if (color.a < 0.01) { return color; }

    float2 p = position + seed * 61.7;
    // Fine tooth.
    float tooth = vnoise(p * 0.9) - 0.5;
    // Longer horizontal fibers.
    float fiber = vnoise(float2(p.x * 0.12, p.y * 1.7)) - 0.5;
    // Sparse darker flecks, like recycled pulp.
    float fleck = step(0.992, phash(floor(p / 2.0))) * 0.5;

    float shade = 1.0 + (tooth * 0.5 + fiber * 0.35) * strength - fleck * strength * 0.35;
    color.rgb *= half(clamp(shade, 0.0, 1.15));
    return color;
}

// Ink texture for the postmark — real cancellation ink never prints solid.
// Erodes edges and opens pinholes in the strokes.
[[ stitchable ]] half4 inkBleed(
    float2 position,
    half4 color,
    float seed
) {
    if (color.a < 0.01) { return color; }
    float n = vnoise(position * 1.4 + seed * 31.0);
    float n2 = vnoise(position * 5.0 - seed * 17.0);
    float erode = smoothstep(0.24, 0.62, n * 0.72 + n2 * 0.38);
    color *= half(0.55 + 0.45 * erode);
    return color;
}
