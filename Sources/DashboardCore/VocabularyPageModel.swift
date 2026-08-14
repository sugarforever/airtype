import Foundation
import Observation
#if SWIFT_PACKAGE
import CorrectionLearningCore
import VocabularyCore
#endif

public enum VocabularyTab: String, CaseIterable, Identifiable, Sendable {
    case properNouns
    case learnedCorrections

    public var id: Self { self }
}

@MainActor
@Observable
@available(macOS 14.0, *)
public final class VocabularyPageModel {
    public var selectedTab: VocabularyTab = .properNouns
    public var query = ""
    public var termText = ""

    public private(set) var terms: [VocabularyTerm] = []
    public private(set) var corrections: [CorrectionSample] = []
    public private(set) var validationText: String?
    public private(set) var isLoading = false
    public private(set) var localErrorText: String?

    @ObservationIgnored private let repository: VocabularyRepository?
    @ObservationIgnored private let learningService: CorrectionLearningService?

    public init(
        repository: VocabularyRepository?,
        learningService: CorrectionLearningService?
    ) {
        self.repository = repository
        self.learningService = learningService
    }

    public var visibleTerms: [VocabularyTerm] {
        let matchingTerms = query.isEmpty
            ? terms
            : terms.filter { $0.value.localizedStandardContains(query) }
        return matchingTerms.sorted {
            let comparison = $0.value.localizedStandardCompare($1.value)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    public var visibleCorrections: [CorrectionSample] {
        guard !query.isEmpty else { return corrections }
        return corrections.filter {
            $0.original.localizedStandardContains(query)
                || $0.replacement.localizedStandardContains(query)
        }
    }

    public func load() async {
        beginLoading()
        var messages: [String] = []

        if let repository {
            publishTerms(await repository.allTerms())
        } else {
            publishTerms([])
            messages.append("Proper-noun storage is unavailable.")
        }

        if let learningService {
            publishCorrections(await learningService.samples())
        } else {
            publishCorrections([])
            messages.append("Learned-correction storage is unavailable.")
        }

        publishLocalError(messages.isEmpty ? nil : messages.joined(separator: " "))
        endLoading()
    }

    public func addTerm() async {
        publishValidation(nil)
        publishLocalError(nil)
        let trimmedTerm = termText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTerm.isEmpty else {
            publishValidation("Enter a proper noun.")
            return
        }
        guard let repository else {
            publishLocalError("Proper-noun storage is unavailable.")
            return
        }

        beginLoading()
        defer { endLoading() }
        do {
            _ = try await repository.add(trimmedTerm)
            publishTerms(await repository.allTerms())
            if !termText.isEmpty {
                termText = ""
            }
        } catch VocabularyRepositoryError.duplicateTerm {
            publishValidation("That proper noun already exists.")
        } catch {
            publishLocalError("The proper noun could not be saved locally.")
        }
    }

    public func deleteTerm(id: UUID) async {
        publishLocalError(nil)
        guard let repository else {
            publishLocalError("Proper-noun storage is unavailable.")
            return
        }

        beginLoading()
        defer { endLoading() }
        do {
            try await repository.delete(id: id)
            publishTerms(await repository.allTerms())
        } catch {
            publishLocalError("The proper noun could not be deleted locally.")
        }
    }

    public func deleteCorrection(id: UUID) async {
        publishLocalError(nil)
        guard let learningService else {
            publishLocalError("Learned-correction storage is unavailable.")
            return
        }

        beginLoading()
        defer { endLoading() }
        do {
            try await learningService.deleteSample(id: id)
            publishCorrections(await learningService.samples())
        } catch {
            publishCorrections(await learningService.samples())
            publishLocalError("The learned correction could not be deleted locally.")
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
        if terms != newTerms {
            terms = newTerms
        }
    }

    private func publishCorrections(_ newCorrections: [CorrectionSample]) {
        if corrections != newCorrections {
            corrections = newCorrections
        }
    }

    private func publishValidation(_ message: String?) {
        if validationText != message {
            validationText = message
        }
    }

    private func publishLocalError(_ message: String?) {
        if localErrorText != message {
            localErrorText = message
        }
    }
}
