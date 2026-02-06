import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var floatingWindowManager: FloatingWindowManager
    @State private var isPulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Recording banner (prominent when recording)
            if appState.isRecording {
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        // Pulsing recording dot
                        Circle()
                            .fill(Color.white)
                            .frame(width: 10, height: 10)
                            .scaleEffect(isPulsing ? 1.2 : 0.8)
                            .opacity(isPulsing ? 1.0 : 0.6)
                            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isPulsing)

                        Text("Recording")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)

                        Spacer()

                        // Duration display
                        Text(appState.audioRecorder.formattedDuration)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                    }

                    // Audio level meter
                    AudioLevelMeter(level: appState.audioRecorder.audioLevel, peakLevel: appState.audioRecorder.peakLevel)

                    // Hint text
                    Text("Release to transcribe")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.8))

                    // Warning for long recordings
                    if appState.audioRecorder.isLongRecording {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 10))
                            Text("Long recording - may take longer to process")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.white.opacity(0.7))
                    }
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
                            .foregroundStyle(statusColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Airtype")
                            .font(.system(size: 13, weight: .semibold))
                        Text(statusText)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            // Processing indicator with progress bar and streaming text
            if appState.isProcessing {
                VStack(alignment: .leading, spacing: 8) {
                    // Stage and spinner
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                        Text(appState.processingStage)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        // Percentage
                        Text("\(Int(appState.processingProgress * 100))%")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.secondary.opacity(0.2))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentColor)
                                .frame(width: geometry.size.width * appState.processingProgress)
                                .animation(.easeInOut(duration: 0.2), value: appState.processingProgress)
                        }
                    }
                    .frame(height: 4)

                    // Show partial transcription text during chunked transcription
                    if !appState.partialTranscription.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Preview:")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(appState.partialTranscription)
                                .font(.system(size: 11))
                                .foregroundStyle(.primary)
                                .lineLimit(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(.rect(cornerRadius: 6))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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
                    .foregroundStyle(.secondary.opacity(0.7))
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
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            Divider()
                .padding(.vertical, 4)

            // Menu items
            if appState.settings.showFloatingWindow {
                MenuButton(
                    title: floatingWindowManager.isVisible ? "Hide Floating Window" : "Show Floating Window",
                    shortcut: nil
                ) {
                    floatingWindowManager.toggle(with: appState)
                }
            }

            MenuButton(title: "Settings...", shortcut: "⌘,") {
                SettingsWindowController.shared.show()
            }

            MenuButton(title: "Quit Airtype", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }

            Spacer()
                .frame(height: 4)
        }
        .frame(width: 260)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Computed Properties

    private var currentModel: String {
        appState.settings.currentTranscriptionModel
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
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
        }
    }

    private func shortcutRow(action: String, keys: String) -> some View {
        HStack {
            Text(action)
                .font(.system(size: 12))
            Spacer()
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
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

// MARK: - Audio Level Meter Component

/// Visual audio level meter with smooth animation
struct AudioLevelMeter: View {
    let level: Float      // Current audio level (0.0 - 1.0)
    let peakLevel: Float  // Peak level for indicator

    private let barCount = 20
    private let activeColor = Color.white
    private let inactiveColor = Color.white.opacity(0.2)
    private let peakColor = Color.yellow

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                let threshold = Float(index) / Float(barCount)
                let isActive = level > threshold
                let isPeak = peakLevel > threshold && peakLevel <= threshold + (1.0 / Float(barCount))

                RoundedRectangle(cornerRadius: 1)
                    .fill(isPeak ? peakColor : (isActive ? activeColor : inactiveColor))
                    .animation(.easeOut(duration: 0.05), value: isActive)
            }
        }
        .frame(height: 6)
    }
}

/// Alternative waveform-style visualization
struct AudioWaveform: View {
    let level: Float
    let barCount: Int = 12

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                // Create varied heights based on index and current level
                let baseHeight = CGFloat(level) * 20
                let variation = sin(Double(index) * 0.5) * 0.3 + 0.7
                let height = max(2, baseHeight * CGFloat(variation))

                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white)
                    .frame(width: 3, height: height)
                    .animation(.easeInOut(duration: 0.1), value: level)
            }
        }
        .frame(height: 20)
    }
}
