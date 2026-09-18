import Foundation

/// 快捷链接：把 URL / 搜索 / deeplink 变成一条可搜索命令。
/// 模板占位符：{query}=当前输入、{clipboard}=剪贴板文本、{date}=今天(yyyy-MM-dd)。
public struct Quicklink: Identifiable, Hashable, Codable {
    public var id: String = UUID().uuidString
    public var name: String
    /// 精确触发词：查询以 "keyword " 开头时进入参数模式（如 "gh swift"）。
    public var keyword: String = ""
    /// URL 模板。无 {query} 时是固定链接；占位符在启动时渲染。
    public var urlTemplate: String

    public init(id: String = UUID().uuidString, name: String, keyword: String = "", urlTemplate: String) {
        self.id = id
        self.name = name
        self.keyword = keyword
        self.urlTemplate = urlTemplate
    }

    public enum CodingKeys: String, CodingKey {
        case id, name, keyword
        case urlTemplate = "url"
    }
}

/// 模板渲染。纯函数：给定参数与日期产出最终 URL。
public enum QuicklinkTemplate {
    /// 渲染结果。
    public enum Rendered: Equatable {
        case url(String)
        /// 需要参数但没给：打开时应提示输入（或由调用方使用 fallback）。
        case needsArgument
        case invalid
    }

    /// 是否包含 {query} 占位符。
    public static func needsArgument(_ template: String) -> Bool {
        template.localizedCaseInsensitiveContains("{query}")
    }

    /// 渲染模板。argument 为 nil 时：有 {query} → needsArgument；
    /// 无 → 直接返回固定 URL。
    public static func render(
        _ template: String,
        argument: String?,
        clipboardText: String?,
        date: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Rendered {
        if needsArgument(template), (argument ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            return .needsArgument
        }

        var result = template
        if let argument, !argument.isEmpty {
            result = replaceCaseInsensitive(result, "{query}", encode(argument))
        }
        if let clipboardText, !clipboardText.isEmpty {
            result = replaceCaseInsensitive(result, "{clipboard}", encode(clipboardText))
        }
        result = replaceCaseInsensitive(result, "{date}", isoDate(date, calendar: calendar))
        return validate(result)
    }

    private static func replaceCaseInsensitive(_ input: String, _ placeholder: String, _ value: String) -> String {
        var result = ""
        var index = input.startIndex
        let lowerPlaceholder = placeholder.lowercased()
        while index < input.endIndex {
            if let range = input.range(of: placeholder, range: index..<input.endIndex),
               input[range].lowercased() == lowerPlaceholder {
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

    /// 对插入参数做 URL 查询编码：空格 → +，保留常见安全字符。
    /// 但当参数本身已经是 URL（含 ://）时不编码，支持嵌套 deeplink。
    private static func encode(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://"), URL(string: trimmed) != nil { return trimmed }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~/:?&=#%+")
        return trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
    }

    private static func isoDate(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        _ = calendar.date(from: components)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0, components.month ?? 0, components.day ?? 0
        )
    }

    private static func validate(_ url: String) -> Rendered {
        guard let parsed = URL(string: url), let scheme = parsed.scheme?.lowercased(),
              !scheme.isEmpty else { return .invalid }
        // 远程链接必须 https；http 仅 loopback；其余 scheme（mailto:、things: 等 deeplink）放行
        if scheme == "https" { return .url(url) }
        if scheme == "http" {
            let host = parsed.host?.lowercased() ?? ""
            return ["localhost", "127.0.0.1", "::1"].contains(host) ? .url(url) : .invalid
        }
        return .url(url)
    }
}

/// 纯查询辅助：从原始查询中提取 keyword 前缀匹配。
public enum QuicklinkQuery {
    public struct Match: Equatable {
        public let link: Quicklink
        public let argument: String?
    }

    /// "gh swift ui" → link(keyword: gh), argument: "swift ui"。
    /// keyword 精确匹配第一个词，大小写不敏感。
    public static func keywordMatch(query: String, links: [Quicklink]) -> Match? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let firstWord = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
        guard !firstWord.isEmpty else { return nil }
        let argument = trimmed.split(separator: " ", maxSplits: 1).count > 1
            ? String(trimmed.split(separator: " ", maxSplits: 1)[1])
            : nil

        guard let link = links.first(where: {
            !$0.keyword.isEmpty && $0.keyword.lowercased() == firstWord.lowercased()
        }) else { return nil }
        return Match(link: link, argument: argument)
    }

    /// 名称 / keyword 模糊匹配。
    public static func search(_ query: String, links: [Quicklink], limit: Int = 5) -> [Quicklink] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return links.compactMap { link -> (Quicklink, Int)? in
            let nameScore = FuzzyMatch.score(query: trimmed, target: link.name) ?? Int.min
            let keywordScore = link.keyword.isEmpty
                ? Int.min
                : (FuzzyMatch.score(query: trimmed, target: link.keyword) ?? Int.min)
            let score = max(nameScore, keywordScore)
            guard score > Int.min else { return nil }
            return (link, score)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        .map(\.0)
    }
}
