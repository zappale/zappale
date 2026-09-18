import Combine
import Foundation

/// 一条自定义命令：命名 shell 脚本，可配热键与确认。
public struct CustomCommand: Identifiable, Hashable, Codable {
    public var id: String = UUID().uuidString
    public var name: String
    public var script: String
    public var requiresConfirmation: Bool = false
    public var hotkey: HotkeySpec? = nil

    public init(
        id: String = UUID().uuidString,
        name: String,
        script: String,
        requiresConfirmation: Bool = false,
        hotkey: HotkeySpec? = nil
    ) {
        self.id = id
        self.name = name
        self.script = script
        self.requiresConfirmation = requiresConfirmation
        self.hotkey = hotkey
    }

    public enum CodingKeys: String, CodingKey {
        case id, name, script
        case requiresConfirmation, hotkey
    }
}

/// 命令集合。JSON 持久化。
@MainActor
public final class CustomCommandStore: ObservableObject {
    @Published public private(set) var commands: [CustomCommand] = []

    private let fileURL: URL?

    public init(directory: URL?) {
        if let directory {
            fileURL = directory.appendingPathComponent("commands.json")
        } else {
            fileURL = nil
        }
        load()
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        commands = (try? JSONDecoder().decode([CustomCommand].self, from: data)) ?? []
    }

    private func save() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(commands) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    public func upsert(_ command: CustomCommand) {
        if let index = commands.firstIndex(where: { $0.id == command.id }) {
            commands[index] = command
        } else {
            commands.append(command)
        }
        save()
    }

    public func delete(ids: [String]) {
        commands.removeAll { ids.contains($0.id) }
        save()
    }

    public func command(_ id: String) -> CustomCommand? {
        commands.first { $0.id == id }
    }

    /// 名称模糊搜索（供 store 调用）。
    public func search(_ query: String, limit: Int = 4) -> [CustomCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return commands.compactMap { command -> (CustomCommand, Int)? in
            guard let score = FuzzyMatch.score(query: trimmed, target: command.name) else { return nil }
            return (command, score)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        .map(\.0)
    }
}

/// 命令名称模糊搜索。纯函数。
public enum CustomCommandQuery {
    public static func search(_ query: String, commands: [CustomCommand], limit: Int = 4) -> [CustomCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return commands.compactMap { command -> (CustomCommand, Int)? in
            guard let score = FuzzyMatch.score(query: trimmed, target: command.name) else { return nil }
            return (command, score)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        .map(\.0)
    }
}
