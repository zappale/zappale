import Foundation

/// 系统动作标识。新增动作 = 新增 case + 目录登记一行；
/// 执行行为在 Service 层的 Runner 里，破坏性动作在面板协调层二次确认。
public enum SystemActionID: String, CaseIterable, Hashable, Codable {
    case lockScreen
    case sleep
    case displaySleep
    case startScreenSaver
    case restart
    case shutdown
    case emptyTrash
    case toggleAppearance
    case toggleHiddenFiles
    case toggleMute
    case volumeUp
    case volumeDown
    case quitAllApps
    case restartFinder
    case restartDock
    case newNote
    // 窗口管理（Rectangle 式）
    case windowLeft, windowRight, windowTop, windowBottom
    case windowTopLeft, windowTopRight, windowBottomLeft, windowBottomRight
    case windowLeftTwoThirds, windowRightTwoThirds
    case windowCenter, windowMaximize, windowAlmostMaximize, windowRestore
    case windowNextDisplay, windowPrevDisplay
    // AI 快捷动作（仅 aiEnabled）
    case aiTranslate, aiPolish, aiSummarize
}

/// 动作分类。设置页与目录展示按此分组。
public enum SystemActionCategory: String, CaseIterable, Hashable {
    case power
    case system
    case appearance
    case audio
    case desktop
    case window
    case ai

    public var displayName: String {
        switch self {
        case .power: return L10n.t("电源", "Power")
        case .system: return L10n.t("系统", "System")
        case .appearance: return L10n.t("外观", "Appearance")
        case .audio: return L10n.t("音频", "Audio")
        case .desktop: return L10n.t("桌面", "Desktop")
        case .window: return L10n.t("窗口", "Window")
        case .ai: return L10n.t("AI 快捷动作", "AI Quick Actions")
        }
    }
}

/// 一个系统动作的描述：中英双字段（显示语言随设置；搜索两种语言都匹配）。
public struct SystemActionDef: Hashable, Identifiable {
    public let id: SystemActionID
    public let zhTitle: String
    public let enTitle: String
    public let zhSubtitle: String
    public let enSubtitle: String
    public let symbol: String
    public let category: SystemActionCategory
    public let requiresConfirmation: Bool

    public var title: String { L10n.t(zhTitle, enTitle) }
    public var subtitle: String { L10n.t(zhSubtitle, enSubtitle) }

    public var confirmationHint: String {
        L10n.t("再按 ↵ 确认「\(title)」", "Press ↵ again to confirm \(enTitle)")
    }
}

/// 目录。纯数据，搜索与展示直接消费。
public enum SystemActionCatalog {
    public static let all: [SystemActionDef] = [
        SystemActionDef(
            id: .lockScreen, zhTitle: "锁定屏幕", enTitle: "Lock Screen", zhSubtitle: "立即锁定回到登录界面", enSubtitle: "Lock now",
            symbol: "lock.fill", category: .power, requiresConfirmation: false
        ),
        SystemActionDef(
            id: .sleep, zhTitle: "睡眠", enTitle: "Sleep", zhSubtitle: "让 Mac 进入睡眠", enSubtitle: "Sleep now",
            symbol: "moon.zzz.fill", category: .power, requiresConfirmation: false
        ),
        SystemActionDef(
            id: .displaySleep, zhTitle: "关闭显示器", enTitle: "Display Off", zhSubtitle: "仅熄屏不睡眠", enSubtitle: "Screen off only",
            symbol: "display", category: .power, requiresConfirmation: false
        ),
        SystemActionDef(
            id: .startScreenSaver, zhTitle: "启动屏幕保护程序", enTitle: "Start Screen Saver",
            zhSubtitle: "立即开始屏幕保护", enSubtitle: "Start screensaver", symbol: "sparkles.tv",
            category: .power, requiresConfirmation: false
        ),
        SystemActionDef(
            id: .restart, zhTitle: "重启电脑", enTitle: "Restart", zhSubtitle: "关闭所有应用并重启", enSubtitle: "Close all & restart",
            symbol: "arrow.triangle.2.circlepath", category: .power, requiresConfirmation: true
        ),
        SystemActionDef(
            id: .shutdown, zhTitle: "关机", enTitle: "Shut Down", zhSubtitle: "关闭所有应用并关机", enSubtitle: "Close all & shut down",
            symbol: "power", category: .power, requiresConfirmation: true
        ),
        SystemActionDef(
            id: .emptyTrash, zhTitle: "清倒废纸篓", enTitle: "Empty Trash", zhSubtitle: "永久删除废纸篓项目", enSubtitle: "Delete permanently",
            symbol: "trash.fill", category: .system, requiresConfirmation: true
        ),
        SystemActionDef(
            id: .quitAllApps, zhTitle: "退出所有应用", enTitle: "Quit All Apps", zhSubtitle: "保留 zappale 逐个退出其余应用", enSubtitle: "Quit others, keep zappale",
            symbol: "xmark.app.fill", category: .system, requiresConfirmation: true
        ),
        SystemActionDef(
            id: .toggleAppearance, zhTitle: "切换深浅外观", enTitle: "Toggle Appearance", zhSubtitle: "深色 ⇄ 浅色", enSubtitle: "Dark ⇄ Light",
            symbol: "circle.lefthalf.filled", category: .appearance, requiresConfirmation: false
        ),
        SystemActionDef(
            id: .toggleHiddenFiles, zhTitle: "切换隐藏文件显示", enTitle: "Toggle Hidden Files", zhSubtitle: "重启 Finder 生效", enSubtitle: "Relaunches Finder",
            symbol: "eye.fill", category: .appearance, requiresConfirmation: false
        ),
        SystemActionDef(
            id: .toggleMute, zhTitle: "静音 / 取消静音", enTitle: "Toggle Mute",
            zhSubtitle: "切换系统输出静音", enSubtitle: "Toggle output mute", symbol: "speaker.slash.fill",
            category: .audio, requiresConfirmation: false
        ),
        SystemActionDef(
            id: .volumeUp, zhTitle: "音量调高", enTitle: "Volume Up", zhSubtitle: "系统输出音量 +12.5%", enSubtitle: "Output +12.5%",
            symbol: "speaker.wave.2.fill", category: .audio, requiresConfirmation: false
        ),
        SystemActionDef(
            id: .volumeDown, zhTitle: "音量调低", enTitle: "Volume Down", zhSubtitle: "系统输出音量 −12.5%", enSubtitle: "Output −12.5%",
            symbol: "speaker.wave.1.fill", category: .audio, requiresConfirmation: false
        ),
        SystemActionDef(
            id: .restartFinder, zhTitle: "重启 Finder", enTitle: "Restart Finder", zhSubtitle: "卡顿时强制重启", enSubtitle: "Force restart",
            symbol: "folder.fill", category: .desktop, requiresConfirmation: false
        ),
        SystemActionDef(
            id: .restartDock, zhTitle: "重启 Dock", enTitle: "Restart Dock", zhSubtitle: "卡顿时强制重启", enSubtitle: "Force restart",
            symbol: "rectangle.bottomthird.inset.filled", category: .desktop,
            requiresConfirmation: false
        ),
        SystemActionDef(
            id: .newNote, zhTitle: "新建笔记", enTitle: "New Note",
            zhSubtitle: "打开编辑器开始记录", enSubtitle: "Open editor",
            symbol: "square.and.pencil", category: .system, requiresConfirmation: false
        ),
    ] + windowActions + aiActions

    public static func def(_ id: SystemActionID) -> SystemActionDef? {
        all.first { $0.id == id }
    }

    /// 搜索：标题/副标题模糊匹配，按得分降序，同分按目录顺序。
    public static func search(_ query: String, limit: Int = 6) -> [SystemActionDef] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return all
            .compactMap { def -> (SystemActionDef, Int)? in
                let scores = [
                    FuzzyMatch.score(query: trimmed, target: def.zhTitle) ?? Int.min,
                    FuzzyMatch.score(query: trimmed, target: def.enTitle) ?? Int.min,
                    FuzzyMatch.score(query: trimmed, target: def.zhSubtitle) ?? Int.min,
                    FuzzyMatch.score(query: trimmed, target: def.enSubtitle) ?? Int.min,
                ]
                let score = scores.max() ?? Int.min
                guard score > Int.min else { return nil }
                return (def, score)
            }
            .sorted { lhs, rhs in
                lhs.1 != rhs.1 ? lhs.1 > rhs.1
                    : (all.firstIndex(of: lhs.0) ?? 0) < (all.firstIndex(of: rhs.0) ?? 0)
            }
            .prefix(limit)
            .map(\.0)
    }

    /// 空查询时展示的常用动作。
    public static let quickPicks: [SystemActionID] = [
        .lockScreen, .sleep, .toggleAppearance, .emptyTrash, .toggleMute,
    ]

    /// 窗口动作目录（由 WindowAction 生成）。
    public static let windowActions: [SystemActionDef] = WindowAction.allCases.map { action in
        SystemActionDef(
            id: SystemActionCatalog.windowActionID(action),
            zhTitle: action.spec.zh,
            enTitle: action.spec.en,
            zhSubtitle: "作用于前台窗口",
            enSubtitle: "Frontmost window",
            symbol: action.spec.symbol,
            category: .window,
            requiresConfirmation: false
        )
    }

    /// AI 快捷动作目录。
    public static let aiActions: [SystemActionDef] = [
        SystemActionDef(
            id: .aiTranslate, zhTitle: "翻译选中文字", enTitle: "Translate Selection",
            zhSubtitle: "复制选中→AI 翻译→贴回原位", enSubtitle: "Copy, translate, paste back",
            symbol: "character.book.closed", category: .ai, requiresConfirmation: false
        ),
        SystemActionDef(
            id: .aiPolish, zhTitle: "润色选中文字", enTitle: "Polish Selection",
            zhSubtitle: "AI 改写更通顺后贴回", enSubtitle: "Rewrite and paste back",
            symbol: "wand.and.stars", category: .ai, requiresConfirmation: false
        ),
        SystemActionDef(
            id: .aiSummarize, zhTitle: "总结选中文字", enTitle: "Summarize Selection",
            zhSubtitle: "AI 摘要后贴回", enSubtitle: "Summarize and paste back",
            symbol: "text.alignleft", category: .ai, requiresConfirmation: false
        ),
    ]

    /// WindowAction ↔ SystemActionID 映射。
    public static func windowActionID(_ action: WindowAction) -> SystemActionID {
        switch action {
        case .leftHalf: return .windowLeft
        case .rightHalf: return .windowRight
        case .topHalf: return .windowTop
        case .bottomHalf: return .windowBottom
        case .topLeft: return .windowTopLeft
        case .topRight: return .windowTopRight
        case .bottomLeft: return .windowBottomLeft
        case .bottomRight: return .windowBottomRight
        case .leftTwoThirds: return .windowLeftTwoThirds
        case .rightTwoThirds: return .windowRightTwoThirds
        case .center: return .windowCenter
        case .maximize: return .windowMaximize
        case .almostMaximize: return .windowAlmostMaximize
        case .restore: return .windowRestore
        case .nextDisplay: return .windowNextDisplay
        case .prevDisplay: return .windowPrevDisplay
        }
    }

    public static func windowAction(for id: SystemActionID) -> WindowAction? {
        WindowAction.allCases.first { windowActionID($0) == id }
    }

    public static func isAIAction(_ id: SystemActionID) -> Bool {
        id == .aiTranslate || id == .aiPolish || id == .aiSummarize
    }
}
