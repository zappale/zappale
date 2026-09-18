import Combine
import Foundation

/// 一条片段：可复用的文本模板。
public struct Snippet: Identifiable, Hashable, Codable {
    public var id: String = UUID().uuidString
    public var name: String
    /// 精确触发词：查询以 "keyword " 开头进入参数模式。
    public var keyword: String = ""
    /// 模板。占位符：{query}=参数、{clipboard}=剪贴板文本、{date}=今天。
    public var template: String

    public init(id: String = UUID().uuidString, name: String, keyword: String = "", template: String) {
        self.id = id
        self.name = name
        self.keyword = keyword
        self.template = template
    }

    public enum CodingKeys: String, CodingKey {
        case id, name, keyword, template
    }
}

/// 片段模板渲染。纯函数：文本占位直接替换，不做 URL 编码。
public enum SnippetTemplate {
    public static func needsArgument(_ template: String) -> Bool {
        template.localizedCaseInsensitiveContains("{query}")
    }

    /// 渲染：argument 为空且有 {query} → 返回 nil（调用方提示输入参数）。
    public static func render(
        _ template: String,
        argument: String?,
        clipboardText: String?,
        date: Date
    ) -> String? {
        if needsArgument(template),
           (argument ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            return nil
        }
        var result = template
        if let argument, !argument.isEmpty {
            result = replace(result, "{query}", argument)
        }
        if let clipboardText, !clipboardText.isEmpty {
            result = replace(result, "{clipboard}", clipboardText)
        }
        result = replace(result, "{date}", Self.dateString(date))
        return result
    }

    private static func replace(_ input: String, _ placeholder: String, _ value: String) -> String {
        guard input.localizedCaseInsensitiveContains(placeholder) else { return input }
        var result = ""
        var index = input.startIndex
        while index < input.endIndex {
            if let range = input.range(of: placeholder, range: index..<input.endIndex),
               input[range].lowercased() == placeholder.lowercased() {
                result += input[index..<range.lowerBound]
                result += value
                index = range.upperBound
            } else {
                result.append(input[index])
                index = input.index(after: index)
            }
        }
        return result
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// 片段查询。keyword 前缀精确模式 + 名称模糊。
public enum SnippetQuery {
    public struct Match: Equatable {
        public let snippet: Snippet
        public let argument: String?
    }

    public static func keywordMatch(query: String, snippets: [Snippet]) -> Match? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: " ", maxSplits: 1)
        guard let firstWord = parts.first.map(String.init), !firstWord.isEmpty else { return nil }
        let argument = parts.count > 1 ? String(parts[1]) : nil
        guard let snippet = snippets.first(where: {
            !$0.keyword.isEmpty && $0.keyword.lowercased() == firstWord.lowercased()
        }) else { return nil }
        return Match(snippet: snippet, argument: argument)
    }

    public static func search(_ query: String, snippets: [Snippet], limit: Int = 4) -> [Snippet] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return snippets.compactMap { snippet -> (Snippet, Int)? in
            let nameScore = FuzzyMatch.score(query: trimmed, target: snippet.name) ?? Int.min
            let keywordScore = snippet.keyword.isEmpty
                ? Int.min
                : (FuzzyMatch.score(query: trimmed, target: snippet.keyword) ?? Int.min)
            let score = max(nameScore, keywordScore)
            guard score > Int.min else { return nil }
            return (snippet, score)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        .map(\.0)
    }
}

/// 片段集合。JSON 文件持久化，主线程小文件同步读写。
@MainActor
public final class SnippetStore: ObservableObject {
    @Published public private(set) var snippets: [Snippet] = []

    private let fileURL: URL?

    public init(directory: URL?) {
        if let directory {
            fileURL = directory.appendingPathComponent("snippets.json")
        } else {
            fileURL = nil
        }
        load()
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        snippets = (try? JSONDecoder().decode([Snippet].self, from: data)) ?? []
    }

    private func save() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(snippets) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    public func upsert(_ snippet: Snippet) {
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[index] = snippet
        } else {
            snippets.append(snippet)
        }
        save()
    }

    public func delete(ids: [String]) {
        snippets.removeAll { ids.contains($0.id) }
        save()
    }

    public func snippet(_ id: String) -> Snippet? {
        snippets.first { $0.id == id }
    }
}
