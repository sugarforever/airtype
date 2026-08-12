import Foundation

protocol LocalASRAdapter {
    func transcribe(
        audioURL: URL,
        language: LocalMLXLanguage,
        computeMode: LocalMLXComputeMode
    ) async throws -> String
}
