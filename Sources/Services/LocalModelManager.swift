import Foundation

enum LocalModelInstallPhase: Equatable, Sendable {
    case preparing
    case downloading(Double?)
    case loading

    static func downloading(_ progress: Progress) -> Self {
        // Snapshot progress has weighted children. The parent's completed unit
        // count alone omits partially downloaded files.
        .downloading(progress.totalUnitCount > 0 ? progress.fractionCompleted : nil)
    }
}

@MainActor
final class LocalModelManager: ObservableObject {
    static let shared = LocalModelManager()

    typealias Installer = @MainActor (
        String, @escaping @MainActor @Sendable (LocalModelInstallPhase) -> Void
    ) async throws -> Void

    @Published private(set) var phase: LocalModelInstallPhase?
    @Published private(set) var model: LocalMLXModel?
    @Published private(set) var isRemoving = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var lastError: String?

    var isInstalling: Bool { phase != nil }

    private let installer: Installer
    private var installationID: UUID?

    init(installer: @escaping Installer = { modelID, report in
        try await MLXAudioRunner.installModel(modelID: modelID, onProgress: report)
    }) {
        self.installer = installer
    }

    func installSelectedModel(settings: Settings = .shared) async {
        guard !isInstalling, !isRemoving, !settings.selectedLocalModelInstalled else { return }
        // Settings can change while awaiting the download. Keep the target fixed.
        let selectedModel = settings.localMLXModel
        let id = UUID()
        installationID = id
        model = selectedModel
        phase = .preparing
        statusMessage = nil
        lastError = nil
        defer {
            installationID = nil
            phase = nil
        }

        do {
            try await installer(selectedModel.repoID) { [weak self] phase in
                guard let self, self.installationID == id else { return }
                let normalized: LocalModelInstallPhase
                if case .downloading(let fraction) = phase {
                    normalized = .downloading(fraction.flatMap {
                        $0.isFinite ? min(max($0, 0), 1) : nil
                    })
                } else {
                    normalized = phase
                }
                if self.phase != normalized { self.phase = normalized }
            }

            if !settings.localMLXInstalledModels.contains(selectedModel.rawValue) {
                settings.localMLXInstalledModels.append(selectedModel.rawValue)
            }
            statusMessage = "Installed \(selectedModel.rawValue)"
        } catch {
            statusMessage = nil
            lastError = "Failed to install local model files: \(error.localizedDescription)"
        }
    }

    func removeSelectedModel(settings: Settings = .shared) {
        guard !isInstalling, !isRemoving, settings.selectedLocalModelInstalled else { return }
        model = settings.localMLXModel
        isRemoving = true
        defer { isRemoving = false }

        MLXAudioRunner.removeModel(modelID: settings.localMLXModel.repoID)
        settings.localMLXInstalledModels.removeAll { $0 == settings.localMLXModel.rawValue }
        statusMessage = "Removed \(settings.localMLXModel.rawValue)"
        lastError = nil
    }
}

enum LocalModelInstallError: LocalizedError {
    case generic(String)

    var errorDescription: String? {
        switch self {
        case .generic(let message):
            return message
        }
    }
}
