import HotKey
import SwiftUI

struct MainView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var hotkeyManager: HotkeyManager

    var body: some View {
        VStack(spacing: 0) {
            dashboardHeader
            Divider()
            ScrollView {
                VStack(spacing: 24) {
                    if let error = settings.configurationError {
                        statusBanner(message: error)
                    }
                    transcriptionSection
                    enhancementSection
                    floatingWindowSection
                    shortcutsSection
                    permissionsSection
                }
                .padding(20)
            }
        }
        .frame(width: 520, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Dashboard Header

    private var dashboardHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(settings.isConfigured ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(settings.isConfigured ? .green : .orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Airtype")
                    .font(.system(size: 16, weight: .semibold))
                HStack(spacing: 4) {
                    Circle()
                        .fill(settings.isConfigured ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(settings.isConfigured ? "Ready" : "Setup required")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Status Banner

    private func statusBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .clipShape(.rect(cornerRadius: 8))
    }

    // MARK: - Transcription Section

    private var transcriptionSection: some View {
        SettingsSection(title: "Voice Input", icon: "mic.fill") {
            VStack(alignment: .leading, spacing: 16) {
                SettingsRow(label: "Service") {
                    Picker("", selection: $settings.transcriptionProvider) {
                        ForEach(TranscriptionProvider.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                if settings.transcriptionProvider == .elevenlabs {
                    elevenlabsSettings
                } else if settings.transcriptionProvider == .mistral {
                    mistralTranscriptionSettings
                } else {
                    openaiTranscriptionSettings
                }

                transcriptionStatus
            }
        }
    }

    private var elevenlabsSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsRow(label: "API Key") {
                SecureField("xi-...", text: $settings.elevenlabsApiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            SettingsRow(label: "Model") {
                Picker("", selection: $settings.elevenlabsModel) {
                    ForEach(Settings.elevenlabsModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .labelsHidden()
            }
        }
    }

    private var openaiTranscriptionSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsRow(label: "API Key") {
                SecureField("sk-...", text: $settings.openaiTranscriptionApiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            SettingsRow(label: "Model") {
                Picker("", selection: $settings.openaiTranscriptionModel) {
                    ForEach(Settings.openaiTranscriptionModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .labelsHidden()
            }
        }
    }

    private var mistralTranscriptionSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsRow(label: "API Key") {
                SecureField("...mistral key...", text: $settings.mistralTranscriptionApiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            SettingsRow(label: "Model") {
                Picker("", selection: $settings.mistralTranscriptionModel) {
                    ForEach(Settings.mistralTranscriptionModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .labelsHidden()
            }
        }
    }

    private var transcriptionStatus: some View {
        HStack(spacing: 6) {
            if settings.currentTranscriptionApiKey.isEmpty {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                Text("API key required")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Ready")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11))
    }

    // MARK: - Enhancement Section

    private var enhancementSection: some View {
        SettingsSection(title: "Enhancement Model", icon: "wand.and.stars") {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $settings.enhancementEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable enhancement")
                            .font(.system(size: 12, weight: .medium))
                        Text("Improve accuracy, add punctuation, and format text")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                if settings.enhancementEnabled {
                    Divider()
                    enhancementProviderSettings
                }
            }
        }
    }

    private var enhancementProviderSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsRow(label: "Provider") {
                Picker("", selection: $settings.enhancementProvider) {
                    ForEach(EnhancementProvider.allCases) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .labelsHidden()
            }

            if settings.enhancementProvider.requiresApiKey {
                SettingsRow(label: "API Key") {
                    SecureField(settings.enhancementProvider.apiKeyPlaceholder, text: Binding(
                        get: { settings.currentEnhancementApiKey },
                        set: { settings.currentEnhancementApiKey = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                }
            }

            if settings.enhancementProvider.requiresCustomURL {
                SettingsRow(label: "Base URL") {
                    TextField(settings.enhancementProvider.baseURL, text: Binding(
                        get: { settings.currentEnhancementBaseURL },
                        set: { settings.currentEnhancementBaseURL = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                }
            }

            SettingsRow(label: "Model") {
                TextField(settings.enhancementProvider.defaultModel, text: Binding(
                    get: { settings.currentEnhancementModel },
                    set: { settings.currentEnhancementModel = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
            }

            enhancementStatus
        }
    }

    private var enhancementStatus: some View {
        HStack(spacing: 6) {
            if settings.enhancementProvider.requiresApiKey && settings.currentEnhancementApiKey.isEmpty {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                Text("\(settings.enhancementProvider.rawValue) API key required")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Using \(settings.enhancementProvider.rawValue)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11))
    }

    // MARK: - Floating Window Section

    private var floatingWindowSection: some View {
        SettingsSection(title: "Floating Window", icon: "macwindow") {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $settings.showFloatingWindow) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show floating window")
                            .font(.system(size: 12, weight: .medium))
                        Text("Display status and progress in a floating panel")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                if settings.showFloatingWindow {
                    SettingsRow(label: "Position") {
                        Picker("", selection: $settings.floatingWindowPosition) {
                            ForEach(FloatingWindowPosition.allCases) { position in
                                Text(position.rawValue).tag(position)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    Toggle(isOn: $settings.previewBeforeInsert) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Preview before inserting")
                                .font(.system(size: 12, weight: .medium))
                            Text("Review transcription and click Apply to insert")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
            }
        }
    }

    // MARK: - Shortcuts Section

    private var shortcutsSection: some View {
        SettingsSection(title: "Keyboard Shortcuts", icon: "keyboard") {
            VStack(spacing: 8) {
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

    // MARK: - Permissions Section

    private var permissionsSection: some View {
        SettingsSection(title: "Permissions", icon: "lock.shield") {
            VStack(alignment: .leading, spacing: 16) {
                SettingsRow(label: "Microphone") {
                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.accentColor)
                            Text("Required for voice recording")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open Settings") {
                            openMicrophoneSettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                SettingsRow(label: "Accessibility") {
                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: "accessibility")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.accentColor)
                            Text("Required for text insertion")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
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
    }

    // MARK: - Helpers

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
