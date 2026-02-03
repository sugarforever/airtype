import SwiftUI

/// Main floating UI view with pill and expanded modes
/// Dark minimal design inspired by Raycast/Spotlight
struct FloatingView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var audioRecorder: AudioRecorder
    @State private var isExpanded = false
    @State private var isHovering = false

    init(appState: AppState) {
        self.appState = appState
        self.audioRecorder = appState.audioRecorder
    }

    // Sizes
    private let pillSize = CGSize(width: 280, height: 60)
    private let expandedSize = CGSize(width: 380, height: 320)

    var body: some View {
        ZStack {
            // Background - rectangular to match window frame
            Rectangle()
                .fill(Color.black.opacity(0.92))

            // Content
            if isExpanded {
                expandedContent
            } else {
                pillContent
            }
        }
        .frame(
            width: isExpanded ? expandedSize.width : pillSize.width,
            height: isExpanded ? expandedSize.height : pillSize.height
        )
        .ignoresSafeArea()
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
        .onTapGesture {
            toggleExpanded()
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private func toggleExpanded() {
        let newExpanded = !isExpanded
        let newSize = newExpanded ? expandedSize : pillSize

        // Resize the window first, then animate the content
        appState.floatingWindowManager.resize(to: NSSize(width: newSize.width, height: newSize.height))

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isExpanded = newExpanded
        }
    }

    // MARK: - Pill Mode (Compact)

    private var pillContent: some View {
        HStack(spacing: 16) {
            // Status indicator / Waveform
            statusIndicator
                .frame(width: 60)

            // Main info
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                Text(statusSubtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            // Expand indicator
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
                .rotationEffect(.degrees(isHovering ? 0 : -90))
                .animation(.easeInOut(duration: 0.2), value: isHovering)
                .padding(.trailing, 4)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Expanded Mode

    private var expandedContent: some View {
        VStack(spacing: 0) {
            // Header
            expandedHeader
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()
                .background(Color.white.opacity(0.1))

            // Content area
            if appState.isRecording {
                recordingExpandedView
            } else if appState.isProcessing {
                processingExpandedView
            } else if !appState.partialTranscription.isEmpty || appState.lastError != nil {
                resultExpandedView
            } else {
                idleExpandedView
            }

            Spacer()

            // Footer with actions
            if showActionButtons {
                expandedFooter
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
    }

    private var expandedHeader: some View {
        HStack {
            // Status indicator
            statusIndicator
                .frame(width: 50, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Text(statusSubtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            // Collapse button
            Button(action: { withAnimation { isExpanded = false } }) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.1))
            }
            .buttonStyle(.plain)
        }
    }

    private var recordingExpandedView: some View {
        VStack(spacing: 20) {
            // Large waveform
            LiveWaveformView(
                audioLevel: audioRecorder.audioLevel,
                isActive: appState.isRecording
            )
            .frame(height: 60)
            .padding(.horizontal, 20)

            // Duration
            Text(formatDuration(audioRecorder.recordingDuration))
                .font(.system(size: 36, weight: .light, design: .monospaced))
                .foregroundColor(.white)

            // Hint
            Text("Release to transcribe")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.vertical, 20)
    }

    private var processingExpandedView: some View {
        VStack(spacing: 16) {
            // Progress bar
            VStack(spacing: 8) {
                ProgressView(value: appState.processingProgress)
                    .progressViewStyle(FloatingProgressStyle())

                Text(appState.processingStage)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            // Partial transcription preview
            if !appState.partialTranscription.isEmpty {
                ScrollView {
                    Text(appState.partialTranscription)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                }
                .frame(maxHeight: 120)
            }
        }
    }

    private var resultExpandedView: some View {
        VStack(spacing: 12) {
            if let error = appState.lastError {
                // Error state
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.orange)

                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            } else {
                // Success - show transcription
                ScrollView {
                    Text(appState.partialTranscription)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.white.opacity(0.05))
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
    }

    private var idleExpandedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.3))

            Text("Hold \u{2325} Space to record")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))

            Text("or \u{2325}\u{21E7} Space to toggle")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.vertical, 30)
    }

    private var expandedFooter: some View {
        HStack(spacing: 12) {
            if appState.isRecording {
                // Cancel button
                Button(action: { appState.cancelRecording() }) {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Color.white.opacity(0.1))
                }
                .buttonStyle(.plain)
            } else if !appState.partialTranscription.isEmpty && !appState.isProcessing && appState.settings.previewBeforeInsert {
                // Apply button (when preview mode is enabled)
                Button(action: { applyText() }) {
                    Text("Apply")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Color.white)
                }
                .buttonStyle(.plain)

                // Discard button
                Button(action: { discardText() }) {
                    Text("Discard")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 80)
                        .frame(height: 32)
                        .background(Color.white.opacity(0.1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private var statusIndicator: some View {
        if appState.isRecording {
            // Recording - show waveform
            WaveformView(
                audioLevel: audioRecorder.audioLevel,
                isAnimating: true
            )
        } else if appState.isProcessing {
            // Processing - show spinner
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(0.8)
        } else if appState.lastError != nil {
            // Error
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.orange)
        } else {
            // Idle
            Image(systemName: "mic.fill")
                .font(.system(size: 18))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private var statusTitle: String {
        if appState.isRecording {
            return "Recording"
        } else if appState.isProcessing {
            return appState.processingStage.isEmpty ? "Processing..." : appState.processingStage
        } else if appState.lastError != nil {
            return "Error"
        } else {
            return "Ready"
        }
    }

    private var statusSubtitle: String {
        if appState.isRecording {
            return formatDuration(audioRecorder.recordingDuration)
        } else if appState.isProcessing {
            return "\(Int(appState.processingProgress * 100))%"
        } else if appState.lastError != nil {
            return "Tap to see details"
        } else {
            return "Hold \u{2325} Space"
        }
    }

    private var showActionButtons: Bool {
        appState.isRecording ||
        (!appState.partialTranscription.isEmpty && !appState.isProcessing && appState.settings.previewBeforeInsert)
    }

    // MARK: - Actions

    private func applyText() {
        Task {
            do {
                try await appState.textInserter.insert(text: appState.partialTranscription)
                appState.partialTranscription = ""
            } catch {
                appState.lastError = error.localizedDescription
            }
        }
    }

    private func discardText() {
        appState.partialTranscription = ""
        appState.lastError = nil
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Custom Progress Style

struct FloatingProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 4)

                // Progress fill
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.white.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * (configuration.fractionCompleted ?? 0), height: 4)
                    .animation(.easeInOut(duration: 0.2), value: configuration.fractionCompleted)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Preview

struct FloatingView_Previews: PreviewProvider {
    static var previews: some View {
        FloatingView(appState: AppState())
            .preferredColorScheme(.dark)
    }
}
