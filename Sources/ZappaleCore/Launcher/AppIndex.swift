import Combine
import Foundation

/// 已安装应用条目。路径是稳定标识；拼音在扫描时预计算（对齐 tinycast-cn
/// 的全拼与首字母搜索，实现走系统 ICU 罗马化）。
public struct AppEntry: Identifiable, Hashable {
    public let path: String
    public let name: String
    /// 全拼（"wei xin"）；非中文名为 nil。
    public var pinyin: String? = nil
    /// 首字母（"wx"）。
    public var pinyinInitials: String? = nil

    public var id: String { path }

    public init(path: String, name: String, pinyin: String? = nil, pinyinInitials: String? = nil) {
        self.path = path
        self.name = name
        self.pinyin = pinyin
        self.pinyinInitials = pinyinInitials
    }
}

@MainActor
public final class AppIndex: ObservableObject {
    @Published public private(set) var entries: [AppEntry] = []

    public init() {}

    private var loadRequested = false

    public func loadIfNeeded() {
        guard !loadRequested else { return }
        rescan()
    }

    /// 后台扫描，回主线程发布。
    /// 强捕获 self（let 常量，避免并发捕获 var 警告）：索引与 AppCore 同生命周期。
    public func rescan() {
        loadRequested = true
        let index = self
        Task.detached(priority: .userInitiated) {
            let scanned = scanInstalledApps()
            await MainActor.run {
                index.entries = scanned
            }
        }
    }

    /// 模糊搜索：按 FuzzyMatch 得分降序。
    public func search(_ query: String, limit: Int = 12) -> [AppEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Array(entries.prefix(limit)) }
        return entries
            .compactMap { entry in
                FuzzyMatch.score(query: trimmed, target: entry.name).map { (entry, $0) }
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}

/// 扫描标准应用目录（含一层子目录，覆盖厂商文件夹安装；
/// 以 bundle id 去重，最早作用域优先）。nonisolated 顶层函数，后台任务直接调用。
private func scanInstalledApps() -> [AppEntry] {
    let directories = [
        "/Applications",
        "/System/Applications",
        NSHomeDirectory() + "/Applications",
    ]

    var seenPaths = Set<String>()
    var seenBundleIDs = Set<String>()
    var result: [AppEntry] = []

    for directory in directories {
        let fileManager = FileManager.default
        let children = (try? fileManager.contentsOfDirectory(atPath: directory)) ?? []

        // 一层子目录：/Applications/Vendor/App.app
        var candidates: [String] = []
        for child in children {
            let fullPath = directory + "/" + child
            if child.hasSuffix(".app") {
                candidates.append(fullPath)
            } else {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory), isDirectory.boolValue {
                    let nested = (try? fileManager.contentsOfDirectory(atPath: fullPath)) ?? []
                    for sub in nested where sub.hasSuffix(".app") {
                        candidates.append(fullPath + "/" + sub)
                    }
                }
            }
        }

        for fullPath in candidates {
            guard seenPaths.insert(fullPath).inserted else { continue }
            let url = URL(fileURLWithPath: fullPath)
            let bundle = Bundle(url: url)
            let identifier = bundle?.bundleIdentifier ?? ""
            if !identifier.isEmpty, !seenBundleIDs.insert(identifier).inserted { continue }

            let name = bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
                ?? bundle?.infoDictionary?["CFBundleDisplayName"] as? String
                ?? bundle?.infoDictionary?["CFBundleName"] as? String
                ?? url.deletingPathExtension().lastPathComponent

            guard !name.isEmpty else { continue }
            let romanized = Pinyin.romanize(name)
            result.append(AppEntry(
                path: fullPath,
                name: name,
                pinyin: romanized?.full,
                pinyinInitials: romanized?.initials
            ))
        }
    }

    return result.sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
}
