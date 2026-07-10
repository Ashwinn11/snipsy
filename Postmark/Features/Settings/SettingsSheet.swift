import SwiftUI

/// Album → gear. About, legal documents, and the one destructive action.
struct SettingsSheet: View {
    let model: AppModel
    var onDeleteAll: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var doc: LegalDoc? = nil
    @State private var confirmDelete = false

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return v ?? "1.0"
    }

    var body: some View {
        ZStack {
            PaperBackdrop(showsGrid: false)

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 6) {
                    Text("POSTMARK")
                        .font(Theme.engraved(17))
                        .tracking(5)
                        .foregroundStyle(Theme.ink)
                    Text("Version \(version)")
                        .font(.system(size: 13, design: .serif))
                        .italic()
                        .foregroundStyle(Theme.inkSoft)
                }
                .padding(.top, 34)
                .padding(.bottom, 26)

                Line()
                    .stroke(Theme.ink.opacity(0.14),
                            style: StrokeStyle(lineWidth: 1, dash: [2.5, 4]))
                    .frame(height: 1)
                    .padding(.horizontal, 26)

                VStack(spacing: 0) {
                    row("Terms of Service") { doc = .terms }
                    row("Privacy Policy") { doc = .privacy }
                }
                .padding(.top, 8)

                Line()
                    .stroke(Theme.ink.opacity(0.14),
                            style: StrokeStyle(lineWidth: 1, dash: [2.5, 4]))
                    .frame(height: 1)
                    .padding(.horizontal, 26)
                    .padding(.top, 8)

                Button {
                    confirmDelete = true
                } label: {
                    HStack {
                        Text("Delete All Data")
                            .font(.system(size: 16, weight: .medium, design: .serif))
                            .foregroundStyle(Theme.postalRed)
                        Spacer()
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.postalRed.opacity(0.8))
                    }
                    .padding(.horizontal, 30)
                    .padding(.vertical, 17)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)

                Text("Every stamp lives only on this device.")
                    .font(.system(size: 12.5, design: .serif))
                    .italic()
                    .foregroundStyle(Theme.inkSoft.opacity(0.85))
                    .padding(.top, 14)

                Spacer(minLength: 0)
            }
        }
        .presentationDetents([.medium])
        .presentationCornerRadius(28)
        .sheet(item: $doc) { LegalDocView(doc: $0) }
        .confirmationDialog(
            "Delete every stamp and photo? This cannot be undone.",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete All Data", role: .destructive) {
                dismiss()
                onDeleteAll()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func row(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .medium, design: .serif))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 17)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A legal document on paper: serif, calm, readable.
struct LegalDocView: View {
    let doc: LegalDoc
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            PaperBackdrop(showsGrid: false)

            VStack(spacing: 0) {
                HStack {
                    Text(doc.rawValue)
                        .font(Theme.serifDisplay(24))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 38, height: 38)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                }
                .padding(.horizontal, 26)
                .padding(.top, 28)
                .padding(.bottom, 14)

                ScrollView(showsIndicators: false) {
                    Text(doc.body)
                        .font(.system(size: 14.5, design: .serif))
                        .lineSpacing(4.5)
                        .foregroundStyle(Theme.ink.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 26)
                        .padding(.bottom, 44)
                }
            }
        }
        .presentationCornerRadius(28)
    }
}
