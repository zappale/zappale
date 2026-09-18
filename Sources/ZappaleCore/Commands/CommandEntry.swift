import Foundation

/// 命令面板中一个可激活的行。所有来源——应用、系统动作、快捷链接、
/// 剪贴板条目、计算结果卡、回退命令——都折叠为同一模型，面板只认
/// section + 扁平选择索引，新增来源不需要改面板。
///
/// 本文件保持 Foundation-only：图标用 IconSpec 描述，不触碰 AppKit。
public struct CommandEntry: Identifiable, Hashable {
    /// 行的来源。协调器据此分发激活行为。
    public enum Kind: Hashable {
        case app(path: String)
        case systemAction(SystemActionID)
        case quicklink(id: String)
        /// 已携带完整数据，UI 无需回查。
        case clipboard(ClipboardItem)
        /// Spotlight 文件搜索结果。
        case file(FileSearchEntry)
        /// 表情 / 符号条目。
        case emoji(EmojiDef)
        /// 笔记条目。
        case note(id: String)
        /// 进入 AI 对话（仅 aiEnabled 时出现）。
        case askAI(query: String)
        /// 片段（含 keyword 参数模式的实参）。
        case snippet(id: String, argument: String?)
        /// 自定义命令。
        case customCommand(id: String)
        /// 内联计算卡：回车复制结果。
        case calculator(display: String)
        case webSearch(query: String)
        case openURL(url: String)
    }

    /// 图标描述。symbol = SF Symbol 名；filePath 取文件图标（应用）；
    /// clipboardKind 用剪贴板三分类图标。
    public enum IconSpec: Hashable {
        case symbol(String)
        case filePath(String)
    }

    public let id: String
    public let kind: Kind
    public var title: String
    public var subtitle: String?
    public var icon: IconSpec
    /// 激活是否需要二次确认（关机、清倒废纸篓等破坏性动作）。
    public var requiresConfirmation: Bool

    public init(
        id: String,
        kind: Kind,
        title: String,
        subtitle: String? = nil,
        icon: IconSpec,
        requiresConfirmation: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.requiresConfirmation = requiresConfirmation
    }
}

/// 一个分区：可选标题 + 若干行。分区标题不参与选择索引。
public struct CommandSection: Identifiable, Hashable {
    public let id: String
    public let title: String?
    public var entries: [CommandEntry]

    public init(id: String, title: String? = nil, entries: [CommandEntry] = []) {
        self.id = id
        self.title = title
        self.entries = entries
    }
}

/// 扁平选择索引：面板的唯一选择真相。行顺序 = 各分区顺序拼接，
/// 分区标题不可选也不占索引。保持纯函数，单测直接覆盖。
public enum PaletteRows {
    /// 分区列表 → 可见行平铺。返回的数组顺序即面板渲染顺序。
    public static func flatten(_ sections: [CommandSection]) -> [CommandEntry] {
        sections.flatMap(\.entries)
    }

    /// 选中行移动 delta（-1 上移 / +1 下移），越界钳制。
    /// 返回移动后的索引。
    public static func moveSelection(index: Int, delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index + delta, 0), count - 1)
    }

    /// ⌘ 数字键映射：'1'…'9' → 0…8；其他字符返回 nil。
    public static func quickActivateIndex(character: String) -> Int? {
        guard character.count == 1, let scalar = character.unicodeScalars.first,
              ("1"..."9").contains(scalar) else { return nil }
        return Int(character)! - 1
    }
}
