import SwiftUI
import AppKit

/// Main floating UI view with pill and expanded modes
/// Liquid Glass design using native macOS glass effects
struct FloatingView: View {
    static let pillSize = CGSize(width: 280, height: 60)
    static let expandedSize = CGSize(width: 380, height: 320)

    @ObservedObject var appState: AppState
    @ObservedObject var audioRecorder: AudioRecorder
    @StateObject private var appearanceObserver = GlassAppearanceObserver()
    @State private var isExpanded = false
    @State private var isHovering = false

    init(appState: AppState) {
        self.appState = appState
        self.audioRecorder = appState.audioRecorder
    }

    // Fixed colors - white text on tinted glass
    private var labelColor: Color { .white }
    private var secondaryLabelColor: Color { Color.white.opacity(0.7) }
    private var tertiaryLabelColor: Color { Color.white.opacity(0.5) }
    private var quaternaryLabelColor: Color { Color.white.opacity(0.15) }

    // Sizes
    private let pillSize = Self.pillSize
    private let expandedSize = Self.expandedSize
    private let pillCornerRadius: CGFloat = 30
    private let expandedCornerRadius: CGFloat = 18

    var body: some View {
        ZStack {
            FloatingGlassBackgroundView(cornerRadius: currentCornerRadius, appearanceObserver: appearanceObserver)
                .frame(width: currentContentSize.width, height: currentContentSize.height)
                .clipShape(RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous))

            // Dark tint for white text readability
            RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.4))
                .frame(width: currentContentSize.width, height: currentContentSize.height)

            // Content
            Group {
                if isExpanded {
                    expandedContent
                } else {
                    pillContent
                }
            }
            .frame(width: currentContentSize.width, height: currentContentSize.height)
            .clipShape(RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous))
        }
        .frame(width: currentContentSize.width, height: currentContentSize.height)
        .contentShape(RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous))
        .ignoresSafeArea()
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
        .onTapGesture {
            toggleExpanded()
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .onChange(of: appState.partialTranscription) { newValue in
            // Auto-expand when streaming text starts arriving during recording
            if appState.isRecording && !newValue.isEmpty && !isExpanded && appState.settings.previewBeforeInsert {
                toggleExpanded()
            }
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
                    .foregroundStyle(labelColor)

                if appState.isRecording {
                    RecordingTimer(
                        startTime: appState.recordingStartTime,
                        font: .system(size: 11),
                        color: secondaryLabelColor
                    )
                } else {
                    Text(statusSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(secondaryLabelColor)
                }
            }

            Spacer()

            // Expand indicator
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(secondaryLabelColor)
                .rotationEffect(.degrees(isHovering ? 0 : -90))
                .animation(.easeInOut(duration: 0.2), value: isHovering)
                .padding(.trailing, 4)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Expanded Mode

    private var showExpandedHeader: Bool {
        // Hide header when streaming preview is active during recording
        !(appState.isRecording && showStreamingText)
    }

    private var expandedContent: some View {
        VStack(spacing: 0) {
            // Header (hidden when streaming preview is active)
            if showExpandedHeader {
                expandedHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                Divider()
                    .background(secondaryLabelColor.opacity(0.3))
            }

            // Content area
            if appState.isRecording {
                recordingExpandedView
            } else if appState.isProcessing {
                processingExpandedView
            } else if !appState.partialTranscription.isEmpty || appState.lastError != nil || appState.lastNotice != nil {
                resultExpandedView
            } else {
                idleExpandedView
            }

            if !(appState.isRecording && showStreamingText) {
                Spacer()
            }

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
                    .foregroundStyle(labelColor)

                if appState.isRecording {
                    RecordingTimer(
                        startTime: appState.recordingStartTime,
                        font: .system(size: 11),
                        color: secondaryLabelColor
                    )
                } else {
                    Text(statusSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(secondaryLabelColor)
                }
            }

            Spacer()

            // Collapse button
            Button(action: toggleExpanded) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(secondaryLabelColor)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(quaternaryLabelColor)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var showStreamingText: Bool {
        appState.isRecording && !appState.partialTranscription.isEmpty
    }

    private var recordingExpandedView: some View {
        VStack(spacing: 0) {
            if showStreamingText {
                // Minimal status bar: pulsing dot + timer
                HStack(spacing: 6) {
                    PulsingDot()

                    Text("REC")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(tertiaryLabelColor)

                    RecordingTimer(startTime: appState.recordingStartTime, color: tertiaryLabelColor)

                    Spacer()

                    // Collapse button
                    Button(action: toggleExpanded) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(secondaryLabelColor)
                            .frame(width: 24, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(quaternaryLabelColor)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // Streaming text
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(appState.partialTranscription)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(labelColor)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .id("streamingText")
                    }
                    .onChange(of: appState.partialTranscription) { _ in
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("streamingText", anchor: .bottom)
                        }
                    }
                }
            } else {
                // No streaming text yet: waveform + duration centered
                Spacer()

                LiveWaveformView(
                    audioLevel: audioRecorder.audioLevel,
                    isActive: appState.isRecording
                )
                .frame(height: 60)
                .padding(.horizontal, 20)

                RecordingTimer(
                    startTime: appState.recordingStartTime,
                    font: .system(size: 36, weight: .light, design: .monospaced),
                    color: labelColor
                )
                .padding(.top, 8)

                if audioRecorder.recordingDuration >= 2.0 && audioRecorder.maxLevelDuringRecording < 0.05 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text("No audio detected — check your microphone")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .padding(.top, 8)
                } else {
                    Text("Release to transcribe")
                        .font(.system(size: 12))
                        .foregroundStyle(secondaryLabelColor)
                        .padding(.top, 8)
                }

                Spacer()
            }
        }
    }

    private var processingExpandedView: some View {
        VStack(spacing: 16) {
            // Progress bar
            VStack(spacing: 8) {
                ProgressView(value: appState.processingProgress)
                    .progressViewStyle(FloatingProgressStyle(trackColor: quaternaryLabelColor))

                Text(appState.processingStage)
                    .font(.system(size: 12))
                    .foregroundStyle(secondaryLabelColor)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            // Partial transcription preview
            if !appState.partialTranscription.isEmpty {
                ScrollView {
                    Text(appState.partialTranscription)
                        .font(.system(size: 13))
                        .foregroundStyle(labelColor)
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
                        .foregroundStyle(.orange)

                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(secondaryLabelColor)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            } else if let notice = appState.lastNotice {
                // Notice state (not an error, just info)
                VStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(secondaryLabelColor)

                    Text(notice)
                        .font(.system(size: 12))
                        .foregroundStyle(tertiaryLabelColor)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            } else {
                // Success - show transcription
                ScrollView {
                    Text(appState.partialTranscription)
                        .font(.system(size: 13))
                        .foregroundStyle(labelColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(quaternaryLabelColor)
                        )
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
                .foregroundStyle(secondaryLabelColor)

            Text("Hold \u{2325} Space to record")
                .font(.system(size: 13))
                .foregroundStyle(secondaryLabelColor)

            Text("or \u{2325}\u{21E7} Space to toggle")
                .font(.system(size: 11))
                .foregroundStyle(tertiaryLabelColor)
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
                        .foregroundStyle(secondaryLabelColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(quaternaryLabelColor)
                        )
                }
                .buttonStyle(.plain)
            } else if !appState.partialTranscription.isEmpty && !appState.isProcessing && appState.settings.previewBeforeInsert {
                // Apply button (when preview mode is enabled)
                Button(action: { applyText() }) {
                    Text("Apply")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.accentColor)
                        )
                }
                .buttonStyle(.plain)

                // Discard button
                Button(action: { discardText() }) {
                    Text("Discard")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(secondaryLabelColor)
                        .frame(width: 80)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(quaternaryLabelColor)
                        )
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
                .progressViewStyle(CircularProgressViewStyle(tint: secondaryLabelColor))
                .scaleEffect(0.8)
        } else if appState.lastError != nil {
            // Error
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.orange)
        } else if appState.lastNotice != nil {
            // Notice
            Image(systemName: "info.circle")
                .font(.system(size: 20))
                .foregroundStyle(secondaryLabelColor)
        } else {
            // Idle
            Image(systemName: "mic.fill")
                .font(.system(size: 18))
                .foregroundStyle(secondaryLabelColor)
        }
    }

    private var statusTitle: String {
        if appState.isRecording {
            return "Recording"
        } else if appState.isProcessing {
            return appState.processingStage.isEmpty ? "Thinking..." : appState.processingStage
        } else if appState.lastError != nil {
            return "Error"
        } else if appState.lastNotice != nil {
            return "Notice"
        } else {
            return "Ready"
        }
    }

    private var statusSubtitle: String {
        if appState.isRecording {
            return "" // Handled by RecordingTimer view
        } else if appState.isProcessing {
            return "\(Int(appState.processingProgress * 100))%"
        } else if appState.lastError != nil || appState.lastNotice != nil {
            return "Tap to see details"
        } else {
            return "Hold \u{2325} Space"
        }
    }

    private var showActionButtons: Bool {
        appState.isRecording ||
        (!appState.partialTranscription.isEmpty && !appState.isProcessing && appState.settings.previewBeforeInsert)
    }

    private var currentCornerRadius: CGFloat {
        isExpanded ? expandedCornerRadius : pillCornerRadius
    }

    private var currentContentSize: CGSize {
        isExpanded ? expandedSize : pillSize
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
        appState.lastNotice = nil
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Recording Timer (TimelineView-driven, never blocks)

struct RecordingTimer: View {
    let startTime: Date?
    var font: Font = .system(size: 12, weight: .medium, design: .monospaced)
    var color: Color = .white.opacity(0.5)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let duration = startTime.map { context.date.timeIntervalSince($0) } ?? 0
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            Text(String(format: "%d:%02d", minutes, seconds))
                .font(font)
                .foregroundStyle(color)
        }
    }
}

// MARK: - Pulsing Recording Dot

struct PulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 8, height: 8)
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

// MARK: - Custom Progress Style

struct FloatingProgressStyle: ProgressViewStyle {
    var trackColor: Color

    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(trackColor)
                    .frame(height: 4)

                // Progress fill
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
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
