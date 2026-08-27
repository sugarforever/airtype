#if canImport(Airtype)
import XCTest
@testable import Airtype

@MainActor
final class WindowActivationCoordinatorTests: XCTestCase {
    func testWindowPresentationMakesApplicationRegularBeforeOrderingAndActivating() {
        var events: [String] = []
        let coordinator = WindowActivationCoordinator(
            makeRegular: { events.append("regular") },
            orderWindowFront: { events.append("window") },
            activateApplication: { events.append("activate") }
        )

        coordinator.present()

        XCTAssertEqual(events, ["regular", "window", "activate"])
    }

    func testReopenRoutesToSetupUntilSetupIsComplete() {
        XCTAssertEqual(
            ApplicationReopenRouter.destination(
                hasVisibleWindows: false,
                hasCompletedSetup: false
            ),
            .setupWizard
        )
        XCTAssertEqual(
            ApplicationReopenRouter.destination(
                hasVisibleWindows: false,
                hasCompletedSetup: true
            ),
            .mainWindow
        )
        XCTAssertNil(
            ApplicationReopenRouter.destination(
                hasVisibleWindows: true,
                hasCompletedSetup: false
            )
        )
    }
}
#endif
