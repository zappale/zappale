import SwiftUI

// MARK: - 纯解析器（无 SwiftUI 依赖部分）

/// Markdown 块级结构。
public enum MarkdownBlock: Equatable {
    case heading(level: Int, inline: [MarkdownInline])
    case paragraph([MarkdownInline])
    case listItem(ordered: Bool, index: Int, inline: [MarkdownInline])
    case quote([MarkdownInline])
    case code(lang: String, text: String)
    case divider
}

/// 行内元素。
public enum MarkdownInline: Equatable {
    case text(String)
    case bold(String)
    case italic(String)
    case code(String)
    case link(text: String, url: String)
}

/// Markdown 解析器：覆盖笔记场景的常用子集。纯函数，直接单测。
public enum MarkdownParser {

    public static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var index = 0

        while index < lines.count {
            let line = String(lines[index])
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 空行
            if trimmed.isEmpty {
                index += 1
                continue
            }

            // 围栏代码
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                index += 1
                var codeLines: [String] = []
                while index < lines.count {
                    let candidate = String(lines[index])
                    if candidate.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        index += 1
                        break
                    }
                    codeLines.append(candidate)
                    index += 1
                }
                blocks.append(.code(lang: lang, text: codeLines.joined(separator: "\n")))
                continue
            }

            // 分隔线
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.divider)
                index += 1
                continue
            }

            // 标题
            if let heading = parseHeading(trimmed) {
                blocks.append(heading)
                index += 1
                continue
            }

            // 引用
            if trimmed.hasPrefix(">") {
                let content = String(trimmed.dropFirst())
                    .trimmingCharacters(in: .whitespaces)
                blocks.append(.quote(parseInline(content)))
                index += 1
                continue
            }

            // 列表
            if let item = parseListItem(trimmed) {
                blocks.append(item)
                index += 1
                continue
            }

            // 段落（连续非空行合并）
            var paragraphLines = [trimmed]
            index += 1
            while index < lines.count {
                let next = String(lines[index]).trimmingCharacters(in: .whitespaces)
                if next.isEmpty || next.hasPrefix("#") || next.hasPrefix(">")
                    || next.hasPrefix("-") || next.hasPrefix("*") || next.hasPrefix("```")
                    || isOrderedItem(next) || next == "---" {
                    break
                }
                paragraphLines.append(next)
                index += 1
            }
            blocks.append(.paragraph(parseInline(paragraphLines.joined(separator: " "))))
        }
        return blocks
    }

    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard hashes >= 1, hashes <= 6 else { return nil }
        let after = line.dropFirst(hashes)
        guard after.first == " " || after.first == "\t" || after.isEmpty else { return nil }
        let content = after.trimmingCharacters(in: .whitespaces)
        return .heading(level: hashes, inline: parseInline(content))
    }

    private static func isOrderedItem(_ line: String) -> Bool {
        guard let dot = line.firstIndex(of: ".") else { return false }
        let numberPart = line[line.startIndex..<dot]
        return !numberPart.isEmpty && numberPart.allSatisfy(\.isNumber)
            && line.index(after: dot) < line.endIndex
            && line[line.index(after: dot)] == " "
    }

    private static func parseListItem(_ line: String) -> MarkdownBlock? {
        // 无序：- / * / + 开头
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            let content = String(line.dropFirst(2))
            return .listItem(ordered: false, index: 0, inline: parseInline(content))
        }
        // 有序：1. 内容
        guard isOrderedItem(line), let dot = line.firstIndex(of: ".") else { return nil }
        let numberText = String(line[line.startIndex..<dot])
        let content = String(line[line.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
        return .listItem(
            ordered: true,
            index: Int(numberText) ?? 0,
            inline: parseInline(content)
        )
    }

    // MARK: 行内解析

    public static func parseInline(_ text: String) -> [MarkdownInline] {
        var result: [MarkdownInline] = []
        var buffer = ""
        var index = text.startIndex

        func flush() {
            if !buffer.isEmpty {
                result.append(.text(buffer))
                buffer = ""
            }
        }

        while index < text.endIndex {
            // 行内代码 `code`
            if text[index] == "`", let close = text[text.index(after: index)...].firstIndex(of: "`") {
                flush()
                let code = String(text[text.index(after: index)..<close])
                result.append(.code(code))
                index = text.index(after: close)
                continue
            }
            // 粗体 **bold**
            if text[index] == "*", index < text.endIndex,
               let second = text.index(index, offsetBy: 1, limitedBy: text.endIndex),
               second < text.endIndex, text[second] == "*",
               let close = findClosingStar(text, after: second) {
                flush()
                let contentStart = text.index(after: second)
                result.append(.bold(String(text[contentStart..<close])))
                // close 指向收尾 ** 的第一颗星，跳过两颗
                index = text.index(close, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
                continue
            }
            // 斜体 *italic*
            if text[index] == "*", let close = text[text.index(after: index)...].firstIndex(of: "*") {
                flush()
                result.append(.italic(String(text[text.index(after: index)..<close])))
                index = text.index(after: close)
                continue
            }
            // 链接 [text](url)
            if text[index] == "[", let closeBracket = text[text.index(after: index)...].firstIndex(of: "]"),
               let openParen = text.index(closeBracket, offsetBy: 1, limitedBy: text.endIndex),
               openParen < text.endIndex, text[openParen] == "(",
               let closeParen = text[text.index(after: openParen)...].firstIndex(of: ")") {
                let label = String(text[text.index(after: index)..<closeBracket])
                let url = String(text[text.index(after: openParen)..<closeParen])
                flush()
                result.append(.link(text: label, url: url))
                index = text.index(after: closeParen)
                continue
            }
            buffer.append(text[index])
            index = text.index(after: index)
        }
        flush()
        return result
    }

    /// 从 start 之后找成对收尾的 `**`：返回第二颗星位置（内容终点）。
    private static func findClosingStar(_ text: String, after start: String.Index) -> String.Index? {
        var index = text.index(after: start)
        while index < text.endIndex {
            if text[index] == "*" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "*" {
                    // ** 收尾：内容到第一颗星前
                    return index
                }
                // 单颗星：可能是斜体收尾或内容字符，跳过
                index = next
                continue
            }
            index = text.index(after: index)
        }
        return nil
    }
}
