import SwiftUI
#if SWIFT_PACKAGE
import DashboardCore
#endif

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
    @Bindable var dashboardModel: DashboardModel
    let historyModel: HistoryPageModel
    let vocabularyModel: VocabularyPageModel

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
            TranscriptionHistoryView(model: historyModel)
        case .vocabulary:
            VocabularyView(model: vocabularyModel)
        case .settings:
            AirtypeSettingsView(
                settings: settings,
                hotkeyManager: hotkeyManager
            )
        }
    }
}
