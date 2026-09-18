import AppKit
import Combine
import Foundation
import ZappaleCore

/// 应用级组合根：持有设置、凭据、索引、各功能服务与窗口控制器。
/// UI 层由此装配；功能行为在各自的协调层，这里只做接线。
@MainActor
final class AppCore: NSObject, ObservableObject, NSApplicationDelegate {
    static let shared = AppCore()

    override init() {
        featureGate = .current()
        super.init()
    }

    let settings = AppSettings()
    /// 平台能力门（OS 版本 → 功能档位；注入式，测试可替换）。
    let featureGate: FeatureGate
    let keychain = KeychainStore(service: "dev.zappale.apikeys", legacyService: "dev.quickagent.apikeys")
    let keychainAccount = "default"
    lazy var launcher = AppIndex()

    // MARK: 功能服务（启动时装配）

    private(set) var supportDirectory: URL?
    private(set) var ranking: LauncherRankingStore?
    private(set) var quicklinks: QuicklinkStore?
    private(set) var clipboardStore: ClipboardStore?
    private(set) var clipboard: ClipboardManager!
    private(set) var notes: NotesStore?
    private(set) var notesEditor: NotesEditorController?
    private(set) var snippets: SnippetStore?
    private(set) var commands: CustomCommandStore?
    private(set) var chatHistory: ChatHistoryStore?

    /// AI 图片落盘目录（附件与生成图）。
    private(set) var mediaDirectory: URL?
    let fileSearch = FileSearchService()

    private var statusItem: NSStatusItem?
    private var hotkeyCenter: HotkeyCenter?
    private var doubleTapMonitor: DoubleTapMonitor?
    private var paletteController: PaletteWindowController?
    private var settingsController: SettingsWindowController?
    private var cancellables: Set<AnyCancellable> = []

    /// 最近一次热键注册失败的描述（设置页展示用）。
    @Published private(set) var hotkeyFailures: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        L10n.apply(settings.language)
        bootstrapServices()
        installStatusItem()
        installHotkey()
        paletteController = PaletteWindowController(core: self)
        settingsController = SettingsWindowController(core: self)
        observeSettings()
    }

    /// 长生命周期服务一次装配：支持目录、频次排行、快捷链接、剪贴板。
    private func bootstrapServices() {
        let support = Self.resolveSupportDirectory()
        supportDirectory = support

        launcher.loadIfNeeded()
        ranking = LauncherRankingStore(fileURL: support?.appendingPathComponent("launcher-ranking.json"))

        let quicklinkStore = QuicklinkStore(directory: support)
        quicklinkStore.installDefaultsIfNeeded()
        quicklinks = quicklinkStore

        let clipboardDirectory = support.map { $0.appendingPathComponent("clipboard", isDirectory: true) }
        let store = ClipboardStore(
            directory: clipboardDirectory,
            capacity: settings.clipboardCapacity
        )
        clipboardStore = store
        let manager = ClipboardManager(store: store, settings: settings, directory: clipboardDirectory)
        clipboard = manager

        let notesStore = NotesStore(directory: support?.appendingPathComponent("notes", isDirectory: true))
        notes = notesStore
        notesEditor = NotesEditorController(store: notesStore)

        snippets = SnippetStore(directory: support)
        commands = CustomCommandStore(directory: support)

        chatHistory = ChatHistoryStore(directory: support)
        let media = support?.appendingPathComponent("ai-media", isDirectory: true)
        if let media {
            try? FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        }
        mediaDirectory = media
    }

    /// 保存 AI 图片数据，返回相对文件名（ai-media 目录内）。
    func saveMediaImage(_ data: Data) -> String? {
        guard let mediaDirectory else { return nil }
        let name = UUID().uuidString + ".png"
        do {
            try data.write(to: mediaDirectory.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    func mediaImageURL(_ name: String) -> URL? {
        mediaDirectory?.appendingPathComponent(name)
    }

    private static func resolveSupportDirectory() -> URL? {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let base else { return nil }
        let url = base.appendingPathComponent("zappale", isDirectory: true)
        // 旧名迁移：QuickAgent 目录改名为 zappale（保留剪贴板/链接/排行数据）
        let legacy = base.appendingPathComponent("QuickAgent", isDirectory: true)
        if !fileManager.fileExists(atPath: url.path),
           fileManager.fileExists(atPath: legacy.path) {
            try? fileManager.moveItem(at: legacy, to: url)
        }
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 设置变化 → 应用副作用（剪贴板开关、容量重建）。
    private func observeSettings() {
        settings.$clipboardEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.clipboard.applyEnabled(enabled)
            }
            .store(in: &cancellables)

        settings.$clipboardCapacity
            .receive(on: DispatchQueue.main)
            .dropFirst()
            .sink { [weak self] capacity in
                guard let self else { return }
                // 容量变化：先停旧轮询器，再以新容量重建存储（保留现有条目文件）
                self.clipboard.applyEnabled(false)
                let directory = self.supportDirectory?
                    .appendingPathComponent("clipboard", isDirectory: true)
                self.clipboardStore?.save()
                let store = ClipboardStore(directory: directory, capacity: capacity)
                self.clipboardStore = store
                self.clipboard = ClipboardManager(
                    store: store, settings: self.settings, directory: directory
                )
                self.clipboard.applyEnabled(self.settings.clipboardEnabled)
            }
            .store(in: &cancellables)

        // 语言切换：菜单重建 + 面板令牌刷新（面板由 PaletteState 订阅处理）
        settings.$language
            .receive(on: DispatchQueue.main)
            .dropFirst()
            .sink { [weak self] language in
                L10n.apply(language)
                self?.installStatusItem()
            }
            .store(in: &cancellables)

        // 热键相关设置任一变化 → 呼出方式应用 + 全量重注
        Publishers.Merge4(
            settings.$paletteHotkey.dropFirst().map { _ in () },
            settings.$clipboardHotkey.dropFirst().map { _ in () },
            settings.$perAppHotkeys.dropFirst().map { _ in () },
            settings.$paletteSummonMode.dropFirst().map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.applySummonMode() }
        .store(in: &cancellables)
    }

    // MARK: - 菜单栏

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "bolt.circle.fill",
            accessibilityDescription: "zappale"
        )

        let menu = NSMenu()

        let paletteRow = menu.addItem(
            withTitle: L10n.t("呼出面板", "Summon Palette") + "（\(settings.paletteSummonMode == .hotkey ? settings.paletteHotkey.display : "⌘⌘")）",
            action: #selector(togglePaletteFromMenu),
            keyEquivalent: ""
        )
        paletteRow.target = self

        let clipboardRow = menu.addItem(
            withTitle: L10n.t("剪贴板历史", "Clipboard History"),
            action: #selector(openClipboardHistory),
            keyEquivalent: ""
        )
        clipboardRow.target = self

        let clearRow = menu.addItem(
            withTitle: L10n.t("清空剪贴板历史", "Clear History"),
            action: #selector(clearClipboardHistory),
            keyEquivalent: ""
        )
        clearRow.target = self

        menu.addItem(.separator())
        let settingsRow = menu.addItem(
            withTitle: L10n.t("设置…", "Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsRow.target = self
        let rescanRow = menu.addItem(
            withTitle: L10n.t("重新扫描应用", "Rescan Apps"),
            action: #selector(rescanApps),
            keyEquivalent: "r"
        )
        rescanRow.target = self
        menu.addItem(.separator())
        let quitRow = menu.addItem(
            withTitle: L10n.t("退出 zappale", "Quit zappale"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitRow.target = self

        item.menu = menu
        statusItem = item
    }

    private func installHotkey() {
        let center = HotkeyCenter()
        center.onTrigger = { [weak self] id in
            Task { @MainActor in self?.handleHotkey(id: id) }
        }
        do {
            try center.installHandler()
            hotkeyCenter = center
            rebindHotkeys()
        } catch {
            NSLog("zappale: 热键处理器安装失败: \(error)")
        }

        let monitor = DoubleTapMonitor()
        monitor.onTrigger = { [weak self] in
            Task { @MainActor in self?.togglePalette() }
        }
        doubleTapMonitor = monitor
        applySummonMode()
    }

    /// 呼出方式变化：启停双击监听 + 重注组合键。
    func applySummonMode() {
        if settings.paletteSummonMode == .doubleTapCommand {
            if doubleTapMonitor?.start() == false {
                // 无辅助功能权限：功能不可用，设置页会展示引导
                doubleTapMonitor?.stop()
            }
        } else {
            doubleTapMonitor?.stop()
        }
        rebindHotkeys()
    }

    private func rebindHotkeys() {
        guard let hotkeyCenter else { return }
        var commandHotkeys: [String: HotkeySpec] = [:]
        for command in commands?.commands ?? [] {
            if let hotkey = command.hotkey { commandHotkeys[command.id] = hotkey }
        }
        let failures = hotkeyCenter.rebind(settings.hotkeyBindings(commandHotkeys: commandHotkeys))
        hotkeyFailures = failures.map { "\($0.0.spec.display)：\($0.1.localizedDescription)" }
    }

    private func handleHotkey(id: String) {
        if id == "palette" {
            togglePalette()
        } else if id == "clipboard" {
            showClipboardHistory()
        } else if id.hasPrefix("app:") {
            toggleApp(path: String(id.dropFirst(4)))
        } else if id.hasPrefix("cmd:") {
            runCustomCommand(id: String(id.dropFirst(4)))
        }
    }

    /// 应用切换 toggle 语义（对齐 tinycast）：运行中且在最前 → 隐藏；
    /// 运行中不在最前 → 激活；未运行 → 启动。
    func toggleApp(path: String) {
        let url = URL(fileURLWithPath: path)
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleURL?.path == path
        }) {
            if running.isActive {
                running.hide()
            } else {
                _ = running.activate()
            }
        } else {
            NSWorkspace.shared.openApplication(
                at: url, configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }

    // MARK: - 动作

    func togglePalette() {
        paletteController?.toggle()
    }

    func showClipboardHistory() {
        paletteController?.showClipboard()
    }

    func showSettings() {
        settingsController?.show()
    }

    /// 记录一次应用启动（frecency 排序用）。
    func recordAppLaunch(path: String) {
        ranking?.launch(path)
    }

    func openNote(id: String) {
        notesEditor?.show(noteID: id)
    }

    func createNote() {
        notesEditor?.createAndShow()
    }

    /// 热键触发：静默运行自定义命令（面板不必在前）。
    func runCustomCommand(id: String) {
        guard let command = commands?.command(id) else { return }
        Task { @MainActor in
            let outcome = await CustomCommandRunner.run(command.script)
            if !outcome.succeeded {
                paletteController?.state.showNotice(
                    L10n.t("命令失败（\(outcome.exitCode)）", "Command failed (\(outcome.exitCode))")
                )
            }
        }
    }

    @objc private func togglePaletteFromMenu() { togglePalette() }
    @objc private func openClipboardHistory() { showClipboardHistory() }
    @objc private func openSettings() { showSettings() }
    @objc private func rescanApps() { launcher.rescan() }
    @objc private func clearClipboardHistory() {
        clipboardStore?.clear()
        clipboardStore?.save()
        paletteController?.state.showNotice("剪贴板历史已清空")
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
