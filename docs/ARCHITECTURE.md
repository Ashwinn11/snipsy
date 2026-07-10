# Postmark — Architecture

iOS 26.0+, SwiftUI, portrait iPhone. Xcodegen project (`project.yml` → `xcodegen`).

## Flow state machine (RootView)
```
Phase: .camera → .developing(Capture) → .reveal(PendingStamp) → .camera
                                   Retake ↩︎        Keep → StampStore + fly-to-pill
Album overlays camera (custom ZStack transition, not sheet).
```

## Modules
- `App/` — PostmarkApp, RootView (phase machine + album presentation), Theme.
- `Core/`
  - `CameraController` — @Observable. Device: AVCaptureSession (.photo preset,
    AVCapturePhotoOutput). Simulator: DemoFeed (bundled samples, Ken Burns drift).
    One capture API returns normalized-.up UIImage.
  - `FrameGeometry` — aspect-fill math: viewfinder rect (view coords) → pixel crop
    rect. Same path for device & demo (demo adds drift transform).
  - `VisionService` — VNGenerateForegroundInstanceMaskRequest (cutout),
    VNClassifyImageRequest (title), dominant color. Graceful fallbacks: demo bundle
    masks on simulator; classic (full-rect) stamp style when no mask.
  - `StampStore` — @Observable; Documents/stamps.json + images/*.png.
  - `Haptics` — CoreHaptics patterns: shutter, grain texture, thunk, tick.
  - `StampRenderer` — flattened share PNG via ImageRenderer.
- `Features/Camera` — CameraScreen, CameraPreviewView (UIViewRepresentable),
  DemoFeedView, ViewfinderOverlay, ShutterButton, chrome.
- `Features/Develop` — DevelopOverlay: frozen image + grainDissolve layerEffect,
  drives Vision task in parallel.
- `Features/Reveal` — RevealScreen: stamp assembly, rename, keep/retake.
- `Features/Stamp` — StampView (hero composite), PerforatedRect (Shape),
  PostmarkSeal, StampPaper (texture shader wrapper).
- `Features/Album` — AlbumScreen, StampCell, StampDetail (tilt + holo).
- `Shaders/` — Dissolve.metal (grain dissolve, rect + texture-mask variants),
  Holo.metal (rainbow shimmer), Paper.metal (speckle grain, dot grid).

## Shader notes
SwiftUI ShaderLibrary (`colorEffect` / `layerEffect`). Mask images passed as
`.image` args → `texture2d<half>`. `maxSampleOffset` = max grain drift (80 pt).

## Tools
- `tools/prepare_assets.swift` — macOS CLI: runs the *same* Vision pipeline on
  bundled sample photos → SampleFeed masks/labels (simulator demo parity).
- `tools/make_icon.swift` — renders AppIcon 1024 (CoreGraphics).

## Verification loop
xcodebuild → simctl install/launch → `simctl io screenshot` + `recordVideo`
→ ffmpeg frame extraction → visual audit → fix → repeat. Notes in docs/PROGRESS.md.
