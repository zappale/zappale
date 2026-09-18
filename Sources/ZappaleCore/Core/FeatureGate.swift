import Foundation

/// 应用功能清单（FeatureGate 按平台版本判断可用性）。
public enum AppFeature: String, CaseIterable {
    case appLauncher
    case clipboardHistory
    case fileSearch
    case calculator
    case quicklinks
    case snippets
    case customCommands
    case windowManagement
    case notes
    case emoji
    case aiChat
    case aiImages
    case hotkeys
    case doubleTapCommand
    case backup
}

/// 功能档位：基础 / 完整。低版本系统（或受限平台）只保留基础功能。
public enum FeatureTier: Equatable {
    case basic
    case full
}

/// 平台能力门：OS 版本由外部注入（AppCore 用 ProcessInfo 提供；测试可注入任意值）。
/// 规则表集中在此——新增系统版本专属功能时只改这张表。
public struct FeatureGate {
    /// 当前系统主版本（macOS 15 / iOS 18 / macOS 26 …）。
    public let osMajor: Int
    /// 是否桌面端（影响个别能力的意义，如双击 ⌘）。
    public let isDesktop: Bool

    public init(osMajor: Int, isDesktop: Bool = true) {
        self.osMajor = osMajor
        self.isDesktop = isDesktop
    }

    /// 便捷构造：读取当前进程系统版本。
    public static func current() -> FeatureGate {
        FeatureGate(
            osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            isDesktop: true
        )
    }

    /// 功能最低系统版本表。默认全部 14（当前实现的可运行下限）；
    /// 未来仅在引入更高版本专属 API 时上调单项。
    private static let minimumOS: [AppFeature: Int] = [
        .appLauncher: 14, .clipboardHistory: 14, .fileSearch: 14, .calculator: 14,
        .quicklinks: 14, .snippets: 14, .customCommands: 14, .windowManagement: 14,
        .notes: 14, .emoji: 14, .aiChat: 14, .aiImages: 14,
        .hotkeys: 14, .doubleTapCommand: 14, .backup: 14,
    ]

    public func isAvailable(_ feature: AppFeature) -> Bool {
        guard let minimum = Self.minimumOS[feature] else { return true }
        return osMajor >= minimum
    }

    /// 整体档位：≥14 完整；以下只保留基础功能（应用启动 / 剪贴板 / 计算器 / 快捷链接）。
    public var tier: FeatureTier {
        let basicSet: [AppFeature] = [.appLauncher, .clipboardHistory, .calculator, .quicklinks]
        return basicSet.allSatisfy { isAvailable($0) } ? .full : .basic
    }

    /// macOS 26（Liquid Glass 一代）视觉前向开关：UI 层据此选择新视觉或降级样式。
    public var supportsEnhancedVisuals: Bool { osMajor >= 26 }
}
