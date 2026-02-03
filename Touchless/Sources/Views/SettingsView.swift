import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    var onClose: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Content
            ScrollView {
                VStack(spacing: 20) {
                    transcriptionSection
                    apiKeysSection
                    enhancementSection
                    floatingWindowSection
                    shortcutsSection
                    permissionsSection
                }
                .padding(20)
            }
        }
        .frame(width: 440, height: 600)
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

    // MARK: - Sections

    private var transcriptionSection: some View {
        SettingsSection(title: "Transcription") {
            VStack(alignment: .leading, spacing: 16) {
                // Provider picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Provider")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    Picker("", selection: $settings.transcriptionProvider) {
                        ForEach(TranscriptionProvider.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // Model picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    Picker("", selection: settings.transcriptionProvider == .openai ? $settings.openaiModel : $settings.elevenlabsModel) {
                        ForEach(currentModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .labelsHidden()
                }
            }
        }
    }

    private var currentModels: [String] {
        settings.transcriptionProvider == .openai ? Settings.openaiModels : Settings.elevenlabsModels
    }

    private var apiKeysSection: some View {
        SettingsSection(title: "API Keys") {
            VStack(alignment: .leading, spacing: 16) {
                // OpenAI API Key
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text("OpenAI API Key")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        if settings.transcriptionProvider == .elevenlabs {
                            Text("(for enhancement)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                    SecureField("sk-...", text: $settings.openaiApiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }

                // OpenAI Base URL (for OpenRouter, etc.)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text("API Base URL")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("(OpenRouter, Azure, etc.)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    HStack(spacing: 8) {
                        TextField(Settings.defaultOpenAIBaseURL, text: $settings.openaiBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                        Button("Reset") {
                            settings.openaiBaseURL = Settings.defaultOpenAIBaseURL
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    if settings.openaiBaseURL != Settings.defaultOpenAIBaseURL {
                        Text("Using custom endpoint")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }

                // ElevenLabs API Key
                if settings.transcriptionProvider == .elevenlabs {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ElevenLabs")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        SecureField("xi-...", text: $settings.elevenlabsApiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                }

                // Status indicator
                configurationStatus
            }
        }
    }

    private var configurationStatus: some View {
        HStack(spacing: 6) {
            if let error = settings.configurationError {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.orange)
                Text(error)
                    .foregroundColor(.secondary)
            } else if settings.isConfigured {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Ready to use")
                    .foregroundColor(.secondary)
            }
        }
        .font(.system(size: 11))
    }

    private var enhancementSection: some View {
        SettingsSection(title: "Error Correction") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $settings.enhancementEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable AI error correction")
                            .font(.system(size: 12))
                        Text("Fix misrecognized words, add punctuation, format numbers")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)

                if settings.enhancementEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Model")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Picker("", selection: $settings.enhancementModel) {
                            ForEach(Settings.enhancementModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()
                    }
                }
            }
        }
    }

    private var floatingWindowSection: some View {
        SettingsSection(title: "Floating Window") {
            VStack(alignment: .leading, spacing: 16) {
                // Show floating window toggle
                Toggle(isOn: $settings.showFloatingWindow) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show floating window")
                            .font(.system(size: 12))
                        Text("Display status and progress in a floating panel")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)

                if settings.showFloatingWindow {
                    // Window position
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Position")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        Picker("", selection: $settings.floatingWindowPosition) {
                            ForEach(FloatingWindowPosition.allCases) { position in
                                Text(position.rawValue).tag(position)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    // Preview before insert
                    Toggle(isOn: $settings.previewBeforeInsert) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Preview before inserting")
                                .font(.system(size: 12))
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

    private var shortcutsSection: some View {
        SettingsSection(title: "Keyboard Shortcuts") {
            VStack(spacing: 8) {
                ShortcutRow(
                    name: "Push-to-talk",
                    shortcut: "⌥ Space",
                    description: "Hold to record, release to transcribe"
                )
                ShortcutRow(
                    name: "Toggle mode",
                    shortcut: "⌥⇧ Space",
                    description: "Press to start/stop recording"
                )
            }
        }
    }

    private var permissionsSection: some View {
        SettingsSection(title: "Permissions") {
            VStack(alignment: .leading, spacing: 12) {
                PermissionRow(
                    icon: "mic.fill",
                    name: "Microphone",
                    description: "Required for voice recording"
                )
                PermissionRow(
                    icon: "accessibility",
                    name: "Accessibility",
                    description: "Required for text insertion"
                )

                Button(action: openSystemSettings) {
                    HStack(spacing: 4) {
                        Image(systemName: "gear")
                        Text("Open System Settings")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.link)
            }
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Components

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 0) {
                content
                    .padding(12)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
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

struct PermissionRow: View {
    let icon: String
    let name: String
    let description: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                Text(description)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
}
