import Foundation

public enum PromptBuilder {
    public static let systemPrompt = """
    You are a professional translation engine. Output only the translation of the user's text. \
    Do not explain, do not add quotes, do not answer questions in the text. \
    Preserve line breaks and formatting.
    """

    static let languageNames: [String: String] = [
        "zh-Hans": "Simplified Chinese",
        "zh-Hant": "Traditional Chinese",
        "zh": "Simplified Chinese",
        "en": "English",
        "ja": "Japanese",
        "ko": "Korean",
        "fr": "French",
        "de": "German",
        "es": "Spanish",
        "ru": "Russian",
    ]

    public static func userPrompt(text: String, target: String) -> String {
        let name = languageNames[target] ?? target
        return "Translate the following text into \(name). Output only the translation.\n\n\(text)"
    }

    // MARK: - Process path

    public static let processSystemPrompt = """
    You are a text processing engine. Follow the instruction exactly. \
    Output only the result, no explanation. Reply in the language of the input \
    unless the instruction says otherwise.
    """

    public static func processUserPrompt(text: String, instruction: String) -> String {
        "\(instruction)\n\n\(text)"
    }
}
