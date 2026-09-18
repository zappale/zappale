import AppKit
import SwiftUI
import ZappaleCore

/// 无边框悬浮面板。canBecomeKey 是 borderless panel 的关键覆写，
/// 否则搜索框永远拿不到键盘。
final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// 面板窗口的唯一权威：定位、显隐、会话边界都由它决定。
/// 同时记录"呼出时的前台应用"，作为粘贴回注的目标。
@MainActor
final class PaletteWindowController {
    private let panel: PalettePanel
    let state: PaletteState

    /// 呼出面板时的前台应用：粘贴动作的目标。
    private(set) var previousApp: NSRunningApplication?

    private let core: AppCore

    init(core: AppCore) {
        self.core = core
        let state = PaletteState(core: core)
        self.state = state

        panel = PalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: PaletteMetrics.width, height: PaletteMetrics.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        panel.worksWhenModal = true

        let root = PaletteView(state: state)
        let hostingView = NSHostingView(rootView: root)
        // 关键不变量（对齐 tinycast）：SwiftUI 不得驱动面板尺寸，
        // 否则内容变化（如长副标题换行）会把窗口顶来顶去。
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        state.onShouldHide = { [weak self] in self?.hide() }
        state.onPasteRequested = { [weak self] item in
            self?.hideAndPaste(item)
        }
        state.onQuickAction = { [weak self] prompt, core in
            self?.hideAndRunQuickAction(prompt: prompt, core: core)
        }

        // 失焦即收起：启动器的心智模型是"呼出—完成—消失"。
        // 右键菜单跟踪开始的瞬间面板会短暂 resign key——直接收起会把
        // 刚打开的菜单一起关掉。防抖 150ms 后复检：仍是面板失焦才真正隐藏。
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard let self, self.panel.isVisible, !self.panel.isKeyWindow else { return }
                self.hide()
            }
        }
    }

    var isVisible: Bool { panel.isVisible }

    // MARK: - 显隐

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show(mode: PaletteMode = .apps) {
        previousApp = NSWorkspace.shared.frontmostApplication
        position()
        state.beginSession(mode: mode)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // 快速淡入（Sequoia 面板质感）
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    /// 菜单栏入口：直接打开剪贴板屏。
    func showClipboard() {
        show(mode: .clipboard)
    }

    func hide() {
        guard panel.isVisible else { return }
        // 快速淡出后收起；面板不可见时 orderOut 幂等
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            context.completionHandler = { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if !self.panel.isKeyWindow {
                        self.panel.orderOut(nil)
                        self.panel.alphaValue = 1
                    } else {
                        // 复检时面板又拿到焦点（如菜单选择触发了动作）——不关
                        self.panel.alphaValue = 1
                    }
                }
            }
            panel.animator().alphaValue = 0
        })
    }

    /// 隐藏面板后执行粘贴回注：面板先收起，目标应用回到前台，
    /// 再写粘贴板并发送 ⌘V。
    func hideAndPaste(_ item: ClipboardItem) {
        let target = previousApp
        hide()
        Task { [weak self] in
            guard let self else { return }
            let result = await Paster.paste(item, manager: self.core.clipboard, previousApp: target)
            switch result {
            case .pasted:
                break
            case .copiedOnly:
                self.show(mode: .clipboard)
                self.state.showNotice("已复制；开启辅助功能权限后可自动粘贴")
            case .failed(let message):
                self.show(mode: .clipboard)
                self.state.showNotice(message)
            }
        }
    }

    /// AI 快捷动作闭环：收起面板 → ⌘C 取选中 → AI → 结果贴回原位。
    func hideAndRunQuickAction(prompt: String, core: AppCore) {
        let target = previousApp
        hide()
        Task { [weak self] in
            // 1) 复制选中文字
            Paster.postCommandC()
            try? await Task.sleep(nanoseconds: 300_000_000)
            let selection = core.clipboard.currentText?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !selection.isEmpty else {
                self?.show(mode: .apps)
                self?.state.showNotice(L10n.t("没有检测到选中文字", "No selection detected"))
                return
            }

            // 2) AI 处理
            guard let key = core.keychain.get(account: core.keychainAccount), !key.isEmpty,
                  let endpoint = core.settings.endpointURL else {
                self?.show(mode: .apps)
                self?.state.showNotice(L10n.t("请先在设置中保存 API Key", "Save your API key first"))
                return
            }
            let connection = AIConnection(
                provider: core.settings.provider,
                endpoint: endpoint,
                model: core.settings.model
            )
            let client = AIClient(connection: connection, apiKey: key)
            let messages = [AIChatMessage(role: "user", content: prompt + selection)]
            final class Collector {
                var text = ""
                var failure: String?
            }
            let collector = Collector()
            await client.streamChat(messages: messages) { event in
                switch event {
                case .delta(let delta): collector.text += delta
                case .done: break
                case .failed(let message): collector.failure = message
                }
            }
            let answer = collector.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let failure = collector.failure, answer.isEmpty {
                self?.show(mode: .apps)
                self?.state.showNotice(L10n.t("AI 请求失败：", "AI failed: ") + failure)
                return
            }
            guard !answer.isEmpty else { return }

            // 3) 写回并贴回原位
            core.clipboard.writeToSystemPasteboard(text: answer)
            if let target {
                _ = target.activate()
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            Paster.pasteDirectly()
            self?.state.showNotice(L10n.t("已完成", "Done"))
        }
    }

    /// 定位在鼠标所在屏幕水平居中、垂直偏上。
    private func position() {
        let screens = NSScreen.screens
        let screen = screens.first { screen in
            let mouse = NSEvent.mouseLocation
            return NSMouseInRect(mouse, screen.frame, false)
        } ?? NSScreen.main

        guard let screen else { return }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        var origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2 + visible.height * 0.12
        )
        // 钳制：小屏/分屏下保证面板完整可见
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        panel.setFrameOrigin(origin)
    }
}
