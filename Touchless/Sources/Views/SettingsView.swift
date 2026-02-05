import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    var onClose: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 24) {
                    transcriptionSection
                    enhancementSection
                    floatingWindowSection
                    shortcutsSection
                    permissionsSection
                }
                .padding(20)
            }
        }
        .frame(width: 480, height: 640)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button("Done") {
                onClose?()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Transcription Section

    private var transcriptionSection: some View {
        SettingsSection(title: "Transcription", icon: "mic.fill") {
            VStack(alignment: .leading, spacing: 16) {
                // Provider picker
                SettingsRow(label: "Provider") {
                    Picker("", selection: $settings.transcriptionProvider) {
                        ForEach(TranscriptionProvider.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // Provider-specific settings
                if settings.transcriptionProvider == .elevenlabs {
                    elevenlabsSettings
                } else {
                    openaiTranscriptionSettings
                }

                // Status indicator
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

    private var transcriptionStatus: some View {
        HStack(spacing: 6) {
            if settings.currentTranscriptionApiKey.isEmpty {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.orange)
                Text("API key required")
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Ready")
                    .foregroundColor(.secondary)
            }
        }
        .font(.system(size: 11))
    }

    // MARK: - Enhancement Section

    private var enhancementSection: some View {
        SettingsSection(title: "AI Enhancement", icon: "wand.and.stars") {
            VStack(alignment: .leading, spacing: 16) {
                // Enable toggle
                Toggle(isOn: $settings.enhancementEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable error correction")
                            .font(.system(size: 12, weight: .medium))
                        Text("Fix transcription errors, add punctuation, format text")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
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
            // Provider picker
            SettingsRow(label: "Provider") {
                Picker("", selection: $settings.enhancementProvider) {
                    ForEach(EnhancementProvider.allCases) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .labelsHidden()
            }

            // API Key (if required)
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

            // Base URL (for providers that need custom URLs)
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

            // Model
            SettingsRow(label: "Model") {
                TextField(settings.enhancementProvider.defaultModel, text: Binding(
                    get: { settings.currentEnhancementModel },
                    set: { settings.currentEnhancementModel = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
            }

            // Enhancement status
            enhancementStatus
        }
    }

    private var enhancementStatus: some View {
        HStack(spacing: 6) {
            if settings.enhancementProvider.requiresApiKey && settings.currentEnhancementApiKey.isEmpty {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.orange)
                Text("\(settings.enhancementProvider.rawValue) API key required")
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Using \(settings.enhancementProvider.rawValue)")
                    .foregroundColor(.secondary)
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
                            .foregroundColor(.secondary)
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
                                .foregroundColor(.secondary)
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
                ShortcutRow(
                    name: "Push-to-talk",
                    shortcut: "\u{2325} Space",
                    description: "Hold to record, release to transcribe"
                )
                ShortcutRow(
                    name: "Toggle mode",
                    shortcut: "\u{2325}\u{21E7} Space",
                    description: "Press to start/stop recording"
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
                                .foregroundColor(.accentColor)
                            Text("Required for voice recording")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
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
                                .foregroundColor(.accentColor)
                            Text("Required for text insertion")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
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
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
            }

            VStack(alignment: .leading, spacing: 0) {
                content
                    .padding(14)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
        }
    }
}

struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            content
        }
    }
}

struct ShortcutRow: View {
    let name: String
    let shortcut: String
    let description: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                Text(description)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(shortcut)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
        }
    }
}

