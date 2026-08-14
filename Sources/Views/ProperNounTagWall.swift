import SwiftUI
#if SWIFT_PACKAGE
import VocabularyCore
#endif

struct ProperNounTagWall: View {
    let terms: [VocabularyTerm]
    let totalTermCount: Int
    let isSearching: Bool
    @Binding var termText: String
    let validationText: String?
    let isBusy: Bool
    let onAdd: () async -> Bool
    let onDelete: (UUID) async -> Void

    @State private var isPresentingAddField = false
    @State private var didAttemptAdd = false
    @FocusState private var isAddFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            actionBar

            Divider()
                .overlay(Theme.border)

            if terms.isEmpty {
                ProperNounEmptyState(
                    hasStoredTerms: totalTermCount > 0,
                    isSearching: isSearching
                )
            } else {
                ScrollView {
                    WrappingTagLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                        ForEach(terms) { term in
                            ProperNounTag(
                                term: term,
                                isBusy: isBusy,
                                onDelete: onDelete
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(28)
                }
            }
        }
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if isPresentingAddField {
                    TextField("Enter the correct proper noun", text: $termText)
                        .textFieldStyle(.roundedBorder)
                        .focused($isAddFieldFocused)
                        .onSubmit(submitTerm)
                        .onAppear {
                            isAddFieldFocused = true
                        }

                    Button("Add", action: submitTerm)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isBusy)

                    Button("Cancel", action: cancelAdd)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    Text("Add names, brands, products, and other terms that should be spelled exactly.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)

                    Spacer()

                    Button("Add Proper Noun", systemImage: "plus", action: presentAddField)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.brand)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.brand.opacity(0.12), in: .rect(cornerRadius: 6))
                        .buttonStyle(.plain)
                }
            }

            if didAttemptAdd, let validationText {
                Text(validationText)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.statusRed)
                    .accessibilityLabel("Proper noun error: \(validationText)")
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
    }

    private func presentAddField() {
        didAttemptAdd = false
        isPresentingAddField = true
    }

    private func cancelAdd() {
        termText = ""
        didAttemptAdd = false
        isAddFieldFocused = false
        isPresentingAddField = false
    }

    private func submitTerm() {
        guard !isBusy else { return }
        didAttemptAdd = true
        Task {
            if await onAdd() {
                didAttemptAdd = false
                isAddFieldFocused = false
                isPresentingAddField = false
            }
        }
    }
}

private struct ProperNounTag: View {
    let term: VocabularyTerm
    let isBusy: Bool
    let onDelete: (UUID) async -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 5) {
            Text(term.value)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Theme.textPrimary)

            Button {
                Task {
                    await onDelete(term.id)
                }
            } label: {
                Label("Delete \(term.value)", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 14, height: 14)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            .disabled(isBusy)
            .accessibilityLabel("Delete \(term.value)")
            .help("Delete \(term.value)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(Theme.cardBg, in: .rect(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(isHovered ? Theme.brand.opacity(0.45) : Theme.border, lineWidth: 1)
        }
        .onHover { isHovered in
            if self.isHovered != isHovered {
                self.isHovered = isHovered
            }
        }
    }
}

private struct ProperNounEmptyState: View {
    let hasStoredTerms: Bool
    let isSearching: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: showsNoMatches ? "magnifyingglass" : "textformat.abc")
                .font(.system(size: 30))
                .foregroundStyle(Theme.textSecondary)

            Text(showsNoMatches ? "No matching proper nouns" : "No proper nouns yet")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)

            if !showsNoMatches {
                Text("Add a term above to help Airtype spell it correctly.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var showsNoMatches: Bool {
        hasStoredTerms && isSearching
    }
}

private struct WrappingTagLayout: Layout {
    struct Cache {
        var sizes: [CGSize]
    }

    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        let naturalWidth = cache.sizes.reduce(0) { $0 + $1.width }
            + horizontalSpacing * CGFloat(max(0, cache.sizes.count - 1))
        let availableWidth = max(0, proposal.width ?? naturalWidth)
        let arrangement = arrangement(for: cache.sizes, maxWidth: availableWidth)
        return CGSize(width: proposal.width ?? arrangement.size.width, height: arrangement.size.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        let arrangement = arrangement(for: cache.sizes, maxWidth: max(0, bounds.width))
        for (index, subview) in subviews.enumerated() {
            guard index < arrangement.origins.count, index < cache.sizes.count else { continue }
            let origin = arrangement.origins[index]
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(cache.sizes[index])
            )
        }
    }

    private func arrangement(for sizes: [CGSize], maxWidth: CGFloat) -> Arrangement {
        guard !sizes.isEmpty else { return Arrangement(size: .zero, origins: []) }

        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var contentWidth: CGFloat = 0

        for size in sizes {
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }

            origins.append(CGPoint(x: x, y: y))
            contentWidth = max(contentWidth, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + horizontalSpacing
        }

        return Arrangement(
            size: CGSize(width: contentWidth, height: y + rowHeight),
            origins: origins
        )
    }
}

private struct Arrangement {
    let size: CGSize
    let origins: [CGPoint]
}
