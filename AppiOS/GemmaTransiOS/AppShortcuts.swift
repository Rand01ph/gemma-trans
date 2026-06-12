import AppIntents

/// 让各 intent 出现在快捷指令库 / Spotlight / Siri，降低用户配置门槛
/// （否则用户要从零创建快捷指令；有了它可直接搜到、加到操作按钮或喊 Siri）。
struct GemmaTransShortcuts: AppShortcutsProvider {
    // appShortcuts 是 @AppShortcutsBuilder：多条 AppShortcut 直接并列，不写数组字面量
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
        AppShortcut(
            intent: ProcessTextIntent(),
            phrases: [
                "用 \(.applicationName) 处理",
                "\(.applicationName) 处理这段文字"
            ],
            shortTitle: "本地 AI 处理",
            systemImageName: "wand.and.stars"
        )
    }
}
