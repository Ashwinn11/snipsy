import SwiftUI

/// Page 2: the share-extension pitch — a miniature, non-interactive echo
/// of the real ShareComposerView (mock sheet card, live StampView preview,
/// option row, Keep capsule) that gently cycles sticker ↔ stamp to show
/// one photo becoming many forms.
struct OnboardingSharePage: View {
    let demo: OnboardingDemo
    let isActive: Bool
    let screenSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stickerSelected = true
    @State private var gen = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Text("STAMP ANYTHING")
                    .font(Theme.engraved(21))
                    .tracking(5)
                    .foregroundStyle(Theme.ink)
                Text("Send any photo to Postmark from the share sheet —\nno need to open the app.")
                    .font(.system(size: 14.5, design: .serif))
                    .italic()
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 7) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                Text("From Photos, Safari, anywhere")
                    .font(.system(size: 12.5, design: .serif))
                    .italic()
            }
            .foregroundStyle(Theme.inkSoft.opacity(0.8))
            .padding(.top, 16)

            Spacer(minLength: 0)

            mockSheet
                .allowsHitTesting(false)

            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .padding(.top, 30)
        .onChange(of: isActive) { _, active in
            if active { startCycle() } else { gen += 1 }
        }
        .onAppear { if isActive { startCycle() } }
        .onDisappear { gen += 1 }
    }

    // MARK: Mock share sheet

    @ViewBuilder
    private var mockSheet: some View {
        let cardWidth = min(screenSize.width * 0.74, 330)

        VStack(spacing: 16) {
            Capsule()
                .fill(Theme.inkSoft.opacity(0.35))
                .frame(width: 34, height: 4)
                .padding(.top, 10)

            HStack {
                Text("POSTMARK")
                    .font(Theme.engraved(11))
                    .tracking(3)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 24, height: 24)
                    .glassEffect(.regular, in: .circle)
            }
            .padding(.horizontal, 16)

            if let assets = demo.share {
                StampView(
                    image: assets.sticker,
                    style: .cutout,
                    tint: OnboardingDemo.shareTint.color,
                    title: assets.title,
                    number: 1,
                    year: String(Calendar.current.component(.year, from: Date())),
                    variant: .airmail,
                    stickerBox: assets.box,
                    rawCrop: assets.photo,
                    maskImage: assets.cutout,
                    labelAnchor: assets.labelAnchor,
                    assembly: stickerSelected ? stickerAssembly : stampAssembly
                )
                .frame(width: 128)
                .shadow(color: Theme.shadow.opacity(0.4), radius: 9, y: 5)

                optionRow(assets: assets)
            }

            HStack(spacing: 8) {
                Image(systemName: "seal.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("Keep")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 26)
            .frame(height: 34)
            .background(Theme.postalRed, in: Capsule())
            .padding(.bottom, 16)
        }
        .frame(width: cardWidth)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Theme.paperDeep)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(Theme.inkSoft.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: Theme.shadow.opacity(0.5), radius: 22, y: 12)
        )
    }

    private func optionRow(assets: OnboardingDemo.Subject) -> some View {
        HStack(spacing: 8) {
            Image(uiImage: assets.sticker)
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 38)
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Theme.postalRed, lineWidth: 1.2)
                        .padding(-3)
                        .opacity(stickerSelected ? 1 : 0)
                }

            ForEach(StampVariant.allCases) { v in
                StampView(
                    image: assets.sticker,
                    style: .cutout,
                    tint: OnboardingDemo.shareTint.color,
                    title: "",
                    number: 1,
                    year: "",
                    variant: v,
                    stickerBox: assets.box,
                    rawCrop: assets.photo,
                    assembly: thumbAssembly
                )
                .frame(width: 30)
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Theme.postalRed, lineWidth: 1.2)
                        .padding(-3)
                        .opacity(!stickerSelected && v == .airmail ? 1 : 0)
                }
            }
        }
    }

    // MARK: Assemblies
    // Both states keep waste at 0 (the shader stays blank — its progress
    // argument tweens through the shatter's dust field if animated) and
    // crossfade on the complementary border/photoFade pair instead, with
    // flight gliding the sheet between forms — the reveal's own morph.

    private var stickerAssembly: StampView.Assembly {
        StampView.Assembly(paper: 0, caption: 0, settle: 1,
                           border: 1, flight: 1, photoFade: 0,
                           waste: 0, content: .raw)
    }

    private var stampAssembly: StampView.Assembly {
        StampView.Assembly(paper: 1, caption: 1, settle: 1,
                           border: 0, flight: 0, photoFade: 1,
                           waste: 0, content: .raw)
    }

    private var thumbAssembly: StampView.Assembly {
        StampView.Assembly(paper: 1, caption: 0, settle: 1,
                           border: 0, waste: 1, content: .raw)
    }

    private func startCycle() {
        guard !reduceMotion else { return }
        gen += 1
        let g = gen
        Task { @MainActor in
            while gen == g {
                try? await Task.sleep(for: .seconds(2.2))
                guard gen == g else { return }
                withAnimation(Theme.spring) { stickerSelected.toggle() }
            }
        }
    }
}
