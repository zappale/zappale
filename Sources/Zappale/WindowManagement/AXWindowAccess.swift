import AppKit
import ApplicationServices
import Foundation
import ZappaleCore

/// AX 窗口操作：枚举前台应用的标准窗口、读写 frame。
/// 坐标翻转集中在这里：AppKit（原点主屏左下）↔ AX（原点主屏左上）。
@MainActor
enum AXWindowAccess {

    static var isTrusted: Bool { AXIsProcessTrusted() }

    // MARK: - 前台窗口

    /// 取前台应用第一个标准窗口及其 frame（AppKit 坐标）。nil = 无窗口/无权限。
    static func frontmostStandardWindow() -> (element: AXUIElement, frame: CGRect)? {
        guard isTrusted else { return nil }
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else { return nil }

        for window in windows {
            var subroleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleValue) == .success,
                  let subrole = subroleValue as? String,
                  subrole == kAXStandardWindowSubrole as String else { continue }
            var roleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleValue) == .success,
               let role = roleValue as? String,
               role != kAXWindowRole as String {
                continue
            }
            if let frame = frame(of: window) {
                return (window, frame)
            }
        }
        return nil
    }

    /// 读窗口 frame（AppKit 坐标）。
    static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              let positionAX = positionValue else { return nil }
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let sizeAX = sizeValue else { return nil }

        var point = CGPoint.zero
        guard AXValueGetValue(positionAX as! AXValue, .cgPoint, &point) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(sizeAX as! AXValue, .cgSize, &size) else { return nil }

        let flipped = flipToAppKit(CGRect(origin: point, size: size))
        return CGRect(origin: flipped.origin, size: size)
    }

    /// 设置窗口 frame（AppKit 坐标输入，内部翻转）。
    @discardableResult
    static func setFrame(_ rect: CGRect, of window: AXUIElement) -> Bool {
        let flipped = flipToAX(rect)
        var point = flipped.origin
        var size = rect.size
        guard let positionValue = AXValueCreate(.cgPoint, &point),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return false }
        let positionOK = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue) == .success
        let sizeOK = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue) == .success
        return positionOK || sizeOK
    }

    // MARK: - 坐标翻转

    /// 主屏顶边的 y（AppKit 坐标）。
    private static var primaryTopY: CGFloat {
        guard let primary = NSScreen.screens.first else { return 0 }
        return primary.frame.maxY
    }

    private static func flipToAX(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryTopY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private static func flipToAppKit(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryTopY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    // MARK: - 动作执行

    enum ApplyResult: Equatable {
        case applied
        case noWindow
        case notTrusted
        case failed
    }

    /// 对前台标准窗口应用布局动作。restore 需要 lastFrames 记忆（本类内维护）。
    private static var lastFrames: [pid_t: CGRect] = [:]

    static func apply(_ action: WindowAction) -> ApplyResult {
        guard isTrusted else { return .notTrusted }
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return .noWindow }
        guard let (window, frame) = frontmostStandardWindow() else { return .noWindow }

        // 当前所在屏
        let screens = NSScreen.screens.map(\.frame)
        guard !screens.isEmpty else { return .failed }
        let visibleScreens = NSScreen.screens.map(\.visibleFrame)
        var screenIndex = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, screenFrame) in screens.enumerated() {
            let centerDistance = abs(frame.midX - screenFrame.midX)
            if centerDistance < bestDistance {
                bestDistance = centerDistance
                screenIndex = index
            }
        }

        if action == .restore {
            guard let previous = lastFrames[frontApp.processIdentifier] else { return .noWindow }
            guard setFrame(previous, of: window) else { return .failed }
            return .applied
        }

        guard let target = WindowPlacement.target(
            action: action,
            window: frame,
            screen: visibleScreens[screenIndex],
            screens: visibleScreens,
            screenIndex: screenIndex
        ) else { return .noWindow }

        // 记忆当前位置供还原（最大化/半屏类动作前记录）
        lastFrames[frontApp.processIdentifier] = frame
        guard setFrame(target, of: window) else { return .failed }
        return .applied
    }
}
