#if canImport(Airtype)
import XCTest
@testable import Airtype

final class ModelDownloadSizeProviderTests: XCTestCase {
    func testRemoteEstimateIncludesOnlyFilesDownloadedByMLXAudio() async {
        let provider = ModelDownloadSizeProvider { _ in
            [
                .init(path: "model.safetensors", size: 1_500_000_000),
                .init(path: "config.json", size: 2_000),
                .init(path: "tokenizer.json", size: 3_000),
                .init(path: "README.md", size: 900_000),
                .init(path: "preview.png", size: 4_000_000)
            ]
        }

        let estimate = await provider.estimate(for: .qwen3ASR17B4bit)

        XCTAssertEqual(estimate, .init(bytes: 1_500_005_000, source: .remote))
    }

    func testMissingRemoteMetadataFallsBackToCatalogEstimate() async {
        let provider = ModelDownloadSizeProvider { _ in
            throw URLError(.notConnectedToInternet)
        }

        let estimate = await provider.estimate(for: .qwen3ASR06B4bit)

        XCTAssertEqual(estimate, .init(bytes: 710_000_000, source: .catalogFallback))
    }

    func testSuccessfulRemoteEstimateIsCachedPerModel() async {
        let counter = RequestCounter()
        let provider = ModelDownloadSizeProvider { _ in
            await counter.increment()
            return [.init(path: "model.safetensors", size: 42)]
        }

        _ = await provider.estimate(for: .qwen3ASR06B5bit)
        _ = await provider.estimate(for: .qwen3ASR06B5bit)

        let requestCount = await counter.value
        XCTAssertEqual(requestCount, 1)
    }
}

private actor RequestCounter {
    private var count = 0

    var value: Int { count }

    func increment() {
        count += 1
    }
}
#endif
