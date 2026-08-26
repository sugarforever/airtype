#if canImport(Airtype)
import XCTest
@testable import Airtype

@MainActor
final class LocalModelManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var settings: Settings!

    override func setUp() async throws {
        suiteName = "airtype-model-install-tests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        settings = Settings(defaults: defaults)
        settings.localMLXModel = .qwen3ASR06B4bit
        settings.localMLXInstalledModels = []
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testPublishesDownloadAndLoadingBeforeMarkingInstalled() async {
        var manager: LocalModelManager!
        manager = LocalModelManager(installer: { modelID, report in
            XCTAssertEqual(modelID, "mlx-community/Qwen3-ASR-0.6B-4bit")
            XCTAssertTrue(manager.isInstalling)
            XCTAssertEqual(manager.phase, .preparing)
            report(.downloading(0.42))
            XCTAssertEqual(manager.phase, .downloading(0.42))
            report(.downloading(1))
            XCTAssertTrue(self.settings.localMLXInstalledModels.isEmpty)
            report(.loading)
            XCTAssertEqual(manager.phase, .loading)
            XCTAssertTrue(manager.isInstalling)
            XCTAssertTrue(self.settings.localMLXInstalledModels.isEmpty)
        })

        await manager.installSelectedModel(settings: settings)

        XCTAssertFalse(manager.isInstalling)
        XCTAssertNil(manager.phase)
        XCTAssertNil(manager.lastError)
        XCTAssertEqual(settings.localMLXInstalledModels, ["Qwen3-ASR-0.6B-4bit"])
    }

    func testSelectionChangeDoesNotChangeInstalledModelIdentity() async {
        let manager = LocalModelManager(installer: { _, report in
            report(.downloading(0.5))
            self.settings.localMLXModel = .qwen3ASR17B
            await Task.yield()
            report(.loading)
        })

        await manager.installSelectedModel(settings: settings)

        XCTAssertEqual(manager.model, .qwen3ASR06B4bit)
        XCTAssertEqual(settings.localMLXInstalledModels, ["Qwen3-ASR-0.6B-4bit"])
        XCTAssertTrue(manager.statusMessage?.contains("Qwen3-ASR-0.6B-4bit") == true)
    }

    func testConcurrentInstallIsIgnoredAndCannotResetProgress() async {
        var manager: LocalModelManager!
        var calls = 0
        manager = LocalModelManager(installer: { _, report in
            calls += 1
            guard calls == 1 else { return }
            report(.downloading(0.42))
            self.settings.localMLXModel = .qwen3ASR17B
            await manager.installSelectedModel(settings: self.settings)
            XCTAssertEqual(manager.phase, .downloading(0.42))
            XCTAssertEqual(manager.model, .qwen3ASR06B4bit)
        })

        await manager.installSelectedModel(settings: settings)

        XCTAssertEqual(calls, 1)
        XCTAssertEqual(settings.localMLXInstalledModels, ["Qwen3-ASR-0.6B-4bit"])
    }

    func testFailureClearsProgressAndRetryClearsError() async {
        var manager: LocalModelManager!
        var attempts = 0
        manager = LocalModelManager(installer: { _, report in
            attempts += 1
            XCTAssertNil(manager.lastError)
            XCTAssertEqual(manager.phase, .preparing)
            report(.downloading(0.8))
            if attempts == 1 {
                throw LocalModelInstallError.generic("Network unavailable")
            }
            report(.loading)
        })

        await manager.installSelectedModel(settings: settings)

        XCTAssertFalse(manager.isInstalling)
        XCTAssertNil(manager.phase)
        XCTAssertNil(manager.statusMessage)
        XCTAssertTrue(manager.lastError?.contains("Network unavailable") == true)
        XCTAssertTrue(settings.localMLXInstalledModels.isEmpty)

        await manager.installSelectedModel(settings: settings)

        XCTAssertNil(manager.lastError)
        XCTAssertFalse(manager.isInstalling)
        XCTAssertEqual(settings.localMLXInstalledModels, ["Qwen3-ASR-0.6B-4bit"])
    }

    func testLoadingFailureDoesNotMarkDownloadedModelInstalled() async {
        let manager = LocalModelManager(installer: { _, report in
            report(.downloading(1))
            report(.loading)
            throw LocalModelInstallError.generic("Invalid model weights")
        })

        await manager.installSelectedModel(settings: settings)

        XCTAssertTrue(settings.localMLXInstalledModels.isEmpty)
        XCTAssertNotNil(manager.lastError)
        XCTAssertFalse(manager.isInstalling)
    }

    func testUnknownAndInvalidProgressNeverProducesInvalidPercentage() async {
        var manager: LocalModelManager!
        manager = LocalModelManager(installer: { _, report in
            for value: Double? in [nil, .nan, .infinity] {
                report(.downloading(value))
                XCTAssertEqual(manager.phase, .downloading(nil))
            }
            report(.downloading(-0.1))
            XCTAssertEqual(manager.phase, .downloading(0))
            report(.downloading(1.1))
            XCTAssertEqual(manager.phase, .downloading(1))
        })

        await manager.installSelectedModel(settings: settings)
    }

    func testSnapshotProgressIncludesPartiallyDownloadedWeightedChildren() {
        let snapshot = Progress(totalUnitCount: 1_000)
        let weights = Progress(totalUnitCount: 900, parent: snapshot, pendingUnitCount: 900)
        weights.completedUnitCount = 450

        // Parent completedUnitCount is still zero while the large child is in flight.
        XCTAssertEqual(LocalModelInstallPhase.downloading(snapshot), .downloading(0.45))
        XCTAssertEqual(LocalModelInstallPhase.downloading(Progress(totalUnitCount: 0)), .downloading(nil))
    }

    func testLateCallbackCannotOverwriteCompletedOrNewInstallation() async {
        var previousReport: (@MainActor @Sendable (LocalModelInstallPhase) -> Void)?
        var manager: LocalModelManager!
        manager = LocalModelManager(installer: { _, report in
            if let previousReport {
                report(.downloading(0.25))
                previousReport(.downloading(0.9))
                XCTAssertEqual(manager.phase, .downloading(0.25))
            } else {
                previousReport = report
            }
        })

        await manager.installSelectedModel(settings: settings)
        previousReport?(.downloading(0.9))
        XCTAssertNil(manager.phase)
        XCTAssertFalse(manager.isInstalling)

        settings.localMLXModel = .qwen3ASR17B
        await manager.installSelectedModel(settings: settings)
        XCTAssertEqual(settings.localMLXInstalledModels, ["Qwen3-ASR-0.6B-4bit", "Qwen3-ASR-1.7B"])
    }
}
#endif
