import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @State private var isPulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Recording banner (prominent when recording)
            if appState.isRecording {
                HStack(spacing: 10) {
                    // Pulsing recording dot
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .scaleEffect(isPulsing ? 1.2 : 0.8)
                        .opacity(isPulsing ? 1.0 : 0.6)
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isPulsing)

                    Text("Recording...")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()

                    Text("Release to transcribe")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.red)
                .onAppear { isPulsing = true }
                .onDisappear { isPulsing = false }
            }

            // Header with app name and status (hidden when recording)
            if !appState.isRecording {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: statusIcon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(statusColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Touchless")
                            .font(.system(size: 13, weight: .semibold))
                        Text(statusText)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            // Processing indicator with streaming text
            if appState.isProcessing {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                        Text(isStreamingText ? "Transcribing..." : appState.processingStage)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    // Show streaming transcription text
                    if isStreamingText {
                        Text(appState.processingStage)
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                            .lineLimit(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            Divider()
                .padding(.vertical, 4)

            // Current configuration
            VStack(alignment: .leading, spacing: 6) {
                configRow(label: "Provider", value: appState.settings.transcriptionProvider.rawValue)
                configRow(label: "Model", value: currentModel)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()
                .padding(.vertical, 4)

            // Shortcuts section
            VStack(alignment: .leading, spacing: 4) {
                Text("Shortcuts")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.7))
                    .textCase(.uppercase)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 2)

                shortcutRow(action: "Push-to-talk", keys: "⌥ Space")
                shortcutRow(action: "Toggle mode", keys: "⌥⇧ Space")
            }
            .padding(.vertical, 6)

            // Error display
            if let error = appState.lastError {
                Divider()
                    .padding(.vertical, 4)

                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            Divider()
                .padding(.vertical, 4)

            // Menu items
            MenuButton(title: "Settings...", shortcut: "⌘,") {
                SettingsWindowController.shared.show()
            }

            MenuButton(title: "Quit Touchless", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }

            Spacer()
                .frame(height: 4)
        }
        .frame(width: 260)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Computed Properties

    /// Check if processing stage contains streaming transcription text
    private var isStreamingText: Bool {
        let stage = appState.processingStage
        return !stage.isEmpty &&
               stage != "Transcribing..." &&
               stage != "Enhancing..." &&
               stage != "Inserting..."
    }

    private var currentModel: String {
        switch appState.settings.transcriptionProvider {
        case .openai:
            return appState.settings.openaiModel
        case .elevenlabs:
            return appState.settings.elevenlabsModel
        }
    }

    private var statusIcon: String {
        if appState.isRecording {
            return "mic.fill"
        } else if appState.isProcessing {
            return "arrow.trianglehead.2.clockwise"
        } else if !appState.settings.isConfigured {
            return "exclamationmark.circle.fill"
        } else {
            return "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        if appState.isRecording {
            return .red
        } else if appState.isProcessing {
            return .orange
        } else if !appState.settings.isConfigured {
            return .yellow
        } else {
            return .green
        }
    }

    private var statusText: String {
        if appState.isRecording {
            return "Recording..."
        } else if appState.isProcessing {
            return "Processing..."
        } else if !appState.settings.isConfigured {
            return "Setup required"
        } else {
            return "Ready"
        }
    }

    // MARK: - Subviews

    private func configRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
        }
    }

    private func shortcutRow(action: String, keys: String) -> some View {
        HStack {
            Text(action)
                .font(.system(size: 12))
            Spacer()
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }
}

// MARK: - Menu Button Component

struct MenuButton: View {
    let title: String
    var shortcut: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
