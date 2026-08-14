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
    public private(set) var properNounErrorText: String?
    public private(set) var correctionErrorText: String?

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
        query.isEmpty
            ? terms
            : terms.filter { $0.value.localizedStandardContains(query) }
    }

    public var visibleCorrections: [CorrectionSample] {
        guard !query.isEmpty else { return corrections }
        return corrections.filter {
            $0.original.localizedStandardContains(query)
                || $0.replacement.localizedStandardContains(query)
        }
    }

    public var localErrorText: String? {
        let messages = [properNounErrorText, correctionErrorText].compactMap { $0 }
        return messages.isEmpty ? nil : messages.joined(separator: " ")
    }

    public func load() async {
        beginLoading()

        if let repository {
            publishTerms(await repository.allTerms())
            publishProperNounError(nil)
        } else {
            publishTerms([])
            publishProperNounError("Proper-noun storage is unavailable.")
        }

        if let learningService {
            publishCorrections(await learningService.samples())
            if await learningService.persistenceHealth == .unavailable {
                publishCorrectionError("Learned-correction storage is unavailable.")
            } else {
                publishCorrectionError(nil)
            }
        } else {
            publishCorrections([])
            publishCorrectionError("Learned-correction storage is unavailable.")
        }

        endLoading()
    }

    public func observeCorrectionUpdates() async {
        guard let learningService else { return }
        for await snapshot in await learningService.updates() {
            guard !Task.isCancelled else { return }
            publishCorrections(snapshot.samples)
            publishCorrectionError(
                snapshot.persistenceHealth == .available
                    ? nil
                    : "Learned-correction storage is unavailable."
            )
        }
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

    public func deleteCorrection(id: UUID) async {
        publishCorrectionError(nil)
        guard let learningService else {
            publishCorrectionError("Learned-correction storage is unavailable.")
            return
        }

        beginLoading()
        defer { endLoading() }
        do {
            try await learningService.deleteSample(id: id)
            publishCorrections(await learningService.samples())
        } catch {
            publishCorrections(await learningService.samples())
            publishCorrectionError("The learned correction could not be deleted locally.")
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

    private func publishProperNounError(_ message: String?) {
        if properNounErrorText != message {
            properNounErrorText = message
        }
    }

    private func publishCorrectionError(_ message: String?) {
        if correctionErrorText != message {
            correctionErrorText = message
        }
    }
}
