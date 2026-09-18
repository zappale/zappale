import Foundation

/// 剪贴板条目类型。只记录捕获时能从粘贴板分辨的三类；
/// 链接/颜色等派生信息按需从文本解析，永不入库。
public enum ClipboardKind: String, Codable, Hashable {
    case text
    case image
    case file
}

/// 一条剪贴板历史。
public struct ClipboardItem: Identifiable, Hashable, Codable {
    public var id: String = UUID().uuidString
    public var kind: ClipboardKind
    /// 文本内容；file 类型时是首个文件的绝对路径（完整列表在 filePaths）。
    public var text: String
    /// image 类型时的图片文件相对路径（相对存储目录）。
    public var imagePath: String?
    public var date: Date
    public var pinned: Bool = false
    /// file 类型时的完整文件路径列表（多选复制）。
    public var filePaths: [String]? = nil
    /// image 类型时的像素尺寸（如 "1024×768"），捕获时记录。
    public var imageSize: String? = nil

    public init(
        id: String = UUID().uuidString,
        kind: ClipboardKind,
        text: String,
        imagePath: String? = nil,
        date: Date,
        pinned: Bool = false,
        filePaths: [String]? = nil,
        imageSize: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imagePath = imagePath
        self.date = date
        self.pinned = pinned
        self.filePaths = filePaths
        self.imageSize = imageSize
    }

    /// 展示用的首行预览（截断到单行）。
    public var preview: String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        if firstLine.count > 120 { return String(firstLine.prefix(117)) + "…" }
        return firstLine
    }

    public var byteCountDescription: String? { nil }
}

/// 文本派生信息：链接或颜色，从文本按需解析，不入库。
public enum ClipboardDerived {
    public enum Info: Equatable {
        case url(String)
        case color(hex: String)
    }

    public static func parse(_ text: String) -> Info? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2048 else { return nil }
        guard !trimmed.contains(where: \.isNewline) else { return nil }

        if let parsed = URL(string: trimmed),
           let scheme = parsed.scheme?.lowercased(),
           ["http", "https"].contains(scheme), parsed.host != nil {
            return .url(trimmed)
        }
        // 裸域名形式
        if looksLikeHost(trimmed) {
            return .url("https://" + trimmed)
        }
        // #RGB / #RRGGBB / #RRGGBBAA
        if trimmed.hasPrefix("#"), trimmed.count == 4 || trimmed.count == 5
            || trimmed.count == 7 || trimmed.count == 9,
           trimmed.dropFirst().allSatisfy({ $0.isHexDigit }) {
            return .color(hex: trimmed.lowercased())
        }
        return nil
    }

    private static func looksLikeHost(_ text: String) -> Bool {
        guard !text.contains(" ") else { return false }
        let parts = text.split(separator: ".")
        guard parts.count >= 2 else { return false }
        let tld = parts.last ?? ""
        return tld.count >= 2 && tld.allSatisfy { $0.isLetter }
    }
}

/// 环形历史存储。Foundation-only：目录与时钟注入，nil 目录 = 不落盘。
/// 自身不做任何 AppKit 调用；捕获由 Service 层的轮询器驱动。
public final class ClipboardStore {
    /// 容量（文本与图片合计）。出厂默认 200。
    public let capacity: Int
    private let directory: URL?
    private let now: () -> Date

    public private(set) var items: [ClipboardItem] = []

    private var manifestURL: URL? { directory?.appendingPathComponent("items.json") }
    private var blobsDirectory: URL? { directory?.appendingPathComponent("blobs") }

    /// 磁盘上的图片 blob 路径（供 UI 加载缩略图）。
    public func imageURL(for item: ClipboardItem) -> URL? {
        guard let imagePath = item.imagePath, let blobsDirectory else { return nil }
        return blobsDirectory.appendingPathComponent(imagePath)
    }

    public init(directory: URL? = nil, capacity: Int = 200, now: @escaping () -> Date = { Date() }) {
        self.directory = directory
        self.capacity = max(1, min(capacity, 2000))
        self.now = now
        loadIfNeeded()
    }

    // MARK: 写入

    /// 捕获一条。与最新条目同文本（且都未固定）→ 顶置并刷新时间，不新增行。
    @discardableResult
    public func insert(
        kind: ClipboardKind, text: String, imagePath: String? = nil,
        filePaths: [String]? = nil, imageSize: String? = nil
    ) -> ClipboardItem {
        let trimmedText = text.count > 100_000 ? String(text.prefix(100_000)) : text
        if let first = items.first(where: { !$0.pinned }),
           first.kind == kind, first.text == trimmedText, first.imagePath == imagePath {
            if let index = items.firstIndex(of: first) {
                var updated = first
                updated.date = now()
                items.remove(at: index)
                items.insert(updated, at: insertIndex())
                return updated
            }
        }

        let item = ClipboardItem(
            id: UUID().uuidString,
            kind: kind,
            text: trimmedText,
            imagePath: imagePath,
            date: now(),
            filePaths: filePaths,
            imageSize: imageSize
        )
        items.insert(item, at: insertIndex())
        pruneOverflow()
        return item
    }

    /// 新条目插到固定区之后（固定项永远在最前）。
    private func insertIndex() -> Int {
        items.firstIndex(where: { !$0.pinned }) ?? items.count
    }

    private func pruneOverflow() {
        // 固定项不参与容量淘汰
        while items.filter({ !$0.pinned }).count > capacity {
            if let lastUnpinnedIndex = items.lastIndex(where: { !$0.pinned }) {
                deleteBlob(for: items[lastUnpinnedIndex])
                items.remove(at: lastUnpinnedIndex)
            } else { break }
        }
    }

    public func togglePin(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pinned.toggle()
        reorder()
    }

    public func delete(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        deleteBlob(for: items[index])
        items.remove(at: index)
    }

    public func clear() {
        for item in items { deleteBlob(for: item) }
        items.removeAll()
    }

    public func item(_ id: String) -> ClipboardItem? {
        items.first { $0.id == id }
    }

    /// 固定项置顶、其余按时间倒序的规范顺序。
    private func reorder() {
        items.sort { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            return lhs.date > rhs.date
        }
    }

    // MARK: 持久化

    /// 把当前 items 落盘（JSON manifest）。图片 blob 由调用方先写入。
    public func save() {
        guard let manifestURL, let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(items) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }

    private func loadIfNeeded() {
        guard let manifestURL, let data = try? Data(contentsOf: manifestURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([ClipboardItem].self, from: data) {
            items = loaded
            reorder()
        }
    }

    private func deleteBlob(for item: ClipboardItem) {
        guard let imagePath = item.imagePath, let blobsDirectory else { return }
        try? FileManager.default.removeItem(at: blobsDirectory.appendingPathComponent(imagePath))
    }
}

/// 剪贴板搜索与面板分区构建。纯函数。
public enum ClipboardSearch {
    /// 匹配得分：前缀包含 > 包含 > 模糊子序列。nil = 不匹配。
    public static func score(query: String, item: ClipboardItem) -> Int? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let haystack = String(item.text.prefix(500))
        let lowerHay = haystack.lowercased()
        let lowerNeedle = trimmed.lowercased()

        var score: Int
        if lowerHay.hasPrefix(lowerNeedle) {
            score = 100
        } else if lowerHay.contains(lowerNeedle) {
            score = 60
        } else if let fuzzy = FuzzyMatch.score(query: trimmed, target: haystack) {
            score = min(fuzzy, 59)
        } else {
            return nil
        }
        // 同分按时间排序由调用方处理
        return score
    }

    /// 面板剪贴板屏的分区：固定（如有）+ 历史。
    public static func sections(items: [ClipboardItem], query: String, limit: Int = 50) -> [CommandSection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var filtered = items
        if !trimmed.isEmpty {
            filtered = items.compactMap { item in
                score(query: trimmed, item: item).map { (item, $0) }
            }
            .sorted { lhs, rhs in
                lhs.1 != rhs.1 ? lhs.1 > rhs.1 : lhs.0.date > rhs.0.date
            }
            .prefix(limit)
            .map(\.0)
        } else {
            filtered = Array(
                items.sorted { $0.date > $1.date }.prefix(limit)
            )
        }

        var sections: [CommandSection] = []
        let pinned = filtered.filter(\.pinned)
        let history = filtered.filter { !$0.pinned }
        if !pinned.isEmpty {
            sections.append(CommandSection(
                id: "clipboard-pinned",
                title: L10n.t("已固定", "Pinned"),
                entries: pinned.map(entry)
            ))
        }
        sections.append(CommandSection(
            id: "clipboard-history",
            title: pinned.isEmpty ? L10n.t("剪贴板历史", "Clipboard History") : L10n.t("最近复制", "Recent"),
            entries: history.map(entry)
        ))
        return sections.filter { !$0.entries.isEmpty }
    }

    public static func entry(_ item: ClipboardItem) -> CommandEntry {
        CommandEntry(
            id: "clipboard-\(item.id)",
            kind: .clipboard(item),
            title: item.preview,
            subtitle: subtitle(for: item),
            icon: .symbol(badgeSymbol(for: item) ?? symbol(for: item.kind))
        )
    }

    public static func symbol(for item: ClipboardKind) -> String {
        switch item {
        case .text: return "doc.on.doc"
        case .image: return "photo"
        case .file: return "doc.badge.arrow.up"
        }
    }

    public static func subtitle(for item: ClipboardItem) -> String? {
        let kindName: String
        switch item.kind {
        case .text:
            // 派生信息：链接 / 颜色（按需解析，不入库）
            if case .url = ClipboardDerived.parse(item.text) {
                kindName = L10n.t("链接", "Link")
            } else if case .color(let hex) = ClipboardDerived.parse(item.text) {
                kindName = L10n.t("颜色 \(hex)", "Color \(hex)")
            } else {
                kindName = L10n.t("文本", "Text")
            }
        case .image:
            kindName = item.imageSize.map { L10n.t("图片 · \($0)", "Image · \($0)") } ?? L10n.t("图片", "Image")
        case .file:
            let count = item.filePaths?.count ?? 1
            kindName = count > 1 ? L10n.t("\(count) 个文件", "\(count) files") : L10n.t("文件", "File")
        }
        return "\(kindName) · \(Self.relativeDate(item.date, now: Date()))"
    }

    /// 行图标带派生徽标：链接 → link，颜色 → 调色盘。
    public static func badgeSymbol(for item: ClipboardItem) -> String? {
        guard item.kind == .text else { return nil }
        switch ClipboardDerived.parse(item.text) {
        case .url: return "link"
        case .color: return "paintpalette.fill"
        case nil: return nil
        }
    }

    /// 相对时间（"刚刚"、"5 分钟前"…）。now 由调用方注入便于测试。
    public static func relativeDate(_ date: Date, now: Date) -> String {
        let interval = now.timeIntervalSince(date)
        switch interval {
        case ..<60: return "刚刚"
        case ..<3600: return "\(Int(interval / 60)) 分钟前"
        case ..<86_400: return "\(Int(interval / 3600)) 小时前"
        case ..<604_800: return "\(Int(interval / 86_400)) 天前"
        default:
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            return formatter.string(from: date)
        }
    }
}
