import Foundation

@MainActor
final class LocalModelManager: ObservableObject {
    @Published var isInstalling = false
    @Published var isRemoving = false
    @Published var statusMessage: String?
    @Published var lastError: String?

    func installSelectedModel(settings: Settings = .shared) async {
        guard !settings.selectedLocalModelInstalled else { return }
        isInstalling = true
        statusMessage = nil
        lastError = nil
        defer { isInstalling = false }

        do {
            statusMessage = "Downloading native model snapshot..."
            try await MLXAudioRunner.installModel(modelID: settings.localMLXModel.repoID)

            if !settings.localMLXInstalledModels.contains(settings.localMLXModel.rawValue) {
                settings.localMLXInstalledModels.append(settings.localMLXModel.rawValue)
            }
            statusMessage = "Installed \(settings.localMLXModel.rawValue)"
        } catch {
            statusMessage = nil
            lastError = "Failed to install local model files: \(error.localizedDescription)"
        }
    }

    func removeSelectedModel(settings: Settings = .shared) {
        guard settings.selectedLocalModelInstalled else { return }
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
