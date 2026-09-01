import SwiftUI
#if SWIFT_PACKAGE
import DashboardCore
#endif

struct AnalyticsView: View {
    @Bindable var model: AnalyticsPageModel

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 280), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if model.summary.callCount == 0 {
                    emptyState
                } else {
                    overview
                    modelComparison
                    recentRequests
                }

                openRouterUsage
                privacyNote
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .task {
            await model.refreshOpenRouterUsage()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Analytics")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Transcription reliability, speed, and provider usage")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("All recorded requests")
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                MetricCard(title: "Calls", value: model.summary.callCount.formatted(), detail: "Transcription attempts")
                MetricCard(
                    title: "Success rate",
                    value: model.summary.successRate.formatted(.percent.precision(.fractionLength(1))),
                    detail: "\(model.summary.successCount) successful"
                )
                MetricCard(
                    title: "Average latency",
                    value: Self.duration(model.summary.averageLatencyMilliseconds),
                    detail: "P95 \(Self.duration(model.summary.p95LatencyMilliseconds))"
                )
                MetricCard(
                    title: "Audio processed",
                    value: model.summary.hasAudioDurationData ? Self.audioDuration(model.summary.audioDurationSeconds) : "—",
                    detail: model.summary.hasAudioDurationData ? "Provider-reported when available" : "Audio duration unavailable"
                )
                MetricCard(
                    title: "Tokens",
                    value: model.summary.hasTokenData ? model.summary.totalTokens.formatted() : "—",
                    detail: model.summary.hasTokenData ? "OpenRouter input + output" : "Not reported by providers"
                )
                MetricCard(
                    title: "API cost",
                    value: model.summary.hasCostData ? Self.currency(model.summary.costUSD) : "—",
                    detail: model.summary.hasCostData ? "OpenRouter billed cost" : "No billed cost reported"
                )
            }
        }
    }

    private var modelComparison: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Provider and model comparison")
            VStack(spacing: 0) {
                ForEach(model.summary.modelSummaries) { item in
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.model)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Text(item.provider)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        compactValue(item.callCount.formatted(), label: "calls")
                        compactValue(item.successRate.formatted(.percent.precision(.fractionLength(0))), label: "success")
                        compactValue(Self.duration(item.averageLatencyMilliseconds), label: "avg")
                        compactValue(item.totalTokens?.formatted() ?? "—", label: "tokens")
                        compactValue(item.costUSD.map(Self.currency) ?? "—", label: "cost")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)

                    if item.id != model.summary.modelSummaries.last?.id {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private var recentRequests: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Recent requests")
            VStack(spacing: 0) {
                ForEach(model.recentRecords) { record in
                    HStack(spacing: 12) {
                        Image(systemName: record.outcome == .success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(record.outcome == .success ? Theme.statusGreen : Theme.statusRed)
                            .accessibilityLabel(record.outcome == .success ? "Succeeded" : "Failed")

                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.model)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Text("\(record.provider) · \(record.startedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        compactValue(Self.duration(record.latencyMilliseconds), label: "latency")
                        compactValue(record.totalTokens?.formatted() ?? "—", label: "tokens")
                        compactValue(record.costUSD.map(Self.currency) ?? "—", label: "cost")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    if record.id != model.recentRecords.last?.id {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private var openRouterUsage: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("OpenRouter key usage")
                Spacer()
                Button {
                    Task { await model.refreshOpenRouterUsage() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.isRefreshingOpenRouterUsage)
            }

            Group {
                if let usage = model.openRouterUsage {
                    HStack(spacing: 24) {
                        compactValue(Self.currency(usage.daily), label: "today")
                        compactValue(Self.currency(usage.weekly), label: "this week")
                        compactValue(Self.currency(usage.monthly), label: "this month")
                        compactValue(Self.currency(usage.total), label: "key total")
                        if let remaining = usage.limitRemaining {
                            compactValue(Self.currency(remaining), label: "limit remaining")
                        }
                        Spacer()
                    }
                } else if model.isRefreshingOpenRouterUsage {
                    ProgressView("Loading OpenRouter usage…")
                        .controlSize(.small)
                } else {
                    Text(model.openRouterUsageError ?? "OpenRouter usage is available after configuring an API key.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No analytics yet", systemImage: "chart.xyaxis.line")
        } description: {
            Text("Metrics will appear after your next transcription. Historical requests cannot be backfilled.")
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private var privacyNote: some View {
        Label("Stored locally. Analytics never includes audio, transcription text, prompts, vocabulary, or API keys.", systemImage: "lock.shield")
            .font(.system(size: 11))
            .foregroundStyle(Theme.textTertiary)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
    }

    private func compactValue(_ value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(minWidth: 54, alignment: .trailing)
    }

    private static func duration(_ milliseconds: Double) -> String {
        if milliseconds >= 1_000 {
            return (milliseconds / 1_000).formatted(.number.precision(.fractionLength(1))) + "s"
        }
        return milliseconds.formatted(.number.precision(.fractionLength(0))) + "ms"
    }

    private static func audioDuration(_ seconds: Double) -> String {
        if seconds >= 60 {
            return (seconds / 60).formatted(.number.precision(.fractionLength(1))) + " min"
        }
        return seconds.formatted(.number.precision(.fractionLength(1))) + "s"
    }

    private static func currency(_ value: Double) -> String {
        let fractionLength = value > 0 && value < 0.01 ? 6 : 2
        return "$" + value.formatted(.number.precision(.fractionLength(fractionLength)))
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(Theme.cardBg, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.border, lineWidth: 1)
        }
    }
}
