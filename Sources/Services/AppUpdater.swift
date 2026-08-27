import Combine
import Foundation
import Sparkle

enum AppUpdaterConfiguration {
    static func shouldStartUpdater(
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> Bool {
        guard let feed = infoDictionary["SUFeedURL"] as? String,
              let url = URL(string: feed),
              url.scheme?.lowercased() == "https",
              url.host != nil else { return false }
        return true
    }
}

@MainActor
final class UpdateCheckCoordinator {
    private let canCheckForUpdates: () -> Bool
    private let performCheck: () -> Void
    private let automaticallyChecksForUpdates: () -> Bool
    private let performBackgroundCheck: () -> Void

    init(
        canCheckForUpdates: @escaping () -> Bool,
        performCheck: @escaping () -> Void,
        automaticallyChecksForUpdates: @escaping () -> Bool = { false },
        performBackgroundCheck: @escaping () -> Void = {}
    ) {
        self.canCheckForUpdates = canCheckForUpdates
        self.performCheck = performCheck
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        self.performBackgroundCheck = performBackgroundCheck
    }

    @discardableResult
    func checkForUpdates() -> Bool {
        guard canCheckForUpdates() else { return false }
        performCheck()
        return true
    }

    @discardableResult
    func checkForUpdatesInBackgroundAtLaunch() -> Bool {
        guard automaticallyChecksForUpdates() else { return false }
        performBackgroundCheck()
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
        performCheck: { [weak self] in self?.updaterController.checkForUpdates(nil) },
        automaticallyChecksForUpdates: { [weak self] in
            self?.updaterController.updater.automaticallyChecksForUpdates == true
        },
        performBackgroundCheck: { [weak self] in
            self?.updaterController.updater.checkForUpdatesInBackground()
        }
    )

    private init() {
        let shouldStartUpdater = AppUpdaterConfiguration.shouldStartUpdater()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: shouldStartUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        updaterController.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)

        if shouldStartUpdater {
            checkCoordinator.checkForUpdatesInBackgroundAtLaunch()
        }
    }

    func checkForUpdates() {
        checkCoordinator.checkForUpdates()
    }
}
