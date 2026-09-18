import AppKit
import Combine
import Foundation
import Observation
import ZappaleCore

/// 面板屏：应用/命令主屏、剪贴板历史屏、文件搜索屏。Tab 循环切换。
enum PaletteMode: String, CaseIterable {
    case apps
    case clipboard
    case files
    case emoji
    /// AI 对话屏：不参与 Tab 循环与模式胶囊（由"询问 AI"入口进入）。
    case chat

    var displayName: String {
        switch self {
        case .apps: return L10n.t("应用", "Apps")
        case .clipboard: return L10n.t("剪贴板", "Clipboard")
        case .files: return L10n.t("文件", "Files")
        case .emoji: return L10n.t("表情", "Emoji")
        case .chat: return L10n.t("AI 对话", "AI Chat")
        }
    }

    /// 是否出现在模式胶囊里（chat 不出现）。
    var showsInSwitcher: Bool { self != .chat }

    /// Tab 循环顺序：应用 → 剪贴板 → 文件 → 表情 → 应用。
    var next: PaletteMode {
        switch self {
        case .apps: return .clipboard
        case .clipboard: return .files
        case .files: return .emoji
        case .emoji: return .apps
        case .chat: return .apps
        }
    }
}

/// 面板状态机 + 协调器。
///
/// 职责（对齐 tinycast 的分层）：选择索引与可见行一一对应；
/// 破坏性动作的二次确认在协调层，不在 Runner；通知限时自动消失；
/// 激活副作用（隐藏面板、粘贴回注）通过回调交给窗口控制器执行。
@MainActor
@Observable
final class PaletteState {
    // MARK: 输入状态

    var mode: PaletteMode = .apps
    var query = ""
    private(set) var selection = 0

    // MARK: 派生状态

    private(set) var sections: [CommandSection] = []
    private(set) var rows: [CommandEntry] = []
    /// 待二次确认的行 id；输入或换行即取消。
    private(set) var pendingConfirmID: String?

    // MARK: AI 对话状态

    private(set) var chatMessages: [AIChatMessage] = []
    /// 流式输出中的部分回复。
    private(set) var chatPartial = ""
    private(set) var chatStreaming = false
    private var chatTask: Task<Void, Never>?

    /// 聊天图片附件（识别输入或图生图底图）。
    struct ChatAttachment {
        let data: Data
        let mime: String
        let pixelSize: String
    }

    private(set) var chatAttachment: ChatAttachment?
    /// 生图子模式（对话 ↔ 生图）。
    var chatImageMode = false
    private(set) var currentConversationID: String?
    private(set) var notice: String?
    /// 每次会话递增，驱动搜索框重新聚焦。
    private(set) var focusToken = 0
    /// 语言切换递增，驱动面板整体重渲染。
    private(set) var languageVersion = 0

    weak var core: AppCore?

    // MARK: 回调（窗口控制器注入）

    var onShouldHide: (() -> Void)?
    /// 隐藏面板后执行粘贴回注（面板必须先收起，目标应用才能回到前台）。
    var onPasteRequested: ((ClipboardItem) -> Void)?
    var onShowAccessibilityHint: (() -> Void)?

    private var noticeTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(core: AppCore?) {
        self.core = core

        // 剪贴板功能关闭时：Tab 不进入该屏；已在屏内则退回应用屏。
        // 文件搜索结果回填时重建文件屏分区。
        if let core {
            core.settings.$clipboardEnabled
                .receive(on: DispatchQueue.main)
                .sink { [weak self] enabled in
                    guard let self, !enabled, self.mode == .clipboard else { return }
                    self.mode = .apps
                    self.rebuild()
                }
                .store(in: &cancellables)

            core.settings.$language
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.languageVersion += 1
                }
                .store(in: &cancellables)

            core.settings.$fileSearchScopes
                .receive(on: DispatchQueue.main)
                .dropFirst()
                .sink { [weak self] _ in
                    guard let self, self.mode == .files else { return }
                    self.queryChanged()
                }
                .store(in: &cancellables)

            core.fileSearch.$results
                .receive(on: DispatchQueue.main)
                .sink { [weak self] results in
                    guard let self, self.mode == .files else { return }
                    _ = results
                    self.rebuild()
                }
                .store(in: &cancellables)
        }
    }

    // MARK: - 会话

    func beginSession(mode: PaletteMode = .apps) {
        let targetMode = (mode == .clipboard && core?.settings.clipboardEnabled == false) ? .apps : mode
        self.mode = targetMode
        query = ""
        selection = 0
        pendingConfirmID = nil
        focusToken += 1
        core?.launcher.loadIfNeeded()
        core?.fileSearch.clear()
        chatTask?.cancel()
        chatMessages = []
        chatPartial = ""
        chatStreaming = false
        chatAttachment = nil
        chatImageMode = false
        currentConversationID = nil
        rebuild()
    }

    // MARK: - 查询

    func queryChanged() {
        pendingConfirmID = nil
        if mode == .chat { return } // 输入即消息草稿，不触发搜索
        if mode == .files {
            // 文件搜索走防抖异步服务；查询为空时清空
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                core?.fileSearch.clear()
                rebuild()
            } else {
                core?.fileSearch.search(
                    query: query,
                    scopes: core?.settings.fileSearchScopes ?? []
                )
                rebuild()
            }
            return
        }
        rebuild()
    }

    private func rebuild() {
        guard let core else { return }
        switch mode {
        case .apps:
            let context = CommandQuery.Context(
                apps: core.launcher.entries,
                aiEnabled: core.settings.aiEnabled,
                frecency: { [weak core] path in
                    core?.ranking?.boost(for: path) ?? 0
                },
                runningPaths: Set(
                    NSWorkspace.shared.runningApplications
                        .compactMap(\.bundleURL?.path)
                ),
                snippets: core.snippets?.snippets ?? [],
                commands: core.commands?.commands ?? [],
                windowManagementEnabled: core.settings.windowManagementEnabled
                    && (core.featureGate.isAvailable(.windowManagement)),
                quicklinks: core.quicklinks?.links ?? [],
                notes: core.notes?.notes ?? [],
                quicklinkArgumentClipboard: core.clipboard.currentText,
                now: Date(),
                systemActionsEnabled: core.settings.systemActionsEnabled
            )
            sections = CommandQuery.sections(query: query, context: context)
        case .clipboard:
            sections = ClipboardSearch.sections(items: core.clipboard.store.items, query: query)
        case .files:
            let entries = core.fileSearch.results.map(fileEntry)
            sections = entries.isEmpty
                ? []
                : [CommandSection(id: "files", title: L10n.t("文件", "Files"), entries: entries)]
        case .emoji:
            sections = emojiSections()
        case .chat:
            sections = [] // 对话由专用视图渲染，不走结果列表
        }
        rows = PaletteRows.flatten(sections)
        if selection >= rows.count { selection = 0 }
    }

    /// 表情屏分区：空查询按分类浏览；有查询合并为单区。
    private func emojiSections() -> [CommandSection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let results = EmojiCatalog.search(trimmed.isEmpty ? "" : trimmed)
        if trimmed.isEmpty {
            return EmojiCatalog.categories.compactMap { category in
                let entries = results
                    .filter { $0.category == category }
                    .map(emojiEntry)
                guard !entries.isEmpty else { return nil }
                return CommandSection(
                    id: "emoji-\(category)",
                    title: EmojiCatalog.categoryName(category),
                    entries: entries
                )
            }
        }
        return results.isEmpty
            ? []
            : [CommandSection(id: "emoji-search", title: L10n.t("表情与符号", "Emoji & Symbols"), entries: results.map(emojiEntry))]
    }

    private func emojiEntry(_ def: EmojiDef) -> CommandEntry {
        CommandEntry(
            id: "emoji-\(def.character)",
            kind: .emoji(def),
            title: def.character,
            subtitle: "\(def.name) · \(def.zh)",
            icon: .symbol("face.smiling")
        )
    }

    /// 文件行：目录与文件共用文件图标，副标题为父目录。
    private func fileEntry(_ entry: FileSearchEntry) -> CommandEntry {
        CommandEntry(
            id: "file-\(entry.path)",
            kind: .file(entry),
            title: entry.name,
            subtitle: entry.parentDirectory,
            icon: .filePath(entry.isDirectory ? entry.path + "/" : entry.path)
        )
    }

    /// 外部数据变化（索引刷新、新捕获）后重建，保持查询与选择尽量稳定。
    func refreshFromData() {
        let savedQuery = query
        let savedSelection = selection
        rebuild()
        _ = savedQuery
        if savedSelection < rows.count { selection = savedSelection }
    }

    // MARK: - 选择

    func moveSelection(_ delta: Int) {
        pendingConfirmID = nil
        selection = PaletteRows.moveSelection(index: selection, delta: delta, count: rows.count)
    }

    func setSelection(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        pendingConfirmID = nil
        selection = index
    }

    // MARK: - 模式与退出

    func toggleMode() {
        pendingConfirmID = nil
        var target = mode.next
        // 剪贴板屏被禁用时跳过
        if target == .clipboard, core?.settings.clipboardEnabled == false {
            target = target.next
        }
        guard target != mode else { return }
        if mode == .chat { cancelStreaming() }
        mode = target
        queryChanged()
    }

    /// 点击模式胶囊直接切屏（剪贴板禁用时落回应用屏）。
    func switchMode(to target: PaletteMode) {
        var resolved = target
        if resolved == .clipboard, core?.settings.clipboardEnabled == false {
            resolved = .apps
        }
        guard resolved != mode else { return }
        if mode == .chat { cancelStreaming() }
        mode = resolved
        pendingConfirmID = nil
        queryChanged()
    }

    /// Esc：有查询先清空，空查询才关闭面板。
    /// 清空时文件屏同步终止搜索。
    func escape() {
        if mode == .chat {
            // 对话中的 Esc：先退回应用屏；空对话直接收起。
            // 离开即取消进行中的流式请求，防止重进会话后双流交错。
            if chatMessages.isEmpty && query.isEmpty {
                onShouldHide?()
            } else {
                cancelStreaming()
                mode = .apps
                query = ""
                rebuild()
            }
            return
        }
        if !query.isEmpty {
            query = ""
            pendingConfirmID = nil
            core?.fileSearch.clear()
            rebuild()
        } else {
            onShouldHide?()
        }
    }

    /// 取消进行中的 AI 流式请求并复位状态。
    func cancelStreaming() {
        chatTask?.cancel()
        chatTask = nil
        chatStreaming = false
        // 半截回复保留为一条消息，避免内容凭空消失
        if !chatPartial.isEmpty {
            chatMessages.append(AIChatMessage(role: "assistant", content: chatPartial))
            persistConversation()
        }
        chatPartial = ""
    }

    /// 面板内 ⌘, 直达设置。
    func openSettings() {
        onShouldHide?()
        core?.showSettings()
    }

    // MARK: - 剪贴板行快捷操作（⌘P / ⌫）

    func clipboardShortcutPin() {
        guard mode == .clipboard, let id = selectedClipboardItemID() else { return }
        clipboardTogglePin(id: id)
    }

    func clipboardShortcutDelete() {
        guard mode == .clipboard, query.isEmpty, let id = selectedClipboardItemID() else { return }
        clipboardDelete(id: id)
        showNotice(L10n.t("已删除", "Deleted"))
    }

    private func selectedClipboardItemID() -> String? {
        guard let entry = selectedEntry, case .clipboard(let item) = entry.kind else { return nil }
        return item.id
    }

    // MARK: - 激活

    func activateSelected(commandPressed: Bool = false) {
        guard rows.indices.contains(selection) else { return }
        activate(rows[selection], commandPressed: commandPressed)
    }

    /// ⌘1…⌘9 快速激活。
    func quickActivate(character: String) {
        guard let index = PaletteRows.quickActivateIndex(character: character),
              rows.indices.contains(index) else { return }
        activate(rows[index])
    }

    func activate(_ entry: CommandEntry, commandPressed: Bool = false) {
        // 破坏性动作：首次回车进入确认态，二次回车执行
        if entry.requiresConfirmation, pendingConfirmID != entry.id {
            pendingConfirmID = entry.id
            return
        }
        pendingConfirmID = nil

        switch entry.kind {
        case .app(let path):
            launchApp(path: path)

        case .systemAction(let id):
            runSystemAction(id)

        case .quicklink(let id):
            openQuicklink(id: id)

        case .clipboard(let item):
            activateClipboardItem(item, commandPressed: commandPressed)

        case .file(let entry):
            activateFile(entry, commandPressed: commandPressed)

        case .emoji(let def):
            core?.clipboard.writeToSystemPasteboard(text: def.character)
            showNotice(L10n.t("已复制 \(def.character)", "Copied \(def.character)"))

        case .note(let id):
            core?.openNote(id: id)
            onShouldHide?()

        case .askAI(let queryText):
            enterChat(with: queryText)

        case .snippet(let id, let argument):
            activateSnippet(id: id, argument: argument, commandPressed: commandPressed)

        case .customCommand(let id):
            activateCustomCommand(id: id, commandPressed: commandPressed)

        case .calculator:
            copyCalculatorResult(entry)

        case .webSearch(let text):
            openSearch(query: text)

        case .openURL(let url):
            openURLString(url)
        }
    }

    // MARK: 激活实现

    /// 打开文件；⌘↵ 在 Finder 中显示。
    private func activateFile(_ entry: FileSearchEntry, commandPressed: Bool) {
        let url = URL(fileURLWithPath: entry.path)
        if commandPressed {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            onShouldHide?()
        } else {
            NSWorkspace.shared.open(url)
            onShouldHide?()
        }
    }

    /// 拷贝文件路径（右键菜单用）。
    // MARK: - 片段 / 命令 / 窗口 / 快捷动作

    private func activateSnippet(id: String, argument: String?, commandPressed: Bool) {
        guard let core, let snippet = core.snippets?.snippet(id) else { return }
        guard let expanded = SnippetTemplate.render(
            snippet.template,
            argument: argument,
            clipboardText: core.clipboard.currentText,
            date: Date()
        ) else {
            showNotice(L10n.t("输入参数后回车", "Type query then ↵"))
            return
        }
        if commandPressed {
            // ⌘↵：粘贴回前一个应用
            let item = ClipboardItem(kind: .text, text: expanded, date: Date())
            onPasteRequested?(item)
        } else {
            core.clipboard.writeToSystemPasteboard(text: expanded)
            showNotice(L10n.t("已复制片段", "Snippet copied"))
        }
    }

    private func activateCustomCommand(id: String, commandPressed: Bool) {
        guard let core, let command = core.commands?.command(id) else { return }
        showNotice(L10n.t("运行中：\(command.name)", "Running: \(command.name)"))
        Task { @MainActor [weak self] in
            let outcome = await CustomCommandRunner.run(command.script)
            guard let self else { return }
            if commandPressed {
                if !outcome.output.isEmpty {
                    core.clipboard.writeToSystemPasteboard(text: outcome.output)
                    self.showNotice(L10n.t("输出已复制", "Output copied"))
                } else {
                    self.showNotice(L10n.t("无输出", "No output"))
                }
            } else if outcome.succeeded {
                self.showNotice(L10n.t("完成：\(command.name)", "Done: \(command.name)"))
            } else {
                self.showNotice(L10n.t("失败（\(outcome.exitCode)）", "Failed (\(outcome.exitCode))"))
            }
        }
    }

    private func applyWindowAction(_ action: WindowAction) {
        guard AXWindowAccess.isTrusted else {
            showNotice(L10n.t("窗口管理需要辅助功能权限", "Window management needs Accessibility"))
            return
        }
        switch AXWindowAccess.apply(action) {
        case .applied, .failed:
            onShouldHide?()
        case .noWindow:
            showNotice(L10n.t("前台应用没有可操作的窗口", "No operable window in front"))
        case .notTrusted:
            showNotice(L10n.t("窗口管理需要辅助功能权限", "Window management needs Accessibility"))
        }
    }

    /// AI 快捷动作：取选中 → AI → 贴回。面板先收起。
    private func startQuickAction(_ id: SystemActionID) {
        guard let core else { return }
        guard core.settings.aiEnabled else { return }
        guard let key = core.keychain.get(account: core.keychainAccount), !key.isEmpty else {
            showNotice(L10n.t("请先在设置中保存 API Key", "Save your API key first"))
            return
        }
        guard Paster.isTrusted else {
            showNotice(L10n.t("快捷动作需要辅助功能权限", "Quick actions need Accessibility"))
            return
        }
        let prompt: String
        switch id {
        case .aiTranslate:
            prompt = "Translate the following text into Chinese. Output only the translation:\n\n"
        case .aiPolish:
            prompt = "Polish and rewrite the following text to be clear and natural, keeping the original language. Output only the rewritten text:\n\n"
        case .aiSummarize:
            prompt = "Summarize the following text in its original language, in 1-3 concise sentences. Output only the summary:\n\n"
        default:
            return
        }
        onQuickAction?(prompt, core)
    }

    /// 由窗口控制器注入：收起面板后执行 AI 快捷动作闭环。
    var onQuickAction: ((String, AppCore) -> Void)?

    /// 退出运行中的应用（右键菜单）。
    func quitApp(path: String) {
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleURL?.path == path
        }) {
            running.terminate()
            showNotice(L10n.t("已请求退出", "Quit requested"))
            rebuild()
        }
    }

    func isAppRunning(path: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.path == path }
    }

    func copyFilePath(_ entry: FileSearchEntry) {
        core?.clipboard.writeToSystemPasteboard(text: entry.path)
        showNotice(L10n.t("已复制路径", "Path copied"))
    }

    private func launchApp(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.openApplication(
            at: url,
            configuration: NSWorkspace.OpenConfiguration()
        ) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.showNotice(L10n.t("启动失败：\(error.localizedDescription)", "Launch failed: \(error.localizedDescription)"))
                } else {
                    self.core?.recordAppLaunch(path: path)
                    self.onShouldHide?()
                }
            }
        }
    }

    private func runSystemAction(_ id: SystemActionID) {
        // 新建笔记走编辑器，不进 Runner
        if id == .newNote {
            core?.createNote()
            onShouldHide?()
            return
        }
        // 窗口动作走 AX 服务
        if let windowAction = SystemActionCatalog.windowAction(for: id) {
            applyWindowAction(windowAction)
            return
        }
        // AI 快捷动作走取词→AI→贴回闭环
        if SystemActionCatalog.isAIAction(id) {
            startQuickAction(id)
            return
        }
        let outcome = SystemActionRunner.run(id)
        switch outcome {
        case .done:
            onShouldHide?()
        case .failed(let message):
            showNotice(message)
        }
    }

    private func openQuicklink(id: String) {
        guard let core, let link = core.quicklinks?.link(id) else { return }
        let argument: String?
        if let match = QuicklinkQuery.keywordMatch(query: query, links: [link]) {
            argument = match.argument
        } else {
            argument = nil
        }
        let rendered = QuicklinkTemplate.render(
            link.urlTemplate,
            argument: argument,
            clipboardText: core.clipboard.currentText,
            date: Date()
        )
        switch rendered {
        case .url(let urlString):
            openURLString(urlString)
        case .needsArgument:
            showNotice(L10n.t("输入参数后回车打开（如「\(link.keyword.isEmpty ? link.name : link.keyword) 关键词」）", "Type an argument then ↵ (e.g. \"\(link.keyword.isEmpty ? link.name : link.keyword) query\")"))
        case .invalid:
            showNotice(L10n.t("链接模板无效，请在设置中检查", "Invalid template, check settings"))
        }
    }

    private func activateClipboardItem(_ item: ClipboardItem, commandPressed: Bool) {
        guard let core else { return }
        // ↵ 与 ⌘↵ 是一对：一个粘贴一个复制，默认方向由设置决定
        let wantsPaste: Bool
        if commandPressed {
            wantsPaste = core.settings.clipboardDefaultAction == .copy
        } else {
            wantsPaste = core.settings.clipboardDefaultAction == .paste
        }

        if wantsPaste {
            onPasteRequested?(item)
        } else {
            switch item.kind {
            case .text: core.clipboard.writeToSystemPasteboard(text: item.text)
            case .image:
                guard let imagePath = item.imagePath else { return }
                core.clipboard.writeToSystemPasteboard(imagePath: imagePath)
            case .file: core.clipboard.writeToSystemPasteboard(filePaths: item.filePaths ?? [item.text])
            }
            showNotice(L10n.t("已复制", "Copied"))
        }
    }

    private func copyCalculatorResult(_ entry: CommandEntry) {
        guard case .calculator(let display) = entry.kind else { return }
        let text = display.hasPrefix("= ") ? String(display.dropFirst(2)) : display
        core?.clipboard.writeToSystemPasteboard(text: text)
        showNotice("已复制 \(text)")
    }

    private func openSearch(query text: String) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/search"
        components.queryItems = [URLQueryItem(name: "q", value: text)]
        if let url = components.url {
            NSWorkspace.shared.open(url)
            onShouldHide?()
        }
    }

    private func openURLString(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            showNotice(L10n.t("无法解析链接", "Cannot parse URL"))
            return
        }
        NSWorkspace.shared.open(url)
        onShouldHide?()
    }

    // MARK: - 通知

    func showNotice(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    // MARK: - AI 对话

    /// 从粘贴板附图（⌘V 拦截）。返回是否成功附加。
    @discardableResult
    func attachImageFromPasteboard() -> Bool {
        guard mode == .chat else { return false }
        let pasteboard = NSPasteboard.general
        var data: Data?
        if let png = pasteboard.data(forType: .png) {
            data = png
        } else if let tiff = pasteboard.data(forType: .tiff),
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) {
            data = png
        }
        guard let imageData = data else { return false }
        let size = NSBitmapImageRep(data: imageData)
            .map { "\($0.pixelsWide)×\($0.pixelsHigh)" }
        chatAttachment = ChatAttachment(data: imageData, mime: "image/png", pixelSize: size ?? "")
        showNotice(L10n.t("已附图片", "Image attached"))
        return true
    }

    func removeAttachment() {
        chatAttachment = nil
    }

    /// 恢复历史对话。
    func resumeConversation(_ conversation: ChatConversation) {
        mode = .chat
        chatMessages = conversation.messages
        currentConversationID = conversation.id
        chatPartial = ""
        chatStreaming = false
        chatAttachment = nil
        query = ""
        rebuild()
    }

    /// 复制消息文本。
    func copyChatMessage(_ message: AIChatMessage) {
        core?.clipboard.writeToSystemPasteboard(text: message.content)
        showNotice(L10n.t("已复制", "Copied"))
    }

    /// 气泡图片加载（附件/生成图）。
    func chatImage(_ name: String) -> NSImage? {
        core?.mediaImageURL(name).flatMap { NSImage(contentsOf: $0) }
    }

    /// 在 Finder 中显示生成图。
    func revealChatImage(_ name: String) {
        if let url = core?.mediaImageURL(name) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func persistConversation() {
        guard let history = core?.chatHistory else { return }
        let conversation = ChatConversation(
            id: currentConversationID ?? UUID().uuidString,
            startedAt: Date(),
            updatedAt: Date(),
            messages: chatMessages
        )
        currentConversationID = conversation.id
        history.upsert(conversation)
    }

    /// 进入对话屏并发送首条消息。
    func enterChat(with text: String) {
        mode = .chat
        rebuild()
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        sendChat(text: text)
    }

    /// 发送一条消息（回车触发）。
    func sendChat() {
        guard mode == .chat, !chatStreaming else { return }
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        query = ""
        sendChat(text: text)
    }

    private func sendChat(text: String) {
        guard let core else { return }
        guard let key = core.keychain.get(account: core.keychainAccount), !key.isEmpty else {
            showNotice(L10n.t("请先在设置中保存 API Key", "Save your API key first"))
            return
        }

        // 附件落盘并挂到用户消息
        var attachmentNames: [String]? = nil
        if let attachment = chatAttachment, let name = core.saveMediaImage(attachment.data) {
            attachmentNames = [name]
        }
        chatMessages.append(AIChatMessage(role: "user", content: text, images: attachmentNames))
        chatPartial = ""
        chatStreaming = true

        let connection = AIConnection(
            provider: core.settings.provider,
            endpoint: core.settings.endpointURL ?? URL(string: core.settings.endpointText)!,
            model: core.settings.model
        )
        let client = AIClient(connection: connection, apiKey: key)
        let history = chatMessages
        let attachment = chatAttachment
        let imageMode = chatImageMode
        chatAttachment = nil
        persistConversation()

        let imageAllowed = core.featureGate.isAvailable(.aiImages)
        chatTask = Task { [weak self] in
            if imageMode && imageAllowed {
                await self?.runImageGeneration(client: client, prompt: text, attachment: attachment)
            } else {
                let imageData = attachment.map { (data: $0.data, mime: $0.mime) }
                await client.streamChat(messages: history, image: imageData) { event in
                    Task { @MainActor [weak self] in
                        self?.handleStreamEvent(event)
                    }
                }
            }
        }
    }

    /// 文生图 / 图生图。
    private func runImageGeneration(client: AIClient, prompt: String, attachment: ChatAttachment?) async {
        do {
            let images: [Data]
            if let attachment {
                images = try await client.editImage(prompt: prompt, imageData: attachment.data, mime: attachment.mime)
            } else {
                images = try await client.generateImages(prompt: prompt)
            }
            let names = images.compactMap { core?.saveMediaImage($0) }
            chatMessages.append(AIChatMessage(
                role: "assistant",
                content: L10n.t("已生成 \(names.count) 张图片", "Generated \(names.count) image(s)"),
                images: names
            ))
            chatStreaming = false
            persistConversation()
        } catch {
            chatStreaming = false
            showNotice(L10n.t("生图失败：", "Image generation failed: ") + error.localizedDescription)
        }
    }

    private func handleStreamEvent(_ event: AIStreamEvent) {
        switch event {
        case .delta(let text):
            chatPartial += text
        case .done:
            let reply = chatPartial
            if !reply.isEmpty {
                chatMessages.append(AIChatMessage(role: "assistant", content: reply))
            }
            chatPartial = ""
            chatStreaming = false
            persistConversation()
        case .failed(let message):
            chatStreaming = false
            chatPartial = ""
            // 失败时回退用户消息为可编辑文本
            if let last = chatMessages.last, last.role == "user" {
                chatMessages.removeLast()
                query = last.content
            }
            showNotice(L10n.t("AI 请求失败：\(message)", "AI failed: \(message)"))
        }
    }

    // MARK: - 剪贴板行操作（右键菜单）

    func clipboardTogglePin(id: String) {
        core?.clipboard.store.togglePin(id)
        core?.clipboard.store.save()
        rebuild()
    }

    func clipboardDelete(id: String) {
        core?.clipboard.store.delete(id)
        core?.clipboard.store.save()
        rebuild()
    }

    func clearClipboardHistory() {
        core?.clipboard.store.clear()
        core?.clipboard.store.save()
        rebuild()
        showNotice(L10n.t("剪贴板历史已清空", "Clipboard history cleared"))
    }

    /// 剪贴板图片缩略图（clipboard 屏使用）。
    func imageFor(_ item: ClipboardItem) -> NSImage? {
        guard let core, let url = core.clipboard.store.imageURL(for: item) else { return nil }
        return NSImage(contentsOf: url)
    }

    // MARK: - 供视图使用

    var selectedEntry: CommandEntry? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }
}
