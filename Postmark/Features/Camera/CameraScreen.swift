import SwiftUI
import AVFoundation

/// Root camera experience: full-bleed feed, stamp-shaped viewfinder, glass
/// chrome. Always mounted; overlays (develop/reveal/album) sit above it.
struct CameraScreen: View {
    let model: AppModel
    let screenSize: CGSize
    let safeArea: EdgeInsets

    @State private var focusPoint: CGPoint? = nil
    @State private var focusPulse = false

    /// The stamp-to-be. 4:5, centered, slightly above middle. Shared by the
    /// capture path and the reveal handoff — single source of truth.
    static func viewfinderRect(in size: CGSize) -> CGRect {
        let w = size.width * 0.78
        let h = w * 1.25
        return CGRect(x: (size.width - w) / 2, y: size.height * 0.44 - h / 2,
                      width: w, height: h)
    }

    var body: some View {
        let vf = Self.viewfinderRect(in: screenSize)

        ZStack {
            feed

            HoleDim(hole: vf, corner: 12)
                .fill(Color.black.opacity(0.32), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

            ViewfinderOverlay(rect: vf)

            chrome(viewfinder: vf)

            if let p = focusPoint {
                FocusIndicator()
                    .position(p)
                    .id("\(p.x)-\(p.y)")
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .background(Color.black)
    }

    // MARK: Feed

    @ViewBuilder
    private var feed: some View {
        if CameraController.isDemo {
            DemoFeedView(feed: model.camera.demoFeed, size: screenSize)
        } else if model.camera.authorization == .denied {
            PermissionDeniedView()
        } else {
            CameraPreviewView(session: model.camera.session) { viewPoint, devicePoint in
                model.camera.focus(atDevicePoint: devicePoint)
                model.haptics.tick()
                focusPoint = viewPoint
                Task {
                    try? await Task.sleep(for: .seconds(0.9))
                    if focusPoint == viewPoint { focusPoint = nil }
                }
            }
            .frame(width: screenSize.width, height: screenSize.height)
        }
    }

    // MARK: Chrome

    @ViewBuilder
    private func chrome(viewfinder vf: CGRect) -> some View {
        // Wordmark
        Text("POSTMARK")
            .font(Theme.engraved(15))
            .tracking(5)
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black.opacity(0.45), radius: 7, y: 1)
            .position(x: screenSize.width / 2, y: safeArea.top + 24)

        // Flash (device, back camera only)
        if !CameraController.isDemo && !model.camera.frontCamera {
            Button {
                model.camera.flashOn.toggle()
                model.haptics.tick()
            } label: {
                Image(systemName: model.camera.flashOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(model.camera.flashOn ? 1 : 0.75))
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .position(x: screenSize.width - 46, y: safeArea.top + 24)
        }

        // Demo hint — retire it once the first stamp is collected.
        if CameraController.isDemo && model.store.stamps.isEmpty {
            Text("Swipe for another scene")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .shadow(color: .black.opacity(0.5), radius: 5, y: 1)
                .position(x: screenSize.width / 2, y: vf.maxY + 30)
        }

        // Bottom bar
        let barY = screenSize.height - max(safeArea.bottom, 16) - 54

        CollectionPill(model: model)
            .position(x: 66, y: barY)

        ShutterButton {
            let size = screenSize
            let rect = Self.viewfinderRect(in: size)
            Task { await model.capture(viewfinderRect: rect, viewSize: size) }
        }
        .position(x: screenSize.width / 2, y: barY)

        Button {
            model.camera.flip()
            model.haptics.tick()
        } label: {
            Image(systemName: CameraController.isDemo
                  ? "photo.on.rectangle.angled"
                  : "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 48, height: 48)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .position(x: screenSize.width - 66, y: barY)
    }
}

/// Full-screen dim with a rounded-rect hole (even-odd fill).
struct HoleDim: Shape {
    let hole: CGRect
    let corner: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRect(rect)
        p.addRoundedRect(in: hole, cornerSize: CGSize(width: corner, height: corner))
        return p
    }
}

/// Yellow-less, postal-red focus square that pulses once.
struct FocusIndicator: View {
    @State private var appeared = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Theme.postalRed.opacity(0.9), lineWidth: 1.8)
            .frame(width: 74, height: 74)
            .scaleEffect(appeared ? 1 : 1.35)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(Theme.springTight) { appeared = true }
            }
    }
}

/// Friendly camera-permission state on paper — never a dead end.
struct PermissionDeniedView: View {
    var body: some View {
        ZStack {
            PaperBackdrop(showsGrid: true)
            VStack(spacing: 18) {
                PerforatedRect()
                    .stroke(Theme.inkSoft.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1.4, dash: [4, 5]))
                    .frame(width: 120, height: 157)
                    .overlay {
                        Image(systemName: "camera")
                            .font(.system(size: 26))
                            .foregroundStyle(Theme.inkSoft)
                    }
                Text("Postmark needs the camera")
                    .font(Theme.serifDisplay(22))
                    .foregroundStyle(Theme.ink)
                Text("Every stamp starts with a photo.\nAllow camera access in Settings.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open Settings")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 13)
                        .background(Theme.postalRed, in: Capsule())
                }
                .padding(.top, 6)
            }
        }
    }
}
