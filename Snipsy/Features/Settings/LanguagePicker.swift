import SwiftUI

/// Language choice, in the app's own voice rather than a system list.
///
/// Only offers what `Bundle.main` actually carries, so a language cannot be
/// picked until its translations ship. "System" stays first and is the
/// default — most people never want this control, and the ones who do are
/// usually reaching for a language their phone isn't set to.
struct LanguagePicker: View {
    @Environment(\.dismiss) private var dismiss
    private let language = LanguageController.shared
    var onPick: (() -> Void)? = nil

    var body: some View {
        sheetShell(title: "Language") {
            VStack(spacing: 0) {
                option(code: "", name: L("System"))
                ForEach(language.available, id: \.code) { entry in
                    Line()
                        .stroke(Theme.ink.opacity(0.12),
                                style: StrokeStyle(lineWidth: 1, dash: [2.5, 4]))
                        .frame(height: 1)
                        .padding(.horizontal, 30)
                    option(code: entry.code, name: entry.name)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func option(code: String, name: String) -> some View {
        Button {
            language.select(code)
            onPick?()
            dismiss()
        } label: {
            HStack {
                Text(name)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if language.code == code {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.postalRed)
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The globe affordance on the onboarding page — small, top-trailing, out of
/// the way of the headline. Someone who needs it finds it on the very first
/// screen; everyone else reads straight past it.
struct LanguageBadge: View {
    private let language = LanguageController.shared
    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "globe")
                    .font(.system(size: 12, weight: .semibold))
                Text(currentName)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(Theme.inkSoft)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .contentShape(Capsule())
        }
        .glassEffect(.regular.interactive(), in: .capsule)
        .sheet(isPresented: $showPicker) {
            LanguagePicker()
                .presentationDetents([.medium, .large])
        }
    }

    private var currentName: String {
        guard !language.code.isEmpty else { return L("Language") }
        return language.available.first { $0.code == language.code }?.name
            ?? L("Language")
    }
}
