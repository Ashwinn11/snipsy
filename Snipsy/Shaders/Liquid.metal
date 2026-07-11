#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// ────────────────────────────────────────────────────────────────────────────
// Liquid poke — tap the die-cut sticker and a capillary wave rolls out from
// the touch point, then damps away. Displacement is zero at t ≤ 0 (attack
// ramp) and decays to zero, so the effect enters and leaves seamlessly.
// ────────────────────────────────────────────────────────────────────────────

[[ stitchable ]] float2 liquidPoke(
    float2 position,
    float2 center,
    float time,
    float amplitude
) {
    float2 d = position - center;
    float dist = max(length(d), 0.001);
    float t = max(time, 0.0);

    // Crest travels outward; short wavelength reads as surface tension.
    float wave = sin(dist * 0.085 - t * 9.0);
    float attack = smoothstep(0.0, 0.07, t);
    float decay = exp(-t * 3.0);
    float falloff = exp(-dist * 0.011);
    float amp = amplitude * attack * decay * falloff;

    return position + (d / dist) * wave * amp;
}
