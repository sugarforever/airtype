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

    func testModelCatalogMapsEverySupportedVariantToItsRepository() {
        let expected: [(LocalMLXModel, String)] = [
            (.qwen3ASR06B4bit, "Qwen3-ASR-0.6B-4bit"),
            (.qwen3ASR06B5bit, "Qwen3-ASR-0.6B-5bit"),
            (.qwen3ASR06B6bit, "Qwen3-ASR-0.6B-6bit"),
            (.qwen3ASR06B8bit, "Qwen3-ASR-0.6B-8bit"),
            (.qwen3ASR06Bbf16, "Qwen3-ASR-0.6B-bf16"),
            (.qwen3ASR17B4bit, "Qwen3-ASR-1.7B-4bit"),
            (.qwen3ASR17B5bit, "Qwen3-ASR-1.7B-5bit"),
            (.qwen3ASR17B6bit, "Qwen3-ASR-1.7B-6bit"),
            (.qwen3ASR17B8bit, "Qwen3-ASR-1.7B-8bit"),
            (.qwen3ASR17Bbf16, "Qwen3-ASR-1.7B-bf16")
        ]

        XCTAssertEqual(LocalMLXModel.allCases.map(\.rawValue), expected.map(\.1))
        for (model, name) in expected {
            XCTAssertEqual(model.repoID, "mlx-community/\(name)")
            XCTAssertEqual(
                model.defaultDownloadURL,
                "https://huggingface.co/mlx-community/\(name)/resolve/main/model.safetensors"
            )
        }
    }

    func testLegacy17BSelectionAndInstalledRecordMigrateToExplicit4bitIdentity() throws {
        defaults.set("Qwen3-ASR-1.7B", forKey: "local_mlx_model")
        defaults.set(["Qwen3-ASR-0.6B-4bit", "Qwen3-ASR-1.7B"], forKey: "local_mlx_installed_models")
        defaults.set(["Qwen3-ASR-1.7B": "https://example.com/model.safetensors"], forKey: "local_mlx_download_urls")
        defaults.set(["Qwen3-ASR-1.7B": "abc123"], forKey: "local_mlx_checksums")

        let migrated = Settings(defaults: defaults)

        XCTAssertEqual(migrated.localMLXModel, .qwen3ASR17B4bit)
        XCTAssertEqual(
            migrated.localMLXInstalledModels,
            ["Qwen3-ASR-0.6B-4bit", "Qwen3-ASR-1.7B-4bit"]
        )
        XCTAssertEqual(migrated.currentLocalModelDownloadURLOverride, "https://example.com/model.safetensors")
        XCTAssertEqual(migrated.currentLocalModelChecksum, "abc123")
    }

    func testInstallsSelectedVariantRepository() async {
        settings.localMLXModel = .qwen3ASR17Bbf16
        let manager = LocalModelManager(installer: { modelID, report in
            XCTAssertEqual(modelID, "mlx-community/Qwen3-ASR-1.7B-bf16")
            report(.loading)
        })

        await manager.installSelectedModel(settings: settings)

        XCTAssertEqual(settings.localMLXInstalledModels, ["Qwen3-ASR-1.7B-bf16"])
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
            self.settings.localMLXModel = .qwen3ASR17B4bit
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
            self.settings.localMLXModel = .qwen3ASR17B4bit
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

        settings.localMLXModel = .qwen3ASR17B4bit
        await manager.installSelectedModel(settings: settings)
        XCTAssertEqual(settings.localMLXInstalledModels, ["Qwen3-ASR-0.6B-4bit", "Qwen3-ASR-1.7B-4bit"])
    }

    func testRemovalClearsModelAndHubCacheWithoutTouchingOtherModels() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = [
            "mlx-audio/mlx-community_Qwen3-ASR-0.6B-4bit/model.safetensors",
            "models--mlx-community--Qwen3-ASR-0.6B-4bit/blobs/weights",
            ".metadata/models--mlx-community--Qwen3-ASR-0.6B-4bit/file.json",
            "mlx-audio/mlx-community_Qwen3-ASR-1.7B-4bit/model.safetensors",
            "models--mlx-community--Qwen3-ASR-1.7B-4bit/blobs/weights"
        ]
        for path in paths {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: file)
        }

        try MLXAudioRunner.removeModel(modelID: "mlx-community/Qwen3-ASR-0.6B-4bit", cacheDirectory: root)

        for path in paths.prefix(3) {
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
        }
        for path in paths.suffix(2) {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
        }
        // Removing an already absent model is safe.
        XCTAssertNoThrow(try MLXAudioRunner.removeModel(modelID: "mlx-community/Qwen3-ASR-0.6B-4bit", cacheDirectory: root))
    }

    func testRemovalFailureKeepsInstalledRecordAndReportsError() {
        let installedSettings = InstalledModelSettings(defaults: defaults)
        installedSettings.localMLXModel = .qwen3ASR06B4bit
        installedSettings.localMLXInstalledModels = ["Qwen3-ASR-0.6B-4bit"]
        let manager = LocalModelManager(remover: { _ in
            throw CocoaError(.fileWriteNoPermission)
        })

        manager.removeSelectedModel(settings: installedSettings)

        XCTAssertEqual(installedSettings.localMLXInstalledModels, ["Qwen3-ASR-0.6B-4bit"])
        XCTAssertNotNil(manager.lastError)
        XCTAssertNil(manager.statusMessage)
        XCTAssertFalse(manager.isRemoving)
    }

    func testFilesystemRemovalErrorIsNotSwallowed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repository = root.appendingPathComponent("models--mlx-community--Qwen3-ASR-0.6B-4bit")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)

        XCTAssertThrowsError(try MLXAudioRunner.removeModel(
            modelID: "mlx-community/Qwen3-ASR-0.6B-4bit", cacheDirectory: root
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.path))
    }

    func testSuccessfulRemovalClearsInstalledRecord() {
        let installedSettings = InstalledModelSettings(defaults: defaults)
        installedSettings.localMLXModel = .qwen3ASR06B4bit
        installedSettings.localMLXInstalledModels = ["Qwen3-ASR-0.6B-4bit"]
        let manager = LocalModelManager(remover: { modelID in
            XCTAssertEqual(modelID, "mlx-community/Qwen3-ASR-0.6B-4bit")
        })

        manager.removeSelectedModel(settings: installedSettings)

        XCTAssertTrue(installedSettings.localMLXInstalledModels.isEmpty)
        XCTAssertNil(manager.lastError)
        XCTAssertNotNil(manager.statusMessage)
    }
}

private final class InstalledModelSettings: Settings {
    override var selectedLocalModelInstalled: Bool {
        localMLXInstalledModels.contains(localMLXModel.rawValue)
    }
}
#endif
