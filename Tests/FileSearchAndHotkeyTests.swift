import Carbon.HIToolbox
import XCTest

@testable import ZappaleCore
@testable import zappale

final class FileSearchTests: XCTestCase {

    // MARK: 谓词构建

    func testPredicate() {
        XCTAssertEqual(FileSearchQuery.predicate(for: "报告"), "(kMDItemFSName == \"*报告*\"cd)")
        XCTAssertEqual(FileSearchQuery.predicate(for: "  swift  "), "(kMDItemFSName == \"*swift*\"cd)")
        XCTAssertNil(FileSearchQuery.predicate(for: "a")) // 最短 2 字符
        XCTAssertNil(FileSearchQuery.predicate(for: "   "))
        XCTAssertNil(FileSearchQuery.predicate(for: ""))
    }

    func testPredicateEscaping() {
        // 引号与反斜杠必须转义，防谓词注入
        XCTAssertEqual(
            FileSearchQuery.predicate(for: "a\"b"),
            "(kMDItemFSName == \"*a\\\"b*\"cd)"
        )
        XCTAssertEqual(
            FileSearchQuery.predicate(for: "a\\b"),
            "(kMDItemFSName == \"*a\\\\b*\"cd)"
        )
    }

    // MARK: 排序

    private func entry(_ name: String, path: String = "/Users/x/Desktop") -> FileSearchEntry {
        FileSearchEntry(path: path + "/" + name, name: name, isDirectory: false)
    }

    func testRankOrdering() {
        let exact = entry("report")
        let prefix = entry("report-2024.pdf")
        let wordStart = entry("2024-report.pdf")
        let contains = entry("myreport-v2.pdf")

        let query = "report"
        let scores = [
            FileSearchQuery.rank(query: query, entry: exact)!,
            FileSearchQuery.rank(query: query, entry: prefix)!,
            FileSearchQuery.rank(query: query, entry: wordStart)!,
            FileSearchQuery.rank(query: query, entry: contains)!,
        ]
        // 严格递减
        for index in 0..<(scores.count - 1) {
            XCTAssertGreaterThan(scores[index], scores[index + 1], "档位 \(index) 应高于 \(index + 1)")
        }
    }

    func testRankFuzzyCapped() {
        // 模糊子序列命中但非包含 → 封顶 59，低于包含档位 80
        let fuzzy = FileSearchQuery.rank(query: "anrpor", entry: entry("annual report"))!
        XCTAssertEqual(fuzzy, 59)
        let contains = FileSearchQuery.rank(query: "port", entry: entry("annual report"))!
        XCTAssertEqual(contains, 80)
        XCTAssertGreaterThan(contains, fuzzy)
    }

    func testSortPrefersShallowPathsOnTie() {
        let shallow = entry("a.pdf", path: "/Users/x/Desktop")
        let deep = entry("a.pdf", path: "/Users/x/Desktop/sub/dir")
        let sorted = FileSearchQuery.sort(query: "a.pdf", entries: [deep, shallow])
        XCTAssertEqual(sorted.first, shallow)
    }

    func testSortLimit() {
        let entries = (0..<100).map { entry("report-\($0).pdf") }
        XCTAssertEqual(FileSearchQuery.sort(query: "report", entries: entries, limit: 10).count, 10)
    }

    // MARK: 作用域缩写

    func testScopeAbbreviation() {
        let home = NSHomeDirectory()
        XCTAssertEqual(FileSearchScope.abbreviate(home + "/Desktop"), "~/Desktop")
        XCTAssertEqual(FileSearchScope.expand("~/Desktop"), home + "/Desktop")
        XCTAssertEqual(FileSearchScope.abbreviate("/Applications"), "/Applications")
    }
}

final class HotkeySpecTests: XCTestCase {

    func testModifiersMapping() {
        let carbon = HotkeySpec.carbonModifiers(from: [.command, .shift])
        XCTAssertEqual(carbon, UInt32(cmdKey | shiftKey))

        let flags = HotkeySpec(
            keyCode: UInt32(kVK_ANSI_G),
            carbonModifiers: UInt32(cmdKey | optionKey)
        ).cocoaModifiers
        XCTAssertTrue(flags.contains(.command))
        XCTAssertTrue(flags.contains(.option))
        XCTAssertFalse(flags.contains(.shift))
    }

    func testValidityRequiresModifier() {
        XCTAssertTrue(HotkeySpec(keyCode: 49, carbonModifiers: UInt32(optionKey)).isValid)
        XCTAssertFalse(HotkeySpec(keyCode: 49, carbonModifiers: 0).isValid)
    }

    func testDisplayOrder() {
        let spec = HotkeySpec(
            keyCode: UInt32(kVK_ANSI_G),
            carbonModifiers: UInt32(cmdKey | optionKey | shiftKey | controlKey)
        )
        XCTAssertEqual(spec.display, "⌃⌥⇧⌘G")
    }

    func testSpecialKeyNames() {
        XCTAssertEqual(HotkeySpec.keyName(for: UInt32(kVK_Space)), "Space")
        XCTAssertEqual(HotkeySpec.keyName(for: UInt32(kVK_Return)), "↵")
        XCTAssertEqual(HotkeySpec.keyName(for: UInt32(kVK_F5)), "F5")
    }

    func testCodableRoundTrip() throws {
        let spec = HotkeySpec(keyCode: 32, carbonModifiers: UInt32(cmdKey | shiftKey))
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(HotkeySpec.self, from: data)
        XCTAssertEqual(decoded, spec)
    }

    @MainActor
    func testConflictDetection() throws {
        let defaults = UserDefaults(suiteName: "hotkey-conflict-test")!
        defer { defaults.removePersistentDomain(forName: "hotkey-conflict-test") }
        let settings = AppSettings(defaults: defaults)
        settings.paletteSummonMode = .hotkey // 双击模式默认不注册组合键

        let sameAsPalette = HotkeySpec(
            keyCode: settings.paletteHotkey.keyCode,
            carbonModifiers: settings.paletteHotkey.carbonModifiers
        )
        XCTAssertNotNil(settings.hotkeyConflict(sameAsPalette, excluding: "clipboard"))

        // 排除自身则无冲突
        XCTAssertNil(settings.hotkeyConflict(sameAsPalette, excluding: "palette"))

        // 与应用热键冲突
        let other = HotkeySpec(keyCode: UInt32(kVK_ANSI_J), carbonModifiers: UInt32(controlKey))
        settings.perAppHotkeys.entries["/Applications/Notes.app"] = other
        XCTAssertNotNil(settings.hotkeyConflict(other, excluding: "palette"))
        XCTAssertNil(settings.hotkeyConflict(other, excluding: "/Applications/Notes.app"))
    }

    @MainActor
    func testBindingsExcludeInvalidAndSorted() throws {
        let defaults = UserDefaults(suiteName: "hotkey-bindings-test")!
        defer { defaults.removePersistentDomain(forName: "hotkey-bindings-test") }
        let settings = AppSettings(defaults: defaults)
        settings.paletteSummonMode = .hotkey

        settings.perAppHotkeys.entries["/Applications/B.app"] = HotkeySpec(
            keyCode: 11, carbonModifiers: UInt32(controlKey)
        )
        settings.perAppHotkeys.entries["/Applications/A.app"] = HotkeySpec(
            keyCode: 12, carbonModifiers: UInt32(controlKey)
        )
        // 无修饰键的非法绑定应被过滤
        settings.perAppHotkeys.entries["/Applications/C.app"] = HotkeySpec(keyCode: 13, carbonModifiers: 0)

        let bindings = settings.hotkeyBindings()
        XCTAssertEqual(bindings.first?.id, "palette")
        // 剪贴板默认 ⌘⇧V（keyCode 9）
        let clipboard = bindings.first { $0.id == "clipboard" }
        XCTAssertEqual(clipboard?.spec.keyCode, 9)
        XCTAssertEqual(clipboard?.spec.display, "⇧⌘V")
        XCTAssertEqual(
            bindings.compactMap { $0.id.hasPrefix("app:") ? $0 : nil }.map(\.id),
            ["app:/Applications/A.app", "app:/Applications/B.app"]
        )
        XCTAssertFalse(bindings.contains { $0.id.contains("C.app") })
    }
}
