import AVFoundation
import Foundation

class StreamingAudioCapture {
    private var engine: AVAudioEngine?
    private var onChunk: ((Data) -> Void)?

    private let targetSampleRate: Double = 16000

    func start(onChunk: @escaping (Data) -> Void) throws {
        self.onChunk = onChunk
        let engine = AVAudioEngine()
        self.engine = engine

        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        debugLog("StreamingAudioCapture native format: \(nativeFormat)")

        let nativeSR = nativeFormat.sampleRate
        let nativeChannels = max(1, Int(nativeFormat.channelCount))
        let downsampleRatio = max(1, Int(nativeSR / targetSampleRate))

        // Tap in native format — passing nil lets the system use the hardware format
        inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(nativeSR * 0.1), format: nil) { [weak self] buffer, _ in
            guard let self = self else { return }

            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }

            let channelCount = Int(buffer.format.channelCount)
            let isInterleaved = buffer.format.isInterleaved

            let outputFrameCount = frameCount / downsampleRatio
            guard outputFrameCount > 0 else { return }

            var int16Data = Data(count: outputFrameCount * 2)
            int16Data.withUnsafeMutableBytes { rawBuf in
                let int16Buf = rawBuf.bindMemory(to: Int16.self)

                if isInterleaved {
                    // Interleaved: samples are [ch0 ch1 ch2 ch0 ch1 ch2 ...]
                    guard let floatData = buffer.floatChannelData?[0] else { return }
                    for i in 0..<outputFrameCount {
                        let srcFrame = i * downsampleRatio
                        var sum: Float = 0
                        for ch in 0..<channelCount {
                            sum += floatData[srcFrame * channelCount + ch]
                        }
                        let sample = sum / Float(channelCount)
                        let clamped = max(-1.0, min(1.0, sample))
                        int16Buf[i] = Int16(clamped * 32767.0)
                    }
                } else {
                    // Deinterleaved: each channel is a separate buffer
                    guard let floatChannels = buffer.floatChannelData else { return }
                    for i in 0..<outputFrameCount {
                        let srcIdx = i * downsampleRatio
                        var sum: Float = 0
                        for ch in 0..<channelCount {
                            sum += floatChannels[ch][srcIdx]
                        }
                        let sample = sum / Float(channelCount)
                        let clamped = max(-1.0, min(1.0, sample))
                        int16Buf[i] = Int16(clamped * 32767.0)
                    }
                }
            }

            self.onChunk?(int16Data)
        }

        engine.prepare()
        try engine.start()
        debugLog("StreamingAudioCapture started (channels=\(nativeChannels), downsample=\(downsampleRatio), interleaved=\(nativeFormat.isInterleaved))")
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        onChunk = nil
    }
}

enum StreamingAudioCaptureError: LocalizedError {
    case converterCreationFailed

    var errorDescription: String? {
        switch self {
        case .converterCreationFailed:
            return "Failed to create audio format converter"
        }
    }
}
