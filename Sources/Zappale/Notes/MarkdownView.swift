import SwiftUI
import ZappaleCore

// MARK: - 渲染视图

/// 轻量 Markdown 渲染：无第三方依赖，笔记预览用。
struct MarkdownView: View {
    let source: String

    var body: some View {
        let blocks = MarkdownParser.parse(source)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let inline):
            inlineText(inline)
                .font(.system(size: headingSize(level), weight: .semibold))
                .padding(.top, level == 1 ? 4 : 2)
        case .paragraph(let inline):
            inlineText(inline)
                .font(.system(size: 14))
                .lineSpacing(4)
        case .listItem(let ordered, let index, let inline):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ordered ? "\\(index)." : "•")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                inlineText(inline)
                    .font(.system(size: 14))
            }
        case .quote(let inline):
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(width: 3)
                inlineText(inline)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 1)
        case .code(let lang, let text):
            VStack(alignment: .leading, spacing: 4) {
                if !lang.isEmpty {
                    Text(lang)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.06))
                    )
            }
        case .divider:
            Divider()
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 22
        case 2: return 19
        case 3: return 16
        default: return 14
        }
    }

    @ViewBuilder
    private func inlineText(_ inlines: [MarkdownInline]) -> some View {
        // Text 拼接保持粗斜体/代码样式
        _InlineAccumulator(inlines: inlines).build()
    }
}

/// Text 拼接辅助：把行内元素串成一个 Text（保留样式与可选择性）。
private struct _InlineAccumulator {
    let inlines: [MarkdownInline]

    func build() -> Text {
        var combined = Text("")
        for inline in inlines {
            switch inline {
            case .text(let string):
                combined = combined + Text(string)
            case .bold(let string):
                combined = combined + Text(string).bold()
            case .italic(let string):
                combined = combined + Text(string).italic()
            case .code(let string):
                combined = combined + Text(string)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.pink)
            case .link(let label, _):
                combined = combined + Text(label)
                    .foregroundColor(.accentColor)
                    .underline()
            }
        }
        return combined
    }
}
