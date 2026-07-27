import SwiftUI

/// Page 2: the share journey, played inside a mini phone — a photo open in
/// a Photos-style view, the share sheet rising with Snipsy's real icon in
/// the app row, then the Snipsy composer. Three beats, looping.
struct OnboardingSharePage: View {
    let demo: OnboardingDemo
    let haptics: Haptics
    let isActive: Bool
    let screenSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Beat: Int { case photo, sheet, composer
        var hold: Double {
            switch self {
            case .photo: 0.7
            case .sheet: 0.9
            case .composer: 1.3
            }
        }
    }

    @State private var beat: Beat = .photo
    @State private var stickerSelected = true
    @State private var gen = 0

    private var caption: String {
        switch beat {
        case .photo: "Open any photo, tap Share…"
        case .sheet: "…choose Snipsy…"
        case .composer: "…and keep it as a stamp or sticker."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 10) {
                RansomText(text: "NOTHING GETS LOST", fontSize: 16, ink: Theme.ink)
                Text("Any photo you already have\ncan become the next one.")
                    .font(.system(size: 14.5, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            MockPhoneCard(width: cardWidth) { journey }

            Text(caption)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
                .animation(.easeOut(duration: 0.25), value: caption)
                .padding(.top, 22)

            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .padding(.top, 30)
        .onAppear { if isActive { startLoop() } }
        .onChange(of: isActive) { _, active in
            if active { startLoop() } else { gen += 1 }
        }
        .onDisappear { gen += 1 }
    }

    private var cardWidth: CGFloat { min(screenSize.width * 0.74, 330) }

    // MARK: Journey beats (all mounted; opacity/offset driven)

    @ViewBuilder
    private var journey: some View {
        ZStack {
            photosBeat
                .scaleEffect(beat == .photo ? 1 : 0.94)
                .overlay(Color.black.opacity(beat == .photo ? 0 : 0.45))

            shareSheet
                .frame(maxHeight: .infinity, alignment: .bottom)
                .offset(y: beat == .sheet ? 0 : cardWidth * 1.30)
                .opacity(beat == .composer ? 0 : 1)

            composerSheet
                .frame(maxHeight: .infinity, alignment: .bottom)
                .offset(y: beat == .composer ? 0 : cardWidth * 1.30)
        }
    }

    /// Beat A — a photo open in Photos (light chrome, real layout: date
    /// pill up top, filmstrip over the toolbar, share bottom-left).
    private var photosBeat: some View {
        VStack(spacing: 0) {
            HStack {
                lightCircle("chevron.left")
                Spacer()
                VStack(spacing: 1) {
                    Text("Yesterday")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x1C1C1E))
                    Text("11:23 AM")
                        .font(.system(size: 8.5))
                        .foregroundStyle(Color(hex: 0x8E8E93))
                }
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(.white.opacity(0.85), in: Capsule())
                Spacer()
                lightCircle("ellipsis")
            }
            .padding(.horizontal, 12)
            .frame(height: 44)

            if let subject = demo.share {
                Image(uiImage: subject.photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: cardWidth, height: cardWidth * 1.30 - 44 - 72)
                    .clipped()
            } else {
                Color(hex: 0xE5E5EA)
            }

            // Filmstrip + toolbar.
            VStack(spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(0..<6, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: 0xD8D8DC))
                            .frame(width: 15, height: 20)
                    }
                    if let subject = demo.share {
                        Image(uiImage: subject.photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 20, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                HStack {
                    lightCircle("square.and.arrow.up")
                    Spacer()
                    HStack(spacing: 20) {
                        Image(systemName: "heart")
                        Image(systemName: "info.circle")
                        Image(systemName: "slider.horizontal.3")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0x1C1C1E))
                    Spacer()
                    lightCircle("trash")
                }
                .padding(.horizontal, 12)
            }
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .background(Color(hex: 0xF2F2F6))
    }

    private func lightCircle(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color(hex: 0x1C1C1E))
            .frame(width: 28, height: 28)
            .background(.white.opacity(0.85), in: Circle())
    }

    /// Beat B — the real share-sheet anatomy: light card, "1 Photo
    /// Selected" header with an X circle, the app row (Snipsy's real
    /// home), then the circular actions row.
    private var shareSheet: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                if let subject = demo.share {
                    Image(uiImage: subject.photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("1 Photo Selected")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x1C1C1E))
                    Text("Options")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color(hex: 0x505055))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(.white, in: Capsule())
                }
                Spacer()
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x505055))
                    .frame(width: 28, height: 28)
                    .background(.white, in: Circle())
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            // The share-extension app row — where Snipsy really lives.
            HStack(alignment: .top, spacing: 15) {
                appSlot { MockAppTile(size: 44, symbol: "list.bullet") }
                VStack(spacing: 5) {
                    AppIconView(size: 44)
                    Text("Snipsy")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color(hex: 0x1C1C1E))
                }
                appSlot { MockAppTile(size: 44, symbol: "doc.viewfinder") }
                appSlot { MockAppTile(size: 44, symbol: "ellipsis") }
            }

            // Circular quick actions.
            HStack(spacing: 17) {
                actionCircle("doc.on.doc")
                actionCircle("rectangle.stack.badge.plus")
                actionCircle("airplay.video")
                actionCircle("photo")
            }
            .padding(.bottom, 16)
        }
        .frame(width: cardWidth)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)
                .fill(Color(hex: 0xF2F2F6).opacity(0.99))
                .shadow(color: .black.opacity(0.25), radius: 12, y: -4)
        )
    }

    private func appSlot<Icon: View>(@ViewBuilder icon: () -> Icon) -> some View {
        VStack(spacing: 5) {
            icon()
            MockLabelBar(width: 26, height: 4, tone: .dark)
        }
    }

    private func actionCircle(_ symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: 0x1C1C1E))
                .frame(width: 40, height: 40)
                .background(Color(hex: 0xE3E3E8), in: Circle())
            MockLabelBar(width: 28, height: 4, tone: .dark)
        }
    }

    /// Beat C — the Snipsy composer (the extension's real layout).
    private var composerSheet: some View {
        VStack(spacing: 13) {
            Capsule()
                .fill(Theme.inkSoft.opacity(0.4))
                .frame(width: 34, height: 4)
                .padding(.top, 9)

            HStack {
                Text("SNIPSY")
                    .font(Theme.display(11))
                    .tracking(1.5)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 24, height: 24)
                    .glassEffect(.regular, in: .circle)
            }
            .padding(.horizontal, 16)

            if let subject = demo.share {
                StampView(
                    image: subject.sticker,
                    style: .cutout,
                    tint: subject.tint.color,
                    title: subject.title,
                    number: 1,
                    variant: .airmail,
                    stickerBox: subject.box,
                    rawCrop: subject.photo,
                    maskImage: subject.cutout,
                    labelAnchor: subject.labelAnchor,
                    assembly: stickerSelected ? stickerAssembly : stampAssembly
                )
                .frame(width: 116)
                .shadow(color: Theme.shadow.opacity(0.20), radius: 9, y: 5)

                optionRow(subject: subject)
            }

            HStack(spacing: 8) {
                Image(systemName: "seal.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("Keep")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 26)
            .frame(height: 32)
            .background(Theme.postalRed, in: Capsule())
            .padding(.bottom, 14)
        }
        .frame(width: cardWidth)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18)
                .fill(Theme.paper)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Theme.inkSoft.opacity(0.12))
                        .frame(height: 0.7)
                }
        )
    }

    private func optionRow(subject: OnboardingDemo.Subject) -> some View {
        HStack(spacing: 8) {
            Image(uiImage: subject.sticker)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 36)
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Theme.postalRed, lineWidth: 1.2)
                        .padding(-3)
                        .opacity(stickerSelected ? 1 : 0)
                }

            ForEach(Array(StampVariant.allCases.prefix(4))) { v in
                StampView(
                    image: subject.sticker,
                    style: .cutout,
                    tint: subject.tint.color,
                    title: "",
                    number: 1,
                    variant: v,
                    stickerBox: subject.box,
                    rawCrop: subject.photo,
                    assembly: thumbAssembly
                )
                .frame(width: 28)
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
    // Both keep waste at 0 (an animated shader progress replays the
    // shatter's dust) and crossfade on the complementary pair instead.

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

    // MARK: Loop

    private func startLoop() {
        gen += 1
        let g = gen

        if reduceMotion {
            beat = .composer
            stickerSelected = false
            return
        }

        beat = .photo
        stickerSelected = true
        Task { @MainActor in
            while gen == g {
                let current = beat
                if current == .composer {
                    // Mid-beat: flip the composer's selection once.
                    try? await Task.sleep(for: .seconds(0.6))
                    guard gen == g else { return }
                    withAnimation(Theme.springTight) { stickerSelected = false }
                    try? await Task.sleep(for: .seconds(current.hold - 0.6))
                } else {
                    try? await Task.sleep(for: .seconds(current.hold))
                }
                guard gen == g else { return }
                haptics.tick()
                withAnimation(Theme.springTight) {
                    switch beat {
                    case .photo: beat = .sheet
                    case .sheet: beat = .composer
                    case .composer:
                        beat = .photo
                        stickerSelected = true
                    }
                }
            }
        }
    }
}
