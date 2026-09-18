import AppKit
import ApplicationServices
import Foundation
import ZappaleCore

/// 粘贴回注：把历史条目写回粘贴板并向前一个应用发送 ⌘V。
/// 需要辅助功能（Accessibility）权限；未授权时降级为"仅复制"并提示。
@MainActor
enum Paster {

    enum Result: Equatable {
        case pasted
        case copiedOnly
        case failed(String)
    }

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 辅助功能授权页（系统设置 → 隐私与安全性 → 辅助功能）。
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 执行粘贴。调用时机：面板即将收起之后。
    ///
    /// - Parameters:
    ///   - item: 要粘贴的历史条目
    ///   - manager: 粘贴板写入器（打内部标记，避免自捕获）
    ///   - previousApp: 呼出面板时记录的前台应用
    static func paste(_ item: ClipboardItem, manager: ClipboardManager,
                      previousApp: NSRunningApplication?) async -> Result {
        switch item.kind {
        case .text:
            manager.writeToSystemPasteboard(text: item.text)
        case .image:
            guard let imagePath = item.imagePath else { return .failed("图片文件缺失") }
            manager.writeToSystemPasteboard(imagePath: imagePath)
        case .file:
            manager.writeToSystemPasteboard(filePaths: item.filePaths ?? [item.text])
        }

        guard isTrusted else { return .copiedOnly }

        // 重新激活目标应用，等待它就绪再发送 ⌘V
        if let previousApp {
            _ = previousApp.activate()
            try? await Task.sleep(nanoseconds: 120_000_000)
        }

        postCommandV()
        return .pasted
    }

    /// 通过 CGEvent 合成 ⌘C（快捷动作取选中文字用）。要求辅助功能授权。
    static func postCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(8), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(8), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    /// 合成 ⌘V 贴回（快捷动作用）。
    static func pasteDirectly() {
        postCommandV()
    }

    /// 通过 CGEvent 合成 ⌘V。要求辅助功能授权。
    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(9), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(9), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
