import Carbon.HIToolbox
import Foundation
import HotKey
import SwiftUI

// MARK: - Transcription Provider

enum TranscriptionProvider: String, CaseIterable, Identifiable {
    case elevenlabs = "ElevenLabs"
    case openai = "OpenAI"
    case mistral = "Mistral"

    var id: String { rawValue }
}

// MARK: - Enhancement Provider (Multiple OpenAI-compatible providers)

enum EnhancementProvider: String, CaseIterable, Identifiable {
    case openai = "OpenAI"
    case openrouter = "OpenRouter"
    case togetherai = "Together AI"
    case groq = "Groq"
    case deepseek = "DeepSeek"
    case moonshot = "Moonshot AI"
    case zai = "z.ai"
    case azure = "Azure OpenAI"
    case cloudflare = "Cloudflare Workers AI"
    case lmstudio = "LM Studio (Local)"
    case custom = "Custom"

    var id: String { rawValue }

    var baseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .togetherai: return "https://api.together.xyz/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .moonshot: return "https://api.moonshot.ai/v1"
        case .zai: return "https://api.z.ai/api/paas/v4"
        case .azure: return "https://YOUR-RESOURCE.openai.azure.com"
        case .cloudflare: return "https://api.cloudflare.com/client/v4/accounts/YOUR-ACCOUNT/ai/v1"
        case .lmstudio: return "http://localhost:1234/v1"
        case .custom: return ""
        }
    }

    var requiresCustomURL: Bool {
        self == .azure || self == .cloudflare || self == .custom
    }

    var requiresApiKey: Bool {
        self != .lmstudio
    }

    var defaultModel: String {
        switch self {
        case .openai: return "gpt-4o"
        case .openrouter: return "openai/gpt-4o"
        case .togetherai: return "meta-llama/Llama-3.3-70B-Instruct-Turbo"
        case .groq: return "llama-3.3-70b-versatile"
        case .deepseek: return "deepseek-chat"
        case .moonshot: return "moonshot-v1-8k"
        case .zai: return "glm-4-plus"
        case .azure: return "gpt-4o"
        case .cloudflare: return "@cf/meta/llama-3-8b-instruct"
        case .lmstudio: return "local-model"
        case .custom: return ""
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .openai, .azure: return "sk-..."
        case .openrouter: return "sk-or-..."
        case .groq: return "gsk_..."
        case .deepseek, .moonshot: return "sk-..."
        case .togetherai, .zai, .cloudflare, .custom: return "API key..."
        case .lmstudio: return "No key needed"
        }
    }
}

// MARK: - Floating Window Position

enum FloatingWindowPosition: String, CaseIterable, Identifiable {
    case topRight = "Top Right"
    case bottomRight = "Bottom Right"
    case topLeft = "Top Left"
    case bottomLeft = "Bottom Left"

    var id: String { rawValue }
}

// MARK: - Settings

class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    // MARK: - Storage Keys

    private enum Keys {
        // Transcription
        static let transcriptionProvider = "transcription_provider"
        static let openaiTranscriptionApiKey = "openai_transcription_api_key"
        static let openaiTranscriptionModel = "openai_transcription_model"
        static let elevenlabsApiKey = "elevenlabs_api_key"
        static let elevenlabsModel = "elevenlabs_model"
        static let mistralTranscriptionApiKey = "mistral_transcription_api_key"
        static let mistralTranscriptionModel = "mistral_transcription_model"

        // Enhancement
        static let enhancementEnabled = "enhancement_enabled"
        static let enhancementProvider = "enhancement_provider"

        // Per-provider enhancement API keys
        static let enhancementApiKey_openai = "enhancement_api_key_openai"
        static let enhancementApiKey_openrouter = "enhancement_api_key_openrouter"
        static let enhancementApiKey_togetherai = "enhancement_api_key_togetherai"
        static let enhancementApiKey_groq = "enhancement_api_key_groq"
        static let enhancementApiKey_deepseek = "enhancement_api_key_deepseek"
        static let enhancementApiKey_moonshot = "enhancement_api_key_moonshot"
        static let enhancementApiKey_zai = "enhancement_api_key_zai"
        static let enhancementApiKey_azure = "enhancement_api_key_azure"
        static let enhancementApiKey_cloudflare = "enhancement_api_key_cloudflare"
        static let enhancementApiKey_custom = "enhancement_api_key_custom"

        // Per-provider enhancement models
        static let enhancementModel_openai = "enhancement_model_openai"
        static let enhancementModel_openrouter = "enhancement_model_openrouter"
        static let enhancementModel_togetherai = "enhancement_model_togetherai"
        static let enhancementModel_groq = "enhancement_model_groq"
        static let enhancementModel_deepseek = "enhancement_model_deepseek"
        static let enhancementModel_moonshot = "enhancement_model_moonshot"
        static let enhancementModel_zai = "enhancement_model_zai"
        static let enhancementModel_azure = "enhancement_model_azure"
        static let enhancementModel_cloudflare = "enhancement_model_cloudflare"
        static let enhancementModel_lmstudio = "enhancement_model_lmstudio"
        static let enhancementModel_custom = "enhancement_model_custom"

        // Custom base URLs for providers that need them
        static let enhancementBaseURL_azure = "enhancement_base_url_azure"
        static let enhancementBaseURL_cloudflare = "enhancement_base_url_cloudflare"
        static let enhancementBaseURL_custom = "enhancement_base_url_custom"

        // Keyboard shortcuts
        static let pushToTalkKeyCode = "push_to_talk_key_code"
        static let pushToTalkModifiers = "push_to_talk_modifiers"
        static let toggleModeKeyCode = "toggle_mode_key_code"
        static let toggleModeModifiers = "toggle_mode_modifiers"

        // Floating window
        static let showFloatingWindow = "show_floating_window"
        static let floatingWindowPosition = "floating_window_position"
        static let previewBeforeInsert = "preview_before_insert"
    }

    // MARK: - Transcription Settings

    @Published var transcriptionProvider: TranscriptionProvider {
        didSet { defaults.set(transcriptionProvider.rawValue, forKey: Keys.transcriptionProvider) }
    }

    @Published var openaiTranscriptionApiKey: String {
        didSet { defaults.set(openaiTranscriptionApiKey, forKey: Keys.openaiTranscriptionApiKey) }
    }

    @Published var openaiTranscriptionModel: String {
        didSet { defaults.set(openaiTranscriptionModel, forKey: Keys.openaiTranscriptionModel) }
    }

    @Published var elevenlabsApiKey: String {
        didSet { defaults.set(elevenlabsApiKey, forKey: Keys.elevenlabsApiKey) }
    }

    @Published var elevenlabsModel: String {
        didSet { defaults.set(elevenlabsModel, forKey: Keys.elevenlabsModel) }
    }

    @Published var mistralTranscriptionApiKey: String {
        didSet { defaults.set(mistralTranscriptionApiKey, forKey: Keys.mistralTranscriptionApiKey) }
    }

    @Published var mistralTranscriptionModel: String {
        didSet { defaults.set(mistralTranscriptionModel, forKey: Keys.mistralTranscriptionModel) }
    }

    // MARK: - Enhancement Settings

    @Published var enhancementEnabled: Bool {
        didSet { defaults.set(enhancementEnabled, forKey: Keys.enhancementEnabled) }
    }

    @Published var enhancementProvider: EnhancementProvider {
        didSet { defaults.set(enhancementProvider.rawValue, forKey: Keys.enhancementProvider) }
    }

    // Per-provider API keys for enhancement
    @Published var enhancementApiKeys: [EnhancementProvider: String] = [:] {
        didSet { saveEnhancementApiKeys() }
    }

    // Per-provider models for enhancement
    @Published var enhancementModels: [EnhancementProvider: String] = [:] {
        didSet { saveEnhancementModels() }
    }

    // Custom base URLs for Azure, Cloudflare, Custom
    @Published var enhancementBaseURLs: [EnhancementProvider: String] = [:] {
        didSet { saveEnhancementBaseURLs() }
    }

    // MARK: - Floating Window Settings

    @Published var showFloatingWindow: Bool {
        didSet { defaults.set(showFloatingWindow, forKey: Keys.showFloatingWindow) }
    }

    @Published var floatingWindowPosition: FloatingWindowPosition {
        didSet { defaults.set(floatingWindowPosition.rawValue, forKey: Keys.floatingWindowPosition) }
    }

    @Published var previewBeforeInsert: Bool {
        didSet { defaults.set(previewBeforeInsert, forKey: Keys.previewBeforeInsert) }
    }

    // MARK: - Keyboard Shortcut Settings

    static let defaultPushToTalkKeyCode = UInt32(kVK_Space)
    static let defaultPushToTalkModifiers = NSEvent.ModifierFlags.option.carbonFlags
    static let defaultToggleModeKeyCode = UInt32(kVK_Space)
    static let defaultToggleModeModifiers = NSEvent.ModifierFlags([.option, .shift]).carbonFlags

    @Published var pushToTalkKeyCode: UInt32 {
        didSet { defaults.set(Int(pushToTalkKeyCode), forKey: Keys.pushToTalkKeyCode) }
    }

    @Published var pushToTalkModifiers: UInt32 {
        didSet { defaults.set(Int(pushToTalkModifiers), forKey: Keys.pushToTalkModifiers) }
    }

    @Published var toggleModeKeyCode: UInt32 {
        didSet { defaults.set(Int(toggleModeKeyCode), forKey: Keys.toggleModeKeyCode) }
    }

    @Published var toggleModeModifiers: UInt32 {
        didSet { defaults.set(Int(toggleModeModifiers), forKey: Keys.toggleModeModifiers) }
    }

    /// Format a key combo as a human-readable string (e.g. "⌥ Space")
    static func shortcutDisplayString(keyCode: UInt32, modifiers: UInt32) -> String {
        let flags = NSEvent.ModifierFlags(carbonFlags: modifiers)
        let modString = flags.description
        let keyString = Key(carbonKeyCode: keyCode)?.description ?? "?"
        if modString.isEmpty {
            return keyString
        }
        return "\(modString)\(keyString)"
    }

    // MARK: - Available Models

    static let openaiTranscriptionModels = [
        "gpt-4o-transcribe",
        "gpt-4o-mini-transcribe",
        "whisper-1"
    ]

    static let elevenlabsModels = [
        "scribe_v2",
        "scribe_v1"
    ]

    static let mistralTranscriptionModels = [
        "voxtral-mini-2602",
        "voxtral-mini-latest"
    ]

    // MARK: - Computed Properties

    /// Current transcription API key based on selected provider
    var currentTranscriptionApiKey: String {
        switch transcriptionProvider {
        case .openai: return openaiTranscriptionApiKey
        case .elevenlabs: return elevenlabsApiKey
        case .mistral: return mistralTranscriptionApiKey
        }
    }

    /// Current transcription model based on selected provider
    var currentTranscriptionModel: String {
        switch transcriptionProvider {
        case .openai: return openaiTranscriptionModel
        case .elevenlabs: return elevenlabsModel
        case .mistral: return mistralTranscriptionModel
        }
    }

    /// Current enhancement API key for selected provider
    var currentEnhancementApiKey: String {
        get { enhancementApiKeys[enhancementProvider] ?? "" }
        set { enhancementApiKeys[enhancementProvider] = newValue }
    }

    /// Current enhancement model for selected provider
    var currentEnhancementModel: String {
        get { enhancementModels[enhancementProvider] ?? enhancementProvider.defaultModel }
        set { enhancementModels[enhancementProvider] = newValue }
    }

    /// Current enhancement base URL for selected provider
    var currentEnhancementBaseURL: String {
        get {
            if enhancementProvider.requiresCustomURL {
                return enhancementBaseURLs[enhancementProvider] ?? enhancementProvider.baseURL
            }
            return enhancementProvider.baseURL
        }
        set {
            if enhancementProvider.requiresCustomURL {
                enhancementBaseURLs[enhancementProvider] = newValue
            }
        }
    }

    // MARK: - Validation

    var isConfigured: Bool {
        switch transcriptionProvider {
        case .openai:
            return !openaiTranscriptionApiKey.isEmpty
        case .elevenlabs:
            return !elevenlabsApiKey.isEmpty
        case .mistral:
            return !mistralTranscriptionApiKey.isEmpty
        }
    }

    var configurationError: String? {
        switch transcriptionProvider {
        case .openai:
            if openaiTranscriptionApiKey.isEmpty {
                return "OpenAI API key required for transcription"
            }
        case .elevenlabs:
            if elevenlabsApiKey.isEmpty {
                return "ElevenLabs API key required for transcription"
            }
        case .mistral:
            if mistralTranscriptionApiKey.isEmpty {
                return "Mistral API key required for transcription"
            }
        }

        if enhancementEnabled && enhancementProvider.requiresApiKey && currentEnhancementApiKey.isEmpty {
            return "\(enhancementProvider.rawValue) API key required for enhancement"
        }

        return nil
    }

    // MARK: - Initialization

    private init() {
        // Transcription settings
        let providerRaw = defaults.string(forKey: Keys.transcriptionProvider) ?? TranscriptionProvider.elevenlabs.rawValue
        self.transcriptionProvider = TranscriptionProvider(rawValue: providerRaw) ?? .elevenlabs

        self.openaiTranscriptionApiKey = defaults.string(forKey: Keys.openaiTranscriptionApiKey) ?? ""
        self.openaiTranscriptionModel = defaults.string(forKey: Keys.openaiTranscriptionModel) ?? "gpt-4o-transcribe"
        self.elevenlabsApiKey = defaults.string(forKey: Keys.elevenlabsApiKey) ?? ""
        self.elevenlabsModel = defaults.string(forKey: Keys.elevenlabsModel) ?? "scribe_v2"
        self.mistralTranscriptionApiKey = defaults.string(forKey: Keys.mistralTranscriptionApiKey) ?? ""
        self.mistralTranscriptionModel = defaults.string(forKey: Keys.mistralTranscriptionModel) ?? "voxtral-mini-2602"

        // Enhancement settings
        self.enhancementEnabled = defaults.object(forKey: Keys.enhancementEnabled) as? Bool ?? true

        let enhancementProviderRaw = defaults.string(forKey: Keys.enhancementProvider) ?? EnhancementProvider.openai.rawValue
        self.enhancementProvider = EnhancementProvider(rawValue: enhancementProviderRaw) ?? .openai

        // Initialize per-provider enhancement API keys
        var apiKeys: [EnhancementProvider: String] = [:]
        apiKeys[.openai] = defaults.string(forKey: Keys.enhancementApiKey_openai) ?? ""
        apiKeys[.openrouter] = defaults.string(forKey: Keys.enhancementApiKey_openrouter) ?? ""
        apiKeys[.togetherai] = defaults.string(forKey: Keys.enhancementApiKey_togetherai) ?? ""
        apiKeys[.groq] = defaults.string(forKey: Keys.enhancementApiKey_groq) ?? ""
        apiKeys[.deepseek] = defaults.string(forKey: Keys.enhancementApiKey_deepseek) ?? ""
        apiKeys[.moonshot] = defaults.string(forKey: Keys.enhancementApiKey_moonshot) ?? ""
        apiKeys[.zai] = defaults.string(forKey: Keys.enhancementApiKey_zai) ?? ""
        apiKeys[.azure] = defaults.string(forKey: Keys.enhancementApiKey_azure) ?? ""
        apiKeys[.cloudflare] = defaults.string(forKey: Keys.enhancementApiKey_cloudflare) ?? ""
        apiKeys[.custom] = defaults.string(forKey: Keys.enhancementApiKey_custom) ?? ""
        self.enhancementApiKeys = apiKeys

        // Initialize per-provider enhancement models
        var models: [EnhancementProvider: String] = [:]
        for provider in EnhancementProvider.allCases {
            let key = "enhancement_model_\(provider.rawValue.lowercased().replacingOccurrences(of: " ", with: "_"))"
            models[provider] = defaults.string(forKey: key) ?? provider.defaultModel
        }
        self.enhancementModels = models

        // Initialize custom base URLs
        var baseURLs: [EnhancementProvider: String] = [:]
        baseURLs[.azure] = defaults.string(forKey: Keys.enhancementBaseURL_azure) ?? EnhancementProvider.azure.baseURL
        baseURLs[.cloudflare] = defaults.string(forKey: Keys.enhancementBaseURL_cloudflare) ?? EnhancementProvider.cloudflare.baseURL
        baseURLs[.custom] = defaults.string(forKey: Keys.enhancementBaseURL_custom) ?? ""
        self.enhancementBaseURLs = baseURLs

        // Keyboard shortcut settings
        if let val = defaults.object(forKey: Keys.pushToTalkKeyCode) as? Int {
            self.pushToTalkKeyCode = UInt32(val)
        } else {
            self.pushToTalkKeyCode = Settings.defaultPushToTalkKeyCode
        }
        if let val = defaults.object(forKey: Keys.pushToTalkModifiers) as? Int {
            self.pushToTalkModifiers = UInt32(val)
        } else {
            self.pushToTalkModifiers = Settings.defaultPushToTalkModifiers
        }
        if let val = defaults.object(forKey: Keys.toggleModeKeyCode) as? Int {
            self.toggleModeKeyCode = UInt32(val)
        } else {
            self.toggleModeKeyCode = Settings.defaultToggleModeKeyCode
        }
        if let val = defaults.object(forKey: Keys.toggleModeModifiers) as? Int {
            self.toggleModeModifiers = UInt32(val)
        } else {
            self.toggleModeModifiers = Settings.defaultToggleModeModifiers
        }

        // Floating window settings
        self.showFloatingWindow = defaults.object(forKey: Keys.showFloatingWindow) as? Bool ?? true
        let positionRaw = defaults.string(forKey: Keys.floatingWindowPosition) ?? FloatingWindowPosition.bottomRight.rawValue
        self.floatingWindowPosition = FloatingWindowPosition(rawValue: positionRaw) ?? .bottomRight
        self.previewBeforeInsert = defaults.object(forKey: Keys.previewBeforeInsert) as? Bool ?? false
    }

    // MARK: - Persistence Helpers

    private func saveEnhancementApiKeys() {
        defaults.set(enhancementApiKeys[.openai] ?? "", forKey: Keys.enhancementApiKey_openai)
        defaults.set(enhancementApiKeys[.openrouter] ?? "", forKey: Keys.enhancementApiKey_openrouter)
        defaults.set(enhancementApiKeys[.togetherai] ?? "", forKey: Keys.enhancementApiKey_togetherai)
        defaults.set(enhancementApiKeys[.groq] ?? "", forKey: Keys.enhancementApiKey_groq)
        defaults.set(enhancementApiKeys[.deepseek] ?? "", forKey: Keys.enhancementApiKey_deepseek)
        defaults.set(enhancementApiKeys[.moonshot] ?? "", forKey: Keys.enhancementApiKey_moonshot)
        defaults.set(enhancementApiKeys[.zai] ?? "", forKey: Keys.enhancementApiKey_zai)
        defaults.set(enhancementApiKeys[.azure] ?? "", forKey: Keys.enhancementApiKey_azure)
        defaults.set(enhancementApiKeys[.cloudflare] ?? "", forKey: Keys.enhancementApiKey_cloudflare)
        defaults.set(enhancementApiKeys[.custom] ?? "", forKey: Keys.enhancementApiKey_custom)
    }

    private func saveEnhancementModels() {
        for (provider, model) in enhancementModels {
            let key = "enhancement_model_\(provider.rawValue.lowercased().replacingOccurrences(of: " ", with: "_"))"
            defaults.set(model, forKey: key)
        }
    }

    private func saveEnhancementBaseURLs() {
        defaults.set(enhancementBaseURLs[.azure] ?? "", forKey: Keys.enhancementBaseURL_azure)
        defaults.set(enhancementBaseURLs[.cloudflare] ?? "", forKey: Keys.enhancementBaseURL_cloudflare)
        defaults.set(enhancementBaseURLs[.custom] ?? "", forKey: Keys.enhancementBaseURL_custom)
    }
}
