import Foundation
import Observation

/// Local prerequisites only; this does not validate a provider's credentials or network.
public enum DashboardReadiness: Equatable, Sendable {
    case providerRequired
    case microphoneRequired
    case accessibilityRequired
    case ready

    public init(isConfigured: Bool, hasMicrophone: Bool, hasAccessibility: Bool) {
        if !isConfigured { self = .providerRequired }
        else if !hasMicrophone { self = .microphoneRequired }
        else if !hasAccessibility { self = .accessibilityRequired }
        else { self = .ready }
    }

    public var title: String {
        switch self {
        case .providerRequired: "Setup required"
        case .microphoneRequired: "Microphone access required"
        case .accessibilityRequired: "Text insertion access required"
        case .ready: "Ready"
        }
    }

    public var guidance: String {
        switch self {
        case .providerRequired: "Choose a provider and complete its setup to start transcribing."
        case .microphoneRequired: "Allow microphone access so Airtype can record your voice."
        case .accessibilityRequired: "Allow Accessibility access so Airtype can insert text into other apps."
        case .ready: ""
        }
    }

    public var actionTitle: String {
        switch self {
        case .providerRequired: "Complete setup"
        case .microphoneRequired: "Allow microphone"
        case .accessibilityRequired: "Open Accessibility Settings"
        case .ready: ""
        }
    }
}

public enum DashboardDestination: String, CaseIterable, Identifiable, Sendable {
    case home
    case history
    case analytics
    case vocabulary
    case settings

    public var id: Self { self }

    public var title: String {
        switch self {
        case .home: "Home"
        case .history: "History"
        case .analytics: "Analytics"
        case .vocabulary: "Vocabulary"
        case .settings: "Settings"
        }
    }

    public var systemImage: String {
        switch self {
        case .home: "house"
        case .history: "clock.arrow.circlepath"
        case .analytics: "chart.xyaxis.line"
        case .vocabulary: "text.book.closed"
        case .settings: "gearshape"
        }
    }
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
