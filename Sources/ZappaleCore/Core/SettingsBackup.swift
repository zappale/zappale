import Foundation

/// 设置备份：导出/导入 JSON（不含任何密钥；API Key 只在 Keychain）。
public struct SettingsBackup: Codable {
    public static let schemaVersion = 1

    public let version: Int
    public let exportedAt: Date
    public var quicklinks: [Quicklink] = []
    public var snippets: [Snippet] = []
    public var commands: [CustomCommand] = []
    public var perAppHotkeys: PerAppHotkeys = PerAppHotkeys()
    public var paletteHotkey: HotkeySpec?
    public var clipboardHotkey: HotkeySpec?
    public var paletteSummonMode: PaletteSummonMode?
    public var fileSearchScopes: [String] = []
    /// 偏好项（安全子集）。
    public var clipboardEnabled: Bool?
    public var clipboardDefaultAction: ClipboardDefaultAction?
    public var clipboardCapacity: Int?
    public var systemActionsEnabled: Bool?
    public var windowManagementEnabled: Bool?
    public var aiEnabled: Bool?

    public enum CodingKeys: String, CodingKey {
        case version, exportedAt, quicklinks, snippets, commands
        case perAppHotkeys, paletteHotkey, clipboardHotkey, paletteSummonMode
        case fileSearchScopes
        case clipboardEnabled, clipboardDefaultAction, clipboardCapacity
        case systemActionsEnabled, windowManagementEnabled, aiEnabled
    }

    public init() {
        version = Self.schemaVersion
        exportedAt = Date()
    }

    // MARK: - 导出/导入

    @MainActor
    public static func export(
        settings: AppSettings,
        quicklinks: [Quicklink],
        snippets: [Snippet],
        commands: [CustomCommand]
    ) -> Data {
        var backup = SettingsBackup()
        backup.quicklinks = quicklinks
        backup.snippets = snippets
        backup.commands = commands
        backup.perAppHotkeys = settings.perAppHotkeys
        backup.paletteHotkey = settings.paletteHotkey
        backup.clipboardHotkey = settings.clipboardHotkey
        backup.paletteSummonMode = settings.paletteSummonMode
        backup.fileSearchScopes = settings.fileSearchScopes
        backup.clipboardEnabled = settings.clipboardEnabled
        backup.clipboardDefaultAction = settings.clipboardDefaultAction
        backup.clipboardCapacity = settings.clipboardCapacity
        backup.systemActionsEnabled = settings.systemActionsEnabled
        backup.windowManagementEnabled = settings.windowManagementEnabled
        backup.aiEnabled = settings.aiEnabled

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(backup)) ?? Data()
    }

    public enum ImportError: LocalizedError {
        case badFormat
        case unsupportedVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .badFormat:
                return L10n.t("备份文件格式无效", "Invalid backup file")
            case .unsupportedVersion(let v):
                return L10n.t("备份版本（\(v)）不受支持", "Backup version (\(v)) not supported")
            }
        }
    }

    @MainActor
    public static func `import`(
        data: Data,
        settings: AppSettings,
        quicklinks: QuicklinkStore?,
        snippets: SnippetStore?,
        commands: CustomCommandStore?
    ) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(SettingsBackup.self, from: data) else {
            throw ImportError.badFormat
        }
        guard backup.version <= schemaVersion else {
            throw ImportError.unsupportedVersion(backup.version)
        }

        for link in backup.quicklinks { quicklinks?.upsert(link) }
        for snippet in backup.snippets { snippets?.upsert(snippet) }
        for command in backup.commands { commands?.upsert(command) }
        settings.perAppHotkeys = backup.perAppHotkeys
        if let paletteHotkey = backup.paletteHotkey { settings.paletteHotkey = paletteHotkey }
        settings.clipboardHotkey = backup.clipboardHotkey
        if let mode = backup.paletteSummonMode { settings.paletteSummonMode = mode }
        if !backup.fileSearchScopes.isEmpty { settings.fileSearchScopes = backup.fileSearchScopes }
        if let value = backup.clipboardEnabled { settings.clipboardEnabled = value }
        if let value = backup.clipboardDefaultAction { settings.clipboardDefaultAction = value }
        if let value = backup.clipboardCapacity { settings.clipboardCapacity = value }
        if let value = backup.systemActionsEnabled { settings.systemActionsEnabled = value }
        if let value = backup.windowManagementEnabled { settings.windowManagementEnabled = value }
        if let value = backup.aiEnabled { settings.aiEnabled = value }
    }
}
