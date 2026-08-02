import SwiftUI

/// The ask before the ask. iOS gives exactly one shot at the system camera
/// dialog, so it never fires cold: this explains what the camera is for
/// first, and only a tap on "Enable" opens Apple's prompt. Declining here
/// costs nothing — the system dialog is left unspent, so the offer can be
/// made again later from the camera tab.
///
/// Sibling of `PermissionDeniedView` (same paper, perforation and postal-red
/// capsule), but this one is an invitation; that one is the dead end you
/// reach only after a hard denial, and sends you to Settings.
struct CameraPermissionPrimerView: View {
    let model: AppModel
    /// Runs after either choice — onboarding uses it to finish, the camera
    /// tab leaves it empty and just re-renders on the new authorization.
    var onResolved: () -> Void = {}

    @State private var asking = false

    var body: some View {
        ZStack {
            PaperBackdrop(showsGrid: true)
                .ignoresSafeArea()

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

                Text("Ready when you are")
                    .font(Theme.display(22))
                    .foregroundStyle(Theme.ink)

                Text("Every stamp starts with a photo.\nNothing leaves your device.")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                Button {
                    guard !asking else { return }
                    asking = true
                    Task { @MainActor in
                        await model.camera.requestPermission()
                        asking = false
                        onResolved()
                    }
                } label: {
                    Text("Enable Camera")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 30)
                        .frame(height: 50)
                        .background(Theme.postalRed, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(asking)
                .padding(.top, 6)

                Button {
                    model.haptics.tick()
                    onResolved()
                } label: {
                    Text("Not now")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 18)
                        .frame(height: 34)
                }
                .buttonStyle(.plain)
                .disabled(asking)
            }
        }
    }
}
