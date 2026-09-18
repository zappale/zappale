import AppKit
import ServiceManagement
import SwiftUI
import ZappaleCore

// MARK: - 设置窗口控制器

@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(core: AppCore) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "zappale 设置"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(
            rootView: SettingsView(core: core)
        )
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - 侧栏分区

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case shortcuts
    case applications
    case fileSearch
    case clipboard
    case quicklinks
    case snippets
    case commands
    case ai

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return L10n.t("通用", "General")
        case .shortcuts: return L10n.t("快捷键", "Shortcuts")
        case .applications: return L10n.t("应用程序", "Apps")
        case .fileSearch: return L10n.t("文件搜索", "Files")
        case .clipboard: return L10n.t("剪贴板", "Clipboard")
        case .quicklinks: return L10n.t("快捷链接", "Quicklinks")
        case .snippets: return L10n.t("片段", "Snippets")
        case .commands: return L10n.t("命令", "Commands")
        case .ai: return "AI"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        case .applications: return "square.grid.2x2"
        case .fileSearch: return "folder"
        case .clipboard: return "clipboard"
        case .quicklinks: return "link"
        case .snippets: return "text.quote"
        case .commands: return "terminal"
        case .ai: return "sparkles"
        }
    }
}

// MARK: - 设置主视图

struct SettingsView: View {
    let core: AppCore
    @State private var tab: SettingsTab = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.5))
                .frame(width: 0.5)
            detail
                .id(tab)
        }
        .frame(width: 720, height: 500)
        .environment(\.openSettingsTab, OpenSettingsTabAction { tab = $0 })
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsTab.allCases) { item in
                SidebarRow(
                    title: item.title,
                    symbol: item.symbol,
                    selected: tab == item
                ) {
                    tab = item
                }
            }
            Spacer()
        }
        .padding(10)
        .frame(width: 200, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    @ViewBuilder
    private var detail: some View {
        ScrollView {
            switch tab {
            case .general: GeneralSettingsPane(core: core)
            case .shortcuts: ShortcutsSettingsPane(core: core)
            case .applications: ApplicationsSettingsPane(core: core)
            case .fileSearch: FileSearchSettingsPane(core: core)
            case .clipboard: ClipboardSettingsPane(core: core)
            case .quicklinks: QuicklinksSettingsPane(core: core)
            case .snippets: SnippetsSettingsPane(core: core)
            case .commands: CommandsSettingsPane(core: core)
            case .ai: AISettingsPane(core: core)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 允许子视图（如权限提示）跳转设置分区。
struct OpenSettingsTabAction {
    let call: (SettingsTab) -> Void
    func callAsFunction(_ tab: SettingsTab) { call(tab) }
}

private extension EnvironmentValues {
    @Entry var openSettingsTab: OpenSettingsTabAction = OpenSettingsTabAction { _ in }
}

// MARK: - 通用组件

struct SidebarRow: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(selected ? Color.primary : .secondary)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.8))
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? Color.primary.opacity(0.09) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

/// 设置分组：标题 + 表单卡片（Sequoia 系统设置的组样式）。
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            )
            .padding(.horizontal, 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }
}

struct SettingsRow<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var control: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - 通用页

struct GeneralSettingsPane: View {
    let core: AppCore
    @ObservedObject private var settings: AppSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "zappale-backup.json"
        panel.message = L10n.t("导出设置（不含 API Key）", "Export settings (no API keys)")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = SettingsBackup.export(core: core)
        do {
            try data.write(to: url, options: .atomic)
            backupNotice = L10n.t("已导出", "Exported")
        } catch {
            backupNotice = error.localizedDescription
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        do {
            try SettingsBackup.import(data: data, core: core)
            backupNotice = L10n.t("已导入", "Imported")
        } catch {
            backupNotice = error.localizedDescription
        }
    }

    init(core: AppCore) {
        self.core = core
        self.settings = core.settings
    }

    @State private var backupNotice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: L10n.t("通用", "General"))
            if let backupNotice {
                Label(backupNotice, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
            SettingsGroup(title: L10n.t("启动", "Launch")) {
                SettingsRow(title: L10n.t("登录时启动 zappale", "Launch at Login")) {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { _, enabled in
                            do {
                                if enabled {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                launchAtLogin.toggle()
                            }
                        }
                }
                Divider().padding(.horizontal, 8)
                SettingsRow(title: L10n.t("全局热键", "Global Hotkey"), subtitle: L10n.t("随时呼出命令面板", "Summon palette")) {
                    Text("⌥ Space")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.primary.opacity(0.06))
                        )
                }
            }
            SettingsGroup(title: L10n.t("语言", "Language")) {
                SettingsRow(title: L10n.t("界面语言", "Interface Language"), subtitle: L10n.t("切换后立即生效", "Applies immediately")) {
                    Picker("", selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }
            }
            SettingsGroup(title: L10n.t("显示", "Display")) {
                SettingsRow(
                    title: L10n.t("减弱视觉效果", "Reduce visual effects"),
                    subtitle: L10n.t("不透明面板底、关闭动画；低配置或低版本系统建议开启",
                                     "Opaque panel, no animations; recommended on older systems")
                ) {
                    Toggle("", isOn: $settings.reducedVisualEffects)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                Divider().padding(.horizontal, 8)
                SettingsRow(
                    title: L10n.t("功能档位", "Feature tier"),
                    subtitle: core.featureGate.tier == .full
                        ? L10n.t("完整（macOS \(core.featureGate.osMajor)）", "Full (macOS \(core.featureGate.osMajor))")
                        : L10n.t("基础功能（macOS \(core.featureGate.osMajor)）", "Basic features (macOS \(core.featureGate.osMajor))")
                ) {
                    EmptyView()
                }
            }
            SettingsGroup(title: L10n.t("功能开关", "Features")) {
                SettingsRow(title: L10n.t("系统动作", "System Actions"), subtitle: L10n.t("锁定 · 睡眠 · 清倒废纸篓 · 音量等", "Lock, sleep, trash, volume")) {
                    Toggle("", isOn: $settings.systemActionsEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                Divider().padding(.horizontal, 8)
                SettingsRow(title: L10n.t("窗口管理", "Window Management"), subtitle: L10n.t("半屏/四分/最大化等布局动作，需要辅助功能权限", "Halves, quarters, maximize; needs Accessibility")) {
                    Toggle("", isOn: $settings.windowManagementEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            SettingsGroup(title: L10n.t("备份", "Backup")) {
                SettingsRow(
                    title: L10n.t("导出 / 导入设置", "Export / Import"),
                    subtitle: L10n.t("快捷链接、片段、命令、热键与偏好；不含 API Key", "Quicklinks, snippets, commands, hotkeys, prefs; no API keys")
                ) {
                    HStack {
                        Button(L10n.t("导出…", "Export…")) { exportBackup() }
                        Button(L10n.t("导入…", "Import…")) { importBackup() }
                    }
                }
            }
            SettingsGroup(title: L10n.t("关于", "About")) {
                SettingsRow(title: L10n.t("版本", "Version")) { Text("0.2.0").foregroundStyle(.secondary) }
                Divider().padding(.horizontal, 8)
                SettingsRow(title: L10n.t("设计参考", "Design"), subtitle: L10n.t("逻辑规格参照 Tinycast · 界面遵循 macOS Sequoia 设计语言", "Behavior follows Tinycast spec; UI follows Sequoia")) {
                    EmptyView()
                }
            }
        }
        .padding(.top, 16)
    }
}

struct PaneHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 17, weight: .semibold))
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
    }
}

// MARK: - 应用程序页

struct ApplicationsSettingsPane: View {
    let core: AppCore
    @ObservedObject private var launcher: AppIndex
    @State private var scanning = false

    init(core: AppCore) {
        self.core = core
        self.launcher = core.launcher
    }

    private var scopeDirectories: [String] {
        ["/Applications", "/System/Applications", "~/Applications"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: L10n.t("应用程序", "Applications"))
            SettingsGroup(title: L10n.t("搜索范围", "Search Scopes")) {
                ForEach(scopeDirectories, id: \.self) { directory in
                    SettingsRow(title: directory) { EmptyView() }
                    if directory != scopeDirectories.last {
                        Divider().padding(.horizontal, 8)
                    }
                }
            }
            SettingsGroup(title: L10n.t("索引", "Index")) {
                SettingsRow(title: L10n.t("已索引应用", "Indexed Apps"), subtitle: L10n.t("模糊搜索 + 使用频次排序", "Fuzzy + frecency")) {
                    Text("\(launcher.entries.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button(L10n.t("重新扫描", "Rescan")) {
                        scanning = true
                        launcher.rescan()
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            scanning = false
                        }
                    }
                    .disabled(scanning)
                }
            }
        }
        .padding(.top, 16)
    }
}

// MARK: - 剪贴板页

struct ClipboardSettingsPane: View {
    let core: AppCore
    @ObservedObject private var settings: AppSettings

    init(core: AppCore) {
        self.core = core
        self.settings = core.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: L10n.t("剪贴板历史", "Clipboard History"))
            SettingsGroup(title: "功能") {
                SettingsRow(title: L10n.t("启用剪贴板历史", "Enable"), subtitle: L10n.t("关闭即停止捕获已有历史保留", "Off stops capture")) {
                    Toggle("", isOn: $settings.clipboardEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                Divider().padding(.horizontal, 8)
                SettingsRow(title: L10n.t("回车动作", "↵ Action"), subtitle: L10n.t("⌘↵ 永远执行另一项", "⌘↵ does the other")) {
                    Picker("", selection: $settings.clipboardDefaultAction) {
                        ForEach(ClipboardDefaultAction.allCases) { action in
                            Text(action.displayName).tag(action)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }
                Divider().padding(.horizontal, 8)
                SettingsRow(title: L10n.t("历史容量", "Capacity"), subtitle: L10n.t("固定项不参与容量淘汰", "Pinned items exempt")) {
                    Picker("", selection: $settings.clipboardCapacity) {
                        ForEach([50, 100, 200, 500, 1000], id: \.self) { count in
                            Text(L10n.t("\(count) 条", "\(count) items")).tag(count)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
            }
            SettingsGroup(title: L10n.t("数据", "Data")) {
                SettingsRow(title: L10n.t("清空历史", "Clear History"), subtitle: L10n.t("删除全部文本、图片与文件记录", "Remove all entries")) {
                    Button(L10n.t("清空…", "Clear…"), role: .destructive) {
                        core.clipboardStore?.clear()
                        core.clipboardStore?.save()
                    }
                }
            }
            SettingsGroup(title: L10n.t("权限", "Permissions")) {
                SettingsRow(
                    title: L10n.t("辅助功能（自动粘贴需要）", "Accessibility (for auto-paste)"),
                    subtitle: L10n.t("未授权时回车仅复制", "Copy only without permission")
                ) {
                    if Paster.isTrusted {
                        Label(L10n.t("已授权", "Granted"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 12))
                    } else {
                        Button(L10n.t("去授权", "Grant…")) { Paster.openAccessibilitySettings() }
                    }
                }
            }
        }
        .padding(.top, 16)
    }
}

// MARK: - 快捷链接页

struct QuicklinksSettingsPane: View {
    let core: AppCore
    @ObservedObject private var store: QuicklinkStore
    @State private var editing: Quicklink?
    @State private var isNew = false

    init(core: AppCore) {
        self.core = core
        self.store = core.quicklinks ?? QuicklinkStore(directory: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: L10n.t("快捷链接", "Quicklinks"))
            VStack(alignment: .leading, spacing: 6) {
                Text("把 URL、搜索或 deeplink 变成命令。模板支持 {query}、{clipboard}、{date}；keyword 用于参数模式（如「gh swift」）。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)

                if let binding = Binding($editing) {
                    QuicklinkEditor(link: binding) { final in
                        if let final { store.upsert(final) }
                        editing = nil
                    }
                    .padding(.bottom, 10)
                }

                VStack(spacing: 0) {
                    ForEach(store.links) { link in
                        quicklinkRow(link)
                        if link.id != store.links.last?.id {
                            Divider().padding(.leading, 12)
                        }
                    }
                    if store.links.isEmpty {
                        Text(L10n.t("还没有快捷链接", "No quicklinks yet"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                )

                HStack {
                    Button {
                        isNew = true
                        editing = Quicklink(name: "", urlTemplate: "https://")
                    } label: {
                        Label(L10n.t("添加链接", "Add Link"), systemImage: "plus")
                    }
                    Spacer()
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 16)
    }

    private func quicklinkRow(_ link: Quicklink) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(L10n.t("未命名", "Untitled"))
                        .font(.system(size: 13, weight: .medium))
                    if !link.keyword.isEmpty {
                        Text(link.keyword)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(Color.accentColor.opacity(0.15))
                            )
                    }
                }
                Text(link.urlTemplate)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(L10n.t("编辑", "Edit")) {
                isNew = false
                editing = link
            }
            Button(role: .destructive) {
                store.delete(ids: [link.id])
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

struct QuicklinkEditor: View {
    @Binding var link: Quicklink
    var onCommit: (Quicklink?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                editorField(title: L10n.t("名称", "Name"), text: $link.name, placeholder: L10n.t("GitHub 搜索", "GitHub Search"))
                editorField(title: "Keyword", text: $link.keyword, placeholder: L10n.t("gh（可选）", "gh (optional)"))
            }
            editorField(
                title: L10n.t("URL 模板", "Template"), text: $link.urlTemplate,
                placeholder: "https://github.com/search?q={query}"
            )
            HStack {
                if QuicklinkTemplate.needsArgument(link.urlTemplate) {
                    Label(L10n.t("含 {query}：输入参数后回车", "Has {query}: type then ↵"), systemImage: "textformat")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.t("取消", "Cancel")) { onCommit(nil) }
                Button(L10n.t("保存", "Save")) {
                    let trimmed = link
                    onCommit(trimmed)
                }
                .disabled(link.name.trimmingCharacters(in: .whitespaces).isEmpty
                    || link.urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5)
        )
    }

    private func editorField(title: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - AI 页

struct AISettingsPane: View {
    let core: AppCore
    @ObservedObject private var settings: AppSettings
    let keychain: KeychainStore

    private enum TestState: Equatable {
        case idle
        case testing
        case success(modelCount: Int)
        case failure(String)
    }

    @State private var keyInput = ""
    @State private var keyExists = false
    @State private var testState: TestState = .idle

    init(core: AppCore) {
        self.core = core
        self.settings = core.settings
        self.keychain = core.keychain
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "AI")
            SettingsGroup(title: L10n.t("AI 能力", "AI")) {
                SettingsRow(title: L10n.t("启用 AI 功能", "Enable AI"), subtitle: L10n.t("关闭时无入口、无请求、无落盘", "Off = fully off")) {
                    Toggle("", isOn: $settings.aiEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            SettingsGroup(title: L10n.t("模型服务（自带 Key）", "Model Provider (BYOK)")) {
                SettingsRow(title: L10n.t("类型", "Provider")) {
                    Picker("", selection: $settings.provider) {
                        ForEach(AIProviderKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                Divider().padding(.horizontal, 8)
                SettingsRow(title: L10n.t("API 地址", "Endpoint"), subtitle: L10n.t("以 /v1 结尾如 https://api.deepseek.com/v1", "Ends with /v1 e.g. https://api.deepseek.com/v1")) {
                    TextField("endpoint", text: $settings.endpointText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                }
                Divider().padding(.horizontal, 8)
                SettingsRow(title: "API Key", subtitle: L10n.t("仅存本机登录 Keychain", "Keychain only")) {
                    HStack {
                        SecureField(L10n.t("输入后点保存", "Enter & save"), text: $keyInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                        Button(L10n.t("保存", "Save")) { saveKey() }
                            .disabled(keyInput.isEmpty)
                        if keyExists {
                            Image(systemName: "key.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                Divider().padding(.horizontal, 8)
                SettingsRow(title: L10n.t("模型 ID", "Model"), subtitle: L10n.t("如 deepseek-chat / claude-sonnet-4-5", "e.g. deepseek-chat / claude-sonnet-4-5")) {
                    TextField("model", text: $settings.model)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                }
                Divider().padding(.horizontal, 8)
                SettingsRow(title: L10n.t("连通性", "Connection")) {
                    HStack {
                        Button(L10n.t("测试连通", "Test")) { testConnection() }
                            .disabled(testState == .testing)
                        testStateView
                    }
                }
            }
            SettingsGroup(title: L10n.t("隐私", "Privacy")) {
                SettingsRow(
                    title: L10n.t("数据边界", "Data Boundary"),
                    subtitle: L10n.t("Key 不进日志/导出；强制 HTTPS（loopback 除外）；无缓存临时会话", "No logs, HTTPS enforced, ephemeral sessions.")
                ) {
                    EmptyView()
                }
            }
        }
        .padding(.top, 16)
        .onAppear { keyExists = keychain.get(account: core.keychainAccount) != nil }
    }

    @ViewBuilder
    private var testStateView: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView().controlSize(.small)
        case .success(let count):
            Label(L10n.t("连接成功，\(count) 个模型", "OK, \(count) models"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 12))
        case .failure(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .font(.system(size: 12))
                .lineLimit(2)
        }
    }

    private func saveKey() {
        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try keychain.set(trimmed, account: core.keychainAccount)
            keyInput = ""
            keyExists = true
            testState = .idle
        } catch {
            testState = .failure(error.localizedDescription)
        }
    }

    private func testConnection() {
        guard let url = settings.endpointURL, AIEndpointPolicy.validate(url) else {
            testState = .failure(AIError.invalidEndpoint.localizedDescription)
            return
        }
        testState = .testing
        let connection = AIConnection(provider: settings.provider, endpoint: url, model: settings.model)
        let client = AIClient(connection: connection, apiKey: keychain.get(account: core.keychainAccount))
        Task {
            do {
                let count = try await client.testConnection()
                testState = .success(modelCount: count)
            } catch {
                testState = .failure(error.localizedDescription)
            }
        }
    }
}
