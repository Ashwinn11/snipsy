import SwiftUI

/// The gate between onboarding and the camera: one lifetime purchase, no
/// subscription. Hard by design — the close affordance arrives late and
/// closing only returns to onboarding's last slide, never into the app.
struct PaywallScreen: View {
    let purchases: PurchaseController
    let demo: OnboardingDemo
    let screenSize: CGSize
    let safeArea: EdgeInsets
    var onUnlocked: () -> Void
    var onClose: () -> Void

    @State private var closeVisible = false
    @State private var stage = 0
    @State private var doc: LegalDoc? = nil

    var body: some View {
        ZStack {
            PaperBackdrop()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 12) {
                    stickerFan
                        .padding(.bottom, 10)
                    RansomText(text: "KEEP EVERY MOMENT", fontSize: 16, ink: Theme.ink)
                    Text("The coffee, the concert, the two of you —\nturned into stamps and stickers you keep forever.")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .entrance(shown: stage >= 1)

                VStack(alignment: .leading, spacing: 18) {
                    outcome("scissors", "Photos become die-cut stickers")
                    outcome("seal.fill", "Moments become dated stamps")
                    outcome("message.fill", "Your collection rides in iMessage")
                    outcome("infinity", "One purchase — yours for life")
                }
                .padding(.top, 38)
                .padding(.horizontal, 58)
                .entrance(shown: stage >= 2)

                Spacer(minLength: 0)

                VStack(spacing: 14) {
                    Button {
                        Task {
                            if await purchases.purchase() { onUnlocked() }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if purchases.purchasing {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "seal.fill")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            Text(purchases.priceText.map {
                                "Unlock Snipsy — \($0)"
                            } ?? "Unlock Snipsy for Life")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 34)
                        .frame(height: 54)
                        .frame(maxWidth: .infinity)
                        .background(Theme.postalRed, in: Capsule())
                        .padding(.horizontal, 44)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(purchases.purchasing)

                    Text("One-time purchase · No subscription")
                        .font(.system(size: 12.5, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)

                    HStack(spacing: 18) {
                        Button {
                            Task {
                                if await purchases.restore() { onUnlocked() }
                            }
                        } label: {
                            Text("Restore Purchase").underline()
                        }
                        Button { doc = .terms } label: {
                            Text("Terms").underline()
                        }
                        Button { doc = .privacy } label: {
                            Text("Privacy").underline()
                        }
                    }
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Theme.inkSoft.opacity(0.8))
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 40)
                .entrance(shown: stage >= 3)
            }

            // The exit, fashionably late and deliberately quiet — in the
            // exact spot Skip occupied on the onboarding slides.
            if closeVisible {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 38, height: 38)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .position(x: screenSize.width - 44,
                          y: max(safeArea.top, 20) + 18)
                .transition(.opacity)
            }
        }
        .sheet(item: $doc) { LegalDocView(doc: $0) }
        .task {
            await purchases.loadOffering()
        }
        .onAppear {
            Task { @MainActor in
                for s in 1...3 {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                        stage = s
                    }
                    try? await Task.sleep(for: .seconds(0.12))
                }
                try? await Task.sleep(for: .seconds(2.6))
                withAnimation(.easeIn(duration: 0.5)) { closeVisible = true }
            }
        }
    }

    /// The collection as one tossed pile: three fanned behind the hero.
    private var stickerFan: some View {
        ZStack {
            if demo.drawer.count >= 3 {
                fanned(demo.drawer[1], width: 78, degrees: -19, dx: -62, dy: 10)
                fanned(demo.drawer[2], width: 72, degrees: 16, dx: 62, dy: 12)
            }
            if let hero = demo.hero {
                fanned(hero.stickerRender, width: 96, degrees: -7, dx: 0, dy: 6)
            }
        }
        .frame(height: 128)
    }

    private func fanned(_ render: UIImage, width: CGFloat, degrees: Double,
                        dx: CGFloat, dy: CGFloat) -> some View {
        Image(uiImage: render)
            .resizable()
            .scaledToFit()
            .frame(width: width)
            .rotationEffect(.degrees(degrees))
            .shadow(color: Theme.shadow.opacity(0.20), radius: 8, y: 5)
            .offset(x: dx, y: dy)
    }

    private func outcome(_ symbol: String, _ line: String) -> some View {
        HStack(spacing: 15) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.postalRed)
                .frame(width: 26)
            Text(line)
                .font(.system(size: 14.5, design: .rounded))
                .foregroundStyle(Theme.ink.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension View {
    func entrance(shown: Bool) -> some View {
        opacity(shown ? 1 : 0).offset(y: shown ? 0 : 16)
    }
}
