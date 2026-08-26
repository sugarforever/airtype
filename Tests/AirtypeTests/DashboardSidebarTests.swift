#if canImport(Airtype)
import AppKit
import SwiftUI
import XCTest
import DashboardCore
@testable import Airtype

final class DashboardSidebarTests: XCTestCase {
    @MainActor
    func testNavigationRespondsAcrossTheEntireRow() async throws {
        _ = NSApplication.shared
        let model = DashboardModel(destination: .settings)
        var clickedDestination: DashboardDestination?
        let hostingView = NSHostingView(rootView: DashboardSidebar(
            selection: Binding(get: { model.destination }, set: {
                clickedDestination = $0
                model.destination = $0
            }),
            readiness: .ready
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 168, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.orderFront(nil)
        defer { window.close() }
        hostingView.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        // Scan vertically so the regression does not depend on font metrics or row positions.
        // These columns cover the leading padding, icons, text, and trailing whitespace
        // in the dashboard's 168-point sidebar (with 10-point outer margins).
        for x in [CGFloat(12), 26, 60, 156] {
            var reached = Set<DashboardDestination>()
            for y in stride(from: 0, to: 400, by: 4) {
                clickedDestination = nil
                let point = hostingView.convert(NSPoint(x: x, y: CGFloat(y)), to: nil)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    let event = try XCTUnwrap(NSEvent.mouseEvent(
                        with: type, location: point, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil,
                        eventNumber: 0, clickCount: 1, pressure: 1
                    ))
                    window.sendEvent(event)
                }
                try await Task.sleep(for: .milliseconds(5))
                if let clickedDestination { reached.insert(clickedDestination) }
            }
            XCTAssertEqual(reached, Set(DashboardDestination.allCases),
                           "Every navigation item must be clickable at x=\(x)")
        }
    }
}
#endif
