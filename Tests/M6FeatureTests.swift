import XCTest

@testable import ZappaleCore
@testable import zappale

final class M6FeatureTests: XCTestCase {

    override func setUp() {
        super.setUp()
        L10n.apply(.zhHans)
    }

    // MARK: - Markdown 解析

    func testMarkdownHeadingsAndParagraphs() {
        let blocks = MarkdownParser.parse("# 标题\n\n普通段落文字。\n第二行并段。")
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0], .heading(level: 1, inline: [.text("标题")]))
        guard case .paragraph(let inline) = blocks[1] else {
            return XCTFail("第二块应为段落")
        }
        XCTAssertEqual(inline, [.text("普通段落文字。 第二行并段。")])
    }

    func testMarkdownListsAndQuote() {
        let blocks = MarkdownParser.parse("- 苹果\n- 香蕉\n1. 第一\n2. 第二\n> 引用一句")
        XCTAssertEqual(blocks[0], .listItem(ordered: false, index: 0, inline: [.text("苹果")]))
        XCTAssertEqual(blocks[2], .listItem(ordered: true, index: 1, inline: [.text("第一")]))
        XCTAssertEqual(blocks[4], .quote([.text("引用一句")]))
    }

    func testMarkdownCodeAndDivider() {
        let blocks = MarkdownParser.parse("```swift\nlet a = 1\nlet b = 2\n```\n\n---")
        XCTAssertEqual(blocks[0], .code(lang: "swift", text: "let a = 1\nlet b = 2"))
        XCTAssertEqual(blocks[1], .divider)
    }

    func testMarkdownInlineStyles() {
        let inline = MarkdownParser.parseInline("粗体 **重点** 斜体 *次要* 代码 `x = 1` 与 [链接](https://a.b)")
        XCTAssertEqual(inline, [
            .text("粗体 "),
            .bold("重点"),
            .text(" 斜体 "),
            .italic("次要"),
            .text(" 代码 "),
            .code("x = 1"),
            .text(" 与 "),
            .link(text: "链接", url: "https://a.b"),
        ])
    }

    // MARK: - 对话历史

    @MainActor
    func testChatHistoryRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zappale-chat-hist-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ChatHistoryStore(directory: directory)
        XCTAssertTrue(store.conversations.isEmpty)

        var conversation = ChatConversation()
        conversation.messages = [
            AIChatMessage(role: "user", content: "解释一下闭包"),
            AIChatMessage(role: "assistant", content: "闭包是……"),
        ]
        store.upsert(conversation)
        // 更新同 id
        conversation.messages.append(AIChatMessage(role: "user", content: "谢谢"))
        store.upsert(conversation)

        let reloaded = ChatHistoryStore(directory: directory)
        XCTAssertEqual(reloaded.conversations.count, 1)
        XCTAssertEqual(reloaded.conversations.first?.messages.count, 3)
        XCTAssertEqual(reloaded.conversations.first?.title, "解释一下闭包")

        // 标题截断
        var long = ChatConversation()
        long.messages = [AIChatMessage(role: "user", content: String(repeating: "长", count: 50))]
        store.upsert(long)
        XCTAssertEqual(store.conversations.first?.title.count, 25) // 24 + …

        // 消息带图片路径（向后兼容字段）
        var withImage = ChatConversation()
        withImage.messages = [AIChatMessage(role: "assistant", content: "已生成", images: ["a.png"])]
        store.upsert(withImage)
        let decoded = ChatHistoryStore(directory: directory)
        XCTAssertTrue(decoded.conversations.contains {
            $0.messages.first?.images == ["a.png"]
        })
    }

    // MARK: - 多模态消息体

    func testBuildUserContentOpenAI() {
        let textOnly = AIClient.buildUserContent(
            text: "这是什么", imageData: nil, imageMIME: nil, provider: .openAICompatible
        )
        XCTAssertFalse(AIClient.isMultimodal(textOnly))
        XCTAssertEqual(textOnly["type"] as? String, "text")

        let data = Data([0x89, 0x50, 0x4E, 0x47])
        let multimodal = AIClient.buildUserContent(
            text: "这是什么", imageData: data, imageMIME: "image/png", provider: .openAICompatible
        )
        XCTAssertTrue(AIClient.isMultimodal(multimodal))
        let parts = AIClient.openAIContentParts(multimodal)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0]["type"] as? String, "text")
        XCTAssertEqual(parts[1]["type"] as? String, "image_url")
        let imageURL = parts[1]["image_url"] as? [String: Any]
        XCTAssertTrue((imageURL?["url"] as? String)?.hasPrefix("data:image/png;base64,") == true)
    }

    func testBuildUserContentAnthropic() {
        let data = Data([1, 2, 3])
        let multimodal = AIClient.buildUserContent(
            text: "看看", imageData: data, imageMIME: "image/png", provider: .anthropic
        )
        let blocks = AIClient.anthropicContentBlocks(multimodal)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0]["type"] as? String, "image")
        let source = blocks[0]["source"] as? [String: Any]
        XCTAssertEqual(source?["type"] as? String, "base64")
        XCTAssertEqual(source?["media_type"] as? String, "image/png")
        XCTAssertEqual(blocks[1]["type"] as? String, "text")
    }

    // MARK: - 生图响应解析

    func testParseImageResults() {
        let b64: [String: Any] = ["data": [["b64_json": "QUJD"]]]
        XCTAssertEqual(AIClient.parseImageResults(b64).first?.base64, "QUJD")

        let urlJSON: [String: Any] = ["data": [["url": "https://example.com/i.png"]]]
        XCTAssertEqual(AIClient.parseImageResults(urlJSON).first?.url, "https://example.com/i.png")

        let empty: [String: Any] = ["data": []]
        XCTAssertTrue(AIClient.parseImageResults(empty).isEmpty)
        let malformed: [String: Any] = ["error": ["message": "bad model"]]
        XCTAssertTrue(AIClient.parseImageResults(malformed).isEmpty)
    }
}
