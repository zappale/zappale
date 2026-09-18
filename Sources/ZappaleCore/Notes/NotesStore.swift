import Combine
import Foundation

/// 一条笔记 = 一个 Markdown 文件。标题取首行。
public struct Note: Identifiable, Hashable, Codable {
    public let id: String // 文件名（不含 .md）
    public var title: String
    public var content: String
    public var modified: Date
}

/// 笔记搜索。纯函数：标题命中 > 内容命中。
public enum NotesSearch {
    public static func score(query: String, note: Note) -> Int? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let title = note.title.lowercased()
        let content = note.content.lowercased()
        let needle = trimmed.lowercased()
        if title == needle { return 200 }
        if title.hasPrefix(needle) { return 120 }
        if title.contains(needle) { return 80 }
        if let fuzzy = FuzzyMatch.score(query: trimmed, target: note.title) {
            return min(fuzzy, 59)
        }
        if content.contains(needle) { return 50 }
        return nil
    }
}

/// 笔记集合：目录下的一组 .md 文件。小文件同步读写；
/// 目录与时钟注入，nil 目录 = 内存模式（测试用）。
@MainActor
public final class NotesStore: ObservableObject {
    @Published public private(set) var notes: [Note] = []

    private let directory: URL?
    private let now: () -> Date

    public init(directory: URL? = nil, now: @escaping () -> Date = { Date() }) {
        self.directory = directory
        self.now = now
        load()
    }

    public var count: Int { notes.count }

    // MARK: - 读取

    public func note(_ id: String) -> Note? {
        notes.first { $0.id == id }
    }

    public func recent(_ limit: Int = 3) -> [Note] {
        Array(notes.prefix(limit))
    }

    private func load() {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
              ) else { return }
        var loaded: [Note] = []
        for file in files where file.pathExtension.lowercased() == "md" {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))
                .flatMap(\.contentModificationDate) ?? .distantPast
            loaded.append(Note(
                id: file.deletingPathExtension().lastPathComponent,
                title: firstLine(of: text),
                content: text,
                modified: modified
            ))
        }
        notes = loaded.sorted { $0.modified > $1.modified }
    }

    private func firstLine(of text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return line.isEmpty ? L10n.t("未命名", "Untitled") : line
    }

    private func fileURL(_ id: String) -> URL? {
        directory?.appendingPathComponent(id + ".md")
    }

    // MARK: - 写入

    /// 新建空笔记，返回 id。
    @discardableResult
    public func create() -> Note {
        let id = ISO8601DateFormatter().string(from: now())
            .replacingOccurrences(of: ":", with: "-")
        let note = Note(id: id, title: L10n.t("未命名", "Untitled"), content: "", modified: now())
        notes.insert(note, at: 0)
        persist(note)
        return note
    }

    /// 保存内容；标题随首行更新。
    public func save(id: String, content: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        var note = notes[index]
        guard note.content != content else { return }
        note.content = content
        note.title = firstLine(of: content)
        note.modified = now()
        notes[index] = note
        notes.sort { $0.modified > $1.modified }
        persist(note)
    }

    public func delete(id: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let note = notes.remove(at: index)
        if let url = fileURL(note.id) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func persist(_ note: Note) {
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let url = fileURL(note.id) {
            try? note.content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
