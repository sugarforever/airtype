import SwiftUI
import os.log

private let logFile = FileManager.default.temporaryDirectory.appendingPathComponent("touchless_debug.log")

func debugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"

    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logFile.path) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: logFile)
        }
    }

    // Also print to stderr
    fputs(line, stderr)
}

/// Print transcription output to stdout (for terminal streaming)
func streamOutput(_ text: String, newline: Bool = true) {
    if newline {
        print(text)
    } else {
        print(text, terminator: "")
    }
    fflush(stdout)
}

@main
struct TouchlessApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState, floatingWindowManager: appState.floatingWindowManager)
        } label: {
            MenuBarIcon(isRecording: appState.isRecording, isProcessing: appState.isProcessing)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Manages the floating window lifecycle within the app
@MainActor
class FloatingWindowManager: ObservableObject {
    static let shared = FloatingWindowManager()

    private var panel: FloatingPanel?
    @Published var isVisible = false

    private init() {}

    func show(with appState: AppState) {
        if panel == nil {
            createPanel(with: appState)
        }

        updateContent(with: appState)
        panel?.orderFront(nil)
        panel?.position(at: appState.settings.floatingWindowPosition)
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    func toggle(with appState: AppState) {
        if isVisible {
            hide()
        } else {
            show(with: appState)
        }
    }

    func updateContent(with appState: AppState) {
        guard let panel = panel else { return }

        let floatingView = FloatingView(appState: appState)
            .ignoresSafeArea()
        let hostingView = NSHostingView(rootView: floatingView)

        // Make hosting view background fully transparent
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        hostingView.layer?.isOpaque = false

        panel.contentView = hostingView
        panel.backgroundColor = NSColor.clear
        panel.applyRoundedMask()
    }

    func reposition(to position: FloatingWindowPosition) {
        panel?.position(at: position)
    }

    func resize(to size: NSSize) {
        panel?.animateResize(to: size, position: Settings.shared.floatingWindowPosition)
    }

    private func createPanel(with appState: AppState) {
        let initialSize = NSSize(
            width: FloatingView.pillSize.width,
            height: FloatingView.pillSize.height
        )
        let contentRect = NSRect(origin: .zero, size: initialSize)

        panel = FloatingPanel(contentRect: contentRect)

        let floatingView = FloatingView(appState: appState)
            .ignoresSafeArea()
        let hostingView = NSHostingView(rootView: floatingView)
        hostingView.frame = contentRect

        // Make hosting view background fully transparent
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        hostingView.layer?.isOpaque = false

        // Set after contentView is assigned for proper transparency
        panel?.contentView = hostingView
        panel?.backgroundColor = NSColor.clear
        panel?.applyRoundedMask()
    }
}

/// Animated menu bar icon
struct MenuBarIcon: View {
    let isRecording: Bool
    let isProcessing: Bool

    var body: some View {
        if #available(macOS 14.0, *) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(iconColor)
                .symbolEffect(.pulse, isActive: isRecording)
        } else {
            // Fallback for macOS 13
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(iconColor)
        }
    }

    private var iconName: String {
        if isRecording {
            return "record.circle.fill"
        } else if isProcessing {
            return "ellipsis.circle.fill"
        } else {
            return "mic.circle.fill"
        }
    }

    private var iconColor: Color {
        if isRecording {
            return .red
        } else if isProcessing {
            return .orange
        } else {
            return .primary
        }
    }
}

/// Main application state coordinator
@MainActor
class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var processingStage = ""
    @Published var processingProgress: Double = 0.0  // 0.0 to 1.0
    @Published var transcriptionChunkInfo = ""       // e.g., "Chunk 2/5"
    @Published var partialTranscription = ""         // Accumulated text during chunked transcription
    @Published var lastError: String?

    // For streaming output tracking
    private var lastStreamedLength = 0

    let settings = Settings.shared
    let audioRecorder = AudioRecorder()
    let whisperService = WhisperService()
    let elevenlabsService = ElevenLabsService()
    let mistralTranscriptionService = MistralTranscriptionService()
    let enhancementService = EnhancementService()
    let textInserter = TextInserter()
    let hotkeyManager = HotkeyManager()
    let floatingWindowManager = FloatingWindowManager.shared

    var menuBarIcon: String {
        if isRecording {
            return "mic.fill"
        } else if isProcessing {
            return "ellipsis.circle"
        } else {
            return "mic"
        }
    }

    init() {
        setupHotkeyCallbacks()
    }

    private func setupHotkeyCallbacks() {
        // Push-to-talk: start recording on key down
        hotkeyManager.onPushToTalkStart = { [weak self] in
            Task { @MainActor in
                await self?.startRecording()
            }
        }

        // Push-to-talk: stop and process on key up
        hotkeyManager.onPushToTalkEnd = { [weak self] in
            Task { @MainActor in
                await self?.stopAndProcess()
            }
        }

        // Toggle mode: toggle recording state
        hotkeyManager.onToggle = { [weak self] in
            Task { @MainActor in
                if self?.isRecording == true {
                    await self?.stopAndProcess()
                } else {
                    await self?.startRecording()
                }
            }
        }
    }

    // MARK: - Recording Flow

    func startRecording() async {
        debugLog("startRecording called")
        guard !isRecording && !isProcessing else {
            debugLog("Already recording or processing, skipping")
            return
        }
        guard settings.isConfigured else {
            debugLog("API key not configured")
            lastError = settings.configurationError ?? "Please configure API keys in Settings"
            return
        }

        do {
            let url = try audioRecorder.startRecording()
            debugLog("Recording started, saving to: \(url.path)")
            isRecording = true
            lastError = nil

            // Show floating window if enabled
            if settings.showFloatingWindow {
                floatingWindowManager.show(with: self)
            }
        } catch {
            debugLog("Failed to start recording: \(error)")
            lastError = error.localizedDescription
        }
    }

    func stopAndProcess() async {
        debugLog("stopAndProcess called, isRecording: \(isRecording)")
        guard isRecording else {
            debugLog("Not recording, skipping")
            return
        }

        guard let audioURL = audioRecorder.stopRecording() else {
            debugLog("No audio URL returned")
            lastError = "No recording to process"
            isRecording = false
            return
        }

        debugLog("Recording stopped, file: \(audioURL.path)")

        // Check file size and validate
        var fileSize: Int64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: audioURL.path),
           let size = attrs[.size] as? Int64 {
            fileSize = size
            debugLog("Audio file size: \(size) bytes")
        }

        // Check for empty/too short recording
        if fileSize < 1000 {  // Less than 1KB is likely empty
            debugLog("Recording too short, skipping")
            lastError = "Recording too short. Please speak for longer."
            audioRecorder.cleanupRecording(at: audioURL)
            isRecording = false
            return
        }

        isRecording = false
        isProcessing = true
        processingProgress = 0.0
        partialTranscription = ""
        transcriptionChunkInfo = ""

        do {
            // Step 1: Transcribe using selected provider (with progress for OpenAI)
            debugLog("Starting transcription with \(settings.transcriptionProvider.rawValue)...")
            processingStage = "Transcribing..."
            streamOutput("\n--- Transcribing (\(settings.transcriptionProvider.rawValue))... ---")
            lastStreamedLength = 0
            let transcription: String

            switch settings.transcriptionProvider {
            case .openai:
                transcription = try await whisperService.transcribeWithProgress(audioURL: audioURL) { [weak self] progress in
                    Task { @MainActor in
                        guard let self = self else { return }
                        self.processingProgress = progress.progress * 0.7  // Transcription is 70% of total
                        self.partialTranscription = progress.partialText

                        // Stream partial results to terminal (chunk by chunk)
                        if progress.totalChunks > 1 && !progress.partialText.isEmpty {
                            let currentLength = progress.partialText.count
                            if currentLength > self.lastStreamedLength {
                                let startIndex = progress.partialText.index(progress.partialText.startIndex, offsetBy: self.lastStreamedLength)
                                let newText = String(progress.partialText[startIndex...])
                                streamOutput(newText, newline: false)
                                self.lastStreamedLength = currentLength
                            }
                        }

                        // Update stage with chunk info
                        if progress.totalChunks > 1 {
                            self.transcriptionChunkInfo = "(\(progress.currentChunk)/\(progress.totalChunks))"
                            self.processingStage = "\(progress.stage.rawValue) \(self.transcriptionChunkInfo)"
                        } else {
                            self.processingStage = progress.stage.rawValue
                        }
                    }
                }
            case .elevenlabs:
                transcription = try await elevenlabsService.transcribe(audioURL: audioURL)
            case .mistral:
                transcription = try await mistralTranscriptionService.transcribe(audioURL: audioURL)
            }

            debugLog("Transcription result: \(transcription)")
            streamOutput("\n\n--- Raw transcription ---")
            streamOutput(transcription)

            // Check for empty transcription
            if transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw WhisperError.emptyRecording
            }

            // Step 2: Enhance (if enabled)
            let finalText: String
            if settings.enhancementEnabled {
                debugLog("Starting enhancement...")
                processingStage = "Correcting..."
                streamOutput("\n--- Correcting errors... ---")
                processingProgress = 0.75
                finalText = try await enhancementService.enhance(text: transcription)
                debugLog("Enhanced result: \(finalText)")
                streamOutput("\n--- Corrected text ---")
                streamOutput(finalText)
                processingProgress = 0.9
            } else {
                finalText = transcription
                processingProgress = 0.9
            }

            // Step 3: Insert at cursor (or preview if enabled)
            if settings.previewBeforeInsert {
                // Store for preview - user will manually apply
                debugLog("Preview mode - waiting for user to apply")
                processingStage = "Ready to apply"
                streamOutput("\n--- Ready to apply (preview mode) ---")
                partialTranscription = finalText
                processingProgress = 1.0
                isProcessing = false
                // Don't clear partialTranscription - user needs to see it
                lastError = nil
            } else {
                // Direct insert
                debugLog("Inserting text...")
                processingStage = "Inserting..."
                streamOutput("\n--- Inserting at cursor ---")
                processingProgress = 0.95
                try await textInserter.insert(text: finalText)
                debugLog("Text inserted successfully")
                streamOutput("Done!\n")
                processingProgress = 1.0

                lastError = nil

                // Cleanup
                isProcessing = false
                processingStage = ""
                processingProgress = 0.0
                partialTranscription = ""
                transcriptionChunkInfo = ""

                // Hide floating window after successful insert (with delay for feedback)
                if settings.showFloatingWindow {
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 second
                        floatingWindowManager.hide()
                    }
                }
            }
        } catch {
            debugLog("Error: \(error)")
            lastError = error.localizedDescription
            isProcessing = false
            processingStage = ""
            processingProgress = 0.0
        }

        // Cleanup audio file
        audioRecorder.cleanupRecording(at: audioURL)
        transcriptionChunkInfo = ""
        debugLog("Processing complete")
    }

    func cancelRecording() {
        audioRecorder.cancelRecording()
        isRecording = false
    }
}
