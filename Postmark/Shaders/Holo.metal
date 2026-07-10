#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// Holographic foil shimmer — a soft rainbow band that sweeps across the stamp
// (reveal) or follows a tilt gesture (album detail). Masked by luminance so it
// reads as light on ink, never as a sticker on top.

static inline half3 hsv2rgb(float h, float s, float v) {
    float3 k = fmod(float3(5.0, 3.0, 1.0) + h * 6.0, 6.0);
    float3 c = v - v * s * clamp(min(k, 4.0 - k), 0.0, 1.0);
    return half3(c.x, c.y, c.z);
}

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

    // Soft band around the sweep line.
    float band = exp(-pow((proj - sweep) * 5.5, 2.0));
    // Rainbow phase varies along the band so it reads as spectra, not tint.
    float hue = fract(proj * 1.6 + sweep * 0.8);
    half3 rainbow = hsv2rgb(hue, 0.55, 1.0);

    float luma = dot(float3(color.rgb), float3(0.299, 0.587, 0.114));
    // Brightest on midtones — highlights already read as light.
    float lumaMask = smoothstep(0.08, 0.45, luma) * (1.0 - smoothstep(0.75, 1.0, luma) * 0.6);

    color.rgb += rainbow * half(band * lumaMask * strength) * color.a;
    return color;
}
