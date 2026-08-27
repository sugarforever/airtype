#if canImport(Airtype)
import XCTest
@testable import Airtype

@MainActor
final class AppUpdaterTests: XCTestCase {
    func testUpdaterDoesNotStartWithoutAFeedURL() {
        XCTAssertFalse(AppUpdaterConfiguration.shouldStartUpdater(infoDictionary: [:]))
    }

    func testUpdaterStartsWithAValidHTTPSFeedURL() {
        XCTAssertTrue(AppUpdaterConfiguration.shouldStartUpdater(infoDictionary: [
            "SUFeedURL": "https://example.com/appcast.xml"
        ]))
    }

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

    func testLaunchChecksForUpdatesInBackgroundWhenAutomaticChecksAreEnabled() {
        var backgroundCheckCount = 0
        let coordinator = UpdateCheckCoordinator(
            canCheckForUpdates: { true },
            performCheck: {},
            automaticallyChecksForUpdates: { true },
            performBackgroundCheck: { backgroundCheckCount += 1 }
        )

        XCTAssertTrue(coordinator.checkForUpdatesInBackgroundAtLaunch())
        XCTAssertEqual(backgroundCheckCount, 1)
    }

    func testLaunchDoesNotCheckForUpdatesWhenAutomaticChecksAreDisabled() {
        var backgroundCheckCount = 0
        let coordinator = UpdateCheckCoordinator(
            canCheckForUpdates: { true },
            performCheck: {},
            automaticallyChecksForUpdates: { false },
            performBackgroundCheck: { backgroundCheckCount += 1 }
        )

        XCTAssertFalse(coordinator.checkForUpdatesInBackgroundAtLaunch())
        XCTAssertEqual(backgroundCheckCount, 0)
    }
}
#endif
