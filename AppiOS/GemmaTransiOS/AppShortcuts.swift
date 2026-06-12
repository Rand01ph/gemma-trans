import AppIntents

/// 让 TranslateIntent 出现在快捷指令库 / Spotlight / Siri，降低用户配置门槛
/// （否则用户要从零创建快捷指令；有了它可直接搜到、加到操作按钮或喊 Siri）。
struct GemmaTransShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TranslateIntent(),
            phrases: [
                "用 \(.applicationName) 翻译",
                "\(.applicationName) 翻译这段文字"
            ],
            shortTitle: "翻译文本",
            systemImageName: "character.bubble"
        )
    }
}
