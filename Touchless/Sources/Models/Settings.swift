import Foundation
import SwiftUI

/// Supported transcription providers
enum TranscriptionProvider: String, CaseIterable, Identifiable {
    case openai = "OpenAI"
    case elevenlabs = "ElevenLabs"

    var id: String { rawValue }
}

/// Position options for the floating window
enum FloatingWindowPosition: String, CaseIterable, Identifiable {
    case topRight = "Top Right"
    case bottomRight = "Bottom Right"
    case topLeft = "Top Left"
    case bottomLeft = "Bottom Left"

    var id: String { rawValue }
}

/// App settings stored in UserDefaults
class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    // MARK: - Keys
    private enum Keys {
        static let transcriptionProvider = "transcription_provider"
        static let openaiApiKey = "openai_api_key"
        static let openaiBaseURL = "openai_base_url"
        static let elevenlabsApiKey = "elevenlabs_api_key"
        static let openaiModel = "openai_transcription_model"
        static let elevenlabsModel = "elevenlabs_transcription_model"
        static let enhancementModel = "enhancement_model"
        static let enhancementEnabled = "enhancement_enabled"
        // Floating window settings
        static let showFloatingWindow = "show_floating_window"
        static let floatingWindowPosition = "floating_window_position"
        static let previewBeforeInsert = "preview_before_insert"
    }

    // MARK: - Constants
    static let defaultOpenAIBaseURL = "https://api.openai.com/v1"

    // MARK: - Published Properties

    @Published var transcriptionProvider: TranscriptionProvider {
        didSet { defaults.set(transcriptionProvider.rawValue, forKey: Keys.transcriptionProvider) }
    }

    @Published var openaiApiKey: String {
        didSet { defaults.set(openaiApiKey, forKey: Keys.openaiApiKey) }
    }

    @Published var openaiBaseURL: String {
        didSet { defaults.set(openaiBaseURL, forKey: Keys.openaiBaseURL) }
    }

    @Published var elevenlabsApiKey: String {
        didSet { defaults.set(elevenlabsApiKey, forKey: Keys.elevenlabsApiKey) }
    }

    @Published var openaiModel: String {
        didSet { defaults.set(openaiModel, forKey: Keys.openaiModel) }
    }

    @Published var elevenlabsModel: String {
        didSet { defaults.set(elevenlabsModel, forKey: Keys.elevenlabsModel) }
    }

    @Published var enhancementModel: String {
        didSet { defaults.set(enhancementModel, forKey: Keys.enhancementModel) }
    }

    @Published var enhancementEnabled: Bool {
        didSet { defaults.set(enhancementEnabled, forKey: Keys.enhancementEnabled) }
    }

    // Floating window settings
    @Published var showFloatingWindow: Bool {
        didSet { defaults.set(showFloatingWindow, forKey: Keys.showFloatingWindow) }
    }

    @Published var floatingWindowPosition: FloatingWindowPosition {
        didSet { defaults.set(floatingWindowPosition.rawValue, forKey: Keys.floatingWindowPosition) }
    }

    @Published var previewBeforeInsert: Bool {
        didSet { defaults.set(previewBeforeInsert, forKey: Keys.previewBeforeInsert) }
    }

    // MARK: - Available Models

    static let openaiModels = [
        "gpt-4o-transcribe",
        "gpt-4o-mini-transcribe",
        "whisper-1"
    ]

    static let elevenlabsModels = [
        "scribe_v2",
        "scribe_v1"
    ]

    static let enhancementModels = [
        "gpt-4o",
        "gpt-4o-mini",
        "gpt-4o",
        "gpt-4-turbo"
    ]

    // MARK: - Initialization
    private init() {
        let providerRaw = defaults.string(forKey: Keys.transcriptionProvider) ?? TranscriptionProvider.openai.rawValue
        self.transcriptionProvider = TranscriptionProvider(rawValue: providerRaw) ?? .openai

        self.openaiApiKey = defaults.string(forKey: Keys.openaiApiKey) ?? ""
        self.openaiBaseURL = defaults.string(forKey: Keys.openaiBaseURL) ?? Settings.defaultOpenAIBaseURL
        self.elevenlabsApiKey = defaults.string(forKey: Keys.elevenlabsApiKey) ?? ""
        self.openaiModel = defaults.string(forKey: Keys.openaiModel) ?? "gpt-4o-transcribe"
        self.elevenlabsModel = defaults.string(forKey: Keys.elevenlabsModel) ?? "scribe_v2"
        self.enhancementModel = defaults.string(forKey: Keys.enhancementModel) ?? "gpt-4o"
        self.enhancementEnabled = defaults.object(forKey: Keys.enhancementEnabled) as? Bool ?? true

        // Floating window settings
        self.showFloatingWindow = defaults.object(forKey: Keys.showFloatingWindow) as? Bool ?? true
        let positionRaw = defaults.string(forKey: Keys.floatingWindowPosition) ?? FloatingWindowPosition.bottomRight.rawValue
        self.floatingWindowPosition = FloatingWindowPosition(rawValue: positionRaw) ?? .bottomRight
        self.previewBeforeInsert = defaults.object(forKey: Keys.previewBeforeInsert) as? Bool ?? false
    }

    // MARK: - Validation

    var isConfigured: Bool {
        switch transcriptionProvider {
        case .openai:
            return !openaiApiKey.isEmpty
        case .elevenlabs:
            return !elevenlabsApiKey.isEmpty && !openaiApiKey.isEmpty // Need OpenAI for enhancement
        }
    }

    var currentTranscriptionApiKey: String {
        switch transcriptionProvider {
        case .openai:
            return openaiApiKey
        case .elevenlabs:
            return elevenlabsApiKey
        }
    }

    var configurationError: String? {
        switch transcriptionProvider {
        case .openai:
            if openaiApiKey.isEmpty {
                return "OpenAI API key required"
            }
        case .elevenlabs:
            if elevenlabsApiKey.isEmpty {
                return "ElevenLabs API key required"
            }
            if openaiApiKey.isEmpty {
                return "OpenAI API key required for text enhancement"
            }
        }
        return nil
    }
}
