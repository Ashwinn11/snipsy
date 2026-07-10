# Postmark — Design Language

**Concept**: Every photo becomes a postage stamp. Your camera becomes a philatelist's
press; your album, a collector's book. Shoot → the world outside the viewfinder
dissolves into grains → the subject is lifted (Apple Vision) → a perforated stamp is
struck, named, and cancelled with a postmark as it enters your collection.

Inspiration: CapWords (ADA 2025 winner) — warm paper, cutout stickers with white
borders, editorial serif dates, dot-grid album pages. We push it toward *postal*:
perforations, cancellation marks, denominations, engraved serif caps.

## Palette
| Token        | Value                        | Use |
|--------------|------------------------------|-----|
| `paper`      | #F4EFE6                      | album/reveal background |
| `paperDeep`  | #EAE2D3                      | cards, wells |
| `ink`        | #221F1A                      | primary text, postmark |
| `inkSoft`    | #837C6E                      | secondary text |
| `postalRed`  | #C7402D                      | accent: shutter, keep, seals |
| stamp tints  | photo dominant color, muted toward paper | stamp paper |

Camera screen is dark (live feed) with white/glass chrome; everything after capture
lives on warm paper.

## Type
- **New York (system serif)** — date headers, stamp captions (uppercase, tracked +1.5,
  semibold = engraved caps), wordmark.
- **SF Pro / Rounded** — UI chrome, counters.

## Motion
- Springs: `response 0.42–0.55, damping 0.72–0.82`. Nothing linear except shader time.
- **Shutter**: press = inner disc 0.86 scale; release fires; iris flash blink.
- **Grain dissolve** (Metal): wave from viewfinder edge outward; pixels become grains
  that shrink, glint, drift up and die. 1.35 s. Haptic: soft continuous texture.
- **Stamp assembly**: crop glides from viewfinder to center; second grain pass eats
  everything but the Vision subject; perforated paper unfurls behind; caption rises
  letter by letter; № and year fade in.
- **Cancellation**: on Keep, postmark strikes (scale 1.6→1, rot −14°→−8°, heavy haptic),
  then the stamp arcs into the collection pill; pill bounces, count ticks.
- **Album**: staggered entrance; cells rotated ±1.2° (organic); detail = matched
  geometry morph; drag tilts in 3D with holographic shimmer following the tilt.

## Screens
1. **Camera** — full-bleed feed. Viewfinder 4:5 (~78% w), corner brackets + faint
   perforation dots (the stamp metaphor foreshadowed). Chrome: collection pill
   (bottom-left, last-stamp thumb + count), shutter (center), flip (bottom-right),
   flash (top-right). Liquid glass chrome.
2. **Developing** — frozen frame, grain dissolve, Vision runs concurrently.
3. **Reveal** — stamp assembles on paper + dot grid. Tap title to rename.
   Retake (ghost) / Keep (postal red pill).
4. **Album** — slides up. Serif day headers, 2-col stamp grid, empty state = dotted
   outline stamp. Detail: tilt + holo, share (flattened PNG), rename, delete.

## Details ledger (sweat these)
- Perforation holes: r ≈ 3.5% of width, hole at every corner, spacing ≈ 2.6r.
- Paper: procedural speckle + fiber noise shader, faint edge shading; never flat hex.
- Postmark: double circle, arc text "POSTMARK • COLLECTION", date center, 3 wavy
  killer bars; ink at 78% with noise mask (real ink never prints solid).
- Denomination: "№ n" (collection index), year top-right.
- Holo shimmer: rainbow band, masked by luminance, angle follows tilt/sweep. Subtle.
- Launch screen = paper color (no black flash).
- Empty states, permission-denied state (friendly, with Settings link).
- Simulator: demo feed (bundled photos w/ Ken Burns drift, swipe to change subject);
  Vision falls back to precomputed masks so the sim demo equals device magic.
