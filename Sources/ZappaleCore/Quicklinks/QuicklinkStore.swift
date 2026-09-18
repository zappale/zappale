import Combine
import Foundation

/// 快捷链接的持久化集合。JSON 文件落在 Application Support，
/// 内容小，直接主线程同步读写。
@MainActor
public final class QuicklinkStore: ObservableObject {
    @Published public private(set) var links: [Quicklink] = []

    private let fileURL: URL?

    public init(directory: URL?) {
        if let directory {
            fileURL = directory.appendingPathComponent("quicklinks.json")
        } else {
            fileURL = nil
        }
        load()
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        links = (try? JSONDecoder().decode([Quicklink].self, from: data)) ?? []
    }

    private func save() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(links) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - CRUD

    public func upsert(_ link: Quicklink) {
        if let index = links.firstIndex(where: { $0.id == link.id }) {
            links[index] = link
        } else {
            links.append(link)
        }
        save()
    }

    public func delete(ids: [String]) {
        links.removeAll { ids.contains($0.id) }
        save()
    }

    public func link(_ id: String) -> Quicklink? {
        links.first { $0.id == id }
    }

    /// 内置默认链接：首次启动时装载（用户可删）。
    public static let defaults: [Quicklink] = [
        Quicklink(
            name: "Google 搜索", keyword: "g",
            urlTemplate: "https://www.google.com/search?q={query}"
        ),
        Quicklink(
            name: "GitHub 搜索", keyword: "gh",
            urlTemplate: "https://github.com/search?q={query}"
        ),
        Quicklink(
            name: "百度搜索", keyword: "bd",
            urlTemplate: "https://www.baidu.com/s?wd={query}"
        ),
        Quicklink(
            name: "Bilibili 搜索", keyword: "bili",
            urlTemplate: "https://search.bilibili.com/all?keyword={query}"
        ),
    ]

    public func installDefaultsIfNeeded() {
        guard links.isEmpty else { return }
        links = Self.defaults
        save()
    }
}
