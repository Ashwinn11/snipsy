#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// Sheen — a soft band of light that sweeps across the stamp (reveal) or
// follows a tilt gesture (album detail). Pure brightness, no hue: paper
// catching the light, not foil. Signature unchanged from the old rainbow
// shimmer so every call site and warmup stays valid.

[[ stitchable ]] half4 holoShimmer(
    float2 position,
    half4 color,
    float4 bounds,
    float sweep,      // 0→1 band position along the sweep axis (or tilt-driven)
    float2 dir,       // sweep direction (normalized-ish)
    float strength
) {
    if (color.a < 0.01 || strength < 0.001) { return color; }

    float2 uv = (position - bounds.xy) / max(bounds.zw, 2.0);
    float proj = dot(uv - 0.5, normalize(dir)) + 0.5;

    // One soft highlight band, squared for a gentle core.
    float band = 1.0 - smoothstep(0.0, 0.22, fabs(proj - sweep));
    band *= band;

    float luma = dot(float3(color.rgb), float3(0.299, 0.587, 0.114));
    // Reads as light on the surface: midtones and highlights carry it.
    float lumaMask = 0.35 + 0.65 * luma;

    color.rgb += half3(half(band * lumaMask * strength * 0.85)) * color.a;
    return color;
}
