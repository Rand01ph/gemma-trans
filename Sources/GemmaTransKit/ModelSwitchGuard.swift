public enum SwitchBlock: Sendable, Equatable {
    case generating
    case loading
    case apiRunning
    case notInstalled
}

public enum ModelSwitchGuard {
    public static func blockReason(
        isGenerating: Bool,
        isLoading: Bool,
        apiRunning: Bool
    ) -> SwitchBlock? {
        if isGenerating { return .generating }
        if isLoading { return .loading }
        if apiRunning { return .apiRunning }
        return nil
    }
}

public extension SwitchBlock {
    var message: String {
        switch self {
        case .generating:
            "正在翻译，请稍候再切换模型"
        case .loading:
            "模型加载中，请稍候再切换"
        case .apiRunning:
            "本地 API 运行中，请先在设置里关闭 API 再切换模型"
        case .notInstalled:
            "请先下载这个模型，再选择使用它"
        }
    }
}
