import ApplicationServices
import AVFoundation
import SwiftUI

struct SetupWizardView: View {
    let onComplete: () -> Void

    @ObservedObject private var settings = Settings.shared
    @State private var currentStep = 0
    @State private var showSkipWarning = false

    // Permissions state
    @State private var hasMicPermission = false
    @State private var hasAccessibility = AXIsProcessTrusted()
    @State private var permissionTimer: Timer?

    private let totalSteps = 5

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
            Divider().overlay(Theme.border)
            ScrollView {
                VStack(spacing: 20) {
                    stepContent
                }
                .padding(28)
            }
            Divider().overlay(Theme.border)
            navigationButtons
        }
        .frame(width: 520, height: 520)
        .background(Theme.bg)
        .tint(Theme.brand)
        .onAppear { checkMicPermission() }
        .onDisappear { permissionTimer?.invalidate() }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index <= currentStep ? Theme.brand : Theme.border)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 14)
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0: stepWelcome
        case 1: stepEnhancement
        case 2: stepPermissions
        case 3: stepUsageGuide
        case 4: stepReady
        default: EmptyView()
        }
    }

    // MARK: - Step 1: Welcome + Voice Provider

    private var stepWelcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Airtype")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Voice-to-text that types where your cursor is. Let's get you set up.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }

            SettingsCard {
                SettingsCardRow(label: "Voice Provider") {
                    Picker("", selection: $settings.transcriptionProvider) {
                        ForEach(TranscriptionProvider.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                SettingsCardDivider()

                SettingsCardRow(label: "API Key") {
                    HStack(spacing: 6) {
                        SecureField("Enter API key...", text: currentTranscriptionApiKeyBinding)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        if let url = settings.transcriptionProvider.apiKeyURL {
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
                }

                SettingsCardDivider()

                SettingsCardRow(label: "Model") {
                    modelPicker
                }
            }
        }
    }

    private var currentTranscriptionApiKeyBinding: Binding<String> {
        switch settings.transcriptionProvider {
        case .openai: return $settings.openaiTranscriptionApiKey
        case .elevenlabs: return $settings.elevenlabsApiKey
        case .mistral: return $settings.mistralTranscriptionApiKey
        }
    }

    @ViewBuilder
    private var modelPicker: some View {
        switch settings.transcriptionProvider {
        case .openai:
            Picker("", selection: $settings.openaiTranscriptionModel) {
                ForEach(Settings.openaiTranscriptionModels, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .font(.system(size: 12, design: .monospaced))
        case .elevenlabs:
            Picker("", selection: $settings.elevenlabsModel) {
                ForEach(Settings.elevenlabsModels, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .font(.system(size: 12, design: .monospaced))
        case .mistral:
            Picker("", selection: $settings.mistralTranscriptionModel) {
                ForEach(Settings.mistralTranscriptionModels, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .font(.system(size: 12, design: .monospaced))
        }
    }

    // MARK: - Step 2: Enhancement

    private var stepEnhancement: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Text Enhancement")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("An LLM can fix grammar, add punctuation, and clean up your transcription.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }

            SettingsCard {
                Toggle(isOn: $settings.enhancementEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable enhancement")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Optional — you can enable this later in Settings")
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
                                if let url = settings.enhancementProvider.apiKeyURL {
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
                }
            }
        }
    }

    // MARK: - Step 3: Permissions

    private var stepPermissions: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Permissions")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Airtype needs microphone access to record and accessibility access to type text.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }

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
                    if hasMicPermission {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.brand)
                    } else {
                        Button("Grant Access") {
                            AVCaptureDevice.requestAccess(for: .audio) { granted in
                                DispatchQueue.main.async { hasMicPermission = granted }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
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
                    if hasAccessibility {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.brand)
                    } else {
                        Button("Grant Access") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
        .onAppear { startPermissionPolling() }
        .onDisappear { permissionTimer?.invalidate() }
    }

    // MARK: - Step 4: Usage Guide

    private var stepUsageGuide: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("How to Use")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Two shortcuts to control voice input.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }

            SettingsCard {
                HStack(spacing: 12) {
                    shortcutBadge("⌥ Space")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Push-to-talk")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Hold to record, release to transcribe and insert")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                SettingsCardDivider()

                HStack(spacing: 12) {
                    shortcutBadge("⌥⇧ Space")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Toggle mode")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Press to start, press again to stop and insert")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            SettingsCard {
                HStack(spacing: 8) {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.brand)
                    Text("Text is inserted at your cursor position in any app.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func shortcutBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.bg)
            .clipShape(.rect(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }

    // MARK: - Step 5: Ready

    private var stepReady: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("You're All Set")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Here's a summary of your setup.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }

            SettingsCard {
                summaryRow(
                    "Voice Provider",
                    detail: settings.transcriptionProvider.rawValue,
                    done: !settings.currentTranscriptionApiKey.isEmpty
                )
                SettingsCardDivider()
                summaryRow(
                    "Enhancement",
                    detail: settings.enhancementEnabled ? settings.enhancementProvider.rawValue : "Off",
                    done: !settings.enhancementEnabled || !settings.currentEnhancementApiKey.isEmpty || !settings.enhancementProvider.requiresApiKey
                )
                SettingsCardDivider()
                summaryRow("Microphone", detail: hasMicPermission ? "Granted" : "Not granted", done: hasMicPermission)
                SettingsCardDivider()
                summaryRow("Accessibility", detail: hasAccessibility ? "Granted" : "Not granted", done: hasAccessibility)
            }

            HStack(spacing: 12) {
                Button("Open Settings") {
                    onComplete()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button("Start Using Airtype") {
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func summaryRow(_ title: String, detail: String, done: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Theme.brand : Theme.textTertiary)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack {
            if currentStep > 0 && currentStep < totalSteps - 1 {
                Button("Back") { currentStep -= 1 }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }

            Spacer()

            if currentStep < totalSteps - 1 {
                Button(action: nextStep) {
                    Text(currentStep == 0 ? "Continue" : "Next")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .alert("API Key Missing", isPresented: $showSkipWarning) {
            Button("Go Back", role: .cancel) {}
            Button("Skip Anyway") { currentStep += 1 }
        } message: {
            Text("You haven't entered an API key. Airtype won't work without one. You can add it later in Settings.")
        }
    }

    private func nextStep() {
        if currentStep == 0 && settings.currentTranscriptionApiKey.isEmpty {
            showSkipWarning = true
            return
        }
        currentStep += 1
    }

    // MARK: - Helpers

    private func checkMicPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: hasMicPermission = true
        default: hasMicPermission = false
        }
    }

    private func startPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                hasAccessibility = AXIsProcessTrusted()
                checkMicPermission()
            }
        }
    }
}
