#if canImport(Airtype)
import XCTest
@testable import Airtype

@MainActor
final class AppUpdaterTests: XCTestCase {
    func testSharedUpdaterHasApplicationLifetimeIdentity() {
        XCTAssertTrue(AppUpdater.shared === AppUpdater.shared)
    }

    func testCheckForUpdatesRunsWhenUpdaterIsReady() {
        var checkCount = 0
        let coordinator = UpdateCheckCoordinator(
            canCheckForUpdates: { true },
            performCheck: { checkCount += 1 }
        )

        XCTAssertTrue(coordinator.checkForUpdates())
        XCTAssertEqual(checkCount, 1)
    }

    func testCheckForUpdatesIsIgnoredWhileUpdaterIsBusy() {
        var checkCount = 0
        let coordinator = UpdateCheckCoordinator(
            canCheckForUpdates: { false },
            performCheck: { checkCount += 1 }
        )

        XCTAssertFalse(coordinator.checkForUpdates())
        XCTAssertEqual(checkCount, 0)
    }
}
#endif
