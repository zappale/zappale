import Foundation

// MARK: - 纯检测器

/// 双击修饰键检测状态机（对齐 tinycast DoubleTap 行为）：
/// 按下 → 抬起 → 再按下，两次间隔 ≤ 阈值，且期间不按任何其他修饰键。
/// 纯函数式：时间戳由外部注入，直接单测。
public struct DoubleTapDetector {
    /// 双击窗口（秒）。
    public static let threshold: TimeInterval = 0.4

    private enum State {
        case idle
        case firstDown(at: TimeInterval)
        case firstUp(at: TimeInterval)
    }

    private var state: State = .idle

    public init() {}

    public mutating func reset() {
        state = .idle
    }

    /// 喂入一次修饰键状态变化。
    /// - Parameters:
    ///   - isTargetDown: 目标键（⌘）当前是否按下
    ///   - hasOtherModifiers: 是否同时按住其他功能修饰键（⇧⌥⌃）
    /// - Returns: 是否命中双击
    public mutating func feed(isTargetDown: Bool, hasOtherModifiers: Bool, at time: TimeInterval) -> Bool {
        if hasOtherModifiers {
            state = .idle
            return false
        }

        switch state {
        case .idle:
            if isTargetDown { state = .firstDown(at: time) }
        case .firstDown:
            if !isTargetDown { state = .firstUp(at: time) }
        case .firstUp(let upTime):
            if isTargetDown {
                if time - upTime <= Self.threshold {
                    state = .idle
                    return true // 命中双击
                }
                state = .firstDown(at: time) // 超时：这次按下算新一轮
            }
        }
        return false
    }
}
