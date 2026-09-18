import AppKit
import ZappaleCore

// zappale 入口：手动 App 生命周期，菜单栏常驻，无 Dock 图标。
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let core = AppCore.shared
    app.delegate = core
    app.setActivationPolicy(.accessory)
    app.run()
}
