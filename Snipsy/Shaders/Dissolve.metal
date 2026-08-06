#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// ────────────────────────────────────────────────────────────────────────────
// Grain dissolve — the signature Snipsy transition.
// Pixels quantize into visible grains that glint, shrink, drift upward on a
// breeze and die. Two variants: rect-masked (everything outside the
// viewfinder) and texture-masked (everything that is not the Vision subject).
// ────────────────────────────────────────────────────────────────────────────

static inline float hash21(float2 p) {
    p = fract(p * float2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

/// Smooth value noise — soft organic clumps, used to decorrelate grain
/// death times so no geometric front is ever readable in the dissolve.
static inline float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

struct GrainSample {
    float2 samplePos;
    float alpha;
    float glint;
};

/// Shared grain math. `local` is this grain's 0→1 death progress.
/// `windBias` adds a one-directional gust (+x): dust streams off with
/// the sweep instead of scattering symmetrically. 0 = neutral breeze.
static inline GrainSample grainMotion(float2 position, float2 cell, float cellSize, float local, float windBias) {
    GrainSample g;
    float rnd  = hash21(cell);
    float rnd2 = hash21(cell + 71.7);

    // Rigid per-grain drift: up and sideways on a randomized breeze.
    float rise = local * local * (70.0 + 130.0 * rnd);
    float wind = (sin(rnd * 6.28318) * (18.0 + 30.0 * rnd2)
                + windBias * (24.0 + 30.0 * rnd2)) * local;
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

/// Inside the perforated stamp silhouette?
///
/// Mirrors `PerforatedRect` exactly — same hole radius, the same
/// `round(length / pitch)` count, holes punched at every step along all four
/// edges with the corners shared between two edges. The shape the dust
/// leaves behind and the shape the reveal draws have to be the same object,
/// so this math is a transcription, not an approximation: change one and
/// re-derive the other.
static inline bool insidePerforated(float2 p, float4 r, float holeFraction, float spacing) {
    float2 lo = r.xy;
    float2 hi = lo + r.zw;
    if (p.x < lo.x || p.y < lo.y || p.x > hi.x || p.y > hi.y) { return false; }

    float hr = max(2.0, r.z * holeFraction);
    float pitch = max(hr * spacing, 1.0);
    float nx = max(2.0, round(r.z / pitch));
    float ny = max(2.0, round(r.w / pitch));
    float stepX = r.z / nx;
    float stepY = r.w / ny;

    // Every hole on an edge shares that edge's coordinate, so the nearest
    // one is just the nearest index — no need to walk the ring.
    float cx = lo.x + clamp(round((p.x - lo.x) / stepX), 0.0, nx) * stepX;
    float cy = lo.y + clamp(round((p.y - lo.y) / stepY), 0.0, ny) * stepY;

    return distance(p, float2(cx, lo.y)) >= hr
        && distance(p, float2(cx, hi.y)) >= hr
        && distance(p, float2(lo.x, cy)) >= hr
        && distance(p, float2(hi.x, cy)) >= hr;
}

/// The die-cut's waste: everything the mask calls background dissolves in
/// one ragged dust front sweeping left→right across the sheet — and the
/// dying grains STREAM off on the gust, long breaking streaks that cross
/// the screen and exit its right edge — while the subject stays.
/// One-shot and forward-only: switches never reverse it.
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

    // Launch phase at this pixel: the ragged left→right front. `box` no
    // longer steers the wave; the cut line only decides what stays. The
    // sweep field extends a full flight length PAST the sheet's right
    // edge, so the front — and the debris it carries — travels
    // continuously off the sheet and across the screen instead of only
    // bursting out at the wave's end.
    float sweep = clamp((position.x - origin.x) / max(size.x + 340.0, 1.0),
                        0.0, 1.0);
    float2 cellP = floor(position / cellSize);
    float delay = sweep * 0.71
                + vnoise(position / 60.0) * 0.10
                + hash21(cellP + 7.3) * 0.05;
    float window = 0.18 + 0.12 * hash21(cellP + 3.7);
    float lp = clamp((progress * (0.86 + window) - delay) / window, 0.0, 1.0);

    if (lp <= 0.0) { return layer.sample(position); }
    if (lp >= 1.0) { return half4(0.0); }

    // Flight, INVERSE-MAPPED: each output pixel asks "what content has
    // flown HERE?" and samples backward along the gust — rightward with a
    // slight loft, sheared by a smooth flow field so the dust tears into
    // streaks instead of sliding as one sheet. The displacement depends
    // only on (position, progress), so the inversion is exact and grains
    // can travel any distance. (grainMotion's in-cell trick CANNOT carry
    // this: a grain dies the moment its offset exceeds its own ~cell, so
    // no windBias value makes it stream — that path is for the in-place
    // crumble of the capture dissolve only.)
    float flow = vnoise(position / 46.0 + float2(progress * 2.0, 0.0));
    float S = lp * lp * 340.0;
    float2 src = position - float2(S * (0.8 + 0.4 * flow),
                                   -S * (0.10 + 0.22 * flow));

    // Nothing ever flew out of the empty padding, and the subject never
    // streams — only true waste rides the wind.
    float2 suv = (src - origin) / size;
    if (suv.x < 0.0 || suv.y < 0.0 || suv.x > 1.0 || suv.y > 1.0) {
        return half4(0.0);
    }
    if (mask.sample(s, suv).a > 0.5) { return half4(0.0); }

    half4 c = layer.sample(src);

    // Break the streaks into grains (keyed to the SOURCE cell so specks
    // travel with their content), glint at launch, dissipate along the
    // flight, and be gone entirely by lp 1.
    float2 cellS = floor(src / cellSize);
    float speck = mix(1.0, 0.42 + 0.58 * step(0.30, hash21(cellS + 5.1)),
                      smoothstep(0.04, 0.30, lp));
    float glint = smoothstep(0.02, 0.10, lp) * (1.0 - smoothstep(0.10, 0.32, lp))
                * pow(hash21(cellS + 2.2), 3.5) * 2.2;
    float fade = (1.0 - smoothstep(0.10, 0.92, S / 340.0))
               * (1.0 - smoothstep(0.60, 1.0, lp));
    c.rgb += half3(glint) * c.a;
    c *= half(speck * fade);
    return c;
}

/// Everything outside the stamp plate dissolves: a ragged dust front sweeps
/// the screen left→right (the plate itself is untouchable). `plate` =
/// (x, y, w, h) in view points; progress 0→1.
///
/// The kept region is the perforated silhouette, not a plain rounded rect:
/// the wave carves the teeth as its front crosses them, so the capture never
/// resolves into a bare photo that a later beat has to turn into a stamp —
/// what the dust uncovers is already the artifact.
///
/// `size` is the CONTENT size in points, passed explicitly — a
/// layerEffect's .boundingRect is padded by maxSampleOffset, and
/// normalizing the sweep by the padded rect strands the front short of
/// the right edge.
[[ stitchable ]] half4 grainDissolveRect(
    float2 position,
    SwiftUI::Layer layer,
    float2 size,
    float4 plate,
    float holeFraction,
    float holeSpacing,
    float progress,
    float cellSize
) {
    // Inside the plate: untouched, always.
    if (insidePerforated(position, plate, holeFraction, holeSpacing)) {
        return layer.sample(position);
    }

    // Thanos snap: one ragged dust front sweeps across the whole screen,
    // left to right. Grains crumble as it passes and stream off with the
    // gust; noise clumps and per-grain chance tear the front's edge so it
    // never reads as a clean line — and never echoes the plate's outline.
    float sweep = clamp(position.x / max(size.x, 1.0), 0.0, 1.0);
    float2 cell = floor(position / cellSize);
    float rnd = hash21(cell + 13.1);
    float clump = vnoise(position / 74.0);
    // Sweep-dominant: the jitter budget stays small so the front remains
    // ONE coherent traveling wave all the way to the far edge — too much
    // spread and the trailing side fades in place instead of being swept.
    float delay = sweep * 0.71
                + clump * 0.10
                + rnd * 0.05;
    // Per-grain lifespan varies a little — max delay (0.86) + any window
    // still lands by progress 1.
    float window = 0.18 + 0.12 * hash21(cell + 3.7);
    float local = clamp((progress * (0.86 + window) - delay) / window, 0.0, 1.0);

    if (local <= 0.0) { return layer.sample(position); }
    if (local >= 1.0) { return half4(0.0); }

    GrainSample g = grainMotion(position, cell, cellSize, local, 1.0);
    half4 c = layer.sample(g.samplePos);
    c.rgb += half3(g.glint) * c.a;
    c *= half(g.alpha);
    return c;
}

