#if canImport(Airtype)
import Foundation
import XCTest
@testable import Airtype

final class OpenRouterKeyUsageServiceTests: XCTestCase {
    func testFetchUsesCurrentKeyAndDecodesUsageLimitAndExpiry() async throws {
        let (settings, defaults) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
        settings.openrouterTranscriptionApiKey = "sk-or-test"
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        KeyUsageProtocol.respond(
            status: 200,
            body: #"{"data":{"usage":25.5,"usage_daily":1.25,"usage_weekly":7.5,"usage_monthly":20.0,"limit":100,"limit_remaining":74.5,"limit_reset":"monthly","is_free_tier":false,"expires_at":"2027-12-31T23:59:59Z"}}"#
        )

        let usage = try await OpenRouterKeyUsageService(settings: settings, session: session).fetch()

        XCTAssertEqual(KeyUsageProtocol.lastRequest?.url?.absoluteString, "https://openrouter.ai/api/v1/key")
        XCTAssertEqual(KeyUsageProtocol.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(KeyUsageProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-test")
        XCTAssertEqual(usage.total, 25.5)
        XCTAssertEqual(usage.daily, 1.25)
        XCTAssertEqual(usage.weekly, 7.5)
        XCTAssertEqual(usage.monthly, 20)
        XCTAssertEqual(usage.limit, 100)
        XCTAssertEqual(usage.limitRemaining, 74.5)
        XCTAssertEqual(usage.limitReset, "monthly")
        XCTAssertFalse(usage.isFreeTier)
        XCTAssertEqual(usage.expiresAt, ISO8601DateFormatter().date(from: "2027-12-31T23:59:59Z"))
    }

    func testFetchRejectsMissingKeyWithoutSendingRequest() async throws {
        let (settings, defaults) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
        settings.openrouterTranscriptionApiKey = " \n"
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        KeyUsageProtocol.reset()

        await assertError(
            OpenRouterKeyUsageService(settings: settings, session: session),
            equals: "OpenRouter API key not configured"
        )
        XCTAssertNil(KeyUsageProtocol.lastRequest)
    }

    func testFetchReportsUnauthorizedAndMalformedResponses() async throws {
        let (settings, defaults) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
        settings.openrouterTranscriptionApiKey = "sk-or-test"
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let service = OpenRouterKeyUsageService(settings: settings, session: session)

        KeyUsageProtocol.respond(status: 401, body: #"{"error":{"message":"invalid"}}"#)
        await assertError(service, equals: "OpenRouter rejected the API key")

        KeyUsageProtocol.respond(status: 200, body: "{}")
        await assertError(service, equals: "Invalid usage response from OpenRouter")
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [KeyUsageProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeSettings() throws -> (Settings, UserDefaults) {
        let suite = "OpenRouterKeyUsageServiceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(suite, forKey: "test_suite_name")
        return (Settings(defaults: defaults), defaults)
    }

    private func defaultsSuite(_ defaults: UserDefaults) -> String {
        defaults.string(forKey: "test_suite_name")!
    }

    private func assertError(
        _ service: OpenRouterKeyUsageService,
        equals expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await service.fetch()
            XCTFail("Expected usage fetch to fail", file: file, line: line)
        } catch {
            XCTAssertEqual(error.localizedDescription, expected, file: file, line: line)
        }
    }
}

private final class KeyUsageProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var status = 200
    private static var body = Data()
    private static var requestValue: URLRequest?

    static var lastRequest: URLRequest? {
        lock.withLock { requestValue }
    }

    static func respond(status: Int, body: String) {
        lock.withLock {
            self.status = status
            self.body = Data(body.utf8)
            requestValue = nil
        }
    }

    static func reset() {
        lock.withLock { requestValue = nil }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, body) = Self.lock.withLock { () -> (Int, Data) in
            Self.requestValue = request
            return (Self.status, Self.body)
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
#endif
