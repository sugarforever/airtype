import SwiftUI

// MARK: - Design Tokens

enum Theme {
    static let bg = Color(NSColor.windowBackgroundColor)
    static let cardBg = Color(NSColor.controlBackgroundColor)
    static let border = Color(NSColor.separatorColor)
    static let textPrimary = Color(NSColor.labelColor)
    static let textSecondary = Color(NSColor.secondaryLabelColor)
    static let textTertiary = Color(NSColor.tertiaryLabelColor)
    static let brand = Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255)
    static let statusGreen = brand
    static let statusOrange = Color(red: 1.0, green: 0.624, blue: 0.039)
    static let statusRed = Color(red: 1.0, green: 0.271, blue: 0.227)
}

struct MainView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var hotkeyManager: HotkeyManager
    @State private var dashboardModel = DashboardModel()
    @State private var historyModel = HistoryPageModel()

    var body: some View {
        HStack(spacing: 0) {
            DashboardSidebar(
                selection: $dashboardModel.destination,
                isConfigured: settings.isConfigured
            )
            .frame(width: 168)

            Divider()
                .overlay(Theme.border)

            destinationView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg)
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(Theme.bg)
        .tint(Theme.brand)
    }

    @ViewBuilder
    private var destinationView: some View {
        switch dashboardModel.destination {
        case .home:
            HomeView(
                settings: settings,
                historyEntries: historyModel.entries
            )
        case .history:
            TranscriptionHistoryView()
        case .vocabulary:
            DashboardPlaceholderView(
                title: "Vocabulary",
                message: "Your proper nouns and learned corrections will appear here.",
                systemImage: "text.book.closed"
            )
        case .settings:
            AirtypeSettingsView(
                settings: settings,
                hotkeyManager: hotkeyManager
            )
        }
    }
}

private struct DashboardPlaceholderView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundStyle(Theme.textSecondary)
            Text(title)
                .font(.title2)
                .bold()
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
