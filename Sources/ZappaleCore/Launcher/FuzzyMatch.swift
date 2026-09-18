import Foundation

/// 纯函数模糊匹配评分。Foundation-only，无任何 AppKit 依赖，直接单元测试。
///
/// 评分维度：
/// - 每个命中的 query 字符 +10
/// - 连续命中每字符额外 +8（词组连贯性）
/// - 词首命中（首字符 / 分隔符后 / 小写→大写驼峰边界）额外 +12
/// - query 前缀匹配 target 额外 +25
/// - target 以 query 开头整体额外 +30；中间完整连续包含额外 +12
/// - 命中之间的跳过字符惩罚 -1/字符（单段封顶 -6）
/// 返回 nil 表示 query 不是 target 的子序列。
public enum FuzzyMatch {
    public static func score(query: String, target: String) -> Int? {
        let q = Array(query.lowercased())
        let tLower = Array(target.lowercased())
        let tOrig = Array(target)

        if q.isEmpty { return 0 }
        if q.count > tLower.count { return nil }

        var total = 0
        var qi = 0
        var previousMatchIndex: Int?
        var i = 0

        while i < tLower.count && qi < q.count {
            if tLower[i] == q[qi] {
                total += 10

                if let previous = previousMatchIndex {
                    if previous == i - 1 {
                        total += 8
                    } else {
                        total -= min(i - previous - 1, 6)
                    }
                }

                if isWordBoundary(in: tOrig, at: i) {
                    total += 12
                }

                if qi == 0 && i == 0 {
                    total += 25
                }

                previousMatchIndex = i
                qi += 1
            }
            i += 1
        }

        guard qi == q.count else { return nil }

        if tLower.starts(with: q) {
            total += 30
        } else if String(tLower).contains(String(q)) {
            total += 12
        }

        return total
    }

    /// 词边界：串首、前一个字符非字母，或小写→大写的驼峰转折。
    private static func isWordBoundary(in characters: [Character], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = characters[index - 1]
        let current = characters[index]
        if !previous.isLetter { return true }
        if previous.isLowercase && current.isUppercase { return true }
        return false
    }
}
