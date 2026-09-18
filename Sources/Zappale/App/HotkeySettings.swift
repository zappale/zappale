import AppKit
import Carbon.HIToolbox
import SwiftUI
import ZappaleCore

// MARK: - 热键录制器

/// 点击进入录制态，按键捕获组合；Esc 取消；至少一个功能修饰键才有效。
struct HotkeyRecorder: View {
    let spec: HotkeySpec?
    var allowClear: Bool = true
    var onChange: (HotkeySpec?) -> Void

    @State private var recording = false
    @State private var liveDisplay: String?
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                recording ? stopRecording() : startRecording()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: recording ? "keyboard" : (spec == nil ? "plus.circle" : "record.circle"))
                        .font(.system(size: 11))
                    Text(displayText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(recording ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            recording ? Color.accentColor : Color(nsColor: .separatorColor),
                            lineWidth: recording ? 1 : 0.5
                        )
                )
            }
            .buttonStyle(.plain)

            if allowClear, spec != nil, !recording {
                Button {
                    onChange(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(L10n.t("清除热键", "Clear hotkey"))
            }
        }
        .onDisappear { stopRecording() }
    }

    private var displayText: String {
        if recording { return liveDisplay ?? "请按下组合键…" }
        return spec?.display ?? "未设置"
    }

    private func startRecording() {
        recording = true
        liveDisplay = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        recording = false
        liveDisplay = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard recording else { return event }

        if event.type == .flagsChanged {
            // 实时预览修饰键状态
            let carbon = HotkeySpec.carbonModifiers(from: event.modifierFlags)
            if carbon != 0 {
                liveDisplay = modifiersOnlyDisplay(carbon)
            }
            return nil
        }

        // keyDown
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return nil
        }
        if event.keyCode == UInt16(kVK_Tab) {
            return nil // 录制态忽略 Tab，防焦点漂移
        }

        let carbon = HotkeySpec.carbonModifiers(from: event.modifierFlags)
        guard carbon != 0 else {
            NSSound.beep()
            liveDisplay = "需要至少一个修饰键（⌘⌥⌃⇧）"
            return nil
        }

        let spec = HotkeySpec(keyCode: UInt32(event.keyCode), carbonModifiers: carbon)
        stopRecording()
        onChange(spec)
        return nil
    }

    private func modifiersOnlyDisplay(_ carbon: UInt32) -> String {
        var text = ""
        if carbon & UInt32(controlKey) != 0 { text += "⌃" }
        if carbon & UInt32(optionKey) != 0 { text += "⌥" }
        if carbon & UInt32(shiftKey) != 0 { text += "⇧" }
        if carbon & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + "…"
    }
}

// MARK: - 快捷键设置页

struct ShortcutsSettingsPane: View {
    let core: AppCore
    @ObservedObject private var settings: AppSettings
    @State private var conflictMessage: String?
    @State private var newAppPath: String?

    init(core: AppCore) {
        self.core = core
        self.settings = core.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: L10n.t("快捷键", "Shortcuts"))
            SettingsGroup(title: L10n.t("命令面板", "Palette")) {
                SettingsRow(title: L10n.t("呼出方式", "Summon with"), subtitle: L10n.t("全局生效，任意应用内可呼出", "Global, works in any app")) {
                    Picker("", selection: $settings.paletteSummonMode) {
                        ForEach(PaletteSummonMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.radioGroup)
                }
                Divider().padding(.horizontal, 8)
                if settings.paletteSummonMode == .hotkey {
                    SettingsRow(title: L10n.t("组合键", "Hotkey"), subtitle: L10n.t("当前", "Current") + "：\(settings.paletteHotkey.display)") {
                        HotkeyRecorder(spec: settings.paletteHotkey, allowClear: false) { spec in
                            guard let spec else { return }
                            apply(spec, excluding: "palette") {
                                settings.paletteHotkey = spec
                            }
                        }
                    }
                } else {
                    SettingsRow(
                        title: L10n.t("双击 ⌘ Command ×2", "Double-tap ⌘"),
                        subtitle: DoubleTapMonitor.isAvailable
                            ? L10n.t("已启用——在任意应用中快速双击 Command 键", "Active — double-tap ⌘ anywhere")
                            : L10n.t("需要辅助功能权限；未授权时不可用", "Needs Accessibility permission")
                    ) {
                        if DoubleTapMonitor.isAvailable {
                            Label(L10n.t("已就绪", "Ready"), systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 12))
                        } else {
                            Button(L10n.t("去授权", "Grant…")) { Paster.openAccessibilitySettings() }
                        }
                    }
                }
            }
            SettingsGroup(title: L10n.t("剪贴板", "Clipboard")) {
                SettingsRow(title: L10n.t("打开剪贴板历史", "Clipboard History"), subtitle: L10n.t("默认 ⌘⇧V（⇧⌘V）；会全局接管该组合键", "Default ⌘⇧V; takes over this combo globally")) {
                    HotkeyRecorder(spec: settings.clipboardHotkey) { spec in
                        guard let spec else {
                            settings.clipboardHotkey = nil
                            conflictMessage = nil
                            return
                        }
                        apply(spec, excluding: "clipboard") {
                            settings.clipboardHotkey = spec
                        }
                    }
                }
            }
            SettingsGroup(title: L10n.t("应用热键", "App Hotkeys")) {
                SettingsRow(title: L10n.t("按热键切换应用", "Toggle App"), subtitle: L10n.t("前台隐藏 · 后台激活 · 未运行启动", "Hide if front, activate if not, launch if closed")) {
                    EmptyView()
                }
                Divider().padding(.horizontal, 8)
                ForEach(sortedAppBindings, id: \.0) { path, spec in
                    appRow(path: path, spec: spec)
                    if path != sortedAppBindings.last?.0 {
                        Divider().padding(.horizontal, 8)
                    }
                }
                Divider().padding(.horizontal, 8)
                addRow
            }
            if let conflictMessage {
                Label(conflictMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
            ForEach(core.hotkeyFailures, id: \.self) { failure in
                Label(failure, systemImage: "xmark.octagon.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 4)
            }
        }
        .padding(.top, 16)
    }

    private var sortedAppBindings: [(String, HotkeySpec)] {
        settings.perAppHotkeys.entries.sorted { $0.key < $1.key }
    }

    private func appRow(path: String, spec: HotkeySpec) -> some View {
        SettingsRow(title: (path as NSString).lastPathComponent, subtitle: path) {
            HotkeyRecorder(spec: spec) { newSpec in
                guard let newSpec else {
                    settings.perAppHotkeys.entries[path] = nil
                    return
                }
                apply(newSpec, excluding: "perApp") {
                    settings.perAppHotkeys.entries[path] = newSpec
                }
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: 10) {
            Picker("应用", selection: $newAppPath) {
                Text(L10n.t("选择应用…", "Pick an app…")).tag(String?.none)
                ForEach(core.launcher.entries.sorted { $0.name < $1.name }) { app in
                    Text(app.name).tag(String?.some(app.path))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 240)

            if newAppPath != nil, let path = newAppPath {
                HotkeyRecorder(spec: settings.perAppHotkeys.entries[path]) { spec in
                    guard let spec else { return }
                    apply(spec, excluding: "perApp") {
                        settings.perAppHotkeys.entries[path] = spec
                        self.newAppPath = nil
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func apply(_ spec: HotkeySpec, excluding id: String, _ save: @escaping () -> Void) {
        if let conflict = settings.hotkeyConflict(spec, excluding: id) {
            conflictMessage = "「\(spec.display)」\(conflict)"
        } else {
            conflictMessage = nil
            save()
        }
    }
}
