import Foundation

/// 内置处理预设。每个预设含稳定 id、显示名称与中文指令全文。
public struct ProcessPreset: Sendable, Equatable {
    public let id: String
    public let name: String
    public let instruction: String

    public init(id: String, name: String, instruction: String) {
        self.id = id
        self.name = name
        self.instruction = instruction
    }
}

public enum ProcessPresets {
    /// 快递取件信息提取。
    /// 输出契约：单行 `取件: <地点> · 码 <取件码> · <时限>`；缺项跳过；非快递短信输出 `无`。
    public static let courierPickup = ProcessPreset(
        id: "builtin.courier",
        name: "快递取件提取",
        instruction: """
        从短信中提取快递取件信息。
        如果是快递取件短信，输出单行格式：取件: <地点> · 码 <取件码> · <时限>
        缺少的字段直接跳过（不输出该部分），不补占位符。
        如果不是快递取件相关短信，只输出：无
        不要解释，不要加引号，只输出结果。
        """
    )

    /// 要点总结。
    /// 输出契约：三句话以内，纯文本，无前缀。
    public static let summarize = ProcessPreset(
        id: "builtin.summarize",
        name: "要点总结",
        instruction: """
        用三句话以内总结以下文字的要点。
        直接输出总结内容，不加前缀、不加编号、不加引号。
        """
    )

    /// 全部内置预设，顺序稳定。
    public static let all: [ProcessPreset] = [courierPickup, summarize]
}
