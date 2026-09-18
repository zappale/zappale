import Foundation

// MARK: - 结果

/// 内联计算卡的输出。evaluate 解析失败一律返回 nil，
/// 面板据此把查询当普通搜索处理。
public struct CalcResult: Equatable {
    public enum Output: Equatable {
        case number(Double)
        case quantity(value: Double, unit: String)
        /// 进制转换等非数值文本。
        case text(String)
    }

    public let output: Output
    /// 卡片主行，如 "= 6.21371 mi"。
    public let display: String
    /// 回车复制到剪贴板的纯文本（不带单位）。
    public let copyText: String
}

// MARK: - 量纲

/// 基本量纲集合。角度与信息量独立成维，避免与纯数混淆。
public struct CalcDimension: Hashable {
    public enum Base: Hashable, CaseIterable {
        case length, mass, time, temperature, information, angle
    }

    public var exponents: [Base: Int]
    public var isDimensionless: Bool { exponents.values.allSatisfy { $0 == 0 } }

    public init(exponents: [Base: Int] = [:]) {
        // 零指数不保留，保证 == 与哈希的规范形式。
        self.exponents = exponents.filter { $0.value != 0 }
    }

    public static let length = CalcDimension(exponents: [.length: 1])
    public static let mass = CalcDimension(exponents: [.mass: 1])
    public static let time = CalcDimension(exponents: [.time: 1])
    public static let temperature = CalcDimension(exponents: [.temperature: 1])
    public static let information = CalcDimension(exponents: [.information: 1])
    public static let angle = CalcDimension(exponents: [.angle: 1])

    public static func * (lhs: CalcDimension, rhs: CalcDimension) -> CalcDimension {
        var result = lhs
        for (base, exp) in rhs.exponents {
            result.exponents[base, default: 0] += exp
            if result.exponents[base] == 0 { result.exponents[base] = nil }
        }
        return CalcDimension(exponents: result.exponents)
    }

    public static func / (lhs: CalcDimension, rhs: CalcDimension) -> CalcDimension {
        lhs * CalcDimension(exponents: rhs.exponents.mapValues { -$0 })
    }

    /// 规范键，用于查偏好展示单位，如 "L/T"、"L2"、"M*L2/T2"。
    /// 负指数写成分母：L/T、1/T2。
    public var key: String {
        let symbols: [Base: String] = [
            .length: "L", .mass: "M", .time: "T",
            .temperature: "H", .information: "I", .angle: "A",
        ]
        let positive = Base.allCases.compactMap { base -> String? in
            guard let exp = exponents[base], exp > 0 else { return nil }
            return symbols[base]! + (exp == 1 ? "" : String(exp))
        }.joined(separator: "*")
        let negative = Base.allCases.compactMap { base -> String? in
            guard let exp = exponents[base], exp < 0 else { return nil }
            return symbols[base]! + (exp == -1 ? "" : String(-exp))
        }.joined(separator: "*")
        if negative.isEmpty { return positive }
        return positive.isEmpty ? "1/\(negative)" : "\(positive)/\(negative)"
    }
}

// MARK: - 单位

/// 单位定义：符号、量纲、到量纲基单位的线性换算（base = factor·v + offset）。
public struct CalcUnitDef: Hashable {
    public let symbol: String
    public let dimension: CalcDimension
    public let factor: Double
    public let offset: Double

    public init(_ symbol: String, _ dimension: CalcDimension, _ factor: Double, _ offset: Double = 0) {
        self.symbol = symbol
        self.dimension = dimension
        self.factor = factor
        self.offset = offset
    }

    public func toBase(_ value: Double) -> Double { factor * value + offset }
    public func fromBase(_ base: Double) -> Double { (base - offset) / factor }
}

/// 单位目录。符号表一次构建；同符号首个注册者生效。
public enum CalcUnits {
    public static let table: [String: CalcUnitDef] = buildTable()

    private static func buildTable() -> [String: CalcUnitDef] {
        let L = CalcDimension.length
        let M = CalcDimension.mass
        let T = CalcDimension.time
        let H = CalcDimension.temperature
        let I = CalcDimension.information
        let A = CalcDimension.angle

        var units: [CalcUnitDef] = []
        // 长度（基 m）
        units += [
            CalcUnitDef("m", L, 1), CalcUnitDef("km", L, 1e3), CalcUnitDef("dm", L, 0.1),
            CalcUnitDef("cm", L, 1e-2), CalcUnitDef("mm", L, 1e-3), CalcUnitDef("um", L, 1e-6),
            CalcUnitDef("µm", L, 1e-6), CalcUnitDef("nm", L, 1e-9),
            CalcUnitDef("mi", L, 1609.344), CalcUnitDef("yd", L, 0.9144),
            CalcUnitDef("ft", L, 0.3048), CalcUnitDef("in", L, 0.0254),
            CalcUnitDef("nmi", L, 1852), CalcUnitDef("ly", L, 9.4607304726e15),
        ]
        // 质量（基 kg）
        units += [
            CalcUnitDef("kg", M, 1), CalcUnitDef("g", M, 1e-3), CalcUnitDef("mg", M, 1e-6),
            CalcUnitDef("ug", M, 1e-9), CalcUnitDef("µg", M, 1e-9), CalcUnitDef("t", M, 1e3),
            CalcUnitDef("lb", M, 0.45359237), CalcUnitDef("lbs", M, 0.45359237),
            CalcUnitDef("oz", M, 0.028349523125), CalcUnitDef("st", M, 6.35029318),
        ]
        // 时间（基 s）
        units += [
            CalcUnitDef("s", T, 1), CalcUnitDef("sec", T, 1), CalcUnitDef("ms", T, 1e-3),
            CalcUnitDef("us", T, 1e-6), CalcUnitDef("µs", T, 1e-6), CalcUnitDef("ns", T, 1e-9),
            CalcUnitDef("min", T, 60), CalcUnitDef("h", T, 3600), CalcUnitDef("hr", T, 3600),
            CalcUnitDef("day", T, 86400), CalcUnitDef("days", T, 86400),
            CalcUnitDef("week", T, 604800), CalcUnitDef("weeks", T, 604800),
        ]
        // 温度（基 K）
        units += [
            CalcUnitDef("c", H, 1, 273.15), CalcUnitDef("°c", H, 1, 273.15),
            CalcUnitDef("f", H, 5.0 / 9.0, 255.372222222),
            CalcUnitDef("°f", H, 5.0 / 9.0, 255.372222222),
            CalcUnitDef("k", H, 1), CalcUnitDef("kelvin", H, 1),
        ]
        // 信息量（基 byte）
        units += [
            CalcUnitDef("b", I, 0.125), CalcUnitDef("bit", I, 0.125),
            CalcUnitDef("kb", I, 1e3), CalcUnitDef("mb", I, 1e6),
            CalcUnitDef("gb", I, 1e9), CalcUnitDef("tb", I, 1e12),
            CalcUnitDef("kib", I, 1024), CalcUnitDef("mib", I, 1048576),
            CalcUnitDef("gib", I, 1073741824), CalcUnitDef("tib", I, 1.099511627776e12),
        ]
        // 速度（基 m/s）
        let speed = L / T
        units += [
            CalcUnitDef("m/s", speed, 1), CalcUnitDef("mps", speed, 1),
            CalcUnitDef("km/h", speed, 1000.0 / 3600.0),
            CalcUnitDef("kmh", speed, 1000.0 / 3600.0),
            CalcUnitDef("kph", speed, 1000.0 / 3600.0),
            CalcUnitDef("mph", speed, 0.44704), CalcUnitDef("kn", speed, 0.514444444),
        ]
        // 频率（基 1/s）
        let freq = CalcDimension() / T
        units += [
            CalcUnitDef("hz", freq, 1), CalcUnitDef("khz", freq, 1e3),
            CalcUnitDef("mhz", freq, 1e6), CalcUnitDef("ghz", freq, 1e9),
        ]
        // 面积（基 m²）
        let area = L * L
        units += [
            CalcUnitDef("m2", area, 1), CalcUnitDef("km2", area, 1e6),
            CalcUnitDef("cm2", area, 1e-4), CalcUnitDef("ft2", area, 0.09290304),
            CalcUnitDef("in2", area, 0.00064516), CalcUnitDef("ha", area, 1e4),
            CalcUnitDef("acre", area, 4046.8564224),
        ]
        // 体积（基 L）
        let volume = L * L * L
        units += [
            CalcUnitDef("l", volume, 1), CalcUnitDef("ml", volume, 1e-3),
            CalcUnitDef("liter", volume, 1), CalcUnitDef("m3", volume, 1000),
            CalcUnitDef("gal", volume, 3.785411784), CalcUnitDef("qt", volume, 0.946352946),
            CalcUnitDef("pt", volume, 0.473176473), CalcUnitDef("cup", volume, 0.2365882365),
            CalcUnitDef("floz", volume, 0.0295735295625),
            CalcUnitDef("ft3", volume, 28.316846592), CalcUnitDef("in3", volume, 0.016387064),
        ]
        // 能量（基 J）
        let energy = M * L * L / (T * T)
        units += [
            CalcUnitDef("j", energy, 1), CalcUnitDef("kj", energy, 1e3),
            CalcUnitDef("mj", energy, 1e6), CalcUnitDef("cal", energy, 4.184),
            CalcUnitDef("kcal", energy, 4184), CalcUnitDef("wh", energy, 3600),
            CalcUnitDef("kwh", energy, 3.6e6), CalcUnitDef("mwh", energy, 3.6e9),
            CalcUnitDef("btu", energy, 1055.05585262), CalcUnitDef("ev", energy, 1.602176634e-19),
        ]
        // 压力（基 Pa）
        let pressure = M / (L * T * T)
        units += [
            CalcUnitDef("pa", pressure, 1), CalcUnitDef("kpa", pressure, 1e3),
            CalcUnitDef("mpa", pressure, 1e6), CalcUnitDef("bar", pressure, 1e5),
            CalcUnitDef("mbar", pressure, 100), CalcUnitDef("atm", pressure, 101_325),
            CalcUnitDef("psi", pressure, 6_894.757),
            CalcUnitDef("mmhg", pressure, 133.322), CalcUnitDef("torr", pressure, 133.322),
        ]
        // 功率（基 W）
        let power = M * L * L / (T * T * T)
        units += [
            CalcUnitDef("w", power, 1), CalcUnitDef("kw", power, 1e3),
            CalcUnitDef("mw", power, 1e6), CalcUnitDef("hp", power, 745.6999),
            CalcUnitDef("btu/h", power, 0.293071),
        ]
        // 数据速率（基 B/s）：bps 族为比特每秒，b/s 族为字节每秒
        let datarate = I / T
        units += [
            CalcUnitDef("b/s", datarate, 0.125), CalcUnitDef("kb/s", datarate, 1e3),
            CalcUnitDef("mb/s", datarate, 1e6), CalcUnitDef("gb/s", datarate, 1e9),
            CalcUnitDef("kbps", datarate, 125), CalcUnitDef("mbps", datarate, 125_000),
            CalcUnitDef("gbps", datarate, 1.25e8),
        ]
        // 角度（基 deg）
        units += [
            CalcUnitDef("deg", A, 1), CalcUnitDef("rad", A, 180 / Double.pi),
            CalcUnitDef("grad", A, 0.9), CalcUnitDef("turn", A, 360),
            CalcUnitDef("arcmin", A, 1.0 / 60.0), CalcUnitDef("arcsec", A, 1.0 / 3600.0),
        ]

        var table: [String: CalcUnitDef] = [:]
        for unit in units where table[unit.symbol] == nil {
            table[unit.symbol] = unit
        }
        return table
    }

    /// 量纲 → 展示偏好单位（值域合适时优先），避免派生结果出现怪组合。
    public static let preferredDisplay: [String: [String]] = [
        "L/T": ["km/h", "m/s", "mph", "kn"],
        "L2": ["m2", "km2", "ft2", "ha"],
        "L3": ["l", "m3", "gal"],
        "1/T": ["ghz", "mhz", "khz", "hz"],
        "M*L2/T2": ["kwh", "kcal", "kj", "j"],
        "I": ["gb", "mb", "kb", "tb"],
        "I/T": ["gb/s", "mb/s", "kb/s", "b/s"],
        "M/(L*T2)": ["bar", "kpa", "psi", "pa"],
        "M*L2/T3": ["kw", "w", "hp"],
    ]

    /// 基本单位符号，用于组合回退展示（m²、m/s、1/s）。
    private static let baseSymbols: [CalcDimension.Base: String] = [
        .length: "m", .mass: "kg", .time: "s",
        .temperature: "K", .information: "B", .angle: "deg",
    ]

    private static let superscripts: [Character: String] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
    ]

    /// 量纲的基单位（factor = 1），符号按指数组合。
    public static func baseUnit(for dimension: CalcDimension) -> CalcUnitDef {
        var numerator: [(String, Int)] = []
        var denominator: [(String, Int)] = []
        for (base, exp) in dimension.exponents {
            let symbol = baseSymbols[base] ?? "?"
            if exp > 0 { numerator.append((symbol, exp)) }
            else if exp < 0 { denominator.append((symbol, -exp)) }
        }
        let joined = { (parts: [(String, Int)]) in
            parts.map { $0.0 + ($0.1 == 1 ? "" : String($0.1).compactMap { superscripts[$0] }.joined()) }
                .joined(separator: "·")
        }
        let top = joined(numerator)
        let bottom = joined(denominator)
        let symbol: String
        if top.isEmpty { symbol = bottom.isEmpty ? "" : "1/\(bottom)" }
        else { symbol = bottom.isEmpty ? top : "\(top)/\(bottom)" }
        return CalcUnitDef(symbol, dimension, 1)
    }

    /// 为派生量纲挑展示单位：偏好表中值域合适者，否则基单位组合。
    public static func displayUnit(for dimension: CalcDimension, baseValue: Double) -> CalcUnitDef {
        if let candidates = preferredDisplay[dimension.key] {
            for symbol in candidates {
                guard let unit = table[symbol] else { continue }
                let value = baseValue / unit.factor
                if abs(value) >= 0.1 && abs(value) < 10000 { return unit }
            }
            if let first = candidates.compactMap({ table[$0] }).first { return first }
        }
        return baseUnit(for: dimension)
    }

    public static func unit(_ symbol: String) -> CalcUnitDef? {
        table[symbol] ?? table[symbol.lowercased()]
    }
}

// MARK: - 词法

public enum CalcToken: Equatable {
    case number(Double)
    case identifier(String)
    case plus, minus, star, slash, caret, percent
    case lparen, rparen, comma
    case toKeyword
}


/// ASCII 数字判断（Unicode.Scalar 没有便捷 API）。
private func isDigit(_ scalar: Unicode.Scalar) -> Bool {
    scalar.value >= 0x30 && scalar.value <= 0x39
}

public enum CalcTokenizer {
    public static func tokenize(_ input: String) -> [CalcToken]? {
        var tokens: [CalcToken] = []
        let scalars = Array(input.unicodeScalars)
        var i = 0

        func appendNumber(from start: Int) -> Int? {
            // 返回结束下标，或 nil 表示失败。扫描：digits [. digits] [e[+-]digits]
            var j = start
            var sawDigit = false
            while j < scalars.count, isDigit(scalars[j]) {
                sawDigit = true; j += 1
            }
            if j < scalars.count, scalars[j] == ".",
               j + 1 < scalars.count, isDigit(scalars[j + 1]) {
                j += 1
                while j < scalars.count, isDigit(scalars[j]) { j += 1 }
            }
            guard sawDigit else { return nil }

            var text = String(String.UnicodeScalarView(scalars[start..<j]))
            // 科学计数法：e/E 后必须紧跟数字（或符号+数字），否则留给标识符
            if j < scalars.count, scalars[j] == "e" || scalars[j] == "E" {
                var k = j + 1
                if k < scalars.count, scalars[k] == "+" || scalars[k] == "-" { k += 1 }
                if k < scalars.count, isDigit(scalars[k]) {
                    while k < scalars.count, isDigit(scalars[k]) { k += 1 }
                    let exponentText = String(String.UnicodeScalarView(scalars[j..<k]))
                    text += exponentText
                    j = k
                }
            }
            guard let value = Double(text) else { return nil }
            tokens.append(.number(value))
            return j
        }

        while i < scalars.count {
            let scalar = scalars[i]

            if scalar.properties.isWhitespace { i += 1; continue }

            switch scalar {
            case "×", "·", "∗": tokens.append(.star); i += 1; continue
            case "÷", "∕": tokens.append(.slash); i += 1; continue
            case "−", "–", "—": tokens.append(.minus); i += 1; continue
            case "→": tokens.append(.toKeyword); i += 1; continue
            default: break
            }

            if scalar == "%" { tokens.append(.percent); i += 1; continue }
            if scalar == "+" { tokens.append(.plus); i += 1; continue }
            if scalar == "-" {
                if i + 1 < scalars.count, scalars[i + 1] == ">" {
                    tokens.append(.toKeyword); i += 2; continue
                }
                tokens.append(.minus); i += 1; continue
            }
            if scalar == "*" {
                if i + 1 < scalars.count, scalars[i + 1] == "*" {
                    tokens.append(.caret); i += 2; continue
                }
                tokens.append(.star); i += 1; continue
            }
            if scalar == "/" { tokens.append(.slash); i += 1; continue }
            if scalar == "^" { tokens.append(.caret); i += 1; continue }
            if scalar == "(" || scalar == "（" { tokens.append(.lparen); i += 1; continue }
            if scalar == ")" || scalar == "）" { tokens.append(.rparen); i += 1; continue }
            if scalar == "," || scalar == "，" { tokens.append(.comma); i += 1; continue }

            // 0x / 0b / 0o 进制前缀
            if scalar == "0", i + 1 < scalars.count {
                let next = scalars[i + 1]
                let radix: Int?
                let digitTest: (Unicode.Scalar) -> Bool
                switch next {
                case "x", "X": radix = 16; digitTest = { $0.properties.isASCIIHexDigit }
                case "b", "B": radix = 2; digitTest = { $0 == "0" || $0 == "1" }
                case "o", "O": radix = 8; digitTest = { ("0"..."7").contains($0) }
                default: radix = nil; digitTest = { _ in false }
                }
                if let radix {
                    var j = i + 2
                    var digits = ""
                    while j < scalars.count, digitTest(scalars[j]) {
                        digits.unicodeScalars.append(scalars[j]); j += 1
                    }
                    if !digits.isEmpty, let value = UInt64(digits, radix: radix) {
                        tokens.append(.number(Double(value)))
                        i = j
                        continue
                    }
                    // 前缀后无合法数字：整个查询按无法计算处理
                    return nil
                }
            }

            // 数字
            if isDigit(scalar) {
                guard let end = appendNumber(from: i) else { return nil }
                i = end
                continue
            }

            // 标识符：字母（含 π µ °）开头，后跟字母数字；上标归一为数字
            if scalar.properties.isAlphabetic || scalar == "π" || scalar == "µ" || scalar == "°" {
                var j = i
                var name = ""
                while j < scalars.count {
                    let s = scalars[j]
                    if s.properties.isAlphabetic || s == "π" || s == "µ" || s == "°" {
                        name.unicodeScalars.append(s); j += 1
                    } else if s == "²" { name += "2"; j += 1 }
                    else if s == "³" { name += "3"; j += 1 }
                    else if isDigit(s) { name.unicodeScalars.append(s); j += 1 }
                    else { break }
                }
                // "to" 是换算词；"in" 是英寸单位（避免歧义，不做换算词）。
                if name == "to" {
                    tokens.append(.toKeyword)
                } else {
                    tokens.append(.identifier(name))
                }
                i = j
                continue
            }

            return nil
        }

        return tokens.isEmpty ? nil : tokens
    }
}

// MARK: - 值

/// 计算值：纯数或带单位的量。
public enum CalcValue {
    case number(Double)
    case quantity(value: Double, unit: CalcUnitDef)

    public var scalar: Double? {
        switch self {
        case .number(let v): return v
        case .quantity: return nil
        }
    }

    /// 数值大小（取量的原单位值），供百分比语境使用。
    public var magnitude: Double {
        switch self {
        case .number(let v): return v
        case .quantity(let v, _): return v
        }
    }

    public var dimension: CalcDimension {
        switch self {
        case .number: return CalcDimension()
        case .quantity(_, let unit): return unit.dimension
        }
    }
}

// MARK: - 引擎

/// 面板内联计算引擎：词法 → 优先级爬升 → 量纲算术 → 换算/进制。
/// 纯函数；解析或求值失败返回 nil，调用方回落为普通搜索。
public enum CalcEngine {

    public static let functions: [String: ([Double]) -> Double?] = [
        "sqrt": { $0.count == 1 ? __sqrt($0[0]) : nil },
        "cbrt": { $0.count == 1 ? cbrt($0[0]) : nil },
        "abs": { $0.count == 1 ? abs($0[0]) : nil },
        "floor": { $0.count == 1 ? floor($0[0]) : nil },
        "ceil": { $0.count == 1 ? ceil($0[0]) : nil },
        "round": { $0.count == 1 ? $0[0].rounded() : nil },
        "sin": { $0.count == 1 ? sin($0[0]) : nil },
        "cos": { $0.count == 1 ? cos($0[0]) : nil },
        "tan": { $0.count == 1 ? tan($0[0]) : nil },
        "asin": { $0.count == 1 ? asin($0[0]) : nil },
        "acos": { $0.count == 1 ? acos($0[0]) : nil },
        "atan": { $0.count == 1 ? atan($0[0]) : nil },
        "sinh": { $0.count == 1 ? sinh($0[0]) : nil },
        "cosh": { $0.count == 1 ? cosh($0[0]) : nil },
        "tanh": { $0.count == 1 ? tanh($0[0]) : nil },
        "log": { $0.count == 1 ? log10($0[0]) : nil },
        "ln": { $0.count == 1 ? log($0[0]) : nil },
        "log2": { $0.count == 1 ? log2($0[0]) : nil },
        "exp": { $0.count == 1 ? exp($0[0]) : nil },
        "min": { $0.count >= 1 ? $0.min() : nil },
        "max": { $0.count >= 1 ? $0.max() : nil },
        "pow": { $0.count == 2 ? Foundation.pow($0[0], $0[1]) : nil },
        "hypot": { $0.count == 2 ? Foundation.hypot($0[0], $0[1]) : nil },
    ]

    public static let constants: [String: Double] = [
        "pi": .pi, "π": .pi, "e": M_E, "tau": 2 * .pi, "φ": 1.618033988749895,
    ]

    public static let radixTargets: [String: Int] = [
        "hex": 16, "hexadecimal": 16, "bin": 2, "binary": 2,
        "oct": 8, "octal": 8, "dec": 10, "decimal": 10,
    ]

    // MARK: 入口

    public static func evaluate(_ query: String, now: Date = Date()) -> CalcResult? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // 自然语言形式优先：20% of 50 / days till / today + 3 weeks / time in Tokyo
        if let natural = CalcNatural.evaluate(trimmed, now: now) { return natural }
        guard var tokens = CalcTokenizer.tokenize(trimmed) else { return nil }

        // 单个纯词（无数字）永不触发计算卡：那是应用名或搜索词。
        if tokens.count == 1, case .identifier = tokens[0] { return nil }

        // 尾随二元运算符：剥掉重试一次（"5*3+" 仍显示 15）。
        var outcome = parse(tokens)
        if outcome == nil {
            while let last = tokens.last,
                  [.plus, .minus, .star, .slash, .caret].contains(last) {
                tokens.removeLast()
            }
            guard !tokens.isEmpty else { return nil }
            outcome = parse(tokens)
        }
        guard let outcome else { return nil }
        return makeResult(outcome.value, target: outcome.target)
    }

    // MARK: 顶层拆分：表达式 (to 目标)?

    private struct ParseOutcome {
        let value: CalcValue
        let target: ConversionTarget?
    }

    private enum ConversionTarget {
        case unit(CalcUnitDef)
        case radix(Int)
    }

    private static func parse(_ tokens: [CalcToken]) -> ParseOutcome? {
        // 顶层（未被括号包裹）的 to：切分换算
        var depth = 0
        var toIndex: Int?
        for (index, token) in tokens.enumerated() {
            switch token {
            case .lparen: depth += 1
            case .rparen: depth -= 1
            case .toKeyword where depth == 0: toIndex = index
            default: break
            }
        }

        if let toIndex {
            let left = Array(tokens[..<toIndex])
            let right = Array(tokens[(toIndex + 1)...])
            guard !left.isEmpty, !right.isEmpty else { return nil }
            var parser = ParserState(tokens: left)
            guard let value = parser.parseExpression(), parser.isAtEnd else { return nil }
            guard let target = parseTarget(right) else { return nil }
            return ParseOutcome(value: value, target: target)
        }

        var parser = ParserState(tokens: tokens)
        guard let value = parser.parseExpression(), parser.isAtEnd else { return nil }
        return ParseOutcome(value: value, target: nil)
    }

    /// 换算目标：进制关键字、单一单位或 u1/u2 组合。
    private static func parseTarget(_ tokens: [CalcToken]) -> ConversionTarget? {
        if tokens.count == 1, case .identifier(let name) = tokens[0],
           let radix = radixTargets[name.lowercased()] {
            return .radix(radix)
        }

        // u1/u2（"m/s"、"km/h"）
        if tokens.count == 3, case .identifier(let first) = tokens[0],
           tokens[1] == .slash, case .identifier(let second) = tokens[2],
           let u1 = CalcUnits.unit(first), let u2 = CalcUnits.unit(second) {
            let dimension = u1.dimension / u2.dimension
            let factor = u1.factor / u2.factor
            let symbol = "\(u1.symbol)/\(u2.symbol)"
            return .unit(CalcUnitDef(symbol, dimension, factor))
        }

        if tokens.count == 1, case .identifier(let name) = tokens[0],
           let unit = CalcUnits.unit(name) {
            return .unit(unit)
        }

        return nil
    }

    // MARK: 解析器

    /// 带百分比标志的中间结果：percent = 该项带尾随 %（保留原始数值，
    /// 在使用点按语境换算）。
    private struct TermResult {
        var value: CalcValue
        var percent: Bool
    }

    private struct ParserState {
        let tokens: [CalcToken]
        var position = 0

        init(tokens: [CalcToken]) { self.tokens = tokens }

        var isAtEnd: Bool { position >= tokens.count }
        var current: CalcToken? { position < tokens.count ? tokens[position] : nil }

        public mutating func advance() -> CalcToken? {
            guard position < tokens.count else { return nil }
            let token = tokens[position]
            position += 1
            return token
        }

        func peek(_ offset: Int) -> CalcToken? {
            let index = position + offset
            return index < tokens.count ? tokens[index] : nil
        }

        /// 隐式乘法的右因子只允许数字/括号/常量/函数，不允许裸单位。
        private func canStartImplicitPrimary(_ token: CalcToken) -> Bool {
            switch token {
            case .number, .lparen: return true
            case .identifier(let name):
                return CalcEngine.constants[name] != nil
                    || CalcEngine.constants[name.lowercased()] != nil
                    || CalcEngine.functions[name.lowercased()] != nil
            default: return false
            }
        }

        // expression := term { ("+"|"-") term }
        // 百分比规则：a + b% = a + a·b/100；a - b% 同理。
        public mutating func parseExpression() -> CalcValue? {
            guard var leftTerm = parseTerm() else { return nil }
            // 首项带 %（"10%"、"（2+3)%"）：按 /100 归一。
            if leftTerm.percent {
                guard let normalized = scale(leftTerm.value, by: 0.01) else { return nil }
                leftTerm = TermResult(value: normalized, percent: false)
            }
            var left = leftTerm.value

            while current == .plus || current == .minus {
                let isPlus = current == .plus
                _ = advance()
                guard let rightTerm = parseTerm() else { return nil }

                let right: CalcValue
                if rightTerm.percent {
                    // a ± b% → 加减 a·b/100（量纲随左项）
                    guard let rhsNumber = rightTerm.value.numberValueForPercent(),
                          let scaled = scale(left, by: rhsNumber / 100) else { return nil }
                    right = scaled
                } else {
                    right = rightTerm.value
                }

                switch (left, right) {
                case let (.number(l), .number(r)):
                    left = .number(isPlus ? l + r : l - r)
                case let (.quantity(lv, lu), .number(r)):
                    left = .quantity(value: isPlus ? lv + r : lv - r, unit: lu)
                case let (.quantity(lv, lu), .quantity(rv, ru)):
                    guard lu.dimension == ru.dimension else { return nil }
                    let rvInLeft = lu.fromBase(ru.toBase(rv))
                    left = .quantity(value: isPlus ? lv + rvInLeft : lv - rvInLeft, unit: lu)
                default:
                    return nil
                }
            }
            return left
        }

        // term := factor { ("*"|"/" | 隐式) factor }
        // 百分比规则：乘除语境里 % 一律按 /100；首项的 % 若未被乘除消费则冒泡给加法层。
        public mutating func parseTerm() -> TermResult? {
            guard let firstFactor = parseFactor() else { return nil }
            var left = firstFactor.value
            var percent = firstFactor.percent

            while let token = current {
                switch token {
                case .star, .slash:
                    _ = advance()
                    guard let rightFactor = parseFactor() else { return nil }
                    // 进入乘除前，首项的 % 先归一
                    if percent {
                        guard let normalized = scale(left, by: 0.01) else { return nil }
                        left = normalized
                        percent = false
                    }
                    var right = rightFactor.value
                    if rightFactor.percent {
                        guard let normalized = scale(right, by: 0.01) else { return nil }
                        right = normalized
                    }
                    guard let combined = applyMultiplicative(left, right, divide: token == .slash)
                    else { return nil }
                    left = combined
                case let token where canStartImplicitPrimary(token):
                    // 隐式乘法：2pi、2(3+4)；裸单位不参与隐式乘法
                    // （否则 "100kg in lb" 会算出量纲相乘的废话）
                    guard let rightFactor = parseFactor() else { return nil }
                    if percent {
                        guard let normalized = scale(left, by: 0.01) else { return nil }
                        left = normalized
                        percent = false
                    }
                    var right = rightFactor.value
                    if rightFactor.percent {
                        guard let normalized = scale(right, by: 0.01) else { return nil }
                        right = normalized
                    }
                    guard let combined = applyMultiplicative(left, right, divide: false)
                    else { return nil }
                    left = combined
                default:
                    return TermResult(value: left, percent: percent)
                }
            }
            return TermResult(value: left, percent: percent)
        }

        // factor := ("-"|"+") factor | power
        public mutating func parseFactor() -> TermResult? {
            if current == .minus {
                _ = advance()
                guard let inner = parseFactor() else { return nil }
                switch inner.value {
                case .number(let v): return TermResult(value: .number(-v), percent: inner.percent)
                case .quantity(let v, let u):
                    return TermResult(value: .quantity(value: -v, unit: u), percent: inner.percent)
                }
            }
            if current == .plus {
                _ = advance()
                return parseFactor()
            }
            return parsePower()
        }

        // power := postfix [ "^" factor ]（右结合）
        public mutating func parsePower() -> TermResult? {
            guard let base = parsePostfix() else { return nil }
            if current == .caret {
                _ = advance()
                guard let exponentTerm = parseFactor() else { return nil }
                var exponent = exponentTerm.value
                if exponentTerm.percent {
                    guard let normalized = scale(exponent, by: 0.01) else { return nil }
                    exponent = normalized
                }
                guard let result = applyPower(base.value, exponent) else { return nil }
                return TermResult(value: result, percent: false)
            }
            return base
        }

        // postfix := primary { "%" }
        public mutating func parsePostfix() -> TermResult? {
            guard let primary = parsePrimary() else { return nil }
            let value = primary
            var percent = false
            while current == .percent {
                _ = advance()
                guard case .number = value else { return nil } // 量不带 %
                percent = true
            }
            return TermResult(value: value, percent: percent)
        }

        // primary := number [单位链] | 常量 | 函数 | "(" expr ")" | 裸单位
        public mutating func parsePrimary() -> CalcValue? {
            guard let token = current else { return nil }

            if case .number(let value) = token {
                _ = advance()
                // 紧随的单位绑定：10km、2 m/s
                if case .identifier(let name) = current,
                   let unit = CalcUnits.unit(name) {
                    _ = advance()
                    if current == .slash, case .identifier(let secondName)? = peek(1),
                       let u2 = CalcUnits.unit(secondName) {
                        _ = advance() // slash
                        _ = advance() // identifier
                        let dimension = unit.dimension / u2.dimension
                        let factor = unit.factor / u2.factor
                        let symbol = "\(unit.symbol)/\(u2.symbol)"
                        return .quantity(value: value, unit: CalcUnitDef(symbol, dimension, factor))
                    }
                    return .quantity(value: value, unit: unit)
                }
                return .number(value)
            }

            if token == .lparen {
                _ = advance()
                guard let value = parseExpression() else { return nil }
                guard current == .rparen else { return nil }
                _ = advance()
                return value
            }

            if case .identifier(let name) = token {
                // 常量
                if let constant = CalcEngine.constants[name] ?? CalcEngine.constants[name.lowercased()] {
                    _ = advance()
                    if case .identifier(let unitName) = current,
                       let unit = CalcUnits.unit(unitName) {
                        _ = advance()
                        return .quantity(value: constant, unit: unit)
                    }
                    return .number(constant)
                }
                // 函数
                if let function = CalcEngine.functions[name.lowercased()] {
                    _ = advance()
                    var args: [Double] = []
                    if current == .lparen {
                        _ = advance()
                        if current == .rparen { return nil } // f() 空参无意义
                        while true {
                            guard let argValue = parseExpression() else { return nil }
                            guard let scalar = scalarize(argValue) else { return nil }
                            args.append(scalar)
                            if current == .comma { _ = advance(); continue }
                            break
                        }
                        guard current == .rparen else { return nil }
                        _ = advance()
                    } else {
                        // 无括号单参：sqrt 16
                        guard let argValue = parseFactor().map(\.value) else { return nil }
                        guard let scalar = scalarize(argValue) else { return nil }
                        args.append(scalar)
                    }
                    guard let result = function(args) else { return nil }
                    return .number(result)
                }
                // 裸单位（"m to ft" 即 1 m）
                if let unit = CalcUnits.unit(name) {
                    _ = advance()
                    return .quantity(value: 1, unit: unit)
                }
                return nil
            }

            return nil
        }

        /// 函数实参降为标量：角度量纲换算为弧度，其余量纲报错。
        private func scalarize(_ value: CalcValue) -> Double? {
            switch value {
            case .number(let v): return v
            case .quantity(let v, let unit):
                guard unit.dimension == CalcDimension.angle, unit.offset == 0 else { return nil }
                let rad = CalcUnits.table["rad"]!
                return rad.fromBase(unit.toBase(v))
            }
        }
    }

    // MARK: 运算辅助

    /// 数值缩放（百分比语境）：纯数或量都按原单位缩放。
    private static func scale(_ value: CalcValue, by factor: Double) -> CalcValue? {
        switch value {
        case .number(let v): return .number(v * factor)
        case .quantity(let v, let unit): return .quantity(value: v * factor, unit: unit)
        }
    }

    private static func applyMultiplicative(_ left: CalcValue, _ right: CalcValue, divide: Bool) -> CalcValue? {
        let leftBase: Double
        let rightBase: Double
        switch left {
        case .number(let v): leftBase = v
        case .quantity(let v, let unit): leftBase = unit.toBase(v)
        }
        switch right {
        case .number(let v): rightBase = v
        case .quantity(let v, let unit): rightBase = unit.toBase(v)
        }

        let dimension = divide ? left.dimension / right.dimension : left.dimension * right.dimension
        let baseValue = divide ? leftBase / rightBase : leftBase * rightBase
        guard baseValue.isFinite else { return nil }

        if dimension.isDimensionless { return .number(baseValue) }
        let unit = CalcUnits.displayUnit(for: dimension, baseValue: baseValue)
        return .quantity(value: unit.fromBase(baseValue), unit: unit)
    }

    private static func applyPower(_ base: CalcValue, _ exponent: CalcValue) -> CalcValue? {
        switch (base, exponent) {
        case let (.number(b), .number(e)):
            let result = Foundation.pow(b, e)
            return result.isFinite ? .number(result) : nil
        case let (.quantity(v, unit), .number(e)):
            // 量纲幂：仅整指数、无偏移单位（温度等带 offset 的拒绝）
            guard unit.offset == 0, e == e.rounded(), abs(e) <= 6 else { return nil }
            let power = Int(e)
            var newExponents = unit.dimension.exponents
            for (key, value) in newExponents { newExponents[key] = value * power }
            let dimension = CalcDimension(exponents: newExponents)
            let baseValue = Foundation.pow(unit.factor * v, e)
            guard baseValue.isFinite else { return nil }
            if dimension.isDimensionless { return .number(baseValue) }
            let displayUnit = CalcUnits.displayUnit(for: dimension, baseValue: baseValue)
            return .quantity(value: displayUnit.fromBase(baseValue), unit: displayUnit)
        default:
            return nil
        }
    }

    // MARK: 输出

    private static func makeResult(_ value: CalcValue, target: ConversionTarget?) -> CalcResult? {
        if let target {
            switch target {
            case .radix(let radix):
                guard let scalar = value.scalar,
                      scalar == scalar.rounded(), abs(scalar) < 1e15 else { return nil }
                let intValue = Int64(scalar)
                let prefix = radix == 16 ? "0x" : radix == 2 ? "0b" : radix == 8 ? "0o" : ""
                let magnitude = String(radix == 10 ? abs(Int64(scalar)) : abs(intValue), radix: radix)
                let text = (intValue < 0 ? "-" : "") + prefix + magnitude
                return CalcResult(output: .text(text), display: "= \(text)", copyText: text)
            case .unit(let targetUnit):
                guard case .quantity(let v, let unit) = value,
                      unit.dimension == targetUnit.dimension else { return nil }
                let converted = targetUnit.fromBase(unit.toBase(v))
                guard converted.isFinite,
                      let formatted = CalcFormatter.display(converted),
                      let copy = CalcFormatter.copyText(converted) else { return nil }
                return CalcResult(
                    output: .quantity(value: converted, unit: targetUnit.symbol),
                    display: "= \(formatted) \(targetUnit.symbol)",
                    copyText: copy
                )
            }
        }

        switch value {
        case .number(let v):
            guard v.isFinite, let formatted = CalcFormatter.display(v),
                  let copy = CalcFormatter.copyText(v) else { return nil }
            return CalcResult(output: .number(v), display: "= \(formatted)", copyText: copy)
        case .quantity(let v, let unit):
            guard v.isFinite, let formatted = CalcFormatter.display(v),
                  let copy = CalcFormatter.copyText(v) else { return nil }
            return CalcResult(
                output: .quantity(value: v, unit: unit.symbol),
                display: "= \(formatted) \(unit.symbol)",
                copyText: copy
            )
        }
    }
}

extension CalcValue {
    /// 百分比语境需要右侧是纯数。
    public func numberValueForPercent() -> Double? {
        if case .number(let v) = self { return v }
        return nil
    }
}

// MARK: - 格式化

/// 数值展示：≤10 位有效数字，去尾零；千位分隔；极端量级用科学计数。
public enum CalcFormatter {
    /// 卡片展示精度：6 位有效数字；复制精度：12 位。
    public static let displayDigits = 6
    public static let copyDigits = 12

    public static func display(_ value: Double) -> String? {
        display(value, significantDigits: displayDigits)
    }

    public static func copyText(_ value: Double) -> String? {
        display(value, significantDigits: copyDigits)
    }

    public static func display(_ value: Double, significantDigits: Int) -> String? {
        guard value.isFinite else { return nil }
        if value == 0 { return "0" }

        let magnitude = abs(value)
        // 常规量级：按请求的有效位数；大数放宽到 12 位避免误入科学计数
        let digits = magnitude >= 1e6 ? max(significantDigits, 12) : significantDigits
        let format = "%." + String(digits) + "g"
        var text = String(format: format, value)
        if text.contains("e") || text.contains("E") {
            text = text.replacingOccurrences(of: "e+", with: "e")
            return text
        }

        var parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            .map(String.init)
        let negative = parts[0].hasPrefix("-")
        if negative { parts[0].removeFirst() }
        parts[0] = groupDigits(parts[0])
        let joined = parts.joined(separator: ".")
        return negative ? "-" + joined : joined
    }

    private static func groupDigits(_ digits: String) -> String {
        guard digits.count > 3 else { return digits }
        var result = ""
        let characters = Array(digits)
        for (index, character) in characters.enumerated() {
            if index > 0 && (characters.count - index) % 3 == 0 { result += "," }
            result.append(character)
        }
        return result
    }
}

/// 命名冲突：Swift 的 sqrt(Float) 重载会让闭包类型推断跑偏，显式走 Double 版本。
private func __sqrt(_ v: Double) -> Double { Foundation.sqrt(v) }
