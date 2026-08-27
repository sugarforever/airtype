#if canImport(Airtype)
import XCTest
import VocabularyCore
@testable import Airtype

final class TranscriptionRequestTests: XCTestCase {
    func testOpenRouterSettingsPersistSupportedModelAndCredentials() throws {
        let suiteName = "airtype-openrouter-settings-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = Settings(defaults: defaults)
        settings.enhancementEnabled = false
        settings.transcriptionProvider = .openrouter
        settings.openrouterTranscriptionApiKey = "sk-or-test"
        settings.openrouterTranscriptionModel = "qwen/qwen3-asr-1.7b"

        let reloaded = Settings(defaults: defaults)
        XCTAssertEqual(reloaded.transcriptionProvider, .openrouter)
        XCTAssertEqual(reloaded.currentTranscriptionApiKey, "sk-or-test")
        XCTAssertEqual(reloaded.currentTranscriptionModel, "qwen/qwen3-asr-1.7b")
        XCTAssertEqual(Settings.openrouterTranscriptionModels, [
            "qwen/qwen3-asr-0.6b",
            "qwen/qwen3-asr-1.7b",
        ])
        XCTAssertEqual(reloaded.transcriptionProvider.apiKeyURL?.absoluteString, "https://openrouter.ai/keys")
        XCTAssertTrue(reloaded.transcriptionProvider.requiresApiKey)
        XCTAssertTrue(reloaded.isConfigured)
        XCTAssertNil(reloaded.configurationError)

        reloaded.openrouterTranscriptionApiKey = "  \n"
        XCTAssertFalse(reloaded.isConfigured)
        XCTAssertEqual(reloaded.configurationError, "OpenRouter API key required for voice input")
    }

    func testOpenRouterSettingsReplaceUnsupportedPersistedModelWithDefault() throws {
        let suiteName = "airtype-openrouter-model-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("unsupported/model", forKey: "openrouter_transcription_model")

        let settings = Settings(defaults: defaults)

        XCTAssertEqual(settings.openrouterTranscriptionModel, "qwen/qwen3-asr-0.6b")
        XCTAssertEqual(defaults.string(forKey: "openrouter_transcription_model"), "qwen/qwen3-asr-0.6b")
    }

    func testCloudEntryPointsForwardVocabularyToOutgoingRequests() async throws {
        let suiteName = "airtype-wire-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = Settings(defaults: defaults)
        settings.openaiTranscriptionApiKey = "test-only"
        settings.elevenlabsApiKey = "test-only"
        settings.mistralTranscriptionApiKey = "test-only"
        settings.openrouterTranscriptionApiKey = "test-only"
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

        let openrouter = try await OpenRouterTranscriptionService(settings: settings, session: session).transcribe(audioURL: file)
        XCTAssertEqual(openrouter, "recognized")
        let openrouterPayload = try XCTUnwrap(JSONSerialization.jsonObject(with: TranscriptionCaptureProtocol.bodyData) as? [String: Any])
        XCTAssertEqual(openrouterPayload["model"] as? String, "qwen/qwen3-asr-0.6b")
    }

    func testOpenRouterRequestUsesQwenModelJSONAudioAndAirTypeAttribution() async throws {
        let suiteName = "airtype-openrouter-wire-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = Settings(defaults: defaults)
        settings.openrouterTranscriptionApiKey = "sk-or-test"
        settings.openrouterTranscriptionModel = "qwen/qwen3-asr-1.7b"

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TranscriptionCaptureProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("airtype-openrouter-\(UUID().uuidString).m4a")
        let audio = Data([0, 1, 2, 3, 4])
        try audio.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let text = try await OpenRouterTranscriptionService(settings: settings, session: session).transcribe(audioURL: file)

        XCTAssertEqual(text, "recognized")
        let request = try XCTUnwrap(TranscriptionCaptureProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/audio/transcriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "HTTP-Referer"), "https://www.airtype.space")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-OpenRouter-Title"), "AirType")
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: TranscriptionCaptureProtocol.bodyData) as? [String: Any])
        XCTAssertEqual(payload["model"] as? String, "qwen/qwen3-asr-1.7b")
        let inputAudio = try XCTUnwrap(payload["input_audio"] as? [String: String])
        XCTAssertEqual(inputAudio["data"], audio.base64EncodedString())
        XCTAssertEqual(inputAudio["format"], "m4a")
    }

    func testOpenRouterRejectsUnsupportedRuntimeModelBeforeSending() async throws {
        let suiteName = "airtype-openrouter-invalid-model-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = Settings(defaults: defaults)
        settings.openrouterTranscriptionApiKey = "sk-or-test"
        settings.openrouterTranscriptionModel = "unsupported/model"
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TranscriptionCaptureProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("airtype-openrouter-invalid-\(UUID().uuidString).wav")
        try Data([1]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        do {
            _ = try await OpenRouterTranscriptionService(settings: settings, session: session).transcribe(audioURL: file)
            XCTFail("Expected unsupported model to be rejected")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Unsupported OpenRouter transcription model: unsupported/model")
        }
    }

    func testOpenRouterReportsCredentialAndResponseFailures() async throws {
        let suiteName = "airtype-openrouter-errors-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = Settings(defaults: defaults)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TranscriptionCaptureProtocol.self]
        let session = URLSession(configuration: config)
        defer {
            TranscriptionCaptureProtocol.setResponse()
            session.invalidateAndCancel()
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("airtype-openrouter-errors-\(UUID().uuidString).wav")
        try Data([1]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let service = OpenRouterTranscriptionService(settings: settings, session: session)

        settings.openrouterTranscriptionApiKey = "  \n"
        await assertTranscriptionError(service, file: file, equals: "OpenRouter API key not configured")

        settings.openrouterTranscriptionApiKey = "sk-or-test"
        TranscriptionCaptureProtocol.setResponse(statusCode: 401, body: #"{"error":{"message":"Invalid API key"}}"#)
        await assertTranscriptionError(service, file: file, equals: "API error: Invalid API key")

        TranscriptionCaptureProtocol.setResponse(statusCode: 503, body: "unavailable")
        await assertTranscriptionError(service, file: file, equals: "HTTP error: 503")

        TranscriptionCaptureProtocol.setResponse(body: "{}")
        await assertTranscriptionError(service, file: file, equals: "Invalid response from OpenRouter API")

        TranscriptionCaptureProtocol.setResponse(body: #"{"text":"  \n"}"#)
        await assertTranscriptionError(service, file: file, equals: "OpenRouter returned an empty transcription")
    }

    private func assertTranscriptionError(
        _ service: OpenRouterTranscriptionService,
        file: URL,
        equals expected: String,
        filePath: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await service.transcribe(audioURL: file)
            XCTFail("Expected transcription to fail", file: filePath, line: line)
        } catch {
            XCTAssertEqual(error.localizedDescription, expected, file: filePath, line: line)
        }
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
    private static var capturedBodyData = Data()
    private static var capturedRequest: URLRequest?
    private static var responseStatusCode = 200
    private static var responseBody = Data("{\"text\":\"recognized\"}".utf8)
    static var body: String {
        lock.lock()
        defer { lock.unlock() }
        return capturedBody
    }
    static var bodyData: Data {
        lock.lock()
        defer { lock.unlock() }
        return capturedBodyData
    }
    static var lastRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequest
    }
    static func setResponse(statusCode: Int = 200, body: String = "{\"text\":\"recognized\"}") {
        lock.lock()
        responseStatusCode = statusCode
        responseBody = Data(body.utf8)
        lock.unlock()
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
        Self.capturedBodyData = data
        Self.capturedRequest = request
        Self.lock.unlock()
        Self.lock.lock()
        let statusCode = Self.responseStatusCode
        let responseData = Self.responseBody
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseData)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
