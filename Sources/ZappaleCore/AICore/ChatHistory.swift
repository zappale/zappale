import Foundation

/// 一段对话（含生成图片路径）。
public struct ChatConversation: Codable, Identifiable, Hashable {
    public var id: String = UUID().uuidString
    public var startedAt: Date = Date()
    public var updatedAt: Date = Date()
    public var messages: [AIChatMessage] = []

    public init(
        id: String = UUID().uuidString,
        startedAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [AIChatMessage] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.messages = messages
    }

    /// 标题：首条用户消息前 24 字。
    public var title: String {
        let first = messages.first { $0.role == "user" }?.content ?? ""
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return L10n.t("新对话", "New chat") }
        return trimmed.count > 24 ? String(trimmed.prefix(24)) + "…" : trimmed
    }
}

/// 对话历史：JSON 文件持久化，最近 30 段。
@MainActor
public final class ChatHistoryStore: ObservableObject {
    @Published public private(set) var conversations: [ChatConversation] = []

    public static let limit = 30
    private let fileURL: URL?

    public init(directory: URL?) {
        if let directory {
            fileURL = directory.appendingPathComponent("chat-history.json")
        } else {
            fileURL = nil
        }
        load()
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        conversations = (try? decoder.decode([ChatConversation].self, from: data)) ?? []
    }

    private func save() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(conversations) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// 追加或更新当前对话（按 id）。
    public func upsert(_ conversation: ChatConversation) {
        var updated = conversation
        updated.updatedAt = Date()
        if let index = conversations.firstIndex(where: { $0.id == updated.id }) {
            conversations[index] = updated
        } else {
            conversations.insert(updated, at: 0)
        }
        if conversations.count > Self.limit {
            conversations = Array(conversations.prefix(Self.limit))
        }
        save()
    }

    public func delete(ids: [String]) {
        conversations.removeAll { ids.contains($0.id) }
        save()
    }

    public func recent(_ limit: Int = 8) -> [ChatConversation] {
        Array(conversations.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
    }
}
