import XCTest

@testable import ZappaleCore
@testable import zappale

final class M4FeatureTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L10n.apply(.zhHans)
    }

    // MARK: - 双击检测

    func testDoubleTapDetects() {
        var detector = DoubleTapDetector()
        // 按下 → 抬起 → 0.2s 内再按下 = 命中
        XCTAssertFalse(detector.feed(isTargetDown: true, hasOtherModifiers: false, at: 0))
        XCTAssertFalse(detector.feed(isTargetDown: false, hasOtherModifiers: false, at: 0.05))
        XCTAssertTrue(detector.feed(isTargetDown: true, hasOtherModifiers: false, at: 0.25))
    }

    func testDoubleTapRejectsSlow() {
        var detector = DoubleTapDetector()
        XCTAssertFalse(detector.feed(isTargetDown: true, hasOtherModifiers: false, at: 0))
        XCTAssertFalse(detector.feed(isTargetDown: false, hasOtherModifiers: false, at: 0.05))
        // 超过 0.4s 的第二次按下不命中，但作为新一轮开始
        XCTAssertFalse(detector.feed(isTargetDown: true, hasOtherModifiers: false, at: 1.0))
        XCTAssertFalse(detector.feed(isTargetDown: false, hasOtherModifiers: false, at: 1.05))
        XCTAssertTrue(detector.feed(isTargetDown: true, hasOtherModifiers: false, at: 1.2))
    }

    func testDoubleTapRejectsOtherModifiers() {
        var detector = DoubleTapDetector()
        XCTAssertFalse(detector.feed(isTargetDown: true, hasOtherModifiers: false, at: 0))
        // 中途按住其他修饰键 → 整体复位
        XCTAssertFalse(detector.feed(isTargetDown: false, hasOtherModifiers: true, at: 0.05))
        XCTAssertFalse(detector.feed(isTargetDown: true, hasOtherModifiers: false, at: 0.1))
        XCTAssertFalse(detector.feed(isTargetDown: false, hasOtherModifiers: false, at: 0.15))
        XCTAssertTrue(detector.feed(isTargetDown: true, hasOtherModifiers: false, at: 0.3))
    }

    // MARK: - 拼音罗马化

    func testPinyinRomanize() {
        let weixin = Pinyin.romanize("微信")
        XCTAssertEqual(weixin?.full, "wei xin")
        XCTAssertEqual(weixin?.initials, "wx")

        let mixed = Pinyin.romanize("网易云音乐")
        XCTAssertEqual(mixed?.initials, "wyyyl")

        let latin = Pinyin.romanize("Safari")
        // 非中文名：罗马化后仍是自身，由调用方决定是否保留
        XCTAssertNotNil(latin)
    }

    func testAppMatchScorePinyin() {
        let context = CommandQuery.Context()
        let weixin = AppEntry(path: "/Applications/WeChat.app", name: "微信",
                              pinyin: "wei xin", pinyinInitials: "wx")

        // 全拼整词
        XCTAssertGreaterThan(CommandQuery.appMatchScore(query: "weixin", entry: weixin, context: context), 0)
        // 首字母
        XCTAssertGreaterThan(CommandQuery.appMatchScore(query: "wx", entry: weixin, context: context), 0)
        // 中文原名
        XCTAssertGreaterThan(CommandQuery.appMatchScore(query: "微信", entry: weixin, context: context), 0)
        // 无关词
        XCTAssertEqual(CommandQuery.appMatchScore(query: "chrome", entry: weixin, context: context), Int.min)
        // 全拼精确 > 首字母精确
        // 首字母精确命中是明确的档位 130
        XCTAssertEqual(CommandQuery.appMatchScore(query: "wx", entry: weixin, context: context), 130)
    }

    // MARK: - 表情搜索

    func testEmojiSearchChinese() {
        let results = EmojiCatalog.search("笑哭")
        XCTAssertTrue(results.contains { $0.character == "😂" })

        let fire = EmojiCatalog.search("火")
        XCTAssertTrue(fire.contains { $0.character == "🔥" })
    }

    func testEmojiSearchEnglish() {
        let results = EmojiCatalog.search("rocket")
        XCTAssertTrue(results.contains { $0.character == "🚀" })

        let heart = EmojiCatalog.search("heart")
        XCTAssertTrue(heart.contains { $0.character == "❤️" })
    }

    func testEmojiSearchSymbols() {
        let cmd = EmojiCatalog.search("command")
        XCTAssertTrue(cmd.contains { $0.character == "⌘" })

        let zhSymbol = EmojiCatalog.search("版权")
        XCTAssertTrue(zhSymbol.contains { $0.character == "©" })
    }

    func testEmojiEmptyQueryBrowses() {
        let results = EmojiCatalog.search("")
        XCTAssertFalse(results.isEmpty)
    }

    // MARK: - 笔记

    @MainActor
    func testNotesStoreCRUD() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zappale-notes-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = NotesStore(directory: directory) { Date(timeIntervalSince1970: 1_700_000_000) }
        XCTAssertTrue(store.notes.isEmpty)

        let note = store.create()
        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store.note(note.id)?.title, "未命名")

        store.save(id: note.id, content: "购物清单\n- 咖啡\n- 牛奶")
        XCTAssertEqual(store.note(note.id)?.title, "购物清单")

        // 持久化往返：标题来自首行
        let reloaded = NotesStore(directory: directory) { Date() }
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.notes.first?.title, "购物清单")

        reloaded.delete(id: note.id)
        XCTAssertTrue(reloaded.notes.isEmpty)
    }

    func testNotesSearchRanking() {
        let note = Note(id: "x", title: "会议纪要", content: "讨论了发布计划", modified: Date())
        XCTAssertEqual(NotesSearch.score(query: "会议纪要", note: note), 200)
        XCTAssertEqual(NotesSearch.score(query: "会议", note: note), 120)
        XCTAssertEqual(NotesSearch.score(query: "发布", note: note), 50) // 内容命中
        XCTAssertNil(NotesSearch.score(query: "不存在", note: note))
    }

    // MARK: - SSE 增量解析

    func testExtractDeltaOpenAI() {
        let json: [String: Any] = [
            "choices": [["delta": ["content": "你好"], "index": 0]],
        ]
        XCTAssertEqual(AIClient.extractDelta(json, provider: .openAICompatible), "你好")
    }

    func testExtractDeltaAnthropic() {
        let json: [String: Any] = [
            "type": "content_block_delta",
            "delta": ["text": "hello"],
        ]
        XCTAssertEqual(AIClient.extractDelta(json, provider: .anthropic), "hello")

        let stop: [String: Any] = ["type": "message_stop"]
        XCTAssertNil(AIClient.extractDelta(stop, provider: .anthropic))
    }

    // MARK: - 应用屏笔记与 AI 回退入口

    func testAppsScreenNotesSection() {
        let note = Note(id: "n1", title: "旅行计划", content: "东京五日", modified: Date())
        let context = CommandQuery.Context(notes: [note])
        let sections = CommandQuery.sections(query: "旅行", context: context)
        XCTAssertTrue(sections.contains { $0.id == "notes" })

        let empty = CommandQuery.sections(query: "", context: context)
        XCTAssertTrue(empty.contains { $0.id == "notes-top" })
    }

    func testFallbackAskAIGated() {
        // AI 关闭：无入口
        let off = CommandQuery.sections(query: "完全不匹配的查询xyz", context: CommandQuery.Context(aiEnabled: false))
        XCTAssertFalse(PaletteRows.flatten(off).contains { entry in
            if case .askAI = entry.kind { return true }
            return false
        })

        // AI 开启：回退区出现
        let on = CommandQuery.sections(query: "完全不匹配的查询xyz", context: CommandQuery.Context(aiEnabled: true))
        XCTAssertTrue(PaletteRows.flatten(on).contains { entry in
            if case .askAI(let q) = entry.kind { return q == "完全不匹配的查询xyz" }
            return false
        })
    }
}
