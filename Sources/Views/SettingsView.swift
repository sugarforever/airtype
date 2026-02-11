import HotKey
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var hotkeyManager: HotkeyManager
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
        SettingsSection(title: "Voice Input", icon: "mic.fill") {
            VStack(alignment: .leading, spacing: 16) {
                // Provider picker
                SettingsRow(label: "Service") {
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
                } else if settings.transcriptionProvider == .mistral {
                    mistralTranscriptionSettings
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
                HStack(spacing: 6) {
                    SecureField("xi-...", text: $settings.elevenlabsApiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    apiKeyLink(url: settings.transcriptionProvider.apiKeyURL)
                }
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
                HStack(spacing: 6) {
                    SecureField("sk-...", text: $settings.openaiTranscriptionApiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    apiKeyLink(url: settings.transcriptionProvider.apiKeyURL)
                }
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
                HStack(spacing: 6) {
                    SecureField("...mistral key...", text: $settings.mistralTranscriptionApiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    apiKeyLink(url: settings.transcriptionProvider.apiKeyURL)
                }
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
                // Enable toggle
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

    @ViewBuilder
    private func apiKeyLink(url: URL?) -> some View {
        if let url {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Image(systemName: "key.fill")
                    .font(.system(size: 10))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Get API Key")
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
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            VStack(alignment: .leading, spacing: 0) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(.rect(cornerRadius: 10))
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
                .foregroundStyle(.secondary)
            content
        }
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
                Text(description)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isDefault {
                Button("Reset") {
                    onSave(defaultKeyCode, defaultModifiers)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            Button(action: { startRecording() }) {
                Text(isRecording ? "Press shortcut..." : displayString)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isRecording ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        hotkeyManager.disable()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let keyCode = UInt32(event.keyCode)
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Escape cancels
            if keyCode == 53 && modifiers.isEmpty {
                stopRecording()
                return nil
            }

            // Require at least one modifier key
            let carbonMods = modifiers.carbonFlags
            if carbonMods == 0 {
                return nil
            }

            // Ignore standalone modifier key presses
            let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
            if modifierKeyCodes.contains(event.keyCode) {
                return nil
            }

            onSave(keyCode, carbonMods)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isRecording = false
        hotkeyManager.enable()
    }
}
