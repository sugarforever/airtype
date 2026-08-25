import SwiftUI
#if SWIFT_PACKAGE
import DashboardCore
#endif

struct VocabularyView: View {
    @Bindable var model: VocabularyPageModel

    var body: some View {
        VStack(spacing: 0) {
            VocabularyHeader(model: model)

            Divider()
                .overlay(Theme.border)

            if let localErrorText = model.localErrorText {
                VocabularyErrorState(message: localErrorText)
            }

            ProperNounTagWall(
                terms: model.visibleTerms,
                totalTermCount: model.terms.count,
                isSearching: !model.query.isEmpty,
                termText: $model.termText,
                validationText: model.validationText,
                isBusy: model.isLoading,
                onAdd: addTerm,
                onDelete: deleteTerm
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await model.load()
        }
    }

    private func addTerm() async -> Bool {
        await model.addTerm()
    }

    private func deleteTerm(id: UUID) async {
        await model.deleteTerm(id: id)
    }
}

private struct VocabularyHeader: View {
    @Bindable var model: VocabularyPageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Vocabulary")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Proper nouns Airtype uses to improve your text")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                Label(
                    "Stored locally; bounded guidance is sent to your Enhancement provider.",
                    systemImage: "lock.fill"
                )
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }

            HStack(spacing: 12) {
                Text("Proper Nouns")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                Spacer(minLength: 0)

                TextField("Search proper nouns", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)

                ProgressView()
                    .controlSize(.small)
                    .opacity(model.isLoading ? 1 : 0)
                    .accessibilityHidden(!model.isLoading)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }
}

private struct VocabularyErrorState: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.statusOrange)

            Text(message)
                .foregroundStyle(Theme.textPrimary)

            Spacer()
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.statusOrange.opacity(0.1), in: .rect(cornerRadius: 8))
        .padding(.horizontal, 28)
        .padding(.top, 16)
    }
}
