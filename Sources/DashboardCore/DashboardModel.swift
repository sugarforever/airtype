import Foundation
import Observation
#if SWIFT_PACKAGE
import CorrectionLearningCore
#endif

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

@MainActor
@Observable
@available(macOS 14.0, *)
public final class HomePageModel {
    public private(set) var todayLearnedCorrectionCount = 0

    @ObservationIgnored private let learningService: CorrectionLearningService?

    public init(learningService: CorrectionLearningService?) {
        self.learningService = learningService
    }

    public func observeCorrectionUpdates() async {
        guard let learningService else {
            publishTodayCount(0)
            return
        }

        for await snapshot in await learningService.updates() {
            guard !Task.isCancelled else { return }
            let todayCount = snapshot.samples.count {
                Calendar.current.isDateInToday($0.lastCorrectedAt)
            }
            publishTodayCount(todayCount)
        }
    }

    private func publishTodayCount(_ count: Int) {
        if todayLearnedCorrectionCount != count {
            todayLearnedCorrectionCount = count
        }
    }
}
