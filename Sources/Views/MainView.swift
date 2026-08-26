import SwiftUI
import AVFoundation
import ApplicationServices
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
    @State private var hasMicrophone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var hasAccessibility = AXIsProcessTrusted()

    private var readiness: DashboardReadiness {
        DashboardReadiness(isConfigured: settings.isConfigured,
                           hasMicrophone: hasMicrophone,
                           hasAccessibility: hasAccessibility)
    }

    var body: some View {
        HStack(spacing: 0) {
            DashboardSidebar(
                selection: $dashboardModel.destination,
                readiness: readiness
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
        .onAppear(perform: refreshPermissions)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
    }

    private func refreshPermissions() {
        hasMicrophone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        hasAccessibility = AXIsProcessTrusted()
    }

    private func resolveReadiness() {
        switch readiness {
        case .providerRequired:
            dashboardModel.showSettings()
        case .microphoneRequired:
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                Task { @MainActor in
                    _ = await AVCaptureDevice.requestAccess(for: .audio)
                    refreshPermissions()
                }
            } else {
                openPrivacySettings("Privacy_Microphone")
            }
        case .accessibilityRequired:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            openPrivacySettings("Privacy_Accessibility")
        case .ready:
            break
        }
    }

    private func openPrivacySettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    @ViewBuilder
    private var destinationView: some View {
        switch dashboardModel.destination {
        case .home:
            HomeView(
                settings: settings,
                historyEntries: historyModel.entries,
                readiness: readiness,
                onCompleteSetup: resolveReadiness,
                onShowHistory: { dashboardModel.destination = .history }
            )
        case .history:
            TranscriptionHistoryView(model: historyModel)
        case .vocabulary:
            VocabularyView(model: vocabularyModel)
        case .settings:
            AirtypeSettingsView(
                settings: settings,
                hotkeyManager: hotkeyManager,
                readiness: readiness,
                hasAccessibility: hasAccessibility
            )
        }
    }
}
