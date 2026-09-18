import AppKit
import SwiftUI
import ZappaleCore

// MARK: - 根视图

/// 命令面板。Sequoia 设计语言：材质模糊 + 大圆角 + 发丝描边 +
/// 分区标题 + 键帽提示 + 滚动边缘渐隐。
struct PaletteView: View {
    @Bindable var state: PaletteState
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let _ = state.languageVersion // 语言切换时强制重渲染
        VStack(spacing: 0) {
            searchHeader
            divider
            content
            footer
        }
        .frame(width: PaletteMetrics.width, height: PaletteMetrics.height)
        .background(PaletteBackground(reducedEffects: state.core?.settings.reducedVisualEffects == true))
        .clipShape(RoundedRectangle(cornerRadius: PaletteMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PaletteMetrics.cornerRadius, style: .continuous)
                .strokeBorder(PaletteMetrics.hairline, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.30), radius: 24, y: 8)
        .onAppear { fieldFocused = true }
        .onChange(of: state.focusToken, initial: true) { _, _ in fieldFocused = true }
        .onExitCommand { state.escape() }
        .onMoveCommand { direction in
            switch direction {
            case .up:
                state.moveSelection(state.mode == .emoji ? -EmojiScreenView.columns : -1)
            case .down:
                state.moveSelection(state.mode == .emoji ? EmojiScreenView.columns : 1)
            default:
                break
            }
        }
    }

    // MARK: 搜索头部

    private var searchHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 18)

            TextField(placeholder, text: $state.query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .medium))
                .focused($fieldFocused)
                .modifier(PaletteKeyHandling(state: state))
                .onChange(of: state.query) { _, _ in state.queryChanged() }

            if state.mode == .chat {
                chatModeBar
            } else {
                modeSwitcher
                    .padding(.trailing, 14)
            }
        }
        .padding(.vertical, 14)
    }

    /// 对话屏头部：附件缩略图 + 对话/生图切换。
    private var chatModeBar: some View {
        HStack(spacing: 8) {
            if let attachment = state.chatAttachment {
                HStack(spacing: 6) {
                    if let image = NSImage(data: attachment.data) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 26, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text(attachment.pixelSize)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button {
                        state.removeAttachment()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            Picker("", selection: $state.chatImageMode) {
                Text(L10n.t("对话", "Chat")).tag(false)
                Text(L10n.t("生图", "Image")).tag(true)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 120)
        }
        .padding(.trailing, 14)
    }

    private var placeholder: String {
        state.mode == .chat ? L10n.t("输入消息，↵ 发送…", "Message, ↵ to send…") : state.mode == .apps ? L10n.t("搜索应用、计算、系统动作…", "Search apps, calc, actions…") : (state.mode == .clipboard ? L10n.t("搜索剪贴板历史…", "Search clipboard…") : (state.mode == .files ? L10n.t("搜索文件…", "Search files…") : L10n.t("搜索表情…", "Search emoji…")))
    }

    private var modeSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(PaletteMode.allCases, id: \.rawValue) { mode in
                let available = mode != .clipboard || state.core?.settings.clipboardEnabled == true
                modeChip(title: mode.displayName, active: state.mode == mode, available: available) {
                    if state.mode != mode { state.switchMode(to: mode) }
                }
            }
        }
        .padding(2)
        .background(
            Capsule().fill(Color.primary.opacity(0.06))
        )
        .overlay(
            Capsule().strokeBorder(PaletteMetrics.hairline, lineWidth: 0.5)
        )
    }

    private func modeChip(
        title: String, active: Bool, available: Bool = true, action: @escaping () -> Void
    ) -> some View {
        Text(title)
            .font(.system(size: 12, weight: active ? .semibold : .regular))
            .foregroundStyle(active ? Color.primary : (available ? Color.secondary : Color.secondary.opacity(0.4)))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                if active {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.22))
                        .overlay(
                            Capsule().strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 0.5)
                        )
                }
            }
            .contentShape(Capsule())
            .onTapGesture(perform: action)
            .opacity(available ? 1 : 0.45)
    }

    private var divider: some View {
        Rectangle()
            .fill(PaletteMetrics.hairline)
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }

    // MARK: 结果区

    @ViewBuilder
    private var content: some View {
        if state.mode == .chat {
            ChatTranscriptView(state: state)
        } else if state.mode == .emoji {
            EmojiScreenView(state: state)
        } else if state.rows.isEmpty {
            EmptyPaletteView(mode: state.mode, clipboardEnabled: state.core?.settings.clipboardEnabled == true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(state.sections) { section in
                        sectionRows(section)
                    }
                }
                .padding(.vertical, 6)
            }
            .mask(alignment: .top) {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white, location: 0.012),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .onChange(of: state.selection) { _, _ in
                if let entry = state.selectedEntry {
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(entry.id, anchor: .center)
                    }
                }
            }
        }
    }

    private var clipboardImageProvider: (@MainActor (ClipboardItem) -> NSImage?)? {
        state.mode == .clipboard ? state.imageFor : nil
    }

    @ViewBuilder
    private func sectionRows(_ section: CommandSection) -> some View {
        SectionHeaderView(title: section.title)
        ForEach(Array(section.entries.enumerated()), id: \.element.id) { _, entry in
            ResultRow(
                entry: entry,
                selected: state.rows[safe: state.selection]?.id == entry.id,
                pendingConfirm: state.pendingConfirmID == entry.id,
                imageProvider: clipboardImageProvider
            ) {
                state.setSelection(index(of: entry))
                state.activate(entry)
            }
            .contextMenu { contextMenu(for: entry) }
            .id(entry.id)
        }
    }

    private func index(of entry: CommandEntry) -> Int {
        state.rows.firstIndex(where: { $0.id == entry.id }) ?? 0
    }

    @ViewBuilder
    private func contextMenu(for entry: CommandEntry) -> some View {
        if case .clipboard(let item) = entry.kind {
            Button(item.pinned ? L10n.t("取消固定", "Unpin") : L10n.t("固定到顶部", "Pin to top")) {
                state.clipboardTogglePin(id: item.id)
            }
            Button(L10n.t("删除", "Delete")) {
                state.clipboardDelete(id: item.id)
            }
            Divider()
            Button(L10n.t("复制", "Copy")) {
                state.activate(entry, commandPressed: true)
            }
        }
        if case .app(let path) = entry.kind {
            Button(L10n.t("打开", "Open")) {
                state.activate(entry)
            }
            if state.isAppRunning(path: path) {
                Divider()
                Button("退出 App Quit", role: .destructive) {
                    state.quitApp(path: path)
                }
            }
        }
        if case .file(let fileEntry) = entry.kind {
            Button("打开") {
                state.activate(entry)
            }
            Button(L10n.t("在 Finder 中显示", "Reveal in Finder")) {
                state.activate(entry, commandPressed: true)
            }
            Divider()
            Button(L10n.t("拷贝路径", "Copy path")) {
                state.copyFilePath(fileEntry)
            }
        }
    }

    // MARK: 底部提示

    private var footer: some View {
        HStack(spacing: 14) {
            if let notice = state.notice {
                Label(notice, systemImage: "info.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.15), value: state.notice)
            } else {
                footerHints
            }
            Spacer()
            Text("zappale")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .animation(.easeOut(duration: 0.15), value: state.notice)
    }

    @ViewBuilder
    private var footerHints: some View {
        switch state.mode {
        case .apps:
            KeyCapHint(key: "↑↓", label: L10n.t("选择", "Select"))
            KeyCapHint(key: "↵", label: L10n.t("打开", "Open"))
            KeyCapHint(key: "tab", label: L10n.t("剪贴板", "Clip"))
            KeyCapHint(key: "esc", label: L10n.t("关闭", "Esc"))
        case .clipboard:
            KeyCapHint(key: "↵", label: state.core?.settings.clipboardDefaultAction == .copy ? L10n.t("复制", "Copy") : L10n.t("粘贴", "Paste"))
            KeyCapHint(key: "⌘↵", label: state.core?.settings.clipboardDefaultAction == .copy ? L10n.t("粘贴", "Paste") : L10n.t("复制", "Copy"))
            KeyCapHint(key: "⌘P", label: L10n.t("固定", "Pin"))
            KeyCapHint(key: "⌫", label: L10n.t("删除", "Del"))
            KeyCapHint(key: "tab", label: L10n.t("文件", "Files"))
            KeyCapHint(key: "esc", label: L10n.t("关闭", "Esc"))
        case .files:
            KeyCapHint(key: "↵", label: L10n.t("打开", "Open"))
            KeyCapHint(key: "⌘↵", label: L10n.t("Finder 显示", "Reveal"))
            KeyCapHint(key: "tab", label: L10n.t("表情", "Emoji"))
            KeyCapHint(key: "esc", label: L10n.t("关闭", "Esc"))
        case .emoji:
            KeyCapHint(key: "↵", label: L10n.t("复制", "Copy"))
            KeyCapHint(key: "tab", label: L10n.t("应用", "Apps"))
            KeyCapHint(key: "esc", label: L10n.t("关闭", "Esc"))
        case .chat:
            KeyCapHint(key: "↵", label: state.chatStreaming ? L10n.t("生成中…", "Streaming…") : L10n.t("发送", "Send"))
            if !state.chatImageMode {
                KeyCapHint(key: "⌘V", label: L10n.t("附图", "Image"))
            }
            KeyCapHint(key: "esc", label: L10n.t("返回", "Back"))
            KeyCapHint(key: "tab", label: L10n.t("应用", "Apps"))
        }
    }
}

// MARK: - 键盘处理

/// 面板键盘事件统一入口：回车（含 ⌘↵）、Tab 切屏、⌘1-9 快速激活。
/// 其余按键返回 .ignored 交回文本框。
struct PaletteKeyHandling: ViewModifier {
    let state: PaletteState

    func body(content: Content) -> some View {
        content.onKeyPress { press in
            guard press.phase == .down else { return .ignored }

            if press.key == .return {
                if state.mode == .chat {
                    state.sendChat()
                } else {
                    state.activateSelected(commandPressed: press.modifiers.contains(.command))
                }
                return .handled
            }
            if press.key == .tab {
                state.toggleMode()
                return .handled
            }
            if press.modifiers == .command, let character = press.characters.first,
               ("1"..."9").contains(character) {
                state.quickActivate(character: String(character))
                return .handled
            }
            if press.modifiers == .command, press.characters.first == "p" {
                state.clipboardShortcutPin()
                return .handled
            }
            // chat 模式 ⌘V：粘贴板有图则附加；否则交回默认文本粘贴
            if press.modifiers == .command, press.characters.first == "v", state.mode == .chat {
                if state.attachImageFromPasteboard() {
                    return .handled
                }
                return .ignored
            }
            if state.mode == .emoji, press.key == .leftArrow {
                state.moveSelection(-1)
                return .handled
            }
            if state.mode == .emoji, press.key == .rightArrow {
                state.moveSelection(1)
                return .handled
            }
            // ⌫ 仅在空查询时删除剪贴板条目；正在输入时交回文本框做退格
            if press.key == .delete, state.mode == .clipboard, state.query.isEmpty {
                state.clipboardShortcutDelete()
                return .handled
            }
            // ⌘, 从面板直达设置
            if press.modifiers == .command, press.characters.first == "," {
                state.openSettings()
                return .handled
            }
            return .ignored
        }
    }
}

// MARK: - 尺寸与颜色

enum PaletteMetrics {
    static let width: CGFloat = 740
    static let height: CGFloat = 460
    static let cornerRadius: CGFloat = 16

    static var hairline: Color {
        Color(nsColor: .separatorColor).opacity(0.6)
    }
}

// MARK: - 背景

/// 面板背景三档：macOS 26 增强玻璃（前向 availability 分支）→
/// 标准材质 → 减弱视觉（不透明基础显示）。
struct PaletteBackground: View {
    var reducedEffects: Bool = false

    var body: some View {
        if reducedEffects {
            // 基础显示：不透明底，最低视觉开销
            RoundedRectangle(cornerRadius: PaletteMetrics.cornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        } else if #available(macOS 26.0, *) {
            // macOS 26：升级为系统级玻璃材质（低版本自动落入下一分支）
            GlassBackdrop()
        } else {
            VisualEffectBackdrop()
        }
    }
}

/// 标准材质模糊（Sequoia HUD 风格）。
struct VisualEffectBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = PaletteMetrics.cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// macOS 26 玻璃背景：现阶段用现有 API 表达增强通透感；
/// 26 SDK 可用后在此分支内替换为专属新材质，无需改动调用方。
struct GlassBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = PaletteMetrics.cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - 分区标题

struct SectionHeaderView: View {
    let title: String?

    var body: some View {
        if let title {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 结果行

struct ResultRow: View {
    let entry: CommandEntry
    let selected: Bool
    let pendingConfirm: Bool
    var imageProvider: (@MainActor (ClipboardItem) -> NSImage?)? = nil
    let onActivate: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle = entry.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .onHover { hovered = $0 }
        .padding(.horizontal, 8)
        .id(entry.id)
    }

    @ViewBuilder
    private var icon: some View {
        switch entry.kind {
        case .clipboard(let item) where item.kind == .image:
            if let image = imageProvider?(item) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 34, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(PaletteMetrics.hairline, lineWidth: 0.5)
                    )
            } else {
                symbolIcon("photo")
            }
        case .app(let path):
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 28, height: 28)
        case .file(let entry):
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.path))
                .resizable()
                .frame(width: 28, height: 28)
        case .emoji(let def):
            Text(def.character)
                .font(.system(size: 26))
                .frame(width: 30, height: 30)
        case .note:
            symbolIcon("note.text")
        case .askAI:
            symbolIcon("sparkles")
        case .snippet:
            symbolIcon("text.quote")
        case .customCommand:
            symbolIcon("terminal")
        case .calculator:
            Image(systemName: "equal.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.accentColor)
        case .clipboard:
            symbolIcon(Self.clipboardSymbol(entry))
        case .systemAction, .quicklink, .webSearch, .openURL:
            symbolIcon(Self.symbolName(entry))
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if pendingConfirm {
            Label(L10n.t("再按 ↵ 确认", "Confirm ↵"), systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
        } else if selected {
            Image(systemName: "return")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if pendingConfirm {
            shape.fill(Color.orange.opacity(0.16))
                .overlay(shape.strokeBorder(Color.orange.opacity(0.4), lineWidth: 0.5))
        } else if selected {
            shape.fill(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.30), Color.accentColor.opacity(0.20)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(shape.strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 0.5))
        } else if hovered {
            shape.fill(Color.primary.opacity(0.05))
        }
    }

    private func symbolIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(PaletteMetrics.hairline, lineWidth: 0.5)
            )
    }

    private static func symbolName(_ entry: CommandEntry) -> String {
        switch entry.kind {
        case .systemAction(let id):
            return SystemActionCatalog.def(id)?.symbol ?? "gearshape"
        case .quicklink: return "link"
        case .askAI: return "sparkles"
        case .webSearch: return "magnifyingglass"
        case .openURL: return "safari"
        default: return "questionmark"
        }
    }

    private static func clipboardSymbol(_ entry: CommandEntry) -> String {
        if case .clipboard(let item) = entry.kind {
            return ClipboardSearch.symbol(for: item.kind)
        }
        return "doc.on.doc"
    }
}

// MARK: - 键帽

/// 键帽提示：圆角小方块 + 说明文字。
struct KeyCapHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(PaletteMetrics.hairline, lineWidth: 0.5)
                )
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 空状态

struct EmptyPaletteView: View {
    let mode: PaletteMode
    let clipboardEnabled: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: mode == .apps ? "sparkle.magnifyingglass" : (mode == .clipboard ? "clipboard" : (mode == .files ? "folder" : "face.smiling")))
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            VStack(spacing: 6) {
                Text(headline)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(subheadline)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 12)
    }

    private var headline: String {
        switch mode {
        case .apps: return L10n.t("开始输入以搜索", "Start typing to search")
        case .clipboard: return L10n.t("剪贴板历史为空", "Clipboard history is empty")
        case .files: return L10n.t("输入以搜索文件", "Type to search files")
        case .emoji: return L10n.t("表情与符号", "Emoji & Symbols")
        case .chat: return L10n.t("AI 对话", "AI Chat")
        }
    }

    private var subheadline: String {
        switch mode {
        case .apps:
            return clipboardEnabled
                ? L10n.t("启动应用 · 算数 10km to mi · gh 搜 GitHub · Tab 剪贴板", "Launch apps · calc 10km to mi · gh GitHub · Tab clipboard")
                : L10n.t("启动应用 · 算数 10km to mi · gh 搜 GitHub", "Launch apps · calc 10km to mi · gh GitHub")
        case .clipboard:
            return L10n.t("复制文本、图片或文件后，会出现在这里", "Copy something to fill this list")
        case .files:
            return L10n.t("Spotlight 索引搜索所选文件夹 · Tab 表情", "Indexed by Spotlight · Tab for emoji")
        case .emoji:
            return L10n.t("搜索中文名或英文关键词，回车复制", "Search zh/en names, ↵ to copy")
        case .chat:
            return L10n.t("对话视图", "The conversation view")
        }
    }
}

// MARK: - 安全下标

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - AI 对话转录视图

struct ChatTranscriptView: View {
    let state: PaletteState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                chatContent
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .onChange(of: state.chatPartial, initial: true) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: state.chatMessages.count) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.1)) {
            proxy.scrollTo("streaming", anchor: .bottom)
        }
    }

    @ViewBuilder
    private var chatContent: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            historyBubbles
            streamingBubble
            if state.chatMessages.isEmpty && !state.chatStreaming {
                chatEmptyState
            }
        }
    }

    private var historyBubbles: some View {
        ForEach(Array(state.chatMessages.enumerated()), id: \.offset) { _, message in
            ChatBubble(
                message: message,
                imageLoader: { state.chatImage($0) },
                onCopy: { state.copyChatMessage($0) },
                onRevealImage: { state.revealChatImage($0) }
            )
            .id(message.role + String(message.content.hashValue))
        }
    }

    @ViewBuilder
    private var streamingBubble: some View {
        if state.chatStreaming {
            ChatBubble(message: AIChatMessage(
                role: "assistant",
                content: state.chatPartial.isEmpty ? "…" : state.chatPartial
            ))
            .id("streaming")
            .opacity(0.85)
        }
    }

    private var chatEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L10n.t("询问任何问题 · ⌘V 附图识别 · 切到生图可文生图/图生图", "Ask anything · ⌘V image input · switch to Image to generate"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            if !historyRows.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("最近对话", "Recent chats"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                    ForEach(historyRows) { conversation in
                        Button {
                            state.resumeConversation(conversation)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                Text(conversation.title)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(conversation.messages.count) ↩")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color.primary.opacity(0.035))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 6)
                .frame(maxWidth: 380, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.bottom, 12)
    }

    private var historyRows: [ChatConversation] {
        state.core?.chatHistory?.recent(6) ?? []
    }
}

struct ChatBubble: View {
    let message: AIChatMessage
    var imageLoader: ((String) -> NSImage?)? = nil
    var onCopy: ((AIChatMessage) -> Void)? = nil
    var onRevealImage: ((String) -> Void)? = nil

    var body: some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 40) }
            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 6) {
                if let images = message.images, !images.isEmpty {
                    imageRow(images)
                }
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.system(size: 13.5))
                        .textSelection(.enabled)
                        .lineSpacing(3)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(message.role == "user"
                                      ? Color.accentColor.opacity(0.20)
                                      : Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(PaletteMetrics.hairline, lineWidth: 0.5)
                        )
                        .contextMenu {
                            Button(L10n.t("复制", "Copy")) {
                                onCopy?(message)
                            }
                        }
                }
            }
            if message.role != "user" { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private func imageRow(_ names: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(names, id: \.self) { name in
                Group {
                    if let image = imageLoader?(name) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 168, height: 168)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(PaletteMetrics.hairline, lineWidth: 0.5)
                            )
                            .contextMenu {
                                Button(L10n.t("拷贝", "Copy")) {
                                    if let tiff = image.tiffRepresentation,
                                       let rep = NSBitmapImageRep(data: tiff),
                                       let png = rep.representation(using: .png, properties: [:]) {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setData(png, forType: .png)
                                    }
                                }
                                Button(L10n.t("在 Finder 中显示", "Reveal in Finder")) {
                                    onRevealImage?(name)
                                }
                            }
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 168, height: 168)
                    }
                }
            }
        }
    }
}

// MARK: - 表情网格屏

/// 表情屏：浏览态按分类分段网格；搜索态合并为一段。←→ ±1，↑↓ ±一行。
struct EmojiScreenView: View {
    let state: PaletteState
    static let columns = 10

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(state.sections) { section in
                        SectionHeaderView(title: section.title)
                        grid(for: section.entries)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .onChange(of: state.selection) { _, _ in
                if let entry = state.selectedEntry {
                    proxy.scrollTo(entry.id, anchor: .center)
                }
            }
        }
    }

    private func grid(for entries: [CommandEntry]) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(64), spacing: 8), count: Self.columns),
            spacing: 8
        ) {
            ForEach(entries) { entry in
                cell(entry)
            }
        }
    }

    private func cell(_ entry: CommandEntry) -> some View {
        let selected = state.rows[safe: state.selection]?.id == entry.id
        return Group {
            if case .emoji(let def) = entry.kind {
                Text(def.character)
                    .font(.system(size: 30))
                    .frame(width: 64, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selected ? Color.accentColor.opacity(0.25)
                                : (hoveredID == entry.id ? Color.primary.opacity(0.06) : Color.clear))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                selected ? Color.accentColor.opacity(0.5) : .clear,
                                lineWidth: 1
                            )
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        state.setSelection(index(of: entry))
                        state.activate(entry)
                    }
                    .onHover { hovering in
                        hoveredID = hovering ? entry.id : nil
                    }
                    .help("\\(def.name) · \\(def.zh)")
                    .id(entry.id)
            }
        }
    }

    @State private var hoveredID: String?

    private func index(of entry: CommandEntry) -> Int {
        state.rows.firstIndex(where: { $0.id == entry.id }) ?? 0
    }
}
