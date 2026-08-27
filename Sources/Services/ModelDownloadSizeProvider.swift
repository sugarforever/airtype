import Foundation
import HuggingFace

struct RemoteModelFile: Equatable, Sendable {
    let path: String
    let size: Int64?
}

struct ModelDownloadSizeEstimate: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case remote
        case catalogFallback
    }

    let bytes: Int64
    let source: Source
}

actor ModelDownloadSizeProvider {
    typealias MetadataLoader = @Sendable (String) async throws -> [RemoteModelFile]

    static let shared = ModelDownloadSizeProvider()

    private static let downloadedExtensions: Set<String> = [
        "safetensors", "json", "txt", "wav"
    ]

    private let metadataLoader: MetadataLoader
    private var cache: [LocalMLXModel: ModelDownloadSizeEstimate] = [:]

    init(metadataLoader: @escaping MetadataLoader) {
        self.metadataLoader = metadataLoader
    }

    init() {
        self.metadataLoader = { repoID in
            try await ModelDownloadSizeProvider.loadRemoteFiles(repoID: repoID)
        }
    }

    func estimate(for model: LocalMLXModel) async -> ModelDownloadSizeEstimate {
        if let cached = cache[model] {
            return cached
        }

        let estimate: ModelDownloadSizeEstimate
        do {
            let files = try await metadataLoader(model.repoID)
            let bytes = files.reduce(into: Int64.zero) { total, file in
                guard Self.downloadedExtensions.contains(
                    URL(fileURLWithPath: file.path).pathExtension.lowercased()
                ), let size = file.size else { return }
                total += size
            }
            estimate = bytes > 0
                ? .init(bytes: bytes, source: .remote)
                : .init(bytes: model.catalogDownloadSizeBytes, source: .catalogFallback)
        } catch {
            estimate = .init(bytes: model.catalogDownloadSizeBytes, source: .catalogFallback)
        }

        cache[model] = estimate
        return estimate
    }

    private static func loadRemoteFiles(repoID: String) async throws -> [RemoteModelFile] {
        guard let id = Repo.ID(rawValue: repoID) else {
            throw LocalModelInstallError.generic("Invalid repository ID: \(repoID)")
        }
        let model = try await HubClient.default.getModel(id, filesMetadata: true)
        return model.siblings?.map {
            RemoteModelFile(path: $0.relativeFilename, size: $0.size.map(Int64.init))
        } ?? []
    }
}
