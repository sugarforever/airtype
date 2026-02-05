import Foundation
import AVFoundation

/// OpenAI Whisper/GPT-4o API service for speech-to-text
class WhisperService {
    private let settings: Settings

    // Constants for chunking
    private let maxFileSizeBytes: Int64 = 24 * 1024 * 1024  // 24MB (buffer below 25MB limit)
    private let targetChunkDuration: TimeInterval = 120     // 2 minutes per chunk for safety

    init(settings: Settings = .shared) {
        self.settings = settings
    }

    // MARK: - Progress Callback Types

    struct TranscriptionProgress {
        let stage: TranscriptionStage
        let currentChunk: Int
        let totalChunks: Int
        let partialText: String
        let progress: Double  // 0.0 to 1.0

        enum TranscriptionStage: String {
            case preparing = "Preparing audio..."
            case transcribing = "Transcribing..."
            case combining = "Combining results..."
            case complete = "Complete"
        }
    }

    /// Transcribe audio file with progress callback
    /// Automatically chunks long recordings for better UX and to stay within API limits
    func transcribeWithProgress(
        audioURL: URL,
        onProgress: @escaping (TranscriptionProgress) -> Void
    ) async throws -> String {
        // Check file size to determine if chunking is needed
        let fileSize = try getFileSize(url: audioURL)
        let duration = try await getAudioDuration(url: audioURL)

        debugLog("WhisperService: File size: \(fileSize) bytes, duration: \(duration)s")

        // Determine if we need to chunk
        let needsChunking = fileSize > maxFileSizeBytes || duration > targetChunkDuration * 2

        if needsChunking {
            return try await transcribeChunked(audioURL: audioURL, duration: duration, onProgress: onProgress)
        } else {
            // Single file transcription with progress
            onProgress(TranscriptionProgress(
                stage: .transcribing,
                currentChunk: 1,
                totalChunks: 1,
                partialText: "",
                progress: 0.1
            ))

            let result = try await transcribe(audioURL: audioURL)

            onProgress(TranscriptionProgress(
                stage: .complete,
                currentChunk: 1,
                totalChunks: 1,
                partialText: result,
                progress: 1.0
            ))

            return result
        }
    }

    /// Legacy streaming method - now uses progress-based approach
    func transcribeStreaming(
        audioURL: URL,
        onPartialResult: @escaping (String) -> Void
    ) async throws -> String {
        return try await transcribeWithProgress(audioURL: audioURL) { progress in
            if !progress.partialText.isEmpty {
                onPartialResult(progress.partialText)
            }
        }
    }

    // MARK: - Chunked Transcription

    /// Transcribe long audio by splitting into chunks
    private func transcribeChunked(
        audioURL: URL,
        duration: TimeInterval,
        onProgress: @escaping (TranscriptionProgress) -> Void
    ) async throws -> String {
        // Calculate number of chunks
        let chunkCount = Int(ceil(duration / targetChunkDuration))
        debugLog("WhisperService: Splitting into \(chunkCount) chunks")

        onProgress(TranscriptionProgress(
            stage: .preparing,
            currentChunk: 0,
            totalChunks: chunkCount,
            partialText: "",
            progress: 0.05
        ))

        // Split audio into chunks
        let chunkURLs = try await splitAudioIntoChunks(
            audioURL: audioURL,
            duration: duration,
            chunkDuration: targetChunkDuration
        )

        var transcriptions: [String] = []
        var accumulatedText = ""

        // Transcribe each chunk
        for (index, chunkURL) in chunkURLs.enumerated() {
            let chunkNumber = index + 1
            let progressValue = Double(index) / Double(chunkCount) * 0.9 + 0.05

            onProgress(TranscriptionProgress(
                stage: .transcribing,
                currentChunk: chunkNumber,
                totalChunks: chunkCount,
                partialText: accumulatedText,
                progress: progressValue
            ))

            do {
                let chunkText = try await transcribe(audioURL: chunkURL)
                transcriptions.append(chunkText)
                accumulatedText = transcriptions.joined(separator: " ")

                // Update with new text
                onProgress(TranscriptionProgress(
                    stage: .transcribing,
                    currentChunk: chunkNumber,
                    totalChunks: chunkCount,
                    partialText: accumulatedText,
                    progress: progressValue + (0.9 / Double(chunkCount))
                ))
            } catch {
                debugLog("WhisperService: Chunk \(chunkNumber) failed: \(error)")
                // Continue with other chunks, don't fail entirely
                transcriptions.append("[transcription error]")
            }

            // Cleanup chunk file
            try? FileManager.default.removeItem(at: chunkURL)
        }

        // Combine results
        onProgress(TranscriptionProgress(
            stage: .combining,
            currentChunk: chunkCount,
            totalChunks: chunkCount,
            partialText: accumulatedText,
            progress: 0.95
        ))

        let finalText = transcriptions.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        onProgress(TranscriptionProgress(
            stage: .complete,
            currentChunk: chunkCount,
            totalChunks: chunkCount,
            partialText: finalText,
            progress: 1.0
        ))

        return finalText
    }

    // MARK: - Audio Processing Helpers

    /// Get file size in bytes
    private func getFileSize(url: URL) throws -> Int64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attrs[.size] as? Int64 else {
            throw WhisperError.invalidAudioFile("Cannot determine file size")
        }
        return size
    }

    /// Get audio duration using AVFoundation
    private func getAudioDuration(url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }

    /// Split audio file into chunks using AVFoundation
    private func splitAudioIntoChunks(
        audioURL: URL,
        duration: TimeInterval,
        chunkDuration: TimeInterval
    ) async throws -> [URL] {
        let asset = AVURLAsset(url: audioURL)
        var chunkURLs: [URL] = []

        let chunkCount = Int(ceil(duration / chunkDuration))
        let tempDir = FileManager.default.temporaryDirectory

        for i in 0..<chunkCount {
            let startTime = Double(i) * chunkDuration
            let endTime = min(startTime + chunkDuration, duration)

            let chunkURL = tempDir.appendingPathComponent("chunk_\(i)_\(UUID().uuidString).m4a")

            try await exportAudioSegment(
                from: asset,
                startTime: startTime,
                endTime: endTime,
                to: chunkURL
            )

            chunkURLs.append(chunkURL)
        }

        return chunkURLs
    }

    /// Export a segment of audio to a new file
    private func exportAudioSegment(
        from asset: AVAsset,
        startTime: TimeInterval,
        endTime: TimeInterval,
        to outputURL: URL
    ) async throws {
        // Remove existing file if any
        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw WhisperError.audioProcessingFailed("Cannot create export session")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        let startCMTime = CMTime(seconds: startTime, preferredTimescale: 1000)
        let endCMTime = CMTime(seconds: endTime, preferredTimescale: 1000)
        exportSession.timeRange = CMTimeRange(start: startCMTime, end: endCMTime)

        await exportSession.export()

        if let error = exportSession.error {
            throw WhisperError.audioProcessingFailed(error.localizedDescription)
        }

        guard exportSession.status == .completed else {
            throw WhisperError.audioProcessingFailed("Export failed with status: \(exportSession.status.rawValue)")
        }
    }

    /// Transcribe audio file (non-streaming) with timeout and retry
    func transcribe(audioURL: URL) async throws -> String {
        guard !settings.openaiTranscriptionApiKey.isEmpty else {
            throw WhisperError.noAPIKey
        }

        // Validate audio file exists and has content
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw WhisperError.invalidAudioFile("File does not exist")
        }

        let fileSize = try getFileSize(url: audioURL)
        if fileSize < 100 {
            throw WhisperError.emptyRecording
        }

        let baseURL = "https://api.openai.com/v1"
        let url = URL(string: "\(baseURL)/audio/transcriptions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.openaiTranscriptionApiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120  // 2 minute timeout for large files

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioURL)
        let transcriptionModel = settings.openaiTranscriptionModel
        let body = createMultipartBody(
            audioData: audioData,
            fileName: audioURL.lastPathComponent,
            model: transcriptionModel,
            boundary: boundary
        )
        request.httpBody = body

        debugLog("OpenAI: Sending request with model \(transcriptionModel), file size: \(audioData.count) bytes")

        // Use URLSession with timeout configuration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 180
        let session = URLSession(configuration: config)

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw WhisperError.networkTimeout
            case .notConnectedToInternet, .networkConnectionLost:
                throw WhisperError.apiError("No internet connection. Please check your network.")
            case .cannotFindHost, .cannotConnectToHost:
                throw WhisperError.apiError("Cannot connect to OpenAI servers. Please try again.")
            default:
                throw WhisperError.apiError("Network error: \(error.localizedDescription)")
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WhisperError.invalidResponse
        }

        debugLog("OpenAI: Response status \(httpResponse.statusCode)")

        // Debug: log raw response
        if let rawResponse = String(data: data, encoding: .utf8) {
            debugLog("OpenAI: Raw response: \(rawResponse.prefix(500))")
        }

        // Handle specific HTTP error codes
        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                let message = errorResponse.error.message

                // Detect specific error types and provide helpful messages
                if message.lowercased().contains("invalid api key") ||
                   message.lowercased().contains("incorrect api key") {
                    throw WhisperError.apiError("Invalid API key. Please check your OpenAI API key in Settings.")
                }
                if message.lowercased().contains("rate limit") {
                    throw WhisperError.apiError("Rate limit exceeded. Please wait a moment and try again.")
                }
                if message.lowercased().contains("quota") || message.lowercased().contains("billing") {
                    throw WhisperError.apiError("API quota exceeded. Please check your OpenAI account billing.")
                }

                throw WhisperError.apiError(message)
            }

            // Handle common HTTP status codes
            switch httpResponse.statusCode {
            case 401:
                throw WhisperError.apiError("Invalid API key. Please check your OpenAI API key in Settings.")
            case 429:
                throw WhisperError.apiError("Rate limit exceeded. Please wait a moment and try again.")
            case 500, 502, 503:
                throw WhisperError.apiError("OpenAI server error. Please try again in a moment.")
            default:
                throw WhisperError.httpError(httpResponse.statusCode)
            }
        }

        // Log raw response for debugging
        if let rawResponse = String(data: data, encoding: .utf8) {
            print("[Whisper] Raw response: \(rawResponse)")
        }

        let transcription: TranscriptionResponse
        do {
            transcription = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        } catch {
            print("[Whisper] Failed to decode response: \(error)")
            throw WhisperError.invalidResponse
        }
        print("[Whisper] Decoded text: '\(transcription.text)'")

        // Check for empty transcription
        let text = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            throw WhisperError.emptyRecording
        }

        return text
    }

    // MARK: - Multipart Body Creation

    private func createMultipartBody(audioData: Data, fileName: String, model: String, boundary: String) -> Data {
        var body = Data()

        // Model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)

        // Audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return body
    }

}

// MARK: - Response Types

struct TranscriptionResponse: Codable {
    let text: String
}

struct TranscriptStreamEvent: Codable {
    let type: String?
    let delta: String?
    let text: String?
}

struct OpenAIErrorResponse: Codable {
    let error: OpenAIError
}

struct OpenAIError: Codable {
    let message: String
    let type: String?
    let code: String?
}

// MARK: - Errors

enum WhisperError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case invalidAudioFile(String)
    case audioProcessingFailed(String)
    case emptyRecording
    case networkTimeout
    case fileTooLarge(Int64)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "OpenAI API key not configured"
        case .invalidResponse:
            return "Invalid response from Whisper API"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "API error: \(message)"
        case .invalidAudioFile(let reason):
            return "Invalid audio file: \(reason)"
        case .audioProcessingFailed(let reason):
            return "Audio processing failed: \(reason)"
        case .emptyRecording:
            return "Recording is empty or too short"
        case .networkTimeout:
            return "Network request timed out. Please try again."
        case .fileTooLarge(let size):
            let sizeMB = Double(size) / 1024.0 / 1024.0
            return "Recording too large (\(String(format: "%.1f", sizeMB))MB). Please record a shorter segment."
        }
    }
}
