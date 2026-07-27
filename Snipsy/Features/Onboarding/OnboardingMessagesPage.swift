import SwiftUI

/// Page 3: the Messages journey, played inside a mini phone — a thread with
/// the ⊕ compose button, the plus menu with Stickers, the drawer showing
/// the four real stickers under the compose bar, and one landing on a
/// bubble. Four beats, looping.
struct OnboardingMessagesPage: View {
    let demo: OnboardingDemo
    let haptics: Haptics
    let isActive: Bool
    let screenSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Beat: Int { case thread, menu, drawer, landed
        var hold: Double {
            switch self {
            case .thread: 0.7
            case .menu: 0.7
            case .drawer: 1.0
            case .landed: 1.4
            }
        }
    }

    @State private var beat: Beat = .thread
    @State private var sway = false
    @State private var gen = 0

    private var caption: String {
        switch beat {
        case .thread: "In any thread, tap the plus…"
        case .menu: "…open Stickers…"
        case .drawer: "…your Snipsy drawer is there…"
        case .landed: "…peel one onto any message."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 10) {
                RansomText(text: "IT LANDS IN THEIR CHAT", fontSize: 14, ink: Theme.ink)
                Text("Send it the second it's done —\nright where you already talk.")
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

    // MARK: Journey beats

    @ViewBuilder
    private var journey: some View {
        ZStack {
            thread
                .overlay(Color.black.opacity(beat == .menu ? 0.45 : 0))

            plusMenu
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .bottomLeading)
                .padding(.leading, 12)
                .padding(.bottom, 54)
                .opacity(beat == .menu ? 1 : 0)
                .offset(y: beat == .menu ? 0 : 16)

            drawer
                .frame(maxHeight: .infinity, alignment: .bottom)
                .offset(y: beat == .drawer ? 0 : cardWidth * 1.30)
        }
    }

    /// The thread: bubbles + compose bar (metrics from the real compose
    /// bar: ⊕ circle at left, capsule field with mic glyph).
    private var thread: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack {
                    bubble("long day 😮‍💨",
                           fill: Color(hex: 0xE9E9EB), dark: true)
                    Spacer(minLength: 0)
                }
                HStack {
                    Spacer(minLength: 0)
                    bubble("coffee first", fill: Color(hex: 0x0A84FF))
                }
                // The landed sticker: its own outgoing "message".
                HStack {
                    Spacer(minLength: 0)
                    // The bubble above literally reads "coffee first".
                    if let hero = demo.stickerRender(OnboardingDemo.messagesKey) {
                        Image(uiImage: hero)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 112)
                            .scaleEffect(beat == .landed ? 1 : 1.5)
                            .rotationEffect(.degrees(
                                beat == .landed ? (sway ? -6.5 : -9.5) : 4))
                            .opacity(beat == .landed ? 1 : 0)
                            .animation(Theme.springBouncy, value: beat)
                            .animation(
                                .easeInOut(duration: 2.6)
                                    .repeatForever(autoreverses: true),
                                value: sway)
                            .shadow(color: Theme.shadow.opacity(0.18),
                                    radius: 6, y: 4)
                            .padding(.trailing, 28)
                    }
                }
                .padding(.top, -14)
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)

            Spacer(minLength: 0)

            // Compose bar (real proportions: ⊕ circle, capsule, mic).
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: 0x50505A))
                    .frame(width: 30, height: 30)
                    .background(Color(hex: 0xE9E9EB), in: Circle())

                HStack {
                    Text("iMessage")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: 0xB0B0B6))
                    Spacer()
                    Image(systemName: "mic")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: 0xB0B0B6))
                }
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(
                    Capsule().strokeBorder(Color(hex: 0xD9D9DE), lineWidth: 1)
                )
            }
            .padding(.horizontal, 12)
            // The compose bar rides above the sticker drawer when it opens,
            // exactly like real Messages (drawer: grabber 13 + gap 11 +
            // stickers 60 + inset 16 = 100pt tall).
            .padding(.bottom, beat == .drawer ? 112 : 12)
        }
        .background(Color(hex: 0xF7F7F9))
    }

    /// The ⊕ apps list — the surface where Snipsy's real (new)
    /// iMessage icon appears among the system rows.
    private var plusMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuRow("Audio") {
                Circle().fill(Color(hex: 0xFF6A4D))
                    .overlay {
                        Image(systemName: "waveform")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
            menuRow("Check In") {
                Circle().fill(Color(hex: 0xF7CE45))
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.black.opacity(0.8))
                    }
            }
            menuRow("Location") {
                Circle().fill(Color(hex: 0x3478F6))
                    .overlay {
                        Image(systemName: "location.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
            menuRow("Snipsy", highlighted: true) {
                AppIconView(size: 24)
            }
        }
        .padding(.vertical, 7)
        .frame(width: 168)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: 0xFBFBFD).opacity(0.99))
                .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
        )
    }

    private func menuRow<Icon: View>(
        _ title: String, highlighted: Bool = false,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        HStack(spacing: 11) {
            icon()
                .frame(width: 24, height: 24)
            Text(title)
                .font(.system(size: 13,
                              weight: highlighted ? .semibold : .regular))
                .foregroundStyle(Color(hex: 0x1C1C1E))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: 0x1C1C1E).opacity(highlighted ? 0.06 : 0))
                .padding(.horizontal, 5)
        )
    }

    /// The sticker drawer as it really appears: just the grabber and the
    /// stickers on paper — Messages tucks its compose bar above the sheet.
    private var drawer: some View {
        VStack(spacing: 11) {
            Capsule()
                .fill(Theme.inkSoft.opacity(0.4))
                .frame(width: 30, height: 4)
                .padding(.top, 9)

            HStack(spacing: 13) {
                ForEach(Array(demo.drawer.prefix(4).enumerated()),
                        id: \.offset) { i, render in
                    Image(uiImage: render)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 60)
                }
                ForEach(0..<max(0, 4 - demo.drawer.count), id: \.self) { _ in
                    PerforatedRect()
                        .stroke(Theme.inkSoft.opacity(0.25),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .frame(width: 44, height: 56)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)
        }
        .frame(width: cardWidth)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                .fill(Theme.paper)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Theme.inkSoft.opacity(0.12))
                        .frame(height: 0.7)
                }
        )
    }

    private func bubble(_ text: String, fill: Color,
                        dark: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(dark ? Color(hex: 0x1C1C1E) : .white)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(fill, in: RoundedRectangle(cornerRadius: 15))
    }

    // MARK: Loop

    private func startLoop() {
        gen += 1
        let g = gen

        if reduceMotion {
            beat = .landed
            sway = false
            return
        }

        beat = .thread
        sway = false
        Task { @MainActor in
            while gen == g {
                try? await Task.sleep(for: .seconds(beat.hold))
                guard gen == g else { return }
                haptics.tick()
                withAnimation(Theme.springTight) {
                    switch beat {
                    case .thread: beat = .menu
                    case .menu: beat = .drawer
                    case .drawer: beat = .landed
                    case .landed: beat = .thread
                    }
                }
                if beat == .landed {
                    // Start the idle sway once the landing spring settles.
                    try? await Task.sleep(for: .seconds(0.35))
                    guard gen == g else { return }
                    sway = true
                } else if beat == .thread {
                    sway = false
                }
            }
        }
    }
}
