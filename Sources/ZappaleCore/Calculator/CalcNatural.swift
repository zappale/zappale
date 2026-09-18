import Foundation

/// 自然语言计算形式（在普通表达式解析之前尝试）：
/// - `20% of 50` 百分比
/// - `days till 2026-12-25` / `hrs till 9:30` / `min till 9am` 倒计时
/// - `today + 3 weeks` / `now + 2h` / `明天 - 1 天` 日期推算
/// - `time in Tokyo` / `东京时间` 时区查询
/// 全部纯函数，now 注入。
public enum CalcNatural {

    public static func evaluate(_ query: String, now: Date) -> CalcResult? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        if let result = percentOf(trimmed, lower: lower) { return result }
        if let result = countdown(trimmed, lower: lower, now: now) { return result }
        if let result = dateArithmetic(trimmed, lower: lower, now: now) { return result }
        if let result = timeInCity(trimmed, lower: lower, now: now) { return result }
        return nil
    }

    // MARK: - X% of Y

    private static func percentOf(_ raw: String, lower: String) -> CalcResult? {
        // 形如 "20% of 50"
        guard lower.contains(" of ") else { return nil }
        let parts = lower.components(separatedBy: " of ")
        guard parts.count == 2 else { return nil }
        let left = parts[0].trimmingCharacters(in: .whitespaces)
        guard left.hasSuffix("%"),
              let percent = Double(left.dropLast()) else { return nil }
        let right = parts[1].trimmingCharacters(in: .whitespaces)
        guard let base = CalcEngine.evaluate(right)?.output,
              case .number(let value) = base else { return nil }
        let result = value * percent / 100
        guard let formatted = CalcFormatter.display(result) else { return nil }
        return CalcResult(
            output: .number(result),
            display: "= \(formatted)",
            copyText: formatted
        )
    }

    // MARK: - 倒计时 days/hours/minutes till <目标>

    private static let countdownUnits: [String: (String, String, Double)] = [
        "days till": ("天", "Days", 86_400), "day till": ("天", "Days", 86_400),
        "hours till": ("小时", "Hours", 3_600), "hrs till": ("小时", "Hours", 3_600),
        "hr till": ("小时", "Hours", 3_600), "小时 till": ("小时", "Hours", 3_600),
        "minutes till": ("分钟", "Minutes", 60), "min till": ("分钟", "Minutes", 60),
        "分钟 till": ("分钟", "Minutes", 60),
        "weeks till": ("周", "Weeks", 604_800), "week till": ("周", "Weeks", 604_800),
        "周 till": ("周", "Weeks", 604_800), "天 till": ("天", "Days", 86_400),
    ]

    private static func countdown(_ raw: String, lower: String, now: Date) -> CalcResult? {
        for (prefix, (zhLabel, enLabel, seconds)) in countdownUnits {
            guard lower.hasPrefix(prefix) else { continue }
            let targetText = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            guard let target = parseTarget(targetText, now: now) else { return nil }
            let delta = target.timeIntervalSince(now)
            let value = delta / seconds
            guard let formatted = CalcFormatter.display(value) else { return nil }
            return CalcResult(
                output: .number(value),
                display: "= \(formatted) \(L10n.t(zhLabel, enLabel))",
                copyText: formatted
            )
        }
        return nil
    }

    // MARK: - 日期推算

    /// 时间量词 → 秒（月按 30 天，年按 365 天，与工作日口径无关的近似）。
    private static let offsetUnits: [String: (String, Double)] = [
        "weeks": ("周", 604_800), "week": ("周", 604_800), "周": ("周", 604_800),
        "days": ("天", 86_400), "day": ("天", 86_400), "天": ("天", 86_400),
        "months": ("月", 2_592_000), "month": ("月", 2_592_000), "月": ("月", 2_592_000),
        "years": ("年", 31_536_000), "year": ("年", 31_536_000), "年": ("年", 31_536_000),
        "hours": ("小时", 3_600), "hour": ("小时", 3_600), "hrs": ("小时", 3_600),
        "hr": ("小时", 3_600), "h": ("小时", 3_600), "小时": ("小时", 3_600),
        "minutes": ("分钟", 60), "minute": ("分钟", 60), "min": ("分钟", 60),
        "分钟": ("分钟", 60), "m": ("分钟", 60),
        "seconds": ("秒", 1), "second": ("秒", 1), "sec": ("秒", 1), "s": ("秒", 1),
        "秒": ("秒", 1),
    ]

    private static func dateArithmetic(_ raw: String, lower: String, now: Date) -> CalcResult? {
        // 形式：<基准> ± <n> <单位>，基准 ∈ today/now/明天/昨天/后天
        struct Base {
            let keyword: String
            let zh: String
            let en: String
            let includeTime: Bool
        }
        let bases: [Base] = [
            Base(keyword: "today", zh: "今天", en: "Today", includeTime: false),
            Base(keyword: "今天", zh: "今天", en: "Today", includeTime: false),
            Base(keyword: "now", zh: "现在", en: "Now", includeTime: true),
            Base(keyword: "现在", zh: "现在", en: "Now", includeTime: true),
            Base(keyword: "tomorrow", zh: "明天", en: "Tomorrow", includeTime: false),
            Base(keyword: "明天", zh: "明天", en: "Tomorrow", includeTime: false),
            Base(keyword: "yesterday", zh: "昨天", en: "Yesterday", includeTime: false),
            Base(keyword: "昨天", zh: "昨天", en: "Yesterday", includeTime: false),
        ]
        var matchedBase: Base?
        for candidate in bases {
            if lower == candidate.keyword {
                matchedBase = candidate
                break
            }
            if lower.hasPrefix(candidate.keyword + " ") || lower.hasPrefix(candidate.keyword + "+")
                || lower.hasPrefix(candidate.keyword + "-") {
                matchedBase = candidate
                break
            }
        }
        guard let base = matchedBase else { return nil }
        let baseDate = anchored(keyword: base.keyword, now: now)

        let remainder = String(lower.dropFirst(raw.prefix(while: { !$0.isWhitespace && $0 != "+" && $0 != "-" }).count))
            .trimmingCharacters(in: .whitespaces)
        guard remainder.hasPrefix("+") || remainder.hasPrefix("-") else { return nil }
        let sign: Double = remainder.hasPrefix("+") ? 1 : -1
        let body = remainder.dropFirst().trimmingCharacters(in: .whitespaces)
        // "<n> <unit>" 或 "<n><unit>"
        let match = body.range(of: #"^(\d+(\.\d+)?)\s*([a-zA-Z\u4e00-\u9fff]+)$"#, options: .regularExpression)
        guard let match else { return nil }
        let pieces = body[match].split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let numberText: String
        let unitText: String
        if pieces.count == 2 {
            numberText = String(pieces[0])
            unitText = pieces[1].trimmingCharacters(in: .whitespaces)
        } else {
            // 粘连形式 "2h"
            let text = String(pieces[0])
            let digitEnd = text.prefix { $0.isNumber || $0 == "." }.count
            numberText = String(text.prefix(digitEnd))
            unitText = String(text.dropFirst(digitEnd))
        }
        guard let amount = Double(numberText),
              let unit = offsetUnits[unitText.lowercased()] ?? offsetUnits[unitText] else { return nil }

        let result = baseDate.addingTimeInterval(sign * amount * unit.1)
        let includeTime = unit.1 < 86_400 || base.includeTime
        let formatted = formatDate(result, includeTime: includeTime)
        return CalcResult(
            output: .text(formatted),
            display: "= \(formatted)",
            copyText: formatted
        )
    }

    /// 基准锚点：today/明天/昨天取当日零点；now 取当前时刻。
    private static func anchored(keyword: String, now: Date) -> Date {
        let calendar = Calendar.current
        switch keyword {
        case "now", "现在": return now
        case "tomorrow", "明天": return calendar.startOfDay(for: now).addingTimeInterval(86_400)
        case "yesterday", "昨天": return calendar.startOfDay(for: now).addingTimeInterval(-86_400)
        default: return calendar.startOfDay(for: now)
        }
    }

    // MARK: - 时区查询

    private static let cities: [(String, String, String)] = [
        ("tokyo", "东京 Tokyo", "Asia/Tokyo"),
        ("东京", "东京 Tokyo", "Asia/Tokyo"),
        ("seoul", "首尔 Seoul", "Asia/Seoul"),
        ("首尔", "首尔 Seoul", "Asia/Seoul"),
        ("beijing", "北京 Beijing", "Asia/Shanghai"),
        ("北京", "北京 Beijing", "Asia/Shanghai"),
        ("shanghai", "上海 Shanghai", "Asia/Shanghai"),
        ("上海", "上海 Shanghai", "Asia/Shanghai"),
        ("hongkong", "香港 Hong Kong", "Asia/Hong_Kong"),
        ("香港", "香港 Hong Kong", "Asia/Hong_Kong"),
        ("taipei", "台北 Taipei", "Asia/Taipei"),
        ("台北", "台北 Taipei", "Asia/Taipei"),
        ("singapore", "新加坡 Singapore", "Asia/Singapore"),
        ("新加坡", "新加坡 Singapore", "Asia/Singapore"),
        ("bangkok", "曼谷 Bangkok", "Asia/Bangkok"),
        ("曼谷", "曼谷 Bangkok", "Asia/Bangkok"),
        ("dubai", "迪拜 Dubai", "Asia/Dubai"),
        ("迪拜", "迪拜 Dubai", "Asia/Dubai"),
        ("mumbai", "孟买 Mumbai", "Asia/Kolkata"),
        ("孟买", "孟买 Mumbai", "Asia/Kolkata"),
        ("moscow", "莫斯科 Moscow", "Europe/Moscow"),
        ("莫斯科", "莫斯科 Moscow", "Europe/Moscow"),
        ("berlin", "柏林 Berlin", "Europe/Berlin"),
        ("柏林", "柏林 Berlin", "Europe/Berlin"),
        ("paris", "巴黎 Paris", "Europe/Paris"),
        ("巴黎", "巴黎 Paris", "Europe/Paris"),
        ("london", "伦敦 London", "Europe/London"),
        ("伦敦", "伦敦 London", "Europe/London"),
        ("newyork", "纽约 New York", "America/New_York"),
        ("new york", "纽约 New York", "America/New_York"),
        ("纽约", "纽约 New York", "America/New_York"),
        ("chicago", "芝加哥 Chicago", "America/Chicago"),
        ("芝加哥", "芝加哥 Chicago", "America/Chicago"),
        ("denver", "丹佛 Denver", "America/Denver"),
        ("丹佛", "丹佛 Denver", "America/Denver"),
        ("losangeles", "洛杉矶 Los Angeles", "America/Los_Angeles"),
        ("los angeles", "洛杉矶 Los Angeles", "America/Los_Angeles"),
        ("洛杉矶", "洛杉矶 Los Angeles", "America/Los_Angeles"),
        ("seattle", "西雅图 Seattle", "America/Los_Angeles"),
        ("西雅图", "西雅图 Seattle", "America/Los_Angeles"),
        ("vancouver", "温哥华 Vancouver", "America/Vancouver"),
        ("温哥华", "温哥华 Vancouver", "America/Vancouver"),
        ("toronto", "多伦多 Toronto", "America/Toronto"),
        ("多伦多", "多伦多 Toronto", "America/Toronto"),
        ("sydney", "悉尼 Sydney", "Australia/Sydney"),
        ("悉尼", "悉尼 Sydney", "Australia/Sydney"),
        ("melbourne", "墨尔本 Melbourne", "Australia/Melbourne"),
        ("墨尔本", "墨尔本 Melbourne", "Australia/Melbourne"),
        ("auckland", "奥克兰 Auckland", "Pacific/Auckland"),
        ("奥克兰", "奥克兰 Auckland", "Pacific/Auckland"),
        ("honolulu", "檀香山 Honolulu", "Pacific/Honolulu"),
        ("檀香山", "檀香山 Honolulu", "Pacific/Honolulu"),
    ]

    private static func timeInCity(_ raw: String, lower: String, now: Date) -> CalcResult? {
        var cityKey: String?
        if lower.hasPrefix("time in ") {
            cityKey = String(lower.dropFirst("time in ".count)).trimmingCharacters(in: .whitespaces)
        } else if lower.hasSuffix("时间") {
            cityKey = String(lower.dropLast(2))
        }
        guard let key = cityKey, !key.isEmpty else { return nil }
        guard let city = cities.first(where: { $0.0 == key }) else { return nil }
        guard let zone = TimeZone(identifier: city.2) else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        formatter.timeZone = zone
        let localFormatter = DateFormatter()
        localFormatter.dateFormat = "MM-dd HH:mm"
        localFormatter.timeZone = TimeZone.current

        var secondsFromGMT = Double(zone.secondsFromGMT(for: now))
        let localSeconds = Double(TimeZone.current.secondsFromGMT(for: now))
        let deltaHours = (secondsFromGMT - localSeconds) / 3600
        secondsFromGMT /= 3600

        let deltaText: String
        if abs(deltaHours) < 0.01 {
            deltaText = L10n.t("与本地相同", "same as local")
        } else {
            let sign = deltaHours > 0 ? "+" : ""
            deltaText = "\(sign)\(CalcFormatter.display(deltaHours) ?? "")h " + L10n.t("vs 本地", "vs local")
        }
        let text = "\(city.1) \(formatter.string(from: now)) · UTC\(secondsFromGMT >= 0 ? "+" : "")\(Int(secondsFromGMT)) · \(deltaText)"
        let copy = formatter.string(from: now)
        return CalcResult(output: .text(copy), display: "= \(text)", copyText: copy)
    }

    // MARK: - 日期目标解析

    /// 支持：yyyy-mm-dd、yyyy/m/d、m-d、m/d（当年）、9am、9:30、21:00、明天、后天、昨天。
    public static func parseTarget(_ text: String, now: Date) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let calendar = Calendar.current

        switch trimmed {
        case "明天", "tomorrow": return calendar.startOfDay(for: now).addingTimeInterval(86_400)
        case "后天": return calendar.startOfDay(for: now).addingTimeInterval(172_800)
        case "昨天", "yesterday": return calendar.startOfDay(for: now).addingTimeInterval(-86_400)
        default: break
        }

        // yyyy-mm-dd / yyyy/m/d
        if let date = dateFromComponents(trimmed, now: now, calendar: calendar) { return date }

        // 纯时刻：9am / 9:30 / 21:00 / 9:30pm
        if let timeOnly = timeOnly(trimmed, calendar: calendar) {
            return calendar.date(bySettingHour: timeOnly.0, minute: timeOnly.1, second: 0, of: now)
        }
        return nil
    }

    private static func dateFromComponents(_ text: String, now: Date, calendar: Calendar) -> Date? {
        let parts = text.split(whereSeparator: { $0 == "-" || $0 == "/" }).compactMap { Int($0) }
        guard parts.count == 2 || parts.count == 3 else { return nil }
        let year = parts.count == 3 ? parts[0] : calendar.component(.year, from: now)
        let month = parts.count == 3 ? parts[1] : parts[0]
        let day = parts.count == 3 ? parts[2] : parts[1]
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }

    private static func timeOnly(_ text: String, calendar: Calendar) -> (Int, Int)? {
        let lower = text.lowercased()
        var body = lower
        var pm = false
        var am = false
        if body.hasSuffix("pm") { pm = true; body = String(body.dropLast(2)).trimmingCharacters(in: .whitespaces) }
        else if body.hasSuffix("am") { am = true; body = String(body.dropLast(2)).trimmingCharacters(in: .whitespaces) }
        let parts = body.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 1 || parts.count == 2 else { return nil }
        var hour = parts[0]
        let minute = parts.count == 2 ? parts[1] : 0
        if pm, hour < 12 { hour += 12 }
        if am, hour == 12 { hour = 0 }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }

    private static func formatDate(_ date: Date, includeTime: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = includeTime ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
