import AVFoundation
import Foundation

/// Handles microphone audio recording
@MainActor
class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var hasPermission = false
    @Published var errorMessage: String?

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?

    override init() {
        super.init()
        checkPermission()
    }

    // MARK: - Permission
    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            hasPermission = true
        case .notDetermined:
            requestPermission()
        case .denied, .restricted:
            hasPermission = false
            errorMessage = "Microphone access denied. Please enable in System Settings > Privacy & Security > Microphone"
        @unknown default:
            hasPermission = false
        }
    }

    private func requestPermission() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor in
                self?.hasPermission = granted
                if !granted {
                    self?.errorMessage = "Microphone access required for voice input"
                }
            }
        }
    }

    // MARK: - Recording
    func startRecording() throws -> URL {
        guard hasPermission else {
            throw RecordingError.noPermission
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "touchless_recording_\(Date().timeIntervalSince1970).m4a"
        let url = tempDir.appendingPathComponent(fileName)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            recordingURL = url
            isRecording = true
            return url
        } catch {
            throw RecordingError.setupFailed(error.localizedDescription)
        }
    }

    func stopRecording() -> URL? {
        audioRecorder?.stop()
        isRecording = false
        let url = recordingURL
        recordingURL = nil
        return url
    }

    func cancelRecording() {
        audioRecorder?.stop()
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        isRecording = false
    }

    // MARK: - Cleanup
    func cleanupRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

enum RecordingError: LocalizedError {
    case noPermission
    case setupFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPermission:
            return "Microphone permission not granted"
        case .setupFailed(let reason):
            return "Failed to start recording: \(reason)"
        }
    }
}
