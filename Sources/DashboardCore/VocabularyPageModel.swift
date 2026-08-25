import Foundation
import Observation
#if SWIFT_PACKAGE
import VocabularyCore
#endif

@MainActor
@Observable
@available(macOS 14.0, *)
public final class VocabularyPageModel {
    public var query = ""
    public var termText = ""

    public private(set) var terms: [VocabularyTerm] = []
    public private(set) var validationText: String?
    public private(set) var isLoading = false
    public private(set) var properNounErrorText: String?

    @ObservationIgnored private let repository: VocabularyRepository?

    public init(repository: VocabularyRepository?) {
        self.repository = repository
    }

    public var visibleTerms: [VocabularyTerm] {
        query.isEmpty
            ? terms
            : terms.filter { $0.value.localizedStandardContains(query) }
    }

    public var localErrorText: String? { properNounErrorText }

    public func load() async {
        beginLoading()

        if let repository {
            publishTerms(await repository.allTerms())
            publishProperNounError(nil)
        } else {
            publishTerms([])
            publishProperNounError("Proper-noun storage is unavailable.")
        }

        endLoading()
    }

    @discardableResult
    public func addTerm() async -> Bool {
        publishValidation(nil)
        publishProperNounError(nil)
        let trimmedTerm = termText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTerm.isEmpty else {
            publishValidation("Enter a proper noun.")
            return false
        }
        guard let repository else {
            publishProperNounError("Proper-noun storage is unavailable.")
            return false
        }

        beginLoading()
        defer { endLoading() }
        do {
            _ = try await repository.add(trimmedTerm)
            publishTerms(await repository.allTerms())
            if !termText.isEmpty {
                termText = ""
            }
            return true
        } catch VocabularyRepositoryError.duplicateTerm {
            publishValidation("That proper noun already exists.")
            return false
        } catch {
            publishProperNounError("The proper noun could not be saved locally.")
            return false
        }
    }

    public func deleteTerm(id: UUID) async {
        publishProperNounError(nil)
        guard let repository else {
            publishProperNounError("Proper-noun storage is unavailable.")
            return
        }

        beginLoading()
        defer { endLoading() }
        do {
            try await repository.delete(id: id)
            publishTerms(await repository.allTerms())
        } catch {
            publishProperNounError("The proper noun could not be deleted locally.")
        }
    }

    private func beginLoading() {
        if !isLoading {
            isLoading = true
        }
    }

    private func endLoading() {
        if isLoading {
            isLoading = false
        }
    }

    private func publishTerms(_ newTerms: [VocabularyTerm]) {
        let sortedTerms = newTerms.sorted {
            let comparison = $0.value.localizedStandardCompare($1.value)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        if terms != sortedTerms {
            terms = sortedTerms
        }
    }

    private func publishValidation(_ message: String?) {
        if validationText != message {
            validationText = message
        }
    }

    private func publishProperNounError(_ message: String?) {
        if properNounErrorText != message {
            properNounErrorText = message
        }
    }
}
