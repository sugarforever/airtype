import Foundation

/// A per-recording snapshot. Hints are vocabulary, not instructions or hard replacements.
public struct TranscriptionContext: Sendable {
    public enum Backend: Sendable {
        case openai, elevenlabs, mistral
    }

    public static let empty = TranscriptionContext(terms: [])
    public let terms: [String]
    public let qwenContext: String
    public let doubaoContext: String?
    private let whisperPrompt: String
    private let elevenLabsTerms: [String]

    public init(terms: [String]) {
        var candidates: [String] = []
        var seen = Set<String>()
        for raw in terms {
            // Limit work before normalizing potentially huge pasted entries.
            guard raw.utf8.count <= 1024 else { continue }
            let term = raw.precomposedStringWithCanonicalMapping
                .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            guard !term.isEmpty, term.count <= 100,
                  !term.contains("<|"), !term.contains("|>"),
                  !term.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  seen.insert(term.lowercased()).inserted else { continue }
            candidates.append(term)
        }
        // Each backend selects independently: ineligible terms must not consume another
        // backend's count/byte allowance. Only these bounded selections are retained.
        self.terms = Self.select(candidates, byteBudget: 4096)
        self.qwenContext = Self.select(candidates, byteBudget: 1024, separatorBytes: 2).joined(separator: ", ")
        self.whisperPrompt = Self.select(candidates, byteBudget: 192, separatorBytes: 2).joined(separator: ", ")
        let forbidden = CharacterSet(charactersIn: "<>{}[]\\")
        self.elevenLabsTerms = Self.select(candidates.filter {
            $0.unicodeScalars.count < 50 && $0.split(separator: " ").count <= 5
                && $0.rangeOfCharacter(from: forbidden) == nil
        }, byteBudget: 4096)
        self.doubaoContext = Self.makeDoubaoContext(candidates)
    }

    public static func load(repository: VocabularyRepository?, enabled: Bool) async -> Self {
        guard enabled, let repository else { return .empty }
        return Self(terms: await repository.allTerms().map(\.value))
    }

    public func openAIPrompt(model: String) -> String {
        switch model {
        case "whisper-1":
            // Conservative UTF-8 byte ceiling, NOT a bytes/4 token estimate.
            // Keeps even rare Unicode spellings below Whisper's 224-token prompt window.
            return whisperPrompt
        case "gpt-4o-transcribe", "gpt-4o-mini-transcribe":
            return qwenContext
        default:
            return ""
        }
    }

    public func multipartData(for backend: Backend, model: String, boundary: String) -> Data {
        let name: String
        let values: [String]
        switch backend {
        case .openai:
            name = "prompt"
            let prompt = openAIPrompt(model: model)
            values = prompt.isEmpty ? [] : [prompt]
        case .elevenlabs:
            guard model == "scribe_v2" else { return Data() }
            name = "keyterms"
            values = elevenLabsTerms
        case .mistral:
            guard ["voxtral-mini-2602", "voxtral-mini-latest"].contains(model) else { return Data() }
            name = "context_bias"
            values = terms
        }
        // Both list APIs use repeated form parts, not a JSON array in a single field.
        return Data(values.map {
            "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\($0)\r\n"
        }.joined().utf8)
    }

    /// SeedASR expects a JSON STRING at request.corpus.context, not an embedded object.
    private static func makeDoubaoContext(_ candidates: [String]) -> String? {
        var selected: [String] = []
        var result: String?
        for term in candidates {
            let payload = ["hotwords": (selected + [term]).map { ["word": $0] }]
            guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
                  data.count <= 100 else { continue }
            // Conservative bound for the bidirectional endpoint's 100-token context.
            selected.append(term)
            result = String(decoding: data, as: UTF8.self)
        }
        return result
    }

    private static func select(_ candidates: [String], byteBudget: Int, separatorBytes: Int = 0) -> [String] {
        var selected: [String] = []
        var bytes = 0
        for term in candidates {
            let additionalBytes = term.utf8.count + (selected.isEmpty ? 0 : separatorBytes)
            guard bytes + additionalBytes <= byteBudget else { continue }
            selected.append(term)
            bytes += additionalBytes
            // Deliberately below ElevenLabs' 1000 limit to avoid its >100-term minimum billing duration.
            if selected.count == 100 { break }
        }
        return selected
    }
}
