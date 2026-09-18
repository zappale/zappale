import Foundation

/// 应用启动频次与新近度记录（frecency）。纯逻辑：时钟与文件路径注入。
/// boost 有上限：只能让同档相邻结果换位，不能让弱匹配压过强匹配。
public struct LauncherRankingStore {
    public struct Record: Codable, Equatable {
        var count: Int = 0
        var lastUsed: Date = .distantPast
    }

    /// boost 上限。FuzzyMatch 相邻档差 ≥12，取 8 时只能在档内微调。
    public static let boostCap = 8
    /// 新近度半衰期：14 天内用过加权，越久越弱。
    public static let halfLife: TimeInterval = 14 * 86_400

    private var records: [String: Record] = [:]
    private let fileURL: URL?
    private let now: () -> Date

    public init(fileURL: URL? = nil, now: @escaping () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.now = now
        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            records = (try? decoder.decode([String: Record].self, from: data)) ?? [:]
        }
    }

    public func record(for path: String) -> Record? { records[path] }

    /// 记录一次启动。
    public mutating func launch(_ path: String) {
        var record = records[path] ?? Record()
        record.count = min(record.count + 1, 999)
        record.lastUsed = now()
        records[path] = record
        save()
    }

    /// frecency 加分：count 的对数 + 指数衰减的新近度，封顶 boostCap。
    public func boost(for path: String, at date: Date? = nil) -> Int {
        guard let record = records[path], record.count > 0 else { return 0 }
        let reference = date ?? now()
        let age = max(0, reference.timeIntervalSince(record.lastUsed))
        let recency = pow(0.5, age / Self.halfLife) // 1 → 0
        let frequency = log2(Double(record.count) + 1)
        let raw = frequency + recency * 4
        return min(Int(raw.rounded()), Self.boostCap)
    }

    public func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
