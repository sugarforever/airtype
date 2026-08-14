import XCTest
@testable import DashboardCore

@MainActor
@available(macOS 14.0, *)
final class DashboardModelTests: XCTestCase {
    func testNavigationDefaultsToHome() {
        let model = DashboardModel()

        XCTAssertEqual(model.destination, .home)
    }

    func testSettingsEntryPointSelectsSettingsAfterAnotherDestination() {
        let model = DashboardModel(destination: .history)

        model.showSettings()

        XCTAssertEqual(model.destination, .settings)
    }
}
