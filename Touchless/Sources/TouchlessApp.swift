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

@main
struct TouchlessApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            MenuBarIcon(isRecording: appState.isRecording, isProcessing: appState.isProcessing)
        }
        .menuBarExtraStyle(.window)
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
                .foregroundColor(iconColor)
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
    @Published var lastError: String?

    let settings = Settings.shared
    let audioRecorder = AudioRecorder()
    let whisperService = WhisperService()
    let elevenlabsService = ElevenLabsService()
    let textInserter = TextInserter()
    let hotkeyManager = HotkeyManager()

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

        // Check file size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: audioURL.path),
           let size = attrs[.size] as? Int64 {
            debugLog("Audio file size: \(size) bytes")
        }

        isRecording = false
        isProcessing = true

        do {
            // Step 1: Transcribe using selected provider (with streaming for OpenAI)
            debugLog("Starting transcription with \(settings.transcriptionProvider.rawValue)...")
            processingStage = "Transcribing..."
            let transcription: String
            switch settings.transcriptionProvider {
            case .openai:
                transcription = try await whisperService.transcribeStreaming(audioURL: audioURL) { [weak self] partialText in
                    Task { @MainActor in
                        self?.processingStage = partialText.isEmpty ? "Transcribing..." : partialText
                    }
                }
            case .elevenlabs:
                transcription = try await elevenlabsService.transcribe(audioURL: audioURL)
            }
            debugLog("Transcription result: \(transcription)")

            let finalText = transcription

            // Step 3: Insert at cursor
            debugLog("Inserting text...")
            processingStage = "Inserting..."
            try await textInserter.insert(text: finalText)
            debugLog("Text inserted successfully")

            lastError = nil
        } catch {
            debugLog("Error: \(error)")
            lastError = error.localizedDescription
        }

        // Cleanup
        audioRecorder.cleanupRecording(at: audioURL)
        isProcessing = false
        processingStage = ""
        debugLog("Processing complete")
    }

    func cancelRecording() {
        audioRecorder.cancelRecording()
        isRecording = false
    }
}
