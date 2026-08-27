import XCTest
@testable import DashboardCore

@MainActor
@available(macOS 14.0, *)
final class DashboardModelTests: XCTestCase {
    func testReadinessRequiresProviderAndBothPermissions() {
        for provider in [false, true] {
            for microphone in [false, true] {
                for accessibility in [false, true] {
                    let readiness = DashboardReadiness(
                        isConfigured: provider,
                        hasMicrophone: microphone,
                        hasAccessibility: accessibility
                    )
                    XCTAssertEqual(readiness == .ready, provider && microphone && accessibility)
                }
            }
        }
    }

    func testReadinessGuidesSetupBeforePermissions() {
        XCTAssertEqual(DashboardReadiness(isConfigured: false, hasMicrophone: false, hasAccessibility: false), .providerRequired)
        XCTAssertEqual(DashboardReadiness(isConfigured: true, hasMicrophone: false, hasAccessibility: false), .microphoneRequired)
        XCTAssertEqual(DashboardReadiness(isConfigured: true, hasMicrophone: true, hasAccessibility: false), .accessibilityRequired)
    }

    func testNavigationDefaultsToHome() {
        let model = DashboardModel()

        XCTAssertEqual(model.destination, .home)
    }

    func testSettingsEntryPointSelectsSettingsAfterAnotherDestination() {
        let model = DashboardModel(destination: .history)

        model.showSettings()

        XCTAssertEqual(model.destination, .settings)
    }

    func testAnalyticsIsAFirstClassDashboardDestination() {
        XCTAssertTrue(DashboardDestination.allCases.contains(.analytics))
        XCTAssertEqual(DashboardDestination.analytics.title, "Analytics")
        XCTAssertEqual(DashboardDestination.analytics.systemImage, "chart.xyaxis.line")
    }
}
