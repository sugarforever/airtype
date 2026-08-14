public struct VocabularyPromptBuilder: Sendable {
    public init() {}

    public func section(terms: [String]) -> String {
        guard !terms.isEmpty else { return "" }

        let renderedTerms = terms.map { "- \($0)" }.joined(separator: "\n")
        return """
            LOCAL USER VOCABULARY:
            These are correct spellings of terms the user commonly uses. Use them only when they fit the spoken context.
            \(renderedTerms)
            """
    }
}
