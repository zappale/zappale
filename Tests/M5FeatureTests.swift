import Carbon.HIToolbox
import XCTest

@testable import ZappaleCore
@testable import zappale

final class M5FeatureTests: XCTestCase {

    override func setUp() {
        super.setUp()
        L10n.apply(.zhHans)
    }

    // MARK: - 语言包

    func testLanguageSwitch() {
        L10n.apply(.zhHans)
        XCTAssertEqual(L10n.t("剪贴板", "Clipboard"), "剪贴板")
        L10n.apply(.english)
        XCTAssertEqual(L10n.t("剪贴板", "Clipboard"), "Clipboard")
        // 英文为空回退中文
        XCTAssertEqual(L10n.t("仅中文"), "仅中文")
        L10n.apply(.zhHans)
    }

    func testSystemActionDualLanguageSearch() {
        // 中文界面下也能用英文搜到
        XCTAssertTrue(SystemActionCatalog.search("lock").contains { $0.id == .lockScreen })
        XCTAssertTrue(SystemActionCatalog.search("锁定").contains { $0.id == .lockScreen })
        // 窗口与 AI 动作在目录中
        XCTAssertTrue(SystemActionCatalog.all.contains { $0.id == .windowLeft })
        XCTAssertTrue(SystemActionCatalog.all.contains { $0.id == .aiTranslate })
        XCTAssertEqual(SystemActionCatalog.all.count,
                       Set(SystemActionCatalog.all.map(\.id)).count, "动作 id 唯一")
        // 窗口动作往返映射
        for action in WindowAction.allCases {
            XCTAssertEqual(SystemActionCatalog.windowAction(for: SystemActionCatalog.windowActionID(action)), action)
        }
    }

    func testCatalogFilteringByToggles() {
        let context = CommandQuery.Context(
            aiEnabled: false,
            windowManagementEnabled: false,
            systemActionsEnabled: true
        )
        let sections = CommandQuery.sections(query: "half", context: context)
        let ids = Set(PaletteRows.flatten(sections).map(\.id))
        XCTAssertFalse(ids.contains("system-windowLeft"), "窗口关闭时不应出现")

        let context2 = CommandQuery.Context(
            aiEnabled: true,
            windowManagementEnabled: true,
            systemActionsEnabled: true
        )
        let sections2 = CommandQuery.sections(query: "translate", context: context2)
        XCTAssertTrue(PaletteRows.flatten(sections2).contains { $0.id == "system-aiTranslate" })

        let sections3 = CommandQuery.sections(query: "translate", context: CommandQuery.Context(
            aiEnabled: false, systemActionsEnabled: true
        ))
        XCTAssertFalse(PaletteRows.flatten(sections3).contains { $0.id == "system-aiTranslate" })
    }

    // MARK: - 窗口几何

    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let window = CGRect(x: 300, y: 300, width: 400, height: 300)

    private func target(_ action: WindowAction, screens: [CGRect]? = nil) -> CGRect? {
        WindowPlacement.target(
            action: action, window: window, screen: screen,
            screens: screens ?? [screen], screenIndex: 0
        )
    }

    func testHalvesAndQuarters() {
        XCTAssertEqual(target(.leftHalf), CGRect(x: 0, y: 0, width: 500, height: 800))
        XCTAssertEqual(target(.rightHalf), CGRect(x: 500, y: 0, width: 500, height: 800))
        XCTAssertEqual(target(.topHalf), CGRect(x: 0, y: 400, width: 1000, height: 400))
        XCTAssertEqual(target(.bottomHalf), CGRect(x: 0, y: 0, width: 1000, height: 400))
        XCTAssertEqual(target(.topLeft), CGRect(x: 0, y: 400, width: 500, height: 400))
        XCTAssertEqual(target(.bottomRight), CGRect(x: 500, y: 0, width: 500, height: 400))
    }

    func testThirdsCenterMaximize() {
        XCTAssertEqual(target(.leftTwoThirds)?.width, 1000.0 * 2 / 3)
        XCTAssertEqual(target(.rightTwoThirds)?.width, 1000.0 * 2 / 3)
        XCTAssertEqual(target(.rightTwoThirds)?.maxX, 1000)
        // 居中保持尺寸
        let center = target(.center)!
        XCTAssertEqual(center.width, 400)
        XCTAssertEqual(center.midX, screen.midX)
        XCTAssertEqual(target(.maximize), screen)
        XCTAssertEqual(target(.almostMaximize), screen.insetBy(dx: 12, dy: 12))
    }

    func testRestoreAndDisplayMoves() {
        XCTAssertNil(target(.restore), "无记忆时还原返回 nil（服务层处理）")
        // 单屏跨屏不适用
        XCTAssertNil(target(.nextDisplay))
        // 双屏：移到右屏（保持比例、目标屏内居中）
        let screens = [screen, CGRect(x: 1000, y: 0, width: 800, height: 600)]
        let next = target(.nextDisplay, screens: screens)!
        XCTAssertGreaterThanOrEqual(next.minX, 1000)
        XCTAssertLessThanOrEqual(next.maxX, 1800)
        XCTAssertEqual(next.midX, 1400, accuracy: 1.0)
        XCTAssertLessThanOrEqual(next.width, 800)
        // prev 从最左屏环绕到最右屏
        let prev = target(.prevDisplay, screens: screens)!
        XCTAssertGreaterThanOrEqual(prev.minX, 1000)
        XCTAssertLessThanOrEqual(prev.maxX, 1800)
        // 环绕：右屏再 next 回到左屏
        let wrapped = WindowPlacement.target(
            action: .nextDisplay, window: window,
            screen: screens[1], screens: screens, screenIndex: 1
        )
        XCTAssertLessThanOrEqual(wrapped?.maxX ?? -1, 1000)
    }

    // MARK: - 片段

    func testSnippetTemplateRender() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let expectedDate = formatter.string(from: date)
        let rendered = SnippetTemplate.render(
            "您好 {query}，今天是 {date}，来自 {clipboard}",
            argument: "小明",
            clipboardText: "项目 A",
            date: date
        )
        XCTAssertEqual(rendered, "您好 小明，今天是 \(expectedDate)，来自 项目 A")

        // 缺参数 → nil
        XCTAssertNil(SnippetTemplate.render("hi {query}", argument: nil, clipboardText: nil, date: date))
        XCTAssertNil(SnippetTemplate.render("hi {query}", argument: "  ", clipboardText: nil, date: date))
        // 无占位符直接返回
        XCTAssertEqual(SnippetTemplate.render("固定文本", argument: nil, clipboardText: nil, date: date), "固定文本")
    }

    func testSnippetQueryMatch() {
        let snippets = [
            Snippet(name: "邮件签名", keyword: "sig", template: "--\\nZhang"),
            Snippet(name: "问候", keyword: "hi", template: "Hello {query}"),
        ]
        let match = SnippetQuery.keywordMatch(query: "sig 附加说明", snippets: snippets)
        XCTAssertEqual(match?.snippet.keyword, "sig")
        XCTAssertEqual(match?.argument, "附加说明")

        XCTAssertEqual(SnippetQuery.keywordMatch(query: "sig", snippets: snippets)?.argument, nil)
        XCTAssertNil(SnippetQuery.keywordMatch(query: "签名", snippets: snippets))
        XCTAssertTrue(SnippetQuery.search("签名", snippets: snippets).count == 1)
    }

    func testSnippetSectionInAppsScreen() {
        let snippet = Snippet(name: "邮箱", keyword: "mail", template: "hi@zappale.dev")
        let context = CommandQuery.Context(snippets: [snippet])
        let sections = CommandQuery.sections(query: "邮箱", context: context)
        XCTAssertTrue(sections.contains { $0.id == "snippets" })
        // keyword 参数模式
        let sections2 = CommandQuery.sections(query: "mail 给团队", context: context)
        let row = sections2.flatMap(\.entries).first { $0.id == "snippet-\(snippet.id)" }
        XCTAssertEqual(row?.title, "邮箱「给团队」")
    }

    // MARK: - 自定义命令

    func testCustomCommandQueryAndSection() {
        let command = CustomCommand(name: "清理缓存", script: "echo done", requiresConfirmation: true)
        XCTAssertEqual(CustomCommandQuery.search("清理", commands: [command]).count, 1)
        XCTAssertEqual(CustomCommandQuery.search("nothing", commands: [command]).count, 0)

        let context = CommandQuery.Context(commands: [command])
        let sections = CommandQuery.sections(query: "清理", context: context)
        let row = sections.flatMap(\.entries).first { $0.id == "command-\(command.id)" }
        XCTAssertEqual(row?.requiresConfirmation, true)
    }

    func testCustomCommandRunnerEcho() async {
        let outcome = await CustomCommandRunner.run("echo hello-zappale")
        XCTAssertTrue(outcome.succeeded)
        XCTAssertTrue(outcome.output.contains("hello-zappale"))

        let failed = await CustomCommandRunner.run("exit 3")
        XCTAssertFalse(failed.succeeded)
        XCTAssertEqual(failed.exitCode, 3)
    }

    @MainActor
    func testCustomCommandStoreRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zappale-cmds-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = CustomCommandStore(directory: directory)
        var command = CustomCommand(name: "构建", script: "swift build")
        command.hotkey = HotkeySpec(keyCode: 11, carbonModifiers: UInt32(controlKey))
        store.upsert(command)
        let reloaded = CustomCommandStore(directory: directory)
        XCTAssertEqual(reloaded.commands.count, 1)
        XCTAssertEqual(reloaded.commands.first?.hotkey?.keyCode, 11)

        // 命令热键进入 bindings
        let defaults = UserDefaults(suiteName: "cmd-bindings-test")!
        defer { defaults.removePersistentDomain(forName: "cmd-bindings-test") }
        let settings = AppSettings(defaults: defaults)
        settings.paletteSummonMode = .hotkey
        let hotkeys: [String: HotkeySpec] = [reloaded.commands[0].id: reloaded.commands[0].hotkey!]
        XCTAssertTrue(settings.hotkeyBindings(commandHotkeys: hotkeys)
            .contains { $0.id == "cmd:\(reloaded.commands[0].id)" })
    }

    // MARK: - 备份

    @MainActor
    func testBackupRoundTrip() throws {
        // 独立 settings + 临时目录 stores，避免依赖未启动的 AppCore
        let suiteName = "backup-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("zappale-backup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let quicklinkStore = QuicklinkStore(directory: temp)
        let snippetStore = SnippetStore(directory: temp)
        let commandStore = CustomCommandStore(directory: temp)
        quicklinkStore.upsert(Quicklink(name: "备份测试", keyword: "bk", urlTemplate: "https://example.com/?q={query}"))
        snippetStore.upsert(Snippet(name: "备份片段", template: "hello"))
        commandStore.upsert(CustomCommand(name: "备份命令", script: "echo 1"))

        let data = SettingsBackup.export(
            settings: settings,
            quicklinks: quicklinkStore.links,
            snippets: snippetStore.snippets,
            commands: commandStore.commands
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(SettingsBackup.self, from: data)
        XCTAssertEqual(backup.version, SettingsBackup.schemaVersion)
        XCTAssertTrue(backup.quicklinks.contains { $0.name == "备份测试" })
        XCTAssertTrue(backup.snippets.contains { $0.name == "备份片段" })
        XCTAssertTrue(backup.commands.contains { $0.name == "备份命令" })
        // 备份不含任何密钥字段
        let raw = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(raw.lowercased().contains("apikey"))

        // 导入到全新 stores：内容一致
        let freshQuicklinks = QuicklinkStore(directory: nil)
        let freshSnippets = SnippetStore(directory: nil)
        let freshCommands = CustomCommandStore(directory: nil)
        let freshSuite = "backup-apply-\(UUID().uuidString)"
        let freshDefaults = UserDefaults(suiteName: freshSuite)!
        defer { freshDefaults.removePersistentDomain(forName: freshSuite) }
        let freshSettings = AppSettings(defaults: freshDefaults)
        try SettingsBackup.import(
            data: data,
            settings: freshSettings,
            quicklinks: freshQuicklinks,
            snippets: freshSnippets,
            commands: freshCommands
        )
        XCTAssertEqual(freshQuicklinks.links.filter { $0.name == "备份测试" }.count, 1)
        XCTAssertEqual(freshSnippets.snippets.filter { $0.name == "备份片段" }.count, 1)
        XCTAssertEqual(freshCommands.commands.filter { $0.name == "备份命令" }.count, 1)
        XCTAssertEqual(freshSettings.fileSearchScopes, backup.fileSearchScopes)
    }
}

// MARK: - FeatureGate（M7 分层重构）

extension M5FeatureTests {
    func testFeatureGateTiers() {
        // 完整档：macOS 14+
        let modern = FeatureGate(osMajor: 15)
        XCTAssertEqual(modern.tier, .full)
        XCTAssertTrue(modern.isAvailable(.windowManagement))
        XCTAssertTrue(modern.isAvailable(.aiImages))
        XCTAssertFalse(modern.supportsEnhancedVisuals)

        // macOS 26：增强视觉前向开关
        let v26 = FeatureGate(osMajor: 26)
        XCTAssertTrue(v26.supportsEnhancedVisuals)
        XCTAssertEqual(v26.tier, .full)

        // 低版本：仅基础档（启动器/剪贴板/计算器/快捷链接按规则表不可用则整体降级）
        let old = FeatureGate(osMajor: 13)
        XCTAssertEqual(old.tier, .basic)
        XCTAssertFalse(old.isAvailable(.windowManagement))
        XCTAssertFalse(old.isAvailable(.notes))
        // 基础四件套在最低规则下也不可用时 tier 为 basic（13 < 14）
        XCTAssertFalse(old.isAvailable(.appLauncher))
    }
}
