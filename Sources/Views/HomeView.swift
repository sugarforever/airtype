import SwiftUI

struct HomeView: View {
    @ObservedObject var settings: Settings
    let historyEntries: [TranscriptionHistory.Entry]

    @State private var learnedCorrectionCount = 0

    private var recentEntries: [TranscriptionHistory.Entry] {
        Array(historyEntries.prefix(2))
    }

    private var todayTranscriptionCount: Int {
        historyEntries.count { Calendar.current.isDateInToday($0.date) }
    }

    private var primaryShortcut: String {
        Settings.shortcutDisplayString(
            keyCode: settings.pushToTalkKeyCode,
            modifiers: settings.pushToTalkModifiers
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pageHeader
                readyCard
                metrics
                recentSection
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task {
            learnedCorrectionCount = await Self.loadTodayLearnedCorrectionCount()
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Home")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Airtype at a glance")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var readyCard: some View {
        HStack(spacing: 14) {
            Image(systemName: settings.isConfigured ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(settings.isConfigured ? Theme.statusGreen : Theme.statusOrange)

            VStack(alignment: .leading, spacing: 4) {
                Text(settings.isConfigured ? "Ready" : "Setup required")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(settings.isConfigured ? "Hold \(primaryShortcut) to record, then release to transcribe." : "Complete your provider setup in Settings to start transcribing.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Text(primaryShortcut)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.bg, in: .rect(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Theme.border, lineWidth: 1)
                }
        }
        .padding(18)
        .background(Theme.cardBg, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.border, lineWidth: 1)
        }
    }

    private var metrics: some View {
        HStack(spacing: 12) {
            HomeMetricCard(
                title: "Transcriptions today",
                value: todayTranscriptionCount,
                systemImage: "waveform"
            )
            HomeMetricCard(
                title: "Learned corrections today",
                value: learnedCorrectionCount,
                systemImage: "wand.and.stars"
            )
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent transcriptions")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            if recentEntries.isEmpty {
                Text("Your latest transcriptions will appear here.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                    .background(Theme.cardBg, in: .rect(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.border, lineWidth: 1)
                    }
            } else {
                ForEach(recentEntries) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.text)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textPrimary)
                            .textSelection(.enabled)
                        Text(entry.date, style: .relative)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.cardBg, in: .rect(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.border, lineWidth: 1)
                    }
                }
            }
        }
    }

    nonisolated private static func loadTodayLearnedCorrectionCount() async -> Int {
        guard let service = try? CorrectionLearningService.makeDefault() else {
            return 0
        }
        let samples = await service.samples()
        return samples.count { Calendar.current.isDateInToday($0.lastCorrectedAt) }
    }
}

private struct HomeMetricCard: View {
    let title: String
    let value: Int
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(Theme.brand)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(value, format: .number)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.cardBg, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.border, lineWidth: 1)
        }
    }
}
