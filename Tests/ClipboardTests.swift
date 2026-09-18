import XCTest

@testable import ZappaleCore
@testable import zappale

final class ClipboardTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L10n.apply(.zhHans) // 断言固定中文，语言断言另测
    }

    private func fixedDate(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + offset)
    }

    // MARK: 环形存储

    func testInsertDeduplicatesConsecutiveIdentical() {
        var clock: TimeInterval = 0
        let store = ClipboardStore(directory: nil, capacity: 100) { self.fixedDate(clock) }
        clock = 0
        store.insert(kind: .text, text: "hello")
        clock = 10
        store.insert(kind: .text, text: "hello")

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.date, fixedDate(10))
    }

    func testInsertKeepsDifferentEntries() {
        var clock: TimeInterval = 0
        let store = ClipboardStore(directory: nil, capacity: 100) { self.fixedDate(clock) }
        store.insert(kind: .text, text: "hello")
        store.insert(kind: .text, text: "world")

        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.first?.text, "world")
    }

    func testCapacityEvictsOldestUnpinned() {
        var clock: TimeInterval = 0
        let store = ClipboardStore(directory: nil, capacity: 3) { self.fixedDate(clock) }
        for index in 0..<5 {
            clock = Double(index)
            store.insert(kind: .text, text: "text\(index)")
        }
        XCTAssertEqual(store.items.count, 3)
        // 最旧的被淘汰
        XCTAssertEqual(Set(store.items.map(\.text)), ["text2", "text3", "text4"])
    }

    func testPinnedSurvivesCapacityEviction() {
        var clock: TimeInterval = 0
        let store = ClipboardStore(directory: nil, capacity: 3) { self.fixedDate(clock) }
        store.insert(kind: .text, text: "pin me")
        let id = store.items[0].id
        store.togglePin(id)

        for index in 0..<5 {
            clock = Double(index)
            store.insert(kind: .text, text: "text\(index)")
        }

        XCTAssertTrue(store.items.contains { $0.id == id && $0.pinned })
        // 固定项置顶
        XCTAssertEqual(store.items.first?.id, id)
    }

    func testDeleteAndClear() {
        let store = ClipboardStore(directory: nil, capacity: 10) { self.fixedDate(0) }
        store.insert(kind: .text, text: "a")
        store.insert(kind: .text, text: "b")
        let first = store.items[0]
        store.delete(first.id)
        XCTAssertEqual(store.items.map(\.text), ["a"])

        store.clear()
        XCTAssertTrue(store.items.isEmpty)
    }

    func testPersistenceRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quickagent-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var clock: TimeInterval = 0
        let store = ClipboardStore(directory: directory, capacity: 100) { self.fixedDate(clock) }
        clock = 5
        store.insert(kind: .text, text: "persisted")
        clock = 6
        store.insert(kind: .image, text: "", imagePath: "blob.png")
        store.save()

        let reloaded = ClipboardStore(directory: directory, capacity: 100) { self.fixedDate(0) }
        XCTAssertEqual(reloaded.items.count, 2)
        XCTAssertEqual(reloaded.items.first?.text, "")
        XCTAssertEqual(reloaded.items.first?.imagePath, "blob.png")
        XCTAssertEqual(reloaded.items.last?.text, "persisted")
    }

    // MARK: 搜索

    func testSearchRanking() {
        let base = fixedDate(0)
        let items = [
            ClipboardItem(id: "1", kind: .text, text: "https://example.com/page", date: base, pinned: false),
            ClipboardItem(id: "2", kind: .text, text: "example note", date: base, pinned: false),
            ClipboardItem(id: "3", kind: .text, text: "unrelated", date: base, pinned: false),
        ]
        XCTAssertNotNil(ClipboardSearch.score(query: "example", item: items[0]))
        XCTAssertNil(ClipboardSearch.score(query: "example", item: items[2]))
        // 前缀包含("example note") > 中间包含("https://example.com/page")
        let prefixScore = ClipboardSearch.score(query: "example", item: items[1])!
        let containsScore = ClipboardSearch.score(query: "example", item: items[0])!
        XCTAssertGreaterThan(prefixScore, containsScore)
    }

    func testSectionsPinnedFirst() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let items = [
            ClipboardItem(id: "1", kind: .text, text: "older", date: base, pinned: false),
            ClipboardItem(id: "2", kind: .text, text: "pinned", date: base.addingTimeInterval(-100), pinned: true),
            ClipboardItem(id: "3", kind: .text, text: "newer", date: base.addingTimeInterval(100), pinned: false),
        ]
        let sections = ClipboardSearch.sections(items: items, query: "")
        XCTAssertEqual(sections.first?.id, "clipboard-pinned")
        XCTAssertEqual(sections.first?.entries.first?.title, "pinned")
        XCTAssertEqual(sections.last?.entries.first?.title, "newer")
    }

    // MARK: 派生信息

    func testDerivedURLAndColor() {
        XCTAssertEqual(ClipboardDerived.parse("https://apple.com"), .url("https://apple.com"))
        XCTAssertEqual(ClipboardDerived.parse("apple.com"), .url("https://apple.com"))
        XCTAssertEqual(ClipboardDerived.parse("#FF5500"), .color(hex: "#ff5500"))
        XCTAssertNil(ClipboardDerived.parse("just some text"))
        XCTAssertNil(ClipboardDerived.parse("line1\nline2"))
    }
}

// MARK: - M3：多文件与图片尺寸

extension ClipboardTests {
    func testMultiFileCapturePersists() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quickagent-multifile-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ClipboardStore(directory: directory, capacity: 100) { self.fixedDate(0) }
        store.insert(
            kind: .file, text: "/Users/x/a.txt",
            filePaths: ["/Users/x/a.txt", "/Users/x/b.txt"]
        )
        store.save()

        let reloaded = ClipboardStore(directory: directory, capacity: 100) { self.fixedDate(0) }
        XCTAssertEqual(reloaded.items.first?.filePaths?.count, 2)
        XCTAssertEqual(reloaded.items.first?.text, "/Users/x/a.txt")
        // 副标题显示数量
        let subtitle = ClipboardSearch.subtitle(for: reloaded.items.first!)
        XCTAssertTrue(subtitle?.contains("2 个文件") == true)
    }

    func testImageSizeSubtitle() {
        let item = ClipboardItem(
            kind: .image, text: "", imagePath: "blob.png", date: fixedDate(0),
            imageSize: "1024×768"
        )
        let subtitle = ClipboardSearch.subtitle(for: item)
        XCTAssertTrue(subtitle?.contains("1024×768") == true)
    }

    func testDerivedBadgesInSubtitle() {
        let url = ClipboardItem(kind: .text, text: "https://example.com", date: fixedDate(0))
        XCTAssertTrue(ClipboardSearch.subtitle(for: url)?.hasPrefix("链接") == true)
        XCTAssertEqual(ClipboardSearch.badgeSymbol(for: url), "link")

        let color = ClipboardItem(kind: .text, text: "#FF5500", date: fixedDate(0))
        XCTAssertTrue(ClipboardSearch.subtitle(for: color)?.hasPrefix("颜色 #ff5500") == true)
        XCTAssertEqual(ClipboardSearch.badgeSymbol(for: color), "paintpalette.fill")

        let plain = ClipboardItem(kind: .text, text: "hello", date: fixedDate(0))
        XCTAssertNil(ClipboardSearch.badgeSymbol(for: plain))
    }
}
