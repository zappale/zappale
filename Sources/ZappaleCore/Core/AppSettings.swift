import Foundation

/// 模型服务类型。以 OpenAI 兼容协议为主轴（OpenAI/DeepSeek/Moonshot 等），
/// Anthropic 走独立请求头约定。
public enum AIProviderKind: String, CaseIterable, Identifiable, Codable {
    case openAICompatible
    case anthropic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAICompatible: return "OpenAI 兼容"
        case .anthropic: return "Anthropic"
        }
    }
}

/// 剪贴板默认动作：回车行为，⌘↵ 永远做另一件。
public enum ClipboardDefaultAction: String, CaseIterable, Identifiable, Codable {
    case paste
    case copy

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .paste: return "粘贴到前一个应用"
        case .copy: return "复制到剪贴板"
        }
    }
}

/// 面板呼出方式：双击 ⌘（默认）或常规快捷键组合。
public enum PaletteSummonMode: String, Codable, CaseIterable, Identifiable {
    case doubleTapCommand
    case hotkey

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .doubleTapCommand: return L10n.t("双击 ⌘ Command", "Double-tap ⌘")
        case .hotkey: return L10n.t("快捷键组合", "Hotkey")
        }
    }
}

/// 每应用热键的持久化容器：应用路径 → 热键。
public struct PerAppHotkeys: Codable, Hashable {
    public var entries: [String: HotkeySpec] = [:]
}

/// 用户可调设置。落 UserDefaults；API key 永远不进这里（Keychain 专用）。
@MainActor
public final class AppSettings: ObservableObject {
    private enum Keys {
        static let aiEnabled = "ai.enabled"
        static let provider = "ai.provider"
        static let endpoint = "ai.endpoint"
        static let model = "ai.model"
        static let clipboardEnabled = "clipboard.enabled"
        static let clipboardDefaultAction = "clipboard.defaultAction"
        static let clipboardCapacity = "clipboard.capacity"
        static let systemActionsEnabled = "systemActions.enabled"
        static let paletteHotkey = "hotkey.palette"
        static let paletteSummonMode = "hotkey.paletteSummonMode"
        static let clipboardHotkey = "hotkey.clipboard"
        static let perAppHotkeys = "hotkey.perApp"
        static let fileSearchScopes = "fileSearch.scopes"
        static let language = "general.language"
        static let windowManagementEnabled = "windowManagement.enabled"
        static let reducedVisualEffects = "general.reducedVisualEffects"
    }

    private let defaults: UserDefaults

    /// AI 总开关。借鉴 tinycast 不变量：off = fully off ——
    /// 关闭时无 AI 入口、无网络请求、无历史落盘。
    @Published public var aiEnabled: Bool {
        didSet { defaults.set(aiEnabled, forKey: Keys.aiEnabled) }
    }

    @Published public var provider: AIProviderKind {
        didSet { defaults.set(provider.rawValue, forKey: Keys.provider) }
    }

    @Published public var endpointText: String {
        didSet { defaults.set(endpointText, forKey: Keys.endpoint) }
    }

    @Published public var model: String {
        didSet { defaults.set(model, forKey: Keys.model) }
    }

    /// 剪贴板历史开关。出厂默认开——唯一默认开启的功能（对齐 tinycast）；
    /// 缺 key 时必须把"无记录"当作开，才能 outrank 已存的 false 之前的默认态。
    @Published public var clipboardEnabled: Bool {
        didSet { defaults.set(clipboardEnabled, forKey: Keys.clipboardEnabled) }
    }

    @Published public var clipboardDefaultAction: ClipboardDefaultAction {
        didSet { defaults.set(clipboardDefaultAction.rawValue, forKey: Keys.clipboardDefaultAction) }
    }

    @Published public var clipboardCapacity: Int {
        didSet { defaults.set(clipboardCapacity, forKey: Keys.clipboardCapacity) }
    }

    @Published public var systemActionsEnabled: Bool {
        didSet { defaults.set(systemActionsEnabled, forKey: Keys.systemActionsEnabled) }
    }

    /// 面板全局热键（hotkey 模式下生效；默认 ⌥Space）。
    @Published public var paletteHotkey: HotkeySpec {
        didSet { saveCodable(paletteHotkey, forKey: Keys.paletteHotkey) }
    }

    /// 面板呼出方式。默认双击 ⌘。
    @Published public var paletteSummonMode: PaletteSummonMode {
        didSet { defaults.set(paletteSummonMode.rawValue, forKey: Keys.paletteSummonMode) }
    }

    /// 剪贴板历史热键；nil = 未设置。
    @Published public var clipboardHotkey: HotkeySpec? {
        didSet { saveOptionalCodable(clipboardHotkey, forKey: Keys.clipboardHotkey) }
    }

    /// 每应用热键（路径 → 热键）。
    @Published public var perAppHotkeys: PerAppHotkeys {
        didSet { saveCodable(perAppHotkeys, forKey: Keys.perAppHotkeys) }
    }

    /// 文件搜索作用域目录（存 ~ 缩写形式便于阅读与迁移）。
    @Published public var fileSearchScopes: [String] {
        didSet { defaults.set(fileSearchScopes, forKey: Keys.fileSearchScopes) }
    }

    /// 界面语言。
    @Published public var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            L10n.apply(language)
        }
    }

    /// 减弱视觉效果（基础显示：面板用不透明底、关闭动画）。低版本/低配也可手动开。
    @Published public var reducedVisualEffects: Bool {
        didSet { defaults.set(reducedVisualEffects, forKey: Keys.reducedVisualEffects) }
    }

    /// 窗口管理（Rectangle 式动作）。
    @Published public var windowManagementEnabled: Bool {
        didSet { defaults.set(windowManagementEnabled, forKey: Keys.windowManagementEnabled) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        aiEnabled = defaults.bool(forKey: Keys.aiEnabled)
        provider = AIProviderKind(rawValue: defaults.string(forKey: Keys.provider) ?? "")
            ?? .openAICompatible
        endpointText = defaults.string(forKey: Keys.endpoint) ?? "https://api.deepseek.com/v1"
        model = defaults.string(forKey: Keys.model) ?? "deepseek-chat"

        if defaults.object(forKey: Keys.clipboardEnabled) == nil {
            clipboardEnabled = true
        } else {
            clipboardEnabled = defaults.bool(forKey: Keys.clipboardEnabled)
        }
        clipboardDefaultAction = ClipboardDefaultAction(
            rawValue: defaults.string(forKey: Keys.clipboardDefaultAction) ?? ""
        ) ?? .paste
        if let stored = defaults.object(forKey: Keys.clipboardCapacity) as? Int {
            clipboardCapacity = min(max(stored, 20), 2000)
        } else {
            clipboardCapacity = 200
        }
        if defaults.object(forKey: Keys.systemActionsEnabled) == nil {
            systemActionsEnabled = true
        } else {
            systemActionsEnabled = defaults.bool(forKey: Keys.systemActionsEnabled)
        }

        paletteHotkey = Self.loadCodable(HotkeySpec.self, forKey: Keys.paletteHotkey, from: defaults) ?? .defaultPalette
        paletteSummonMode = PaletteSummonMode(
            rawValue: defaults.string(forKey: Keys.paletteSummonMode) ?? ""
        ) ?? .doubleTapCommand
        // 剪贴板热键：从未设置过（无 key）→ 默认 ⌘⇧V；用户主动清除则保持无
        clipboardHotkey = Self.loadCodable(HotkeySpec.self, forKey: Keys.clipboardHotkey, from: defaults)
        if defaults.object(forKey: Keys.clipboardHotkey) == nil {
            clipboardHotkey = HotkeySpec(
                keyCode: 9, // kVK_ANSI_V
                carbonModifiers: CarbonModifierFlags.command | CarbonModifierFlags.shift
            )
        }
        perAppHotkeys = Self.loadCodable(PerAppHotkeys.self, forKey: Keys.perAppHotkeys, from: defaults) ?? PerAppHotkeys()
        if let scopes = defaults.stringArray(forKey: Keys.fileSearchScopes) {
            fileSearchScopes = scopes
        } else {
            fileSearchScopes = [
                "~/Desktop", "~/Documents", "~/Downloads",
            ]
        }
        language = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .system
        if defaults.object(forKey: Keys.windowManagementEnabled) == nil {
            windowManagementEnabled = true
        } else {
            windowManagementEnabled = defaults.bool(forKey: Keys.windowManagementEnabled)
        }
        reducedVisualEffects = defaults.bool(forKey: Keys.reducedVisualEffects)
    }

    // MARK: - Codable 落盘辅助

    private func saveCodable<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private func saveOptionalCodable<T: Encodable>(_ value: T?, forKey key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func loadCodable<T: Decodable>(
        _ type: T.Type, forKey key: String, from defaults: UserDefaults
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: - 热键辅助

    /// 作用域路径展开（~ → 主目录）。
    public static func expandScope(_ scope: String) -> String {
        (scope as NSString).expandingTildeInPath
    }

    /// 检查热键是否与其他绑定冲突（不含自身 id）。
    /// 返回冲突描述，nil = 无冲突。
    public func hotkeyConflict(_ spec: HotkeySpec, excluding excludedID: String? = nil) -> String? {
        var candidates: [(String, HotkeySpec)] = []
        if excludedID != "palette", paletteSummonMode == .hotkey {
            candidates.append(("呼出面板", paletteHotkey))
        }
        if excludedID != "clipboard", let clipboardHotkey {
            candidates.append(("剪贴板历史", clipboardHotkey))
        }
        if excludedID != "perApp" {
            for (path, hotkey) in perAppHotkeys.entries where path != excludedID {
                let name = (path as NSString).lastPathComponent
                candidates.append((name, hotkey))
            }
        }
        return candidates.first { $0.1 == spec }.map { "与「\($0.0)」冲突" }
    }

    /// 当前全部生效绑定（供 HotkeyCenter 全量重注）。
    /// commandHotkeys：自定义命令热键（id → spec），由 AppCore 注入。
    public func hotkeyBindings(commandHotkeys: [String: HotkeySpec] = [:]) -> [HotkeyBinding] {
        var bindings: [HotkeyBinding] = []
        if paletteSummonMode == .hotkey {
            bindings.append(HotkeyBinding(id: "palette", spec: paletteHotkey))
        }
        if let clipboardHotkey {
            bindings.append(HotkeyBinding(id: "clipboard", spec: clipboardHotkey))
        }
        for (path, spec) in perAppHotkeys.entries.sorted(by: { $0.key < $1.key }) {
            bindings.append(HotkeyBinding(id: "app:\(path)", spec: spec))
        }
        for (commandID, spec) in commandHotkeys.sorted(by: { $0.key < $1.key }) {
            bindings.append(HotkeyBinding(id: "cmd:\(commandID)", spec: spec))
        }
        return bindings.filter { $0.spec.isValid }
    }

    public var endpointURL: URL? {
        URL(string: endpointText.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
