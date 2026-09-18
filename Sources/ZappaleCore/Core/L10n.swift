import Foundation

/// 界面语言。
public enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    /// 跟随系统语言（默认）。
    case system
    case zhHans
    case english

    public var id: String { rawValue }

    /// 选项自身用双语展示（选择时刻两种语言都看得懂）。
    public var displayName: String {
        switch self {
        case .system: return "跟随系统 · Follow System"
        case .zhHans: return "简体中文"
        case .english: return "English"
        }
    }
}

/// 语言包。全部界面文案以 `L10n.t(中, en)` 内联登记——调用点即词条，
/// 切换语言时按 AppLanguage 返回单语。
public enum L10n {
    /// 当前生效语言（AppCore 启动与设置变更时写入）。
    private(set) static var language: AppLanguage = .system

    public static func apply(_ newLanguage: AppLanguage) {
        language = newLanguage
    }

    /// 是否中文界面。
    public static var isChinese: Bool {
        switch language {
        case .zhHans: return true
        case .english: return false
        case .system:
            return Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        }
    }

    /// 取词。英文为空时回退中文。
    public static func t(_ zh: String, _ en: String = "") -> String {
        if isChinese || en.isEmpty { return zh }
        return en
    }
}
