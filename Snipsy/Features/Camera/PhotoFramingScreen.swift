import SwiftUI

/// Frame an imported photo the way the viewfinder frames a live one.
///
/// A live capture lets you aim; an import did not — it mapped the live
/// viewfinder rect over a screen-fitted layout, so whatever happened to fall
/// inside won. Off-centre subjects were cut in half, and since the die cut
/// only sees what's inside the crop, the lift failed on exactly the photos
/// people most wanted to use.
///
/// The aperture is the same perforated window as the camera's, at the stamp's
/// own aspect. The photo moves under it — the picture is what travels, not
/// the frame.
struct PhotoFramingScreen: View {
    let image: UIImage
    let screenSize: CGSize
    let safeArea: EdgeInsets
    var onCancel: () -> Void
    /// The cut, plus the screen-exact frame behind it — the develop
    /// dissolve needs both, exactly as a live shutter press provides them.
    var onUse: (_ crop: UIImage, _ screen: UIImage) -> Void

    @State private var zoom: CGFloat = 1
    @State private var didSetEntryZoom = false
    @State private var liveZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var liveOffset: CGSize = .zero
    @State private var punch = false

    /// All measured off the same art as the camera's — the glass, the 4:5
    /// cut inside it and the mount around both, so what you frame here is
    /// what gets cut.
    private var aperture: CGRect { CameraScreen.viewfinderRect(in: screenSize) }
    private var window: CGRect { CameraScreen.windowRect(in: screenSize) }
    private var mount: CGRect { CameraScreen.frameRect(in: screenSize) }

    /// The floor: the photo exactly covers the *window*. Below this a drag
    /// exposes a bare corner, so `zoom` never goes under 1.
    ///
    /// Covering the aperture is not enough — the glass is taller than the
    /// 4:5 cut, and a photo sized to the cut left the opening's top and
    /// bottom slivers showing bare black. The camera fills the whole
    /// opening; so does this.
    ///
    /// This is deliberately *not* where the photo starts. Folding the
    /// screen-filling look in here raised the floor along with the entry
    /// scale, which quietly removed the widest framing — the whole photo in
    /// the window was no longer reachable. Entry scale is `entryZoom`.
    private var baseScale: CGFloat {
        let s = image.size
        guard s.width > 0, s.height > 0 else { return 1 }
        return max(window.width / s.width, window.height / s.height)
    }

    /// Start showing the whole photo across the screen, so the frame reads as
    /// sitting on top of something larger and the pan is obvious. Expressed
    /// as zoom rather than baked into `baseScale`, so zooming back out to the
    /// full-extent crop stays available.
    private var entryZoom: CGFloat {
        let s = image.size
        guard s.width > 0, s.height > 0, baseScale > 0 else { return 1 }
        let fitsScreen = min(screenSize.width / s.width, screenSize.height / s.height)
        return min(6, max(1, fitsScreen / baseScale))
    }

    private var scale: CGFloat { baseScale * zoom * liveZoom }

    private var displaySize: CGSize {
        CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    /// Keep the glass covered: the photo's own half-extent minus the
    /// window's is how far it may travel before an edge shows.
    private func clamped(_ o: CGSize) -> CGSize {
        let slackX = max(0, (displaySize.width - window.width) / 2)
        let slackY = max(0, (displaySize.height - window.height) / 2)
        return CGSize(width: min(slackX, max(-slackX, o.width)),
                      height: min(slackY, max(-slackY, o.height)))
    }

    private var totalOffset: CGSize {
        clamped(CGSize(width: offset.width + liveOffset.width,
                       height: offset.height + liveOffset.height))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .frame(width: displaySize.width, height: displaySize.height)
                .position(x: aperture.midX + totalOffset.width,
                          y: aperture.midY + totalOffset.height)

            // The same mount the camera holds up, composited the same way:
            // dim the world outside the window, then lay the physical frame
            // over it. Framing an imported photo has to be the same object
            // as framing a live one, or it reads as a different feature —
            // and the develop dissolve rebuilds exactly this stack, so a
            // hole cut anywhere else would jump at the handoff.
            HoleDim(hole: window, corner: window.width * 0.026)
                .fill(Color.black.opacity(0.38), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

            // Punches on Use Photo, exactly as the shutter punches it.
            Image("viewfinder_frame")
                .resizable()
                .frame(width: mount.width, height: mount.height)
                .scaleEffect(punch ? CameraScreen.punchScale : 1,
                             anchor: CameraScreen.punchAnchor)
                .position(x: mount.midX, y: mount.midY)
                .allowsHitTesting(false)

            chrome
        }
        .contentShape(Rectangle())
        // `entryZoom` depends on the image and the screen, so it can't be a
        // property initialiser.
        .onAppear {
            guard !didSetEntryZoom else { return }
            didSetEntryZoom = true
            zoom = entryZoom
        }
        .gesture(
            SimultaneousGesture(
                DragGesture()
                    .onChanged { liveOffset = $0.translation }
                    .onEnded { _ in
                        offset = totalOffset
                        liveOffset = .zero
                    },
                MagnifyGesture()
                    .onChanged { liveZoom = $0.magnification }
                    .onEnded { _ in
                        // Never below cover, and a ceiling so the crop can't
                        // be zoomed into mush.
                        zoom = min(6, max(1, zoom * liveZoom))
                        liveZoom = 1
                        offset = totalOffset
                    }
            )
        )
    }

    private var chrome: some View {
        VStack {
            HStack {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                }
                .background(.black.opacity(0.34), in: Capsule())
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 20)
            .padding(.top, max(safeArea.top, 20))

            Spacer(minLength: 0)

            VStack(spacing: 14) {
                Text("Drag and pinch to frame it.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))

                Button {
                    CameraScreen.firePunch($punch)
                    onUse(cropped(), screenFrame())
                } label: {
                    Text("Use Photo")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 30)
                        .frame(height: 52)
                        .background(Theme.postalRed, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(.bottom, max(safeArea.bottom, 18) + 14)
        }
    }


    /// What the user is looking at, at screen size.
    ///
    /// `DevelopOverlay` dissolves everything *outside* the stamp plate out
    /// of a screen-sized frame, rebuilding the dim and the mount over it. A
    /// live capture hands it exactly that. Handing it the 4:5 cut instead
    /// stretched the crop across the whole screen and left no region to
    /// preserve — the sweep ran over the wrong picture.
    private func screenFrame() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        return UIGraphicsImageRenderer(size: screenSize, format: format).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: screenSize))
            let size = displaySize
            let origin = CGPoint(
                x: aperture.midX + totalOffset.width - size.width / 2,
                y: aperture.midY + totalOffset.height - size.height / 2)
            image.draw(in: CGRect(origin: origin, size: size))
        }
    }

    /// The aperture, back-projected into the photo's own pixels.
    private func cropped() -> UIImage {
        let s = scale
        guard s > 0 else { return image }
        let center = CGPoint(x: aperture.midX + totalOffset.width,
                             y: aperture.midY + totalOffset.height)
        func toImage(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - center.x) / s + image.size.width / 2,
                    y: (p.y - center.y) / s + image.size.height / 2)
        }
        let tl = toImage(CGPoint(x: aperture.minX, y: aperture.minY))
        let br = toImage(CGPoint(x: aperture.maxX, y: aperture.maxY))
        let rect = CGRect(x: tl.x, y: tl.y,
                          width: br.x - tl.x, height: br.y - tl.y)
            .intersection(CGRect(origin: .zero, size: image.size))
        guard rect.width > 16, rect.height > 16,
              let out = FrameGeometry.crop(image, to: rect)
        else { return image }
        return out
    }
}
