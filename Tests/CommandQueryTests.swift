import XCTest

@testable import ZappaleCore
@testable import zappale

final class CommandQueryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L10n.apply(.zhHans)
    }

    private func makeContext(
        apps: [AppEntry] = [],
        quicklinks: [Quicklink] = [],
        systemActionsEnabled: Bool = true
    ) -> CommandQuery.Context {
        CommandQuery.Context(
            apps: apps,
            frecency: { _ in 0 },
            quicklinks: quicklinks,
            quicklinkArgumentClipboard: nil,
            now: Date(timeIntervalSince1970: 1_700_000_000),
            systemActionsEnabled: systemActionsEnabled
        )
    }

    // MARK: 空查询

    func testEmptyQueryShowsTopAppsAndQuickActions() {
        let apps = (1...8).map { AppEntry(path: "/Applications/App\($0).app", name: "App\($0)") }
        let context = makeContext(apps: apps)
        let sections = CommandQuery.sections(query: "", context: context)

        XCTAssertEqual(sections.first?.id, "apps-top")
        XCTAssertEqual(sections.first?.entries.count, 6)
        XCTAssertTrue(sections.contains { $0.id == "system-quick" })
        XCTAssertFalse(sections.contains { $0.id == "calc" })
    }

    func testEmptyQueryHidesSystemActionsWhenDisabled() {
        let sections = CommandQuery.sections(
            query: "", context: makeContext(systemActionsEnabled: false)
        )
        XCTAssertFalse(sections.contains { $0.id == "system-quick" })
    }

    // MARK: 计算卡

    func testCalculatorCardIsFirstRow() {
        let apps = [AppEntry(path: "/Applications/A.app", name: "A")]
        let sections = CommandQuery.sections(query: "10km to mi", context: makeContext(apps: apps))
        let rows = PaletteRows.flatten(sections)
        XCTAssertEqual(rows.first?.kind, .calculator(display: "= 6.21371 mi"))
    }

    // MARK: 应用搜索 + frecency

    func testAppSearchRanksExactPrefixFirst() {
        let apps = [
            AppEntry(path: "/Applications/Notes.app", name: "Notes"),
            AppEntry(path: "/Applications/NotesApp.app", name: "NotesApp"),
            AppEntry(path: "/Applications/Xcode.app", name: "Xcode"),
        ]
        let sections = CommandQuery.sections(query: "notes", context: makeContext(apps: apps))
        let appSection = sections.first { $0.id == "apps" }
        XCTAssertEqual(appSection?.entries.first?.title, "Notes")
    }

    func testFrecencyBoostCannotBeatStrongerMatch() {
        let apps = [
            AppEntry(path: "/a.app", name: "Spotlight"),
            AppEntry(path: "/b.app", name: "Spot"),
        ]
        // "Spot" 完全匹配应排第一，即使 Spotlight 有 frecency 加分
        let context = CommandQuery.Context(
            apps: apps,
            frecency: { path in path == "/a.app" ? LauncherRankingStore.boostCap : 0 },
            quicklinks: [], quicklinkArgumentClipboard: nil,
            now: Date(), systemActionsEnabled: true
        )
        let sections = CommandQuery.sections(query: "spot", context: context)
        let appSection = sections.first { $0.id == "apps" }
        XCTAssertEqual(appSection?.entries.first?.title, "Spot")
    }

    // MARK: 快捷链接

    func testQuicklinkKeywordPrefixMode() {
        let gh = Quicklink(name: "GitHub 搜索", keyword: "gh", urlTemplate: "https://github.com/search?q={query}")
        let sections = CommandQuery.sections(query: "gh swift ui", context: makeContext(quicklinks: [gh]))
        let quicklinkSection = sections.first { $0.id == "quicklinks" }
        XCTAssertEqual(quicklinkSection?.entries.first?.title, "GitHub 搜索「swift ui」")
        XCTAssertEqual(quicklinkSection?.entries.first?.subtitle, "https://github.com/search?q=swift%20ui")
    }

    func testQuicklinkNeedsArgumentHint() {
        let gh = Quicklink(name: "GitHub 搜索", keyword: "gh", urlTemplate: "https://github.com/search?q={query}")
        let sections = CommandQuery.sections(query: "gh", context: makeContext(quicklinks: [gh]))
        let row = sections.flatMap(\.entries).first { $0.id.hasPrefix("quicklink-") }
        XCTAssertEqual(row?.subtitle, "输入参数后回车 · https://github.com/search?q={query}")
    }

    func testQuicklinkNameFuzzyMatch() {
        let gh = Quicklink(name: "GitHub 搜索", keyword: "gh", urlTemplate: "https://github.com/search?q={query}")
        let sections = CommandQuery.sections(query: "git", context: makeContext(quicklinks: [gh]))
        XCTAssertTrue(sections.contains { $0.id == "quicklinks" })
    }

    // MARK: 系统动作

    func testSystemActionSearchAndConfirmationFlags() {
        let sections = CommandQuery.sections(query: "关机", context: makeContext())
        let rows = PaletteRows.flatten(sections)
        let shutdown = rows.first { $0.id == "system-shutdown" }
        XCTAssertEqual(shutdown?.requiresConfirmation, true)
        let sections2 = CommandQuery.sections(query: "锁定", context: makeContext())
        let lock = PaletteRows.flatten(sections2).first { $0.id == "system-lockScreen" }
        XCTAssertEqual(lock?.requiresConfirmation, false)
    }

    // MARK: 回退

    func testFallbackWhenNoResults() {
        let sections = CommandQuery.sections(query: "zzzz不存在的应用", context: makeContext())
        let rows = PaletteRows.flatten(sections)
        XCTAssertTrue(rows.contains { $0.kind == .webSearch(query: "zzzz不存在的应用") })
    }

    func testFallbackOpenURL() {
        let sections = CommandQuery.sections(query: "example.com", context: makeContext())
        let rows = PaletteRows.flatten(sections)
        guard case .openURL(let url)? = rows.first?.kind else {
            return XCTFail("首行应是打开网址")
        }
        XCTAssertEqual(url, "https://example.com")
    }

    // MARK: PaletteRows

    func testFlattenAndSelection() {
        let sections = [
            CommandSection(id: "a", title: "A", entries: [
                CommandEntry(id: "1", kind: .webSearch(query: "x"), title: "1", icon: .symbol("x")),
                CommandEntry(id: "2", kind: .webSearch(query: "x"), title: "2", icon: .symbol("x")),
            ]),
            CommandSection(id: "b", title: "B", entries: [
                CommandEntry(id: "3", kind: .webSearch(query: "x"), title: "3", icon: .symbol("x")),
            ]),
        ]
        let rows = PaletteRows.flatten(sections)
        XCTAssertEqual(rows.map(\.id), ["1", "2", "3"])

        XCTAssertEqual(PaletteRows.moveSelection(index: 0, delta: -1, count: 3), 0)
        XCTAssertEqual(PaletteRows.moveSelection(index: 1, delta: -1, count: 3), 0)
        XCTAssertEqual(PaletteRows.moveSelection(index: 1, delta: 5, count: 3), 2)
        XCTAssertEqual(PaletteRows.moveSelection(index: 0, delta: 1, count: 0), 0)

        XCTAssertEqual(PaletteRows.quickActivateIndex(character: "1"), 0)
        XCTAssertEqual(PaletteRows.quickActivateIndex(character: "9"), 8)
        XCTAssertNil(PaletteRows.quickActivateIndex(character: "0"))
        XCTAssertNil(PaletteRows.quickActivateIndex(character: "a"))
    }
}
