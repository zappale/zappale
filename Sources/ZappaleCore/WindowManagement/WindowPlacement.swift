import CoreGraphics
import Foundation

/// 窗口布局动作（Rectangle 式子集）。
public enum WindowAction: String, CaseIterable, Hashable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftTwoThirds, rightTwoThirds
    case center, maximize, almostMaximize, restore
    case nextDisplay, prevDisplay

    public var spec: (zh: String, en: String, symbol: String) {
        switch self {
        case .leftHalf: return ("左半屏", "Left Half", "rectangle.lefthalf.inset.filled")
        case .rightHalf: return ("右半屏", "Right Half", "rectangle.righthalf.inset.filled")
        case .topHalf: return ("上半屏", "Top Half", "rectangle.tophalf.inset.filled")
        case .bottomHalf: return ("下半屏", "Bottom Half", "rectangle.bottomhalf.inset.filled")
        case .topLeft: return ("左上四分之一", "Top Left", "rectangle.topleft.inset.filled")
        case .topRight: return ("右上四分之一", "Top Right", "rectangle.topright.inset.filled")
        case .bottomLeft: return ("左下四分之一", "Bottom Left", "rectangle.bottomleft.inset.filled")
        case .bottomRight: return ("右下四分之一", "Bottom Right", "rectangle.bottomright.inset.filled")
        case .leftTwoThirds: return ("左侧三分之二", "Left Two Thirds", "rectangle.lefttwothirdsinset.filled")
        case .rightTwoThirds: return ("右侧三分之二", "Right Two Thirds", "rectangle.righttwothirdsinset.filled")
        case .center: return ("居中", "Center", "rectangle.center.inset.filled")
        case .maximize: return ("最大化", "Maximize", "rectangle.inset.filled")
        case .almostMaximize: return ("留边最大化", "Almost Maximize", "rectangle.dashed")
        case .restore: return ("还原", "Restore", "arrow.uturn.backward")
        case .nextDisplay: return ("移到下一个显示器", "Next Display", "display.arrow.right.to.line")
        case .prevDisplay: return ("移到上一个显示器", "Previous Display", "display.arrow.left.to.line")
        }
    }
}

/// 窗口布局几何引擎。纯函数：屏幕可见区域、窗口当前 frame、显示器列表全注入。
/// 坐标系：AppKit 全局坐标（原点在主屏左下）——AX 翻转在服务层完成。
public enum WindowPlacement {
    /// 留边最大化的边距。
    public static let almostMaximizeGap: CGFloat = 12

    /// 计算目标 frame。返回 nil = 动作不适用（如单屏时的跨屏、无原 frame 的还原）。
    public static func target(
        action: WindowAction,
        window: CGRect,
        screen: CGRect,
        screens: [CGRect],
        screenIndex: Int
    ) -> CGRect? {
        // 相邻屏（按 x 排序）
        let ordered = screens.sorted { $0.minX < $1.minX }
        switch action {
        case .leftHalf:
            return CGRect(x: screen.minX, y: screen.minY, width: screen.width / 2, height: screen.height)
        case .rightHalf:
            return CGRect(x: screen.midX, y: screen.minY, width: screen.width / 2, height: screen.height)
        case .topHalf:
            return CGRect(x: screen.minX, y: screen.midY, width: screen.width, height: screen.height / 2)
        case .bottomHalf:
            return CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: screen.height / 2)
        case .topLeft:
            return CGRect(x: screen.minX, y: screen.midY, width: screen.width / 2, height: screen.height / 2)
        case .topRight:
            return CGRect(x: screen.midX, y: screen.midY, width: screen.width / 2, height: screen.height / 2)
        case .bottomLeft:
            return CGRect(x: screen.minX, y: screen.minY, width: screen.width / 2, height: screen.height / 2)
        case .bottomRight:
            return CGRect(x: screen.midX, y: screen.minY, width: screen.width / 2, height: screen.height / 2)
        case .leftTwoThirds:
            return CGRect(x: screen.minX, y: screen.minY, width: screen.width * 2 / 3, height: screen.height)
        case .rightTwoThirds:
            let width = screen.width * 2 / 3
            return CGRect(x: screen.maxX - width, y: screen.minY, width: width, height: screen.height)
        case .center:
            guard window.width > 0, window.height > 0 else { return nil }
            return CGRect(
                x: screen.midX - window.width / 2,
                y: screen.midY - window.height / 2,
                width: window.width,
                height: window.height
            )
        case .maximize:
            return screen
        case .almostMaximize:
            let gap = almostMaximizeGap
            return screen.insetBy(dx: gap, dy: gap)
        case .restore:
            return nil // 还原由服务层记住上一位置
        case .nextDisplay, .prevDisplay:
            guard screens.count > 1,
                  let currentIndex = ordered.firstIndex(of: screens[screenIndex])
                  ?? ordered.firstIndex(where: { $0 == screen }) else { return nil }
            let delta = action == .nextDisplay ? 1 : -1
            let targetIndex = (currentIndex + delta + ordered.count) % ordered.count
            let targetScreen = ordered[targetIndex]
            // 保持窗口相对尺寸，位置平移到目标屏左上角附近（按比例映射）
            let widthRatio = screen.width > 0 ? min(window.width / screen.width, 1) : 1
            let heightRatio = screen.height > 0 ? min(window.height / screen.height, 1) : 1
            let targetWidth = targetScreen.width * widthRatio
            let targetHeight = targetScreen.height * heightRatio
            return CGRect(
                x: targetScreen.minX + (targetScreen.width - targetWidth) / 2,
                y: targetScreen.midY - targetHeight / 2,
                width: targetWidth,
                height: targetHeight
            )
        }
    }
}
