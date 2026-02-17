import ApplicationServices
import HotKey
import SwiftUI

// MARK: - Design Tokens

enum Theme {
    static let bg = Color(NSColor.windowBackgroundColor)
    static let cardBg = Color(NSColor.controlBackgroundColor)
    static let border = Color(NSColor.separatorColor)
    static let textPrimary = Color(NSColor.labelColor)
    static let textSecondary = Color(NSColor.secondaryLabelColor)
    static let textTertiary = Color(NSColor.tertiaryLabelColor)
    static let brand = Color(red: 52/255, green: 211/255, blue: 153/255)     // #34D399
    static let statusGreen = brand
    static let statusOrange = Color(red: 1.0, green: 0.624, blue: 0.039)    // #FF9F0A
    static let statusRed = Color(red: 1.0, green: 0.271, blue: 0.227)       // #FF453A
}

// MARK: - Main View

struct MainView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var hotkeyManager: HotkeyManager
    @State private var hasAccessibility = AXIsProcessTrusted()
    @StateObject private var updateChecker = UpdateChecker()

    var body: some View {
        VStack(spacing: 0) {
            dashboardHeader
            Divider().overlay(Theme.border)
            ScrollView {
                VStack(spacing: 16) {
                    if updateChecker.updateAvailable {
                        updateBanner
                    }
                    if !hasAccessibility {
                        accessibilityBanner
                    }
                    if let error = settings.configurationError {
                        statusBanner(message: error)
                    }
                    voiceInputSection
                    enhancementSection
                    floatingWindowSection
                    shortcutsSection
                    permissionsSection
                }
                .padding(24)
            }
        }
        .frame(width: 520, height: 700)
        .background(Theme.bg)
        .tint(Theme.brand)
        .onAppear { updateChecker.check() }
    }

    // MARK: - Header

    private var dashboardHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(settings.isConfigured ? Theme.statusGreen : Theme.statusOrange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Airtype")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 4) {
                    Circle()
                        .fill(settings.isConfigured ? Theme.statusGreen : Theme.statusOrange)
                        .frame(width: 6, height: 6)
                    Text(settings.isConfigured ? "Ready" : "Setup required")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Status Banner

    private func statusBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.statusOrange)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
        }
        .padding(12)
        .background(Theme.statusOrange.opacity(0.1))
        .clipShape(.rect(cornerRadius: 8))
    }

    // MARK: - Accessibility Banner

    private var accessibilityBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.statusOrange)
            Text("Accessibility permission required for text insertion")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button("Grant Access") {
                openAccessibilitySettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(Theme.statusOrange.opacity(0.1))
        .clipShape(.rect(cornerRadius: 8))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasAccessibility = AXIsProcessTrusted()
        }
    }

    // MARK: - Update Banner

    private var updateBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.brand)
            Text("Airtype \(updateChecker.latestVersion) available")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button("Download") {
                NSWorkspace.shared.open(UpdateChecker.downloadURL)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(Theme.brand.opacity(0.1))
        .clipShape(.rect(cornerRadius: 8))
    }

    // MARK: - Voice Input

    private var voiceInputSection: some View {
        SettingsSection(title: "Voice Input", icon: "mic.fill") {
            SettingsCard {
                SettingsCardRow(label: "Service") {
                    Picker("", selection: $settings.transcriptionProvider) {
                        ForEach(TranscriptionProvider.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .labelsHidden()
                }

                SettingsCardDivider()

                if settings.transcriptionProvider == .elevenlabs {
                    elevenlabsSettings
                } else if settings.transcriptionProvider == .mistral {
                    mistralTranscriptionSettings
                } else if settings.transcriptionProvider == .doubao {
                    doubaoSettings
                } else {
                    openaiTranscriptionSettings
                }

                SettingsCardDivider()

                transcriptionStatus
            }
        }
    }

    private var elevenlabsSettings: some View {
        Group {
            SettingsCardRow(label: "API Key") {
                HStack(spacing: 6) {
                    SecureField("xi-...", text: $settings.elevenlabsApiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    apiKeyLink(url: settings.transcriptionProvider.apiKeyURL)
                }
            }
            SettingsCardDivider()
            SettingsCardRow(label: "Model") {
                Picker("", selection: $settings.elevenlabsModel) {
                    ForEach(Settings.elevenlabsModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .labelsHidden()
                .font(.system(size: 12, design: .monospaced))
            }
        }
    }

    private var openaiTranscriptionSettings: some View {
        Group {
            SettingsCardRow(label: "API Key") {
                HStack(spacing: 6) {
                    SecureField("sk-...", text: $settings.openaiTranscriptionApiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    apiKeyLink(url: settings.transcriptionProvider.apiKeyURL)
                }
            }
            SettingsCardDivider()
            SettingsCardRow(label: "Model") {
                Picker("", selection: $settings.openaiTranscriptionModel) {
                    ForEach(Settings.openaiTranscriptionModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .labelsHidden()
                .font(.system(size: 12, design: .monospaced))
            }
        }
    }

    private var mistralTranscriptionSettings: some View {
        Group {
            SettingsCardRow(label: "API Key") {
                HStack(spacing: 6) {
                    SecureField("...mistral key...", text: $settings.mistralTranscriptionApiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    apiKeyLink(url: settings.transcriptionProvider.apiKeyURL)
                }
            }
            SettingsCardDivider()
            SettingsCardRow(label: "Model") {
                Picker("", selection: $settings.mistralTranscriptionModel) {
                    ForEach(Settings.mistralTranscriptionModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .labelsHidden()
                .font(.system(size: 12, design: .monospaced))
            }
        }
    }

    private var doubaoSettings: some View {
        Group {
            SettingsCardRow(label: "App ID") {
                HStack(spacing: 6) {
                    TextField("123456789", text: $settings.doubaoAppId)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    apiKeyLink(url: settings.transcriptionProvider.apiKeyURL)
                }
            }
            SettingsCardDivider()
            SettingsCardRow(label: "Access Token") {
                SecureField("your-access-token", text: $settings.doubaoAccessKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }
            SettingsCardDivider()
            SettingsCardRow(label: "Resource ID") {
                Picker("", selection: $settings.doubaoResourceId) {
                    ForEach(Settings.doubaoResourceIds, id: \.self) { rid in
                        Text(rid).tag(rid)
                    }
                }
                .labelsHidden()
                .font(.system(size: 12, design: .monospaced))
            }
            SettingsCardDivider()
            SettingsCardRow(label: "Language") {
                Picker("", selection: $settings.doubaoLanguage) {
                    ForEach(Settings.doubaoLanguages, id: \.self) { lang in
                        Text(lang).tag(lang)
                    }
                }
                .labelsHidden()
            }
        }
    }

    private var transcriptionStatus: some View {
        HStack(spacing: 6) {
            if settings.currentTranscriptionApiKey.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.statusOrange)
                Text("API key required")
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.statusGreen)
                Text("Ready")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .font(.system(size: 11))
    }

    // MARK: - Enhancement

    private var enhancementSection: some View {
        SettingsSection(title: "Enhancement", icon: "wand.and.stars") {
            SettingsCard {
                Toggle(isOn: $settings.enhancementEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable enhancement")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Improve accuracy, add punctuation, and format text")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .toggleStyle(.switch)
            }

            if settings.enhancementEnabled {
                SettingsCard {
                    SettingsCardRow(label: "Provider") {
                        Picker("", selection: $settings.enhancementProvider) {
                            ForEach(EnhancementProvider.allCases) { provider in
                                Text(provider.rawValue).tag(provider)
                            }
                        }
                        .labelsHidden()
                    }

                    if settings.enhancementProvider.requiresApiKey {
                        SettingsCardDivider()
                        SettingsCardRow(label: "API Key") {
                            HStack(spacing: 6) {
                                SecureField(settings.enhancementProvider.apiKeyPlaceholder, text: Binding(
                                    get: { settings.currentEnhancementApiKey },
                                    set: { settings.currentEnhancementApiKey = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                apiKeyLink(url: settings.enhancementProvider.apiKeyURL)
                            }
                        }
                    }

                    if settings.enhancementProvider.requiresCustomURL {
                        SettingsCardDivider()
                        SettingsCardRow(label: "Base URL") {
                            TextField(settings.enhancementProvider.baseURL, text: Binding(
                                get: { settings.currentEnhancementBaseURL },
                                set: { settings.currentEnhancementBaseURL = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                        }
                    }

                    SettingsCardDivider()

                    SettingsCardRow(label: "Model") {
                        TextField(settings.enhancementProvider.defaultModel, text: Binding(
                            get: { settings.currentEnhancementModel },
                            set: { settings.currentEnhancementModel = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                    }

                    SettingsCardDivider()

                    enhancementStatus
                }
            }
        }
    }

    private var enhancementStatus: some View {
        HStack(spacing: 6) {
            if settings.enhancementProvider.requiresApiKey && settings.currentEnhancementApiKey.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.statusOrange)
                Text("\(settings.enhancementProvider.rawValue) API key required")
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.statusGreen)
                Text("Using \(settings.enhancementProvider.rawValue)")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .font(.system(size: 11))
    }

    // MARK: - Floating Window

    private var floatingWindowSection: some View {
        SettingsSection(title: "Floating Window", icon: "macwindow") {
            SettingsCard {
                Toggle(isOn: $settings.showFloatingWindow) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show floating window")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Display status and progress in a floating panel")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .toggleStyle(.switch)
            }

            if settings.showFloatingWindow {
                SettingsCard {
                    SettingsCardRow(label: "Position") {
                        Picker("", selection: $settings.floatingWindowPosition) {
                            ForEach(FloatingWindowPosition.allCases) { position in
                                Text(position.rawValue).tag(position)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    SettingsCardDivider()

                    Toggle(isOn: $settings.previewBeforeInsert) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Preview before inserting")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Review transcription and click Apply to insert")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
            }
        }
    }

    // MARK: - Shortcuts

    private var shortcutsSection: some View {
        SettingsSection(title: "Shortcuts", icon: "keyboard") {
            SettingsCard {
                ShortcutRecorderRow(
                    name: "Push-to-talk",
                    description: "Hold to record, release to transcribe",
                    currentKeyCode: settings.pushToTalkKeyCode,
                    currentModifiers: settings.pushToTalkModifiers,
                    defaultKeyCode: Settings.defaultPushToTalkKeyCode,
                    defaultModifiers: Settings.defaultPushToTalkModifiers,
                    hotkeyManager: hotkeyManager,
                    onSave: { keyCode, modifiers in
                        settings.pushToTalkKeyCode = keyCode
                        settings.pushToTalkModifiers = modifiers
                        hotkeyManager.rebindHotkeys()
                    }
                )

                SettingsCardDivider()

                ShortcutRecorderRow(
                    name: "Toggle mode",
                    description: "Press to start/stop recording",
                    currentKeyCode: settings.toggleModeKeyCode,
                    currentModifiers: settings.toggleModeModifiers,
                    defaultKeyCode: Settings.defaultToggleModeKeyCode,
                    defaultModifiers: Settings.defaultToggleModeModifiers,
                    hotkeyManager: hotkeyManager,
                    onSave: { keyCode, modifiers in
                        settings.toggleModeKeyCode = keyCode
                        settings.toggleModeModifiers = modifiers
                        hotkeyManager.rebindHotkeys()
                    }
                )
            }
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        SettingsSection(title: "Permissions", icon: "lock.shield") {
            SettingsCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Microphone")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Required for voice recording")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button("Open Settings") {
                        openMicrophoneSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                SettingsCardDivider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Required for text insertion")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button("Open Settings") {
                        openAccessibilitySettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func apiKeyLink(url: URL?) -> some View {
        if let url {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10))
                    Text("Get API Key")
                        .font(.system(size: 11))
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.brand)
            .controlSize(.small)
        }
    }

    private func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Components

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    init(title: String, icon: String = "gear", @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            content
        }
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Theme.cardBg)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}

struct SettingsCardRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            content
        }
    }
}

struct SettingsCardDivider: View {
    var body: some View {
        Divider()
            .overlay(Theme.border)
    }
}

struct ShortcutRecorderRow: View {
    let name: String
    let description: String
    let currentKeyCode: UInt32
    let currentModifiers: UInt32
    let defaultKeyCode: UInt32
    let defaultModifiers: UInt32
    let hotkeyManager: HotkeyManager
    let onSave: (UInt32, UInt32) -> Void

    @State private var isRecording = false
    @State private var eventMonitor: Any?

    private var displayString: String {
        Settings.shortcutDisplayString(keyCode: currentKeyCode, modifiers: currentModifiers)
    }

    private var isDefault: Bool {
        currentKeyCode == defaultKeyCode && currentModifiers == defaultModifiers
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(description)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if !isDefault {
                Button("Reset") {
                    onSave(defaultKeyCode, defaultModifiers)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
            }
            Button(action: { startRecording() }) {
                Text(isRecording ? "Press shortcut..." : displayString)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isRecording ? Color.accentColor.opacity(0.2) : Theme.bg)
                    .clipShape(.rect(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isRecording ? Color.accentColor : Theme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    @MainActor private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        hotkeyManager.disable()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let keyCode = UInt32(event.keyCode)
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if keyCode == 53 && modifiers.isEmpty {
                stopRecording()
                return nil
            }

            let carbonMods = modifiers.carbonFlags
            if carbonMods == 0 {
                return nil
            }

            let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
            if modifierKeyCodes.contains(event.keyCode) {
                return nil
            }

            onSave(keyCode, carbonMods)
            stopRecording()
            return nil
        }
    }

    @MainActor private func stopRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isRecording = false
        hotkeyManager.enable()
    }
}
