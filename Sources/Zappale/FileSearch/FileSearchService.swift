import Combine
import CoreServices
import Foundation
import ZappaleCore

/// 文件搜索服务：借系统 Spotlight 索引（MDQuery），不自建索引。
/// 对齐 tinycast 行为：按名称搜索、作用域目录、防抖、结果排序。
@MainActor
final class FileSearchService: ObservableObject {
    @Published private(set) var results: [FileSearchEntry] = []
    /// 当前查询对应的请求序号，防止乱序回填。
    private(set) var generation = 0

    private var searchTask: Task<Void, Never>?

    /// 防抖搜索：150ms 内连续输入只触发一次；旧任务取消。
    func search(query: String, scopes: [String]) {
        searchTask?.cancel()
        guard let predicate = FileSearchQuery.predicate(for: query) else {
            generation += 1
            results = []
            return
        }
        let expandedScopes = scopes.map(FileSearchScope.expand)
        generation += 1
        let currentGeneration = generation

        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            let entries = await Self.runQuery(predicate: predicate, scopes: expandedScopes)
            guard !Task.isCancelled else { return }
            guard let self, self.generation == currentGeneration else { return }
            self.results = FileSearchQuery.sort(query: query, entries: entries)
        }
    }

    func clear() {
        searchTask?.cancel()
        generation += 1
        results = []
    }

    // MARK: - MDQuery（后台线程）

    /// 同步执行一次查询（kMDQuerySynchronous 在后台队列阻塞，名称谓词通常 <100ms）。
    private nonisolated static func runQuery(predicate: String, scopes: [String]) async -> [FileSearchEntry] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: performQuery(predicate: predicate, scopes: scopes))
            }
        }
    }

    private nonisolated static func performQuery(predicate: String, scopes: [String]) -> [FileSearchEntry] {
        guard let query = MDQueryCreate(nil, predicate as CFString, nil, nil) else {
            return []
        }

        if !scopes.isEmpty {
            MDQuerySetSearchScope(query, scopes as CFArray, 0)
        }

        guard MDQueryExecute(query, CFOptionFlags(1)) else { return [] } // 1 = kMDQuerySynchronous

        let count = min(MDQueryGetResultCount(query), 120)
        var entries: [FileSearchEntry] = []
        entries.reserveCapacity(Int(count))

        let fileManager = FileManager.default
        for index in 0..<count {
            guard let raw = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = unsafeBitCast(raw, to: MDItem.self)
            guard let pathValue = MDItemCopyAttribute(item, kMDItemPath) as? String,
                  !pathValue.isEmpty else { continue }
            let name = (pathValue as NSString).lastPathComponent
            let isDirectory = (try? fileManager.attributesOfItem(atPath: pathValue)[.type]) as? FileAttributeType == .typeDirectory
            entries.append(FileSearchEntry(path: pathValue, name: name, isDirectory: isDirectory))
        }
        return entries
    }
}
