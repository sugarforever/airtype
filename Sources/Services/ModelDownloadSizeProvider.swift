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
    private var inFlight: [LocalMLXModel: Task<ModelDownloadSizeEstimate, Never>] = [:]

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
        if let task = inFlight[model] {
            return await task.value
        }

        let loader = metadataLoader
        let task = Task {
            do {
                let files = try await loader(model.repoID)
                return Self.remoteEstimate(from: files)
                    ?? .init(bytes: model.catalogDownloadSizeBytes, source: .catalogFallback)
            } catch {
                return .init(bytes: model.catalogDownloadSizeBytes, source: .catalogFallback)
            }
        }
        inFlight[model] = task
        let estimate = await task.value
        inFlight[model] = nil
        cache[model] = estimate
        return estimate
    }

    private static func remoteEstimate(from files: [RemoteModelFile]) -> ModelDownloadSizeEstimate? {
        let downloadedFiles = files.filter {
            downloadedExtensions.contains(
                URL(fileURLWithPath: $0.path).pathExtension.lowercased()
            )
        }
        guard !downloadedFiles.isEmpty else { return nil }

        var bytes: Int64 = 0
        for file in downloadedFiles {
            guard let size = file.size, size > 0 else { return nil }
            let addition = bytes.addingReportingOverflow(size)
            guard !addition.overflow else { return nil }
            bytes = addition.partialValue
        }
        return .init(bytes: bytes, source: .remote)
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
