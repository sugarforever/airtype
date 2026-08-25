import Foundation
import Observation

public enum DashboardDestination: String, CaseIterable, Identifiable, Sendable {
    case home
    case history
    case vocabulary
    case settings

    public var id: Self { self }
}

@MainActor
@Observable
@available(macOS 14.0, *)
public final class DashboardModel {
    public var destination: DashboardDestination

    public init(destination: DashboardDestination = .home) {
        self.destination = destination
    }

    public func showSettings() {
        if destination != .settings {
            destination = .settings
        }
    }
}
