# Postmark — Progress & Verification Log

## Status: feature-complete v1, fully verified in simulator (iPhone 17 Pro, iOS 26.5)

### Verified end-to-end (screenshots + frame-by-frame video audits)
- **Camera**: demo feed with Ken Burns drift, scene swipe, viewfinder
  brackets + perforation dots, POSTMARK wordmark, glass chrome, collection
  pill with live mini-stamp thumb + count.
- **Capture → develop**: shutter blink beat (min 0.26 s hold), pixel-exact
  frozen frame, grain dissolve (wave from viewfinder edge outward, grains
  glint + drift upward), dim continuity carried from camera into dissolve.
- **Reveal**: crop glides viewfinder → center, mask grain pass lifts the
  Vision subject, perforated paper unfurls, letter-stagger caption,
  holographic sweep, № + year, tap-caption rename (dashed affordance),
  postmark strike on Keep, fly-to-pill with pill bounce + count tick.
- **Album**: day-grouped 2-col grid, alternating cell tilt, staggered
  entrance, matched-geometry detail, 3D tilt + holo following the finger,
  rename (live + persisted), delete (confirm dialog + file cleanup), share
  sheet with flattened stamp preview, empty state.
- **Styles**: cutout (die-cut sticker w/ white border) and classic
  (full-frame photo) both exercised — coffee scene auto-fell back to classic
  because the cup filled the crop (coverage > 92%).
- **Tints**: derived per subject — sage (cactus), warm gray (coffee), pink
  (teapot), dusty rose (robot).

### Perf/stability fixes landed
- Shader precompilation at launch (first capture stalled ~1 s before).
- Incremental demo-feed decode off-main (was ~2 s white launch; now dark
  launch screen + feed appears as first JPEG lands).
- Safe-area: read insets from a non-ignoring GeometryReader (a reader with
  .ignoresSafeArea reports zero).

### Simulator caveats (by design)
- VNGenerateForegroundInstanceMaskRequest fails on sim → falls back to
  masks precomputed on macOS by `tools/prepare_assets.swift` (same API), so
  the demo equals device behavior. On device the live pipeline runs.
- Haptics are no-ops on sim (CoreHaptics unavailable).
- Debug drivers: `POSTMARK_RESET=1`, `POSTMARK_AUTOCAPTURE=<n>`,
  `POSTMARK_AUTOKEEP=1|2` env vars (DEBUG builds only), plus a tap-location
  probe written to Documents/tapprobe.txt for external click calibration.

### Build & run
```
xcodegen generate
xcodebuild -project Postmark.xcodeproj -scheme Postmark \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcrun simctl install "iPhone 17 Pro" <DerivedData>/Postmark.app
xcrun simctl launch "iPhone 17 Pro" com.ashwinn.postmark
```
Regenerate demo assets: `swift tools/prepare_assets.swift` (needs
tools/raw/*.jpg). Icon: `swift tools/make_icon.swift`.

### Nice-to-haves not yet built
- Pinch zoom on device camera; gyroscope-driven holo in detail; sounds;
  iCloud sync; share as physical-postcard layout; stamp "series" pages.

## Session 3 — smoothness audit & die-cut-first choreography (2026-07-10)

### Choreography change
Reveal is now: glide to center → **die-cut punch** (sheet dips 1.8%, sticker
outline springs in over the raw photo — its subject pixels match the photo
exactly, so only the ring reads) → **waste fade** (raw photo fades out
beneath the cut sticker; end state is pixel-identical to .final, so the
stage swap is invisible) → dress. The earlier grain-mask "subject lift"
dissolve was removed (grainDissolveMask deleted); the full-screen capture
dissolve (grainDissolveRect) stays.

### The smoothness bug class this session killed: main-thread stalls
`withAnimation` springs run on the wall clock. If the commit after them
stalls (texture upload, shader/glass first use, image decode, layer
teardown), the spring finishes during the stall and lands as a
single-frame snap. Fixes, all structural:
- `afterNextCommit()` (Core/MainThread.swift): await two main-queue turns
  so choreography never races an uncommitted frame.
- Blackout curtain (AppModel.blackout, rendered in RootView above phases):
  capture's heavy work — off-main CG crops + preparingForDisplay — and the
  develop overlay's first commit all happen behind it.
- Textures pre-decoded off-main in DevelopOverlay's Vision task; sticker
  pre-warmed via a 2×2 invisible Image at reveal mount; dressed layers
  (paper shader/shadows/caption glyphs) pre-rendered at opacity 0.001 on a
  static beat; reveal chrome always mounted, opacity-driven.
- Beat placement: teardown of the develop overlay happens during the held
  landed beat, pre-pay happens after the punch — never inside an animation.

### Pixel-handoff fix
The camera/develop stacks inherited a transient ±4 pt proposal overshoot at
capture time, rendering content 4 pt high and breaking develop → reveal
continuity (a 12-diff one-frame jump). DevelopOverlay now pins its frame
and cancels the measured drift with a self-correcting offset (commits
behind the blackout). Swap residual is now < 2.

### Audit methodology (correction)
`simctl io recordVideo` output has unreliable timestamps under BOTH the
ffmpeg fps filter AND direct `-ss` seeks. The only trustworthy method:
ffprobe per-frame PTS + passthrough decode (`-vsync 0`), then inter-frame
diffs keyed by PTS. A snap = isolated one-frame spike bracketed by
near-zero diffs; recorder PTS gaps distinguish stillness from recorder
stalls. DEBUG `HitchMonitor` (Core/MainThread.swift) logs display-link
gaps > 90 ms and choreography marks to Documents/hitches.txt for
correlation.
