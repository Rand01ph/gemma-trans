import Foundation

public enum PromptBuilder {
    public static let systemPrompt = """
    You are a professional translation engine. Output only the translation of the user's text. \
    Do not explain, do not add quotes, do not answer questions in the text. \
    Preserve line breaks and formatting.
    """

    static let languageNames: [String: String] = [
        "zh-Hans": "Chinese",
        "zh-Hant": "Traditional Chinese",
        "zh": "Chinese",
        "en": "English",
        "ja": "Japanese",
        "ko": "Korean",
        "fr": "French",
        "de": "German",
        "es": "Spanish",
        "ru": "Russian",
    ]

    static let chineseLanguageNames: [String: String] = [
        "zh-Hans": "中文",
        "zh-Hant": "繁体中文",
        "zh": "中文",
    ]

    public static func userPrompt(text: String, target: String) -> String {
        if let name = chineseLanguageNames[target] {
            return "将以下文本翻译为\(name)，注意只需要输出翻译后的结果，不要额外解释：\n\n\(text)"
        }
        let name = languageNames[target] ?? target
        return "Translate the following text into \(name). Note that you should only output " +
            "the translated result without any additional explanation:\n\n\(text)"
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
