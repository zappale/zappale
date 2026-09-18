import Foundation

/// 汉字罗马化：借系统 ICU 的 CFStringTransform（普通话 → 拉丁字母，去声调），
/// 无需内置拼音表。对混合中英文文本同样有效。
public enum Pinyin {
    public struct Romanized: Equatable {
        let full: String       // "wei xin"
        let initials: String   // "wx"
    }

    public static func romanize(_ text: String) -> Romanized? {
        let mutable = NSMutableString(string: text)
        guard CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false) else { return nil }
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)

        let words = (mutable as String)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
        guard !words.isEmpty else { return nil }
        let full = words.joined(separator: " ")
        let initials = words.compactMap(\.first).map(String.init).joined()
        return Romanized(full: full, initials: initials)
    }
}
