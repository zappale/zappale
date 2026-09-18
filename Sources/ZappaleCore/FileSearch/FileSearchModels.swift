import Foundation

/// 一条文件搜索结果。纯值类型；图标与打开行为由 UI/服务层处理。
public struct FileSearchEntry: Identifiable, Hashable {
    public let path: String
    public let name: String
    public let isDirectory: Bool

    public var id: String { path }

    public init(path: String, name: String, isDirectory: Bool) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
    }

    /// 展示用父目录（含结尾斜杠便于对齐）。
    public var parentDirectory: String {
        let url = URL(fileURLWithPath: path)
        return url.deletingLastPathComponent().path + "/"
    }
}

/// 文件搜索纯逻辑：谓词构建、转义、排序。无任何系统依赖，直接单测。
public enum FileSearchQuery {
    /// 最短查询长度：避免单字符 wildcard 扫全索引。
    public static let minimumLength = 2

    /// MDQuery 字符串字面量转义：反斜杠与引号。
    public static func escape(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// 名称匹配谓词。查询过短返回 nil。
    /// 例：query "报告" → (kMDItemFSName == "*报告*"cd)
    public static func predicate(for query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumLength else { return nil }
        let escaped = escape(trimmed)
        return "(kMDItemFSName == \"*\(escaped)*\"cd)"
    }

    /// 排序得分：精确 = 200 > 前缀 = 120 > 词首包含 = 100 > 包含 = 80；
    /// 模糊子序列封顶 59（永远排在任何包含之下）。nil = 不匹配（基本不出现，谓词已过滤）。
    public static func rank(query: String, entry: FileSearchEntry) -> Int? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        let name = entry.name.lowercased()

        if name == trimmed { return 200 }
        if name.hasPrefix(trimmed) { return 120 }
        if name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" || $0 == "." })
            .contains(where: { $0.hasPrefix(trimmed) }) { return 100 }
        if name.contains(trimmed) { return 80 }
        if let fuzzy = FuzzyMatch.score(query: trimmed, target: entry.name) {
            return min(fuzzy, 59)
        }
        return nil
    }

    /// 排序：得分降序；同分路径浅的优先（更接近作用域根）。
    public static func sort(query: String, entries: [FileSearchEntry], limit: Int = 40) -> [FileSearchEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return entries.compactMap { entry -> (FileSearchEntry, Int)? in
            guard let score = rank(query: trimmed, entry: entry) else { return nil }
            return (entry, score)
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            let lhsDepth = lhs.0.path.filter { $0 == "/" }.count
            let rhsDepth = rhs.0.path.filter { $0 == "/" }.count
            if lhsDepth != rhsDepth { return lhsDepth < rhsDepth }
            return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
        }
        .prefix(limit)
        .map(\.0)
    }
}

/// 作用域路径缩写/展开（存储用 ~ 缩写，查询用绝对路径）。
public enum FileSearchScope {
    public static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    public static func expand(_ scope: String) -> String {
        (scope as NSString).expandingTildeInPath
    }
}
