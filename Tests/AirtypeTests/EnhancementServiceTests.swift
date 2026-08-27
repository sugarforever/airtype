import XCTest
@testable import Airtype

final class EnhancementServiceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "airtype-enhancement-service-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testConfigurationUsesEnhancementRequestShapeWhileEnhancementIsDisabled() async throws {
        let settings = makeSettings(provider: .custom)
        settings.enhancementEnabled = false
        settings.currentEnhancementBaseURL = "https://example.test/v1/"
        settings.currentEnhancementModel = "compatible-model"
        settings.currentEnhancementApiKey = "secret-key"

        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.test/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-key")

            let body = try XCTUnwrap(Self.bodyData(from: request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["model"] as? String, "compatible-model")
            XCTAssertEqual(json["max_completion_tokens"] as? Int, 2048)
            XCTAssertEqual(json["temperature"] as? Double, 0.1)
            let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
            XCTAssertEqual(messages.count, 2)
            XCTAssertEqual(messages[0]["role"], "system")
            XCTAssertEqual(messages[1]["role"], "user")

            return Self.response(
                statusCode: 200,
                body: #"{"choices":[{"message":{"role":"assistant","content":"Airtype works well."}}]}"#,
                for: request
            )
        }

        let output = try await EnhancementService(settings: settings, session: makeSession()).testConfiguration()

        XCTAssertEqual(output, "Airtype works well.")
    }

    func testConfigurationExplainsAuthenticationFailure() async {
        let settings = makeSettings(provider: .moonshot)
        settings.currentEnhancementApiKey = "bad-key"
        URLProtocolStub.requestHandler = { request in
            Self.response(
                statusCode: 401,
                body: #"{"error":{"message":"Invalid Authentication"}}"#,
                for: request
            )
        }

        await XCTAssertThrowsErrorAsync(
            try await EnhancementService(settings: settings, session: makeSession()).testConfiguration()
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Moonshot AI rejected the API key (HTTP 401). Check the key and account permissions."
            )
        }
    }

    func testConfigurationExplainsEndpointOrModelFailure() async {
        let settings = makeSettings(provider: .custom)
        settings.currentEnhancementBaseURL = "https://example.test/v1"
        settings.currentEnhancementModel = "missing-model"
        settings.currentEnhancementApiKey = "key"
        URLProtocolStub.requestHandler = { request in
            Self.response(statusCode: 404, body: "Not found", for: request)
        }

        await XCTAssertThrowsErrorAsync(
            try await EnhancementService(settings: settings, session: makeSession()).testConfiguration()
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Custom could not find the configured endpoint or model “missing-model” (HTTP 404). Check the Base URL and Model fields."
            )
        }
    }

    func testConfigurationExplainsIncompatibleSuccessResponse() async {
        let settings = makeSettings(provider: .custom)
        settings.currentEnhancementBaseURL = "https://example.test/v1"
        settings.currentEnhancementModel = "different-api"
        settings.currentEnhancementApiKey = "key"
        URLProtocolStub.requestHandler = { request in
            Self.response(statusCode: 200, body: #"{"output":"ok"}"#, for: request)
        }

        await XCTAssertThrowsErrorAsync(
            try await EnhancementService(settings: settings, session: makeSession()).testConfiguration()
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Custom responded successfully, but its response is not OpenAI chat-completions compatible."
            )
        }
    }

    func testConfigurationRejectsEmptyCompletionInsteadOfReportingSuccess() async {
        let settings = makeSettings(provider: .custom)
        settings.currentEnhancementBaseURL = "https://example.test/v1"
        settings.currentEnhancementModel = "empty-model"
        settings.currentEnhancementApiKey = "key"
        URLProtocolStub.requestHandler = { request in
            Self.response(
                statusCode: 200,
                body: #"{"choices":[{"message":{"role":"assistant","content":"   "}}]}"#,
                for: request
            )
        }

        await XCTAssertThrowsErrorAsync(
            try await EnhancementService(settings: settings, session: makeSession()).testConfiguration()
        ) { error in
            XCTAssertEqual(error.localizedDescription, "The provider returned an empty completion.")
        }
    }

    func testSmartRewriteSelectionChangesOutgoingEnhancementInstructions() async throws {
        let settings = makeSettings(provider: .custom)
        settings.enhancementEnabled = true
        settings.enhancementMode = .smartRewrite
        settings.currentEnhancementBaseURL = "https://example.test/v1"
        settings.currentEnhancementModel = "compatible-model"
        settings.currentEnhancementApiKey = "secret-key"

        URLProtocolStub.requestHandler = { request in
            let body = try XCTUnwrap(Self.bodyData(from: request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
            XCTAssertTrue(messages[0]["content"]?.contains("Keep only the speaker's final decision") == true)
            return Self.response(
                statusCode: 200,
                body: #"{"choices":[{"message":{"role":"assistant","content":"Friday at 3 PM."}}]}"#,
                for: request
            )
        }

        let output = try await EnhancementService(settings: settings, session: makeSession()).enhance(
            text: "Thursday, no, Friday at 3 PM."
        )

        XCTAssertEqual(output, "Friday at 3 PM.")
    }

    func testSmartRewriteSendsSpokenQuestionAsDelimitedSourceText() async throws {
        let settings = makeSettings(provider: .custom)
        settings.enhancementEnabled = true
        settings.enhancementMode = .smartRewrite
        settings.currentEnhancementBaseURL = "https://example.test/v1"
        settings.currentEnhancementModel = "compatible-model"
        settings.currentEnhancementApiKey = "secret-key"

        URLProtocolStub.requestHandler = { request in
            let body = try XCTUnwrap(Self.bodyData(from: request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
            XCTAssertEqual(
                messages[1]["content"],
                "<speech_transcript>\nCodex 和 DeepSeek Harness 的对比视频可以从哪些方面入手？\n</speech_transcript>"
            )
            return Self.response(
                statusCode: 200,
                body: #"{"choices":[{"message":{"role":"assistant","content":"Codex 和 DeepSeek Harness 的对比视频，可以从哪些方面入手？"}}]}"#,
                for: request
            )
        }

        let output = try await EnhancementService(settings: settings, session: makeSession()).enhance(
            text: "Codex 和 DeepSeek Harness 的对比视频可以从哪些方面入手？"
        )

        XCTAssertEqual(output, "Codex 和 DeepSeek Harness 的对比视频，可以从哪些方面入手？")
    }

    private func makeSettings(provider: EnhancementProvider) -> Settings {
        let settings = Settings(defaults: defaults)
        settings.enhancementProvider = provider
        return settings
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private static func response(statusCode: Int, body: String, for request: URLRequest) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }

        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}

private final class URLProtocolStub: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
