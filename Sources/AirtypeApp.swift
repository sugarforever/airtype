import SwiftUI
import Combine
import os.log

private let logFile = FileManager.default.temporaryDirectory.appendingPathComponent("airtype_debug.log")
private let logQueue = DispatchQueue(label: "com.airtype.debuglog")

func debugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"
    fputs(line, stderr)

    guard let data = line.data(using: .utf8) else { return }
    logQueue.async {
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

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MainWindowController.shared.show()
        }
        return true
    }
}

@main
struct AirtypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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
    @Published var lastNotice: String?
    @Published var recordingStartTime: Date?

    // For streaming output tracking
    private var lastStreamedLength = 0
    // Accumulated finalized utterances from streaming (Doubao resets text per utterance)
    private var finalizedStreamText = ""
    // How much of finalizedStreamText has already been inserted at cursor
    private var insertedStreamLength = 0

    let settings = Settings.shared
    let audioRecorder = AudioRecorder()
    let whisperService = WhisperService()
    let elevenlabsService = ElevenLabsService()
    let mistralTranscriptionService = MistralTranscriptionService()
    let enhancementService = EnhancementService()
    let textInserter = TextInserter()
    let hotkeyManager = HotkeyManager()
    let floatingWindowManager = FloatingWindowManager.shared
    private var streamingCapture: StreamingAudioCapture?
    private var streamingService: (any StreamingTranscriptionService)?
    private var streamingEventTask: Task<Void, Never>?
    private var preconnectedStreamingService: DoubaoStreamingService?
    private var preconnectTask: Task<Void, Never>?

    var menuBarIcon: String {
        if isRecording {
            return "mic.fill"
        } else if isProcessing {
            return "ellipsis.circle"
        } else {
            return "mic"
        }
    }

    private var providerObserver: AnyCancellable?

    init() {
        setupHotkeyCallbacks()
        MainWindowController.shared.hotkeyManager = hotkeyManager
        Task { @MainActor in
            if settings.hasCompletedSetup {
                MainWindowController.shared.show()
            } else {
                MainWindowController.shared.showWizard()
            }
        }
        // Pre-connect streaming when Doubao is selected; tear down otherwise
        preconnectStreamingIfNeeded()
        providerObserver = settings.$transcriptionProvider.sink { [weak self] _ in
            Task { @MainActor in
                self?.preconnectStreamingIfNeeded()
            }
        }
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

    // MARK: - Streaming Pre-connect

    /// Pre-establish a Doubao WebSocket connection so recording starts instantly
    func preconnectStreamingIfNeeded() {
        // Only pre-connect when Doubao is selected and configured
        guard shouldUseStreaming, settings.isConfigured else {
            disconnectPreconnected()
            return
        }
        // Already have a ready connection
        if preconnectedStreamingService != nil { return }

        preconnectTask?.cancel()
        preconnectTask = Task { [weak self] in
            guard let self = self else { return }
            let service = DoubaoStreamingService(
                appId: self.settings.doubaoAppId,
                accessKey: self.settings.doubaoAccessKey,
                resourceId: self.settings.doubaoResourceId,
                language: self.settings.doubaoLanguage
            )
            do {
                try await service.connect()
                guard !Task.isCancelled else {
                    await service.disconnect()
                    return
                }
                await MainActor.run {
                    self.preconnectedStreamingService = service
                    debugLog("Streaming pre-connected")
                }
            } catch {
                debugLog("Streaming pre-connect failed: \(error)")
            }
        }
    }

    private func disconnectPreconnected() {
        preconnectTask?.cancel()
        preconnectTask = nil
        if let service = preconnectedStreamingService {
            preconnectedStreamingService = nil
            Task { await service.disconnect() }
        }
    }

    // MARK: - Recording Flow

    private var shouldUseStreaming: Bool {
        settings.transcriptionProvider.supportsStreaming
    }

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
            if shouldUseStreaming {
                try await startStreamingRecording()
            } else {
                let url = try audioRecorder.startRecording()
                debugLog("Recording started, saving to: \(url.path)")
            }

            isRecording = true
            recordingStartTime = Date()
            lastError = nil
            lastNotice = nil
            partialTranscription = ""

            // Show floating window if enabled
            if settings.showFloatingWindow {
                floatingWindowManager.show(with: self)
            }
        } catch {
            debugLog("Failed to start recording: \(error)")
            lastError = error.localizedDescription
        }
    }

    private func startStreamingRecording() async throws {
        let service: DoubaoStreamingService
        if let preconnected = preconnectedStreamingService, await !preconnected.isStale() {
            service = preconnected
            preconnectedStreamingService = nil
            debugLog("Using pre-connected streaming service")
        } else {
            // Discard stale pre-connected service if any
            if let stale = preconnectedStreamingService {
                preconnectedStreamingService = nil
                Task { await stale.disconnect() }
            }
            service = DoubaoStreamingService(
                appId: settings.doubaoAppId,
                accessKey: settings.doubaoAccessKey,
                resourceId: settings.doubaoResourceId,
                language: settings.doubaoLanguage
            )
            try await service.connect()
            debugLog("Streaming WebSocket connected (fresh)")
        }
        // Send init message now — starts the server's audio timeout
        try await service.startSession()
        self.streamingService = service

        finalizedStreamText = ""
        insertedStreamLength = 0

        // Listen for events (task runs on @MainActor to avoid per-event hops)
        streamingEventTask = Task { @MainActor [weak self] in
            for await event in service.events {
                guard let self = self else { break }
                switch event {
                case .partial(let text):
                    let fullText = self.finalizedStreamText + text
                    self.partialTranscription = fullText
                    self.processingStage = "Listening..."
                case .final_(let text):
                    self.finalizedStreamText += text
                    if !self.settings.previewBeforeInsert && !self.settings.enhancementEnabled {
                        let newText = String(self.finalizedStreamText.dropFirst(self.insertedStreamLength))
                        if !newText.isEmpty {
                            self.insertedStreamLength = self.finalizedStreamText.count
                            let inserter = self.textInserter
                            Task { try? await inserter.insert(text: newText) }
                        }
                    }
                case .error(let error):
                    debugLog("Streaming error: \(error)")
                    self.lastError = error.localizedDescription
                }
            }
        }

        // Start audio capture and feed to WebSocket
        let capture = StreamingAudioCapture()
        self.streamingCapture = capture
        try capture.start { [weak service] data in
            Task { await service?.sendAudio(data) }
        }
        debugLog("Streaming audio capture started")
    }

    private func stopStreamingAndProcess() async {
        streamingCapture?.stop()
        streamingCapture = nil

        isRecording = false
        recordingStartTime = nil
        isProcessing = true
        processingStage = "Finalizing..."

        do {
            try await streamingService?.endAudio()
            debugLog("Sent end-of-audio signal")

            // Wait briefly for final result
            try await Task.sleep(nanoseconds: 1_000_000_000)

            streamingEventTask?.cancel()
            streamingEventTask = nil

            // Use the most complete text: partialTranscription has the latest
            // partial view, finalizedStreamText has all locked-in utterances.
            let transcription = partialTranscription.count >= finalizedStreamText.count
                ? partialTranscription : finalizedStreamText
            await streamingService?.disconnect()
            streamingService = nil

            debugLog("Streaming transcription result: \(transcription)")
            streamOutput("\n--- Raw transcription (streaming) ---")
            streamOutput(transcription)

            if transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw WhisperError.emptyRecording
            }

            // Enhancement
            let finalText: String
            if settings.enhancementEnabled {
                debugLog("Starting enhancement...")
                streamOutput("\n--- Correcting errors... ---")
                processingProgress = 0.75
                finalText = try await enhancementService.enhance(text: transcription)
                debugLog("Enhanced result: \(finalText)")
                streamOutput("\n--- Corrected text ---")
                streamOutput(finalText)
            } else {
                finalText = transcription
            }

            // Insert
            if settings.previewBeforeInsert {
                processingStage = "Ready to apply"
                partialTranscription = finalText
                processingProgress = 1.0
                isProcessing = false
                lastError = nil
                lastNotice = nil
            } else {
                processingProgress = 0.95
                // When enhancement is on, nothing was inserted during streaming,
                // so insert the full enhanced text. Otherwise, only insert what
                // wasn't already inserted via streaming FINALs.
                let textToInsert = settings.enhancementEnabled
                    ? finalText
                    : String(finalText.dropFirst(insertedStreamLength))
                if !textToInsert.isEmpty {
                    try await textInserter.insert(text: textToInsert)
                    debugLog("Inserted text (\(textToInsert.count) chars)")
                } else {
                    debugLog("All text already inserted via streaming")
                }
                streamOutput("Done!\n")

                lastError = nil
                lastNotice = nil
                isProcessing = false
                processingStage = ""
                processingProgress = 0.0
                partialTranscription = ""

                if settings.showFloatingWindow {
                    let manager = floatingWindowManager
                    Task { try? await Task.sleep(nanoseconds: 500_000_000); manager.hide() }
                }
            }
        } catch {
            debugLog("Streaming processing error: \(error)")
            if case WhisperError.emptyRecording = error {
                lastNotice = error.localizedDescription
            } else {
                lastError = error.localizedDescription
            }
            isProcessing = false
            processingStage = ""
            processingProgress = 0.0
            streamingEventTask?.cancel()
            streamingEventTask = nil
            await streamingService?.disconnect()
            streamingService = nil
        }

        // Pre-connect for next recording
        preconnectStreamingIfNeeded()
    }

    func stopAndProcess() async {
        debugLog("stopAndProcess called, isRecording: \(isRecording)")
        guard isRecording else {
            debugLog("Not recording, skipping")
            return
        }

        if shouldUseStreaming {
            await stopStreamingAndProcess()
            return
        }

        guard let audioURL = audioRecorder.stopRecording() else {
            debugLog("No audio URL returned")
            lastError = "No recording to process"
            isRecording = false
            recordingStartTime = nil
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
            lastNotice = "Recording too short. Please speak for longer."
            audioRecorder.cleanupRecording(at: audioURL)
            isRecording = false
            recordingStartTime = nil
            return
        }

        // Check for silence (valid file but no speech detected)
        if audioRecorder.recordingWasSilent {
            debugLog("Recording was silent (max level: \(audioRecorder.maxLevelDuringRecording)), skipping API call")
            lastNotice = "No speech detected. Check that the correct microphone is selected in System Settings → Sound → Input."
            audioRecorder.cleanupRecording(at: audioURL)
            isRecording = false
            recordingStartTime = nil
            return
        }

        isRecording = false
        recordingStartTime = nil
        isProcessing = true
        processingProgress = 0.0
        partialTranscription = ""
        transcriptionChunkInfo = ""

        do {
            // Step 1: Transcribe using selected provider (with progress for OpenAI)
            debugLog("Starting transcription with \(settings.transcriptionProvider.rawValue)...")
            processingStage = "Thinking..."
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

                        // Track chunk info internally for debugging
                        if progress.totalChunks > 1 {
                            self.transcriptionChunkInfo = "(\(progress.currentChunk)/\(progress.totalChunks))"
                        }
                    }
                }
            case .elevenlabs:
                transcription = try await elevenlabsService.transcribe(audioURL: audioURL)
            case .mistral:
                transcription = try await mistralTranscriptionService.transcribe(audioURL: audioURL)
            case .doubao:
                throw WhisperError.emptyRecording // Doubao is streaming-only; non-streaming path shouldn't reach here
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
                lastNotice = nil
            } else {
                // Direct insert
                debugLog("Inserting text...")
                streamOutput("\n--- Inserting at cursor ---")
                processingProgress = 0.95
                try await textInserter.insert(text: finalText)
                debugLog("Text inserted successfully")
                streamOutput("Done!\n")
                processingProgress = 1.0

                lastError = nil
                lastNotice = nil

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
            let isEmptyRecording: Bool
            if case WhisperError.emptyRecording = error { isEmptyRecording = true }
            else if case MistralTranscriptionError.emptyRecording = error { isEmptyRecording = true }
            else { isEmptyRecording = false }

            if isEmptyRecording {
                lastNotice = error.localizedDescription
            } else {
                lastError = error.localizedDescription
            }
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
        if shouldUseStreaming {
            streamingCapture?.stop()
            streamingCapture = nil
            streamingEventTask?.cancel()
            streamingEventTask = nil
            if let service = streamingService {
                streamingService = nil
                Task { await service.disconnect() }
            }
        } else {
            audioRecorder.cancelRecording()
        }
        isRecording = false
        recordingStartTime = nil
        partialTranscription = ""
    }
}
