import AVFoundation
import Foundation

/// Handles microphone audio recording with level monitoring
@MainActor
class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var hasPermission = false
    @Published var errorMessage: String?

    // Audio level monitoring for visual feedback
    @Published var audioLevel: Float = 0.0  // 0.0 to 1.0 normalized
    @Published var peakLevel: Float = 0.0   // Peak level for visual indicator

    // Recording duration tracking
    @Published var recordingDuration: TimeInterval = 0.0
    @Published var recordingStartTime: Date?

    // File size tracking (for chunking decisions)
    @Published var estimatedFileSize: Int64 = 0

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var levelTimer: Timer?
    private var durationTimer: Timer?

    // Constants
    private let maxFileSizeBytes: Int64 = 24 * 1024 * 1024  // 24MB (leave buffer below 25MB limit)
    private let levelUpdateInterval: TimeInterval = 0.05    // 50ms for smooth animation

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
        let fileName = "airtype_recording_\(Date().timeIntervalSince1970).m4a"
        let url = tempDir.appendingPathComponent(fileName)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.isMeteringEnabled = true  // Enable audio level metering
            audioRecorder?.record()
            recordingURL = url
            isRecording = true

            // Reset and start tracking
            recordingDuration = 0.0
            recordingStartTime = Date()
            audioLevel = 0.0
            peakLevel = 0.0
            estimatedFileSize = 0

            // Start level monitoring timer
            startLevelMonitoring()

            return url
        } catch {
            throw RecordingError.setupFailed(error.localizedDescription)
        }
    }

    // MARK: - Level Monitoring

    private func startLevelMonitoring() {
        // Use a timer to poll audio levels
        levelTimer = Timer.scheduledTimer(withTimeInterval: levelUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateLevels()
            }
        }

        // Duration timer (updates every second)
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateDuration()
            }
        }
    }

    private func stopLevelMonitoring() {
        levelTimer?.invalidate()
        levelTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func updateLevels() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }

        recorder.updateMeters()

        // Get average and peak power (in dB, typically -160 to 0)
        let avgPower = recorder.averagePower(forChannel: 0)
        let peakPower = recorder.peakPower(forChannel: 0)

        // Normalize to 0.0-1.0 range (dB to linear)
        // -60dB = silence, 0dB = max
        audioLevel = normalizeDecibels(avgPower)
        peakLevel = normalizeDecibels(peakPower)

        // Update estimated file size
        if let url = recordingURL,
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            estimatedFileSize = size
        }
    }

    private func updateDuration() {
        guard let startTime = recordingStartTime else { return }
        recordingDuration = Date().timeIntervalSince(startTime)
    }

    /// Convert decibels to normalized 0.0-1.0 range
    private func normalizeDecibels(_ db: Float) -> Float {
        // Clamp to reasonable range
        let minDb: Float = -60.0
        let maxDb: Float = 0.0
        let clampedDb = max(minDb, min(maxDb, db))

        // Linear interpolation
        return (clampedDb - minDb) / (maxDb - minDb)
    }

    /// Check if recording is approaching file size limit
    var isApproachingLimit: Bool {
        estimatedFileSize > (maxFileSizeBytes - 2 * 1024 * 1024)  // 2MB buffer
    }

    /// Check if recording has exceeded safe duration (estimate: ~10 minutes at 16kHz mono AAC)
    var isLongRecording: Bool {
        recordingDuration > 300  // 5 minutes
    }

    /// Formatted duration string (MM:SS)
    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func stopRecording() -> URL? {
        stopLevelMonitoring()
        audioRecorder?.stop()
        isRecording = false
        audioLevel = 0.0
        peakLevel = 0.0
        let url = recordingURL
        recordingURL = nil
        return url
    }

    func cancelRecording() {
        stopLevelMonitoring()
        audioRecorder?.stop()
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        isRecording = false
        audioLevel = 0.0
        peakLevel = 0.0
        recordingDuration = 0.0
    }

    // MARK: - Cleanup
    func cleanupRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

enum RecordingError: LocalizedError {
    case noPermission
    case setupFailed(String)
    case recordingTooShort
    case recordingFailed
    case microphoneInUse

    var errorDescription: String? {
        switch self {
        case .noPermission:
            return "Microphone access required. Please enable in System Settings → Privacy & Security → Microphone."
        case .setupFailed(let reason):
            return "Failed to start recording: \(reason)"
        case .recordingTooShort:
            return "Recording too short. Please speak for longer."
        case .recordingFailed:
            return "Recording failed. Please try again."
        case .microphoneInUse:
            return "Microphone is in use by another app. Please close other recording apps."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noPermission:
            return "Open System Settings and grant microphone access to Airtype."
        case .setupFailed:
            return "Try closing other apps that may be using the microphone."
        case .recordingTooShort:
            return "Hold the shortcut key longer while speaking."
        case .recordingFailed:
            return "Check that your microphone is connected and working."
        case .microphoneInUse:
            return "Close apps like Zoom, Teams, or other recording software."
        }
    }
}
