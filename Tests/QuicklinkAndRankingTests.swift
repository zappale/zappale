import XCTest

@testable import ZappaleCore
@testable import zappale

final class QuicklinkAndRankingTests: XCTestCase {

    // MARK: 快捷链接模板

    func testRenderWithQuery() {
        let date = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 UTC
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let rendered = QuicklinkTemplate.render(
            "https://github.com/search?q={query}",
            argument: "swift ui",
            clipboardText: nil,
            date: date,
            calendar: calendar
        )
        XCTAssertEqual(rendered, .url("https://github.com/search?q=swift%20ui"))
    }

    func testRenderWithoutArgument() {
        let rendered = QuicklinkTemplate.render(
            "https://github.com/search?q={query}",
            argument: nil,
            clipboardText: nil,
            date: Date()
        )
        XCTAssertEqual(rendered, .needsArgument)
    }

    func testRenderFixedLink() {
        let rendered = QuicklinkTemplate.render(
            "https://example.com",
            argument: nil,
            clipboardText: nil,
            date: Date()
        )
        XCTAssertEqual(rendered, .url("https://example.com"))
    }

    func testRenderClipboardAndDatePlaceholders() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let rendered = QuicklinkTemplate.render(
            "https://example.com/{clipboard}/{date}",
            argument: nil,
            clipboardText: "hello world",
            date: date,
            calendar: calendar
        )
        XCTAssertEqual(rendered, .url("https://example.com/hello%20world/2023-11-14"))
    }

    func testRenderRejectsNonHTTPSRemote() {
        let rendered = QuicklinkTemplate.render(
            "http://example.com",
            argument: nil, clipboardText: nil, date: Date()
        )
        XCTAssertEqual(rendered, .invalid)

        let loopback = QuicklinkTemplate.render(
            "http://localhost:8080/api",
            argument: nil, clipboardText: nil, date: Date()
        )
        XCTAssertEqual(loopback, .url("http://localhost:8080/api"))
    }

    func testRenderDeeplinkSchemeAllowed() {
        let rendered = QuicklinkTemplate.render(
            "things:///add?title={query}",
            argument: "task",
            clipboardText: nil,
            date: Date()
        )
        XCTAssertEqual(rendered, .url("things:///add?title=task"))
    }

    // MARK: keyword 匹配

    func testKeywordMatch() {
        let links = [
            Quicklink(name: "GitHub", keyword: "gh", urlTemplate: "https://github.com/search?q={query}"),
            Quicklink(name: "百度", keyword: "bd", urlTemplate: "https://baidu.com/s?wd={query}"),
        ]
        let match = QuicklinkQuery.keywordMatch(query: "gh swift language", links: links)
        XCTAssertEqual(match?.link.keyword, "gh")
        XCTAssertEqual(match?.argument, "swift language")

        let noArg = QuicklinkQuery.keywordMatch(query: "gh", links: links)
        XCTAssertEqual(noArg?.argument, nil)

        XCTAssertNil(QuicklinkQuery.keywordMatch(query: "github swift", links: links))
        XCTAssertNil(QuicklinkQuery.keywordMatch(query: "", links: links))
    }

    // MARK: frecency

    func testRankingBoostBoundsAndDecay() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ranking-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var store = LauncherRankingStore(fileURL: url) { now }
        store.launch("/a.app")

        // 刚用过：加分接近上限但不越界
        let fresh = store.boost(for: "/a.app")
        XCTAssertGreaterThan(fresh, 0)
        XCTAssertLessThanOrEqual(fresh, LauncherRankingStore.boostCap)

        // 两周半后衰减
        let later = LauncherRankingStore(fileURL: url) { now.addingTimeInterval(15 * 86_400) }
        XCTAssertLessThan(later.boost(for: "/a.app"), fresh)

        // 从未使用
        XCTAssertEqual(store.boost(for: "/b.app"), 0)

        // 持久化往返
        let reloaded = LauncherRankingStore(fileURL: url) { now }
        XCTAssertNotNil(reloaded.record(for: "/a.app"))
    }

    // MARK: 系统动作目录

    func testSystemActionCatalogIntegrity() {
        let ids = SystemActionCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "动作 id 必须唯一")

        for def in SystemActionCatalog.all {
            XCTAssertFalse(def.title.isEmpty)
            XCTAssertFalse(def.symbol.isEmpty)
        }

        // 破坏性动作必须要求确认
        let destructive: [SystemActionID] = [.restart, .shutdown, .emptyTrash, .quitAllApps]
        for id in destructive {
            XCTAssertTrue(SystemActionCatalog.def(id)?.requiresConfirmation ?? false, "\(id) 应要求确认")
        }
        XCTAssertFalse(SystemActionCatalog.def(.lockScreen)!.requiresConfirmation)

        // 搜索行为
        XCTAssertTrue(SystemActionCatalog.search("锁定").contains { $0.id == .lockScreen })
        XCTAssertTrue(SystemActionCatalog.search("锁屏").contains { $0.id == .lockScreen })
        XCTAssertTrue(SystemActionCatalog.search("音量").contains { $0.id == .volumeUp })
        XCTAssertTrue(SystemActionCatalog.search("zzz").isEmpty)
    }

    // MARK: URL 识别

    func testURLOpenerNormalize() {
        XCTAssertEqual(URLOpener.normalize("https://example.com"), "https://example.com")
        XCTAssertEqual(URLOpener.normalize("example.com"), "https://example.com")
        XCTAssertEqual(URLOpener.normalize("example.com/path?q=1"), "https://example.com/path?q=1")
        XCTAssertEqual(URLOpener.normalize("localhost:3000"), "https://localhost:3000")
        XCTAssertNil(URLOpener.normalize("notes app"))
        XCTAssertEqual(URLOpener.normalize("localhost"), "https://localhost")
        XCTAssertNil(URLOpener.normalize("file:///etc/passwd"))
        XCTAssertNil(URLOpener.normalize("word"))
    }
}
