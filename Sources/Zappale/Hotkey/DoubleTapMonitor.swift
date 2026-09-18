import ApplicationServices
import Foundation
import ZappaleCore

// MARK: - 监听服务

/// 双击 ⌘ 呼出面板的监听器：listen-only CGEventTap 观察 flagsChanged。
/// 需要辅助功能权限；未授权时 start() 返回 false，由设置页引导。
final class DoubleTapMonitor {
    var onTrigger: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var detector = DoubleTapDetector()

    var isRunning: Bool { tap != nil }

    static var isAvailable: Bool {
        AXIsProcessTrusted()
    }

    /// 启动监听。返回 false = 无辅助功能权限或创建失败。
    @discardableResult
    func start() -> Bool {
        guard Self.isAvailable else { return false }
        guard tap == nil else { return true }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, _, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<DoubleTapMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            monitor.handle(event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: callback, userInfo: pointer
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
        }
        tap = nil
        runLoopSource = nil
        detector.reset()
    }

    private func handle(_ event: CGEvent) {
        let flags = event.flags
        let commandDown = flags.contains(.maskCommand)
        let others = !flags.intersection([.maskShift, .maskAlternate, .maskControl]).isEmpty
        let seconds = Double(event.timestamp) / 1_000_000_000

        if detector.feed(isTargetDown: commandDown, hasOtherModifiers: others, at: seconds) {
            DispatchQueue.main.async { [weak self] in
                self?.onTrigger?()
            }
        }
    }
}
