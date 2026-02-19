import Foundation
import Compression

actor DoubaoStreamingService: StreamingTranscriptionService {
    private let appId: String
    private let accessKey: String
    private let resourceId: String
    private let language: String

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var continuation: AsyncStream<StreamingTranscriptionEvent>.Continuation?
    private var receiveTask: Task<Void, Never>?

    nonisolated let events: AsyncStream<StreamingTranscriptionEvent>
    /// Timestamp of when `connect()` completed (for staleness checks)
    private(set) var connectedAt: Date?

    init(appId: String, accessKey: String, resourceId: String, language: String = "zh-CN") {
        self.appId = appId
        self.accessKey = accessKey
        self.resourceId = resourceId
        self.language = language

        var cont: AsyncStream<StreamingTranscriptionEvent>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    /// Open the WebSocket transport only (no init message sent).
    /// Safe for pre-connecting — the server won't start its audio timeout.
    func connect() async throws {
        let endpoint = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"
        guard let url = URL(string: endpoint) else {
            throw DoubaoError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(appId, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessKey, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Api-Connect-Id")

        debugLog("Doubao connecting to \(endpoint) with appId=\(appId), resourceId=\(resourceId)")

        let session = URLSession(configuration: .default)
        self.session = session
        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()
        connectedAt = Date()

        schedulePing()
    }

    /// Send the init message and start listening for responses.
    /// Call this when recording actually begins (right before sending audio).
    func startSession() async throws {
        try await sendInitMessage()
        debugLog("Doubao init message sent")
        startReceiveLoop()
    }

    func sendAudio(_ data: Data) {
        let frame = buildClientFrame(messageType: 0x02, flags: 0x00, serialization: 0x00, compression: 0x00, payload: data)
        webSocketTask?.send(.data(frame)) { [weak self] error in
            if let error = error {
                debugLog("Doubao sendAudio error: \(error)")
                Task { await self?.surfaceSendError(error) }
            }
        }
    }

    private func surfaceSendError(_ error: Error) {
        continuation?.yield(.error(error))
    }

    func endAudio() async throws {
        let frame = buildClientFrame(messageType: 0x02, flags: 0x02, serialization: 0x00, compression: 0x00, payload: Data())
        try await webSocketTask?.send(.data(frame))
        debugLog("Doubao sent end-of-audio")
    }

    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        continuation?.finish()
        connectedAt = nil
    }

    /// Returns true if the connection was established more than `maxAge` seconds ago
    func isStale(maxAge: TimeInterval = 30) -> Bool {
        guard let connectedAt else { return true }
        return Date().timeIntervalSince(connectedAt) > maxAge
    }

    // MARK: - Binary Protocol (SeedASR 2.0)

    private func buildClientFrame(messageType: UInt8, flags: UInt8, serialization: UInt8, compression: UInt8, payload: Data) -> Data {
        var frame = Data()
        frame.append(0x11)
        frame.append((messageType << 4) | flags)
        frame.append((serialization << 4) | compression)
        frame.append(0x00)
        var size = UInt32(payload.count).bigEndian
        frame.append(Data(bytes: &size, count: 4))
        frame.append(payload)
        return frame
    }

    private func sendInitMessage() async throws {
        let config: [String: Any] = [
            "user": ["uid": appId],
            "audio": [
                "format": "pcm",
                "rate": 16000,
                "bits": 16,
                "channel": 1,
                "language": language,
            ],
            "request": [
                "model_name": "bigmodel",
                "show_utterances": true,
                "result_type": "single",
            ],
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: config)
        debugLog("Doubao init JSON: \(String(data: jsonData, encoding: .utf8) ?? "")")
        let compressed = try gzipCompress(jsonData)

        let frame = buildClientFrame(messageType: 0x01, flags: 0x00, serialization: 0x01, compression: 0x01, payload: compressed)
        try await webSocketTask?.send(.data(frame))
    }

    // MARK: - Receive

    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard let task = await self.webSocketTask else { return }
                do {
                    let message = try await task.receive()
                    switch message {
                    case .data(let data):
                        await self.handleServerMessage(data)
                    case .string(let text):
                        debugLog("Doubao text message: \(text)")
                    @unknown default:
                        break
                    }
                } catch {
                    if !Task.isCancelled {
                        debugLog("Doubao receive error: \(error)")
                        await self.surfaceSendError(error)
                        await self.finishContinuation()
                    }
                    return
                }
            }
        }
    }

    private func finishContinuation() {
        continuation?.finish()
    }

    // MARK: - Ping / Keepalive

    private func schedulePing() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000) // 15s
                guard let self else { return }
                guard let task = await self.webSocketTask else { return }
                task.sendPing { error in
                    if let error {
                        debugLog("Doubao ping error: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Server Message Handling

    private func handleServerMessage(_ data: Data) {
        guard data.count >= 4 else { return }

        let headerHex = data.prefix(min(16, data.count)).map { String(format: "%02x", $0) }.joined(separator: " ")
        debugLog("Doubao raw header (\(data.count) bytes): \(headerHex)")

        let messageType = (data[1] >> 4) & 0x0F

        if messageType == 0x0F {
            if data.count > 12 {
                let errorBody = String(data: data[12...], encoding: .utf8) ?? "Unknown error"
                debugLog("Doubao server error: \(errorBody)")
                continuation?.yield(.error(DoubaoError.serverError(errorBody)))
            }
            return
        }

        let flags = data[1] & 0x0F
        let payloadOffset = flags == 0 ? 8 : 12
        guard data.count > payloadOffset else { return }
        let payloadData = Data(data[payloadOffset...])

        let compression = data[2] & 0x0F
        let jsonData: Data
        if compression == 0x01 {
            guard let decompressed = try? gzipDecompress(payloadData) else {
                debugLog("Doubao failed to decompress response")
                return
            }
            jsonData = decompressed
        } else {
            jsonData = payloadData
        }

        guard let text = String(data: jsonData, encoding: .utf8) else { return }
        debugLog("Doubao response: \(text)")

        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return }

        if let payloadMsg = json["payload_msg"] as? [String: Any],
           let result = payloadMsg["result"] as? [String: Any],
           let utterances = result["utterances"] as? [[String: Any]] {
            emitUtterances(utterances)
            return
        }

        if let result = json["result"] as? [String: Any],
           let utterances = result["utterances"] as? [[String: Any]] {
            emitUtterances(utterances)
            return
        }

        if let utterances = json["utterances"] as? [[String: Any]] {
            emitUtterances(utterances)
            return
        }

        if let result = json["result"] as? [String: Any],
           let resultText = result["text"] as? String, !resultText.isEmpty {
            continuation?.yield(.partial(resultText))
        }
    }

    private func emitUtterances(_ utterances: [[String: Any]]) {
        for utterance in utterances {
            guard let text = utterance["text"] as? String, !text.isEmpty else { continue }
            let definite = utterance["definite"] as? Bool ?? false
            if definite {
                continuation?.yield(.final_(text))
            } else {
                continuation?.yield(.partial(text))
            }
        }
    }

    // MARK: - Gzip

    private static let crc32Table: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1 != 0) ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    private func gzipCompress(_ data: Data) throws -> Data {
        var compressed = Data()
        compressed.append(contentsOf: [0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03])
        let deflated = try deflate(data)
        compressed.append(deflated)
        var crc = Self.crc32Checksum(data)
        compressed.append(Data(bytes: &crc, count: 4))
        var sz = UInt32(data.count).littleEndian
        compressed.append(Data(bytes: &sz, count: 4))
        return compressed
    }

    private func deflate(_ data: Data) throws -> Data {
        let bufferSize = max(256, data.count * 2)
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { dst.deallocate() }
        let result = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Data? in
            guard let src = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            let n = compression_encode_buffer(dst, bufferSize, src, data.count, nil, COMPRESSION_ZLIB)
            guard n > 0 else { return nil }
            return Data(bytes: dst, count: n)
        }
        guard let result else { throw DoubaoError.compressionFailed }
        return result
    }

    private func gzipDecompress(_ data: Data) throws -> Data {
        guard data.count > 10 else { throw DoubaoError.decompressionFailed }
        var offset = 10
        let flags = data[3]
        if flags & 0x04 != 0 {
            guard data.count > offset + 2 else { throw DoubaoError.decompressionFailed }
            let extraLen = Int(data[offset]) | (Int(data[offset + 1]) << 8)
            offset += 2 + extraLen
        }
        if flags & 0x08 != 0 { while offset < data.count && data[offset] != 0 { offset += 1 }; offset += 1 }
        if flags & 0x10 != 0 { while offset < data.count && data[offset] != 0 { offset += 1 }; offset += 1 }
        if flags & 0x02 != 0 { offset += 2 }

        let compressedData = data.subdata(in: offset..<max(offset, data.count - 8))

        // Progressive decompression: try increasing buffer sizes
        var bufferSize = max(256, compressedData.count * 4)
        for _ in 0..<4 {
            let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { dst.deallocate() }
            let n = compressedData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
                guard let src = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                return compression_decode_buffer(dst, bufferSize, src, compressedData.count, nil, COMPRESSION_ZLIB)
            }
            if n > 0 && n < bufferSize {
                return Data(bytes: dst, count: n)
            }
            bufferSize *= 4
        }
        throw DoubaoError.decompressionFailed
    }

    private static func crc32Checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data { crc = crc32Table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFFFFFF
    }
}

enum DoubaoError: LocalizedError {
    case invalidURL
    case serverError(String)
    case compressionFailed
    case decompressionFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Doubao WebSocket URL"
        case .serverError(let msg): return "Doubao error: \(msg)"
        case .compressionFailed: return "Failed to compress data"
        case .decompressionFailed: return "Failed to decompress data"
        }
    }
}
