import Combine
import Foundation
import Sparkle

@MainActor
final class UpdateCheckCoordinator {
    private let canCheckForUpdates: () -> Bool
    private let performCheck: () -> Void

    init(
        canCheckForUpdates: @escaping () -> Bool,
        performCheck: @escaping () -> Void
    ) {
        self.canCheckForUpdates = canCheckForUpdates
        self.performCheck = performCheck
    }

    @discardableResult
    func checkForUpdates() -> Bool {
        guard canCheckForUpdates() else { return false }
        performCheck()
        return true
    }
}

@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    @Published private(set) var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController
    private lazy var checkCoordinator = UpdateCheckCoordinator(
        canCheckForUpdates: { [weak self] in self?.canCheckForUpdates == true },
        performCheck: { [weak self] in self?.updaterController.checkForUpdates(nil) }
    )

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        updaterController.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        checkCoordinator.checkForUpdates()
    }
}
