import SwiftUI
#if SWIFT_PACKAGE
import CorrectionLearningCore
#endif

struct LearnedCorrectionsView: View {
    let corrections: [CorrectionSample]
    let totalCorrectionCount: Int
    let isSearching: Bool
    let isBusy: Bool
    let onDelete: (UUID) async -> Void

    var body: some View {
        if corrections.isEmpty {
            LearnedCorrectionsEmptyState(
                hasStoredCorrections: totalCorrectionCount > 0,
                isSearching: isSearching
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(corrections) { correction in
                        LearnedCorrectionRow(
                            correction: correction,
                            isBusy: isBusy,
                            onDelete: onDelete
                        )
                    }
                }
                .background(Theme.cardBg, in: .rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.border, lineWidth: 1)
                }
                .padding(28)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }
}

private struct LearnedCorrectionRow: View {
    let correction: CorrectionSample
    let isBusy: Bool
    let onDelete: (UUID) async -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button(action: toggleContext) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))

                        Text(correction.original)
                            .strikethrough()
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)

                        Text(correction.replacement)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text("\(correction.correctionCount)×")
                            .foregroundStyle(Theme.textTertiary)
                            .monospacedDigit()
                            .accessibilityLabel("Corrected \(correction.correctionCount) times")
                    }
                    .font(.system(size: 12))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                Menu {
                    Button("Delete", role: .destructive, action: deleteCorrection)
                } label: {
                    Label("Correction actions", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 24, height: 24)
                        .contentShape(.rect)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(isBusy)
                .accessibilityLabel("Actions for \(correction.original) to \(correction.replacement)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if isExpanded {
                Text(contextText)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 31)
                    .padding(.trailing, 46)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }

            Divider()
                .overlay(Theme.border)
        }
        .animation(.easeInOut(duration: 0.15), value: isExpanded)
    }

    private var contextText: String {
        [correction.contextBefore, correction.replacement, correction.contextAfter]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func toggleContext() {
        isExpanded.toggle()
    }

    private func deleteCorrection() {
        Task {
            await onDelete(correction.id)
        }
    }
}

private struct LearnedCorrectionsEmptyState: View {
    let hasStoredCorrections: Bool
    let isSearching: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: showsNoMatches ? "magnifyingglass" : "arrow.left.arrow.right")
                .font(.system(size: 30))
                .foregroundStyle(Theme.textSecondary)

            Text(showsNoMatches ? "No matching corrections" : "No learned corrections yet")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)

            if !showsNoMatches {
                Text("Corrections you make after transcription will appear here.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var showsNoMatches: Bool {
        hasStoredCorrections && isSearching
    }
}
