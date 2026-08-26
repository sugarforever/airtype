#if canImport(Airtype)
import XCTest
import VocabularyCore
@testable import Airtype

final class TranscriptionRequestTests: XCTestCase {
    func testCloudEntryPointsForwardVocabularyToOutgoingRequests() async throws {
        let suiteName = "airtype-wire-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = Settings(defaults: defaults)
        settings.openaiTranscriptionApiKey = "test-only"
        settings.elevenlabsApiKey = "test-only"
        settings.mistralTranscriptionApiKey = "test-only"
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TranscriptionCaptureProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("airtype-wire-\(UUID().uuidString).m4a")
        try Data(repeating: 1, count: 256).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let context = TranscriptionContext(terms: ["Airtype", "小木头"])

        let openAI = try await WhisperService(settings: settings, session: session).transcribe(audioURL: file, context: context)
        XCTAssertEqual(openAI, "recognized")
        XCTAssertTrue(TranscriptionCaptureProtocol.body.contains("name=\"prompt\"\r\n\r\nAirtype, 小木头\r\n"))

        let eleven = try await ElevenLabsService(settings: settings, session: session).transcribe(audioURL: file, context: context)
        XCTAssertEqual(eleven, "recognized")
        XCTAssertTrue(TranscriptionCaptureProtocol.body.contains("name=\"keyterms\"\r\n\r\n小木头\r\n"))

        let mistral = try await MistralTranscriptionService(settings: settings, session: session).transcribe(audioURL: file, context: context)
        XCTAssertEqual(mistral, "recognized")
        XCTAssertTrue(TranscriptionCaptureProtocol.body.contains("name=\"context_bias\"\r\n\r\n小木头\r\n"))
    }

    func testTranscriptionVocabularyIsEnabledWithoutSetup() throws {
        let suiteName = "airtype-transcription-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = Settings(defaults: defaults)
        XCTAssertTrue(settings.transcriptionVocabularyEnabled)
    }

    func testLegacyOptOutDoesNotDisableVocabularyWhenEnhancementIsOff() throws {
        let suiteName = "airtype-transcription-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "transcription_vocabulary_enabled")
        let settings = Settings(defaults: defaults)
        settings.enhancementEnabled = false
        let reloaded = Settings(defaults: defaults)
        XCTAssertTrue(reloaded.transcriptionVocabularyEnabled)
        XCTAssertFalse(reloaded.enhancementEnabled)
    }

    func testOpenAIActualMultipartIncludesPromptAndAudio() {
        let body = WhisperService().createMultipartBody(audioData: Data("audio-bytes".utf8), fileName: "voice.m4a", model: "whisper-1", boundary: "b", context: TranscriptionContext(terms: ["Airtype"]))
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"prompt\"\r\n\r\nAirtype\r\n"))
        XCTAssertTrue(text.contains("name=\"model\"\r\n\r\nwhisper-1\r\n"))
        XCTAssertTrue(text.contains("audio-bytes\r\n--b--\r\n"))
    }

    func testElevenLabsActualMultipartIncludesRepeatedKeyterms() {
        let body = ElevenLabsService().createMultipartBody(audioData: Data([1, 2]), fileName: "a.wav", modelId: "scribe_v2", boundary: "b", context: TranscriptionContext(terms: ["Airtype", "SwiftUI"]))
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"keyterms\"\r\n\r\nAirtype\r\n"))
        XCTAssertTrue(text.contains("name=\"keyterms\"\r\n\r\nSwiftUI\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n--b--\r\n"))
    }

    func testMistralActualMultipartIncludesContextBias() {
        let body = MistralTranscriptionService().createMultipartBody(audioData: Data([1, 2]), fileName: "a.wav", model: "voxtral-mini-2602", boundary: "b", context: TranscriptionContext(terms: ["Airtype"]))
        XCTAssertTrue(String(decoding: body, as: UTF8.self).contains("name=\"context_bias\"\r\n\r\nAirtype\r\n"))
    }

    func testEmptyContextKeepsExistingBodiesAndUnsupportedModelOmitsHints() {
        let whisper = WhisperService().createMultipartBody(audioData: Data("audio".utf8), fileName: "a.m4a", model: "whisper-1", boundary: "b")
        XCTAssertEqual(String(decoding: whisper, as: UTF8.self), "--b\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-1\r\n--b\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.m4a\"\r\nContent-Type: audio/m4a\r\n\r\naudio\r\n--b--\r\n")
        let eleven = ElevenLabsService().createMultipartBody(audioData: Data(), fileName: "a.wav", modelId: "scribe_v1", boundary: "b", context: TranscriptionContext(terms: ["Airtype"]))
        XCTAssertFalse(String(decoding: eleven, as: UTF8.self).contains("keyterms"))
    }

    func testDoubaoInitUsesCorpusJSONStringAndDoesNotCacheSessionVocabulary() async throws {
        let service = DoubaoStreamingService(appId: "test-app", accessKey: "test-key", resourceId: "test-resource")
        let initial = try await service.makeInitPayload(context: .empty)
        let empty = try XCTUnwrap(JSONSerialization.jsonObject(with: initial) as? [String: Any])
        XCTAssertNil((empty["request"] as? [String: Any])?["corpus"])
        let payload = try await service.makeInitPayload(context: TranscriptionContext(terms: ["小木头"]))
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let request = try XCTUnwrap(config["request"] as? [String: Any])
        let corpus = try XCTUnwrap(request["corpus"] as? [String: String])
        let context = try XCTUnwrap(corpus["context"])
        let hotwords = try JSONSerialization.jsonObject(with: Data(context.utf8)) as? [String: [[String: String]]]
        XCTAssertEqual(hotwords, ["hotwords": [["word": "小木头"]]])
        XCTAssertEqual(request["model_name"] as? String, "bigmodel")
        XCTAssertEqual((config["audio"] as? [String: Any])?["rate"] as? Int, 16000)
    }
}

/// Intercepts only the test session; no credentials or audio leave the machine.
private final class TranscriptionCaptureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var capturedBody = ""
    static var body: String {
        lock.lock()
        defer { lock.unlock() }
        return capturedBody
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        Self.lock.lock()
        Self.capturedBody = String(decoding: data, as: UTF8.self)
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"text\":\"recognized\"}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
