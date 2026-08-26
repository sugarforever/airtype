#if canImport(Airtype)
import XCTest
import Network
import HuggingFace
import MLXAudioCore
@testable import Airtype

final class ModelDownloadProgressTests: XCTestCase {
    @MainActor
    func testSnapshotReportsChangingPercentagesBeforeWeightDownloadFinishes() async throws {
        let server = try SlowModelServer()
        let host = try await server.start()
        defer { server.stop() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = ModelDownloadProgressDelegate.makeSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let cache = HubCache(cacheDirectory: root)
        let client = HubClient(session: session, host: host, cache: cache)
        var percentagesDuringTransfer = Set<Int>()
        var lastFraction = 0.0

        let directory = try await ModelUtils.resolveOrDownloadModel(
            client: client,
            cache: cache,
            repoID: "test/Qwen3-ASR-fixture",
            requiredExtension: "safetensors",
            progressHandler: { progress in
                let fraction = progress.fractionCompleted
                lastFraction = fraction
                if !server.weightsFinished, fraction > 0.05, fraction < 0.95 {
                    percentagesDuringTransfer.insert(Int(fraction * 100))
                }
            }
        )

        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("model.safetensors")).count, 4 * 1024 * 1024)
        XCTAssertGreaterThanOrEqual(percentagesDuringTransfer.count, 3,
            "Real HTTP transfer must report distinct intermediate percentages, not just repeat 0% then finish")
        XCTAssertEqual(lastFraction, 1, accuracy: 0.0001)
    }
}

/// Loopback HTTP fixture: real sockets, HEAD metadata, a CDN-style redirect, and
/// delayed weight chunks. All mutable server state is confined to `queue`.
private final class SlowModelServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "airtype.slow-model-server")
    private let listener: NWListener
    private var connections: [NWConnection] = []
    private var finished = false
    private let weightSize = 4 * 1024 * 1024

    var weightsFinished: Bool { queue.sync { finished } }

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> URL {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            self.connections.append(connection)
            connection.start(queue: self.queue)
            self.receive(connection, accumulated: Data())
        }
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(returning: URL(string: "http://127.0.0.1:\(self.listener.port!.rawValue)")!)
                case .failed(let error):
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        queue.sync {
            listener.cancel()
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            guard let self, error == nil, let data else { connection.cancel(); return }
            let request = accumulated + data
            guard String(decoding: request, as: UTF8.self).contains("\r\n\r\n") else {
                if complete { connection.cancel() } else { self.receive(connection, accumulated: request) }
                return
            }
            self.respond(connection, request: String(decoding: request, as: UTF8.self))
        }
    }

    private func respond(_ connection: NWConnection, request: String) {
        let line = request.components(separatedBy: "\r\n")[0].split(separator: " ")
        guard line.count >= 2 else { connection.cancel(); return }
        let method = line[0]
        let path = String(line[1])
        let isWeights = path.hasSuffix("model.safetensors") || path == "/cdn/weights"
        let commit = String(repeating: "a", count: 40)
        if method == "HEAD" {
            let size = isWeights ? weightSize : 2
            send(connection, data: Data("HTTP/1.1 200 OK\r\nContent-Length: \(size)\r\nETag: \"\(isWeights ? "weights" : "config")\"\r\nX-Repo-Commit: \(commit)\r\nConnection: close\r\n\r\n".utf8))
        } else if path.contains("/tree/") {
            let body = Data("[{\"path\":\"config.json\",\"type\":\"file\",\"oid\":\"config\",\"size\":2},{\"path\":\"model.safetensors\",\"type\":\"file\",\"oid\":\"weights\",\"size\":\(weightSize)}]".utf8)
            send(connection, data: response(body))
        } else if path.hasSuffix("model.safetensors") {
            send(connection, data: Data("HTTP/1.1 302 Found\r\nLocation: /cdn/weights\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8))
        } else if path == "/cdn/weights" {
            let header = Data("HTTP/1.1 200 OK\r\nContent-Length: \(weightSize)\r\nConnection: close\r\n\r\n".utf8)
            connection.send(content: header, completion: .contentProcessed { [weak self] error in
                guard error == nil else { connection.cancel(); return }
                self?.sendWeightChunk(connection, remaining: 64)
            })
        } else {
            send(connection, data: response(Data("{}".utf8)))
        }
    }

    private func response(_ body: Data) -> Data {
        Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8) + body
    }

    private func send(_ connection: NWConnection, data: Data) {
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func sendWeightChunk(_ connection: NWConnection, remaining: Int) {
        guard remaining > 0 else { finished = true; connection.cancel(); return }
        connection.send(content: Data(repeating: 0xAB, count: 64 * 1024), completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else { connection.cancel(); return }
            self.queue.asyncAfter(deadline: .now() + .milliseconds(40)) { [weak self] in
                self?.sendWeightChunk(connection, remaining: remaining - 1)
            }
        })
    }
}
#endif
