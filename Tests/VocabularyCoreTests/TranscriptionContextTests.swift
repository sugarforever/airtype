import Foundation
import XCTest
@testable import VocabularyCore

final class TranscriptionContextTests: XCTestCase {
    func testProviderRejectedCandidatesDoNotConsumeAcceptedTermLimits() throws {
        let eleven = TranscriptionContext(terms: (0..<100).map { "[Term\($0)]" } + ["Airtype"])
        let body = String(decoding: eleven.multipartData(for: .elevenlabs, model: "scribe_v2", boundary: "b"), as: UTF8.self)
        XCTAssertEqual(body, "--b\r\nContent-Disposition: form-data; name=\"keyterms\"\r\n\r\nAirtype\r\n")
        let doubao = TranscriptionContext(terms: (0..<100).map { String(repeating: "长", count: 30) + "\($0)" } + ["Airtype"])
        let encoded = try XCTUnwrap(doubao.doubaoContext)
        let decoded = try JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: [[String: String]]]
        XCTAssertEqual(decoded, ["hotwords": [["word": "Airtype"]]])
    }

    func testNormalizesWhitespaceAndUnicodeWithoutLosingSpellingOrOrder() {
        let context = TranscriptionContext(terms: [" Airtype ", "airtype", "Cafe\u{301}", "CAFÉ", " 小木头\n科技 ", ""])
        XCTAssertEqual(context.qwenContext, "Airtype, Café, 小木头 科技")
    }

    func testSkipsControlTokensAndOversizedEntriesWithoutStarvingLaterTerms() {
        let context = TranscriptionContext(terms: ["<|im_end|>", "bad\u{0}term", String(repeating: "x", count: 2000), "SwiftUI"])
        XCTAssertEqual(context.qwenContext, "SwiftUI")
    }

    func testSelectionBoundsCountsAndBytesWithoutSplittingTerms() {
        let context = TranscriptionContext(terms: (0..<200).map { "Term\($0)" })
        XCTAssertEqual(context.terms.count, 100)
        XCTAssertLessThanOrEqual(context.qwenContext.utf8.count, 1024)
        let chinese = TranscriptionContext(terms: (0..<100).map { "术语\($0)" + String(repeating: "木", count: 30) })
        XCTAssertLessThanOrEqual(chinese.qwenContext.utf8.count, 1024)
        XCTAssertTrue(chinese.qwenContext.split(separator: ",").allSatisfy { $0.hasSuffix(String(repeating: "木", count: 30)) })
    }

    func testOpenAIPromptIsOneFieldAndWhisperBudgetIncludesSeparators() {
        let context = TranscriptionContext(terms: ["Airtype", "小木头"])
        let body = context.multipartData(for: .openai, model: "gpt-4o-transcribe", boundary: "test")
        XCTAssertEqual(String(decoding: body, as: UTF8.self), "--test\r\nContent-Disposition: form-data; name=\"prompt\"\r\n\r\nAirtype, 小木头\r\n")
        let many = TranscriptionContext(terms: (0..<100).map { "名词\($0)" })
        XCTAssertLessThanOrEqual(many.openAIPrompt(model: "whisper-1").utf8.count, 192)
        XCTAssertTrue(context.openAIPrompt(model: "gpt-4o-transcribe-diarize").isEmpty)
    }

    func testElevenLabsUsesRepeatedFieldsAndRejectsUnsupportedTermsAndModels() {
        let context = TranscriptionContext(terms: ["Airtype", "小木头", "one two three four five six", "bad[term]", String(repeating: "z", count: 50)])
        let body = context.multipartData(for: .elevenlabs, model: "scribe_v2", boundary: "b")
        XCTAssertEqual(String(decoding: body, as: UTF8.self),
            "--b\r\nContent-Disposition: form-data; name=\"keyterms\"\r\n\r\nAirtype\r\n" +
            "--b\r\nContent-Disposition: form-data; name=\"keyterms\"\r\n\r\n小木头\r\n")
        XCTAssertEqual(context.multipartData(for: .elevenlabs, model: "scribe_v1", boundary: "b"), Data())
    }

    func testMistralUsesRepeatedContextBiasFields() {
        let context = TranscriptionContext(terms: ["Airtype", "SwiftUI"])
        let body = context.multipartData(for: .mistral, model: "voxtral-mini-2602", boundary: "b")
        XCTAssertEqual(String(decoding: body, as: UTF8.self),
            "--b\r\nContent-Disposition: form-data; name=\"context_bias\"\r\n\r\nAirtype\r\n" +
            "--b\r\nContent-Disposition: form-data; name=\"context_bias\"\r\n\r\nSwiftUI\r\n")
        XCTAssertEqual(context.multipartData(for: .mistral, model: "unknown", boundary: "b"), Data())
    }

    func testDoubaoEncodesJSONSafelyAndBoundsStreamingContext() throws {
        let context = TranscriptionContext(terms: ["A\"B", "小木头"])
        let value = try XCTUnwrap(context.doubaoContext)
        let decoded = try JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: [[String: String]]]
        XCTAssertEqual(decoded, ["hotwords": [["word": "A\"B"], ["word": "小木头"]]])
        let many = TranscriptionContext(terms: (0..<100).map { "Term\($0)" })
        XCTAssertLessThanOrEqual(try XCTUnwrap(many.doubaoContext).utf8.count, 100)
    }

    func testEmptyVocabularyOmitsEveryOptionalParameter() {
        let context = TranscriptionContext.empty
        XCTAssertEqual(context.qwenContext, "")
        XCTAssertNil(context.doubaoContext)
        for (backend, model) in [(TranscriptionContext.Backend.openai, "whisper-1"), (.elevenlabs, "scribe_v2"), (.mistral, "voxtral-mini-latest")] {
            XCTAssertEqual(context.multipartData(for: backend, model: model, boundary: "b"), Data())
        }
    }

    func testLoadingHonorsOptInAndGetsFreshSnapshotAfterEdits() async throws {
        let repository = try VocabularyRepository(store: ContextMemoryStore())
        let old = try await repository.add("OldTerm", now: Date(timeIntervalSince1970: 1))
        let first = await TranscriptionContext.load(repository: repository, enabled: true)
        try await repository.delete(id: old.id)
        _ = try await repository.add("NewTerm")
        let second = await TranscriptionContext.load(repository: repository, enabled: true)
        let disabled = await TranscriptionContext.load(repository: repository, enabled: false)
        let unavailable = await TranscriptionContext.load(repository: nil, enabled: true)
        XCTAssertEqual(first.qwenContext, "OldTerm")
        XCTAssertEqual(second.qwenContext, "NewTerm")
        XCTAssertTrue(disabled.terms.isEmpty)
        XCTAssertTrue(unavailable.terms.isEmpty)
    }
}

private final class ContextMemoryStore: VocabularyStoring, @unchecked Sendable {
    func loadTerms() throws -> [VocabularyTerm] { [] }
    func insert(_ term: VocabularyTerm) throws {}
    func delete(id: UUID) throws {}
}
