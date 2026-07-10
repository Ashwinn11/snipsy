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
