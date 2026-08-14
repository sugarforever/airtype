import SwiftUI
#if SWIFT_PACKAGE
import DashboardCore
#endif

struct TranscriptionHistoryView: View {
    @Bindable var model: HistoryPageModel

    var body: some View {
        VStack(spacing: 0) {
            pageHeader

            Divider()
                .overlay(Theme.border)

            if model.filteredEntries.isEmpty {
                HistoryEmptyState(
                    isSearching: !model.query.isEmpty && !model.entries.isEmpty
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.filteredEntries) { entry in
                            HistoryEntryCard(
                                entry: entry,
                                isCopied: model.copiedID == entry.id,
                                onCopy: { model.copy(entry) }
                            )
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
        .confirmationDialog(
            "Clear transcription history?",
            isPresented: clearConfirmationBinding
        ) {
            Button("Clear History", role: .destructive, action: model.confirmClear)
            Button("Cancel", role: .cancel, action: model.cancelClear)
        } message: {
            Text("This removes all saved transcriptions from this Mac. This cannot be undone.")
        }
    }

    private var pageHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("History")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Your 50 most recent transcriptions")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            TextField("Search history", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)

            Button("Clear", action: model.requestClear)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.brand)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.brand.opacity(0.12), in: .rect(cornerRadius: 6))
                .buttonStyle(.plain)
                .disabled(model.entries.isEmpty)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    private var clearConfirmationBinding: Binding<Bool> {
        Binding(
            get: { model.isClearConfirmationPresented },
            set: { isPresented in
                if !isPresented {
                    model.cancelClear()
                }
            }
        )
    }
}

private struct HistoryEntryCard: View {
    let entry: TranscriptionHistory.Entry
    let isCopied: Bool
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(entry.text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Text(entry.date, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)

                Spacer()

                Button(action: onCopy) {
                    Image(systemName: isCopied ? "checkmark" : "square.on.square")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isCopied ? Theme.brand : Theme.textSecondary)
                        .frame(width: 20, height: 20)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCopied ? "Copied" : "Copy transcription")
                .help(isCopied ? "Copied" : "Copy to clipboard")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBg, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.border, lineWidth: 1)
        }
    }
}

private struct HistoryEmptyState: View {
    let isSearching: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: isSearching ? "magnifyingglass" : "text.bubble")
                .font(.system(size: 32))
                .foregroundStyle(Theme.textSecondary)
            Text(isSearching ? "No matching transcriptions" : "No transcriptions yet")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }
}
