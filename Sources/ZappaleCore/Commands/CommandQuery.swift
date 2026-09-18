import Foundation

/// 应用屏（主屏）的查询构建器：把所有来源合并为分区列表。
/// 纯函数——所有输入都是参数，不含任何环境读取。
public enum CommandQuery {

    public struct Context {
        public var apps: [AppEntry] = []
        /// AI 总开关：开时回退区出现"询问 AI"。
        public var aiEnabled: Bool = false
        /// 模糊得分 → 应用。调用方已算好，这里只做合并排序。
        public var frecency: (String) -> Int = { _ in 0 }
        public var runningPaths: Set<String> = []
        public var snippets: [Snippet] = []
        public var commands: [CustomCommand] = []
        /// 窗口管理开关（关闭时窗口动作不出现在目录）。
        public var windowManagementEnabled: Bool = true
        public var quicklinks: [Quicklink] = []
        public var notes: [Note] = []
        public var quicklinkArgumentClipboard: String? = nil
        public var now: Date = Date()
        /// 系统动作总开关（默认开）。
        public var systemActionsEnabled: Bool = true

        public init(
            apps: [AppEntry] = [],
            aiEnabled: Bool = false,
            frecency: @escaping (String) -> Int = { _ in 0 },
            runningPaths: Set<String> = [],
            snippets: [Snippet] = [],
            commands: [CustomCommand] = [],
            windowManagementEnabled: Bool = true,
            quicklinks: [Quicklink] = [],
            notes: [Note] = [],
            quicklinkArgumentClipboard: String? = nil,
            now: Date = Date(),
            systemActionsEnabled: Bool = true
        ) {
            self.apps = apps
            self.aiEnabled = aiEnabled
            self.frecency = frecency
            self.runningPaths = runningPaths
            self.snippets = snippets
            self.commands = commands
            self.windowManagementEnabled = windowManagementEnabled
            self.quicklinks = quicklinks
            self.notes = notes
            self.quicklinkArgumentClipboard = quicklinkArgumentClipboard
            self.now = now
            self.systemActionsEnabled = systemActionsEnabled
        }
    }

    public static func sections(query: String, context: Context) -> [CommandSection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var sections: [CommandSection] = []

        // 空查询：常用应用 + 快捷操作 + 快捷链接
        if trimmed.isEmpty {
            if !context.apps.isEmpty {
                sections.append(CommandSection(
                    id: "apps-top",
                    title: L10n.t("应用程序", "Applications"),
                    entries: Array(context.apps.prefix(6)).map { appEntry($0, running: context.runningPaths.contains($0.path)) }
                ))
            }
            if context.systemActionsEnabled {
                let picks = SystemActionCatalog.quickPicks.compactMap(SystemActionCatalog.def)
                sections.append(CommandSection(
                    id: "system-quick",
                    title: L10n.t("快捷操作", "Quick Actions"),
                    entries: picks.map(systemEntry)
                ))
            }
            if !context.quicklinks.isEmpty {
                sections.append(CommandSection(
                    id: "quicklinks-top",
                    title: L10n.t("快捷链接", "Quicklinks"),
                    entries: context.quicklinks.prefix(4).map {
                    argumentEntry(for: $0, argument: nil, clipboard: context.quicklinkArgumentClipboard, now: context.now)
                }
                ))
            }
            if !context.notes.isEmpty {
                sections.append(CommandSection(
                    id: "notes-top",
                    title: L10n.t("笔记", "Notes"),
                    entries: context.notes.prefix(3).map(noteEntry)
                ))
            }
            return sections
        }

        var hasResults = false

        // 1. 内联计算卡：无标题分区，永远第一行
        if let calc = CalcEngine.evaluate(trimmed) {
            hasResults = true
            sections.append(CommandSection(id: "calc", entries: [
                CommandEntry(
                    id: "calc-card",
                    kind: .calculator(display: calc.display),
                    title: calc.display,
                    subtitle: L10n.t("回车复制结果", "Press ↵ to copy"),
                    icon: .symbol("equal.circle")
                ),
            ]))
        }

        // 2. 应用（名称/拼音/首字母 fuzzy + frecency 微调）
        let matchedApps = context.apps.compactMap { entry -> (AppEntry, Int)? in
            let effective = appMatchScore(query: trimmed, entry: entry, context: context)
            guard effective > Int.min else { return nil }
            return (entry, effective)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(8)
        if !matchedApps.isEmpty {
            hasResults = true
            sections.append(CommandSection(
                id: "apps",
                title: L10n.t("应用程序", "Applications"),
                entries: matchedApps.map { appEntry($0.0, running: context.runningPaths.contains($0.0.path)) }
            ))
        }

        // 3. 快捷链接：keyword 前缀精确模式优先，名称模糊补充
        var quicklinkEntries: [CommandEntry] = []
        if let keywordMatch = QuicklinkQuery.keywordMatch(query: trimmed, links: context.quicklinks) {
            quicklinkEntries.append(argumentEntry(for: keywordMatch.link, argument: keywordMatch.argument, clipboard: context.quicklinkArgumentClipboard, now: context.now))
        }
        let fuzzyLinks = QuicklinkQuery.search(trimmed, links: context.quicklinks)
        for link in fuzzyLinks where !quicklinkEntries.contains(where: { $0.id == "quicklink-\(link.id)" }) {
            quicklinkEntries.append(argumentEntry(for: link, argument: nil, clipboard: context.quicklinkArgumentClipboard, now: context.now))
        }
        if !quicklinkEntries.isEmpty {
            hasResults = true
            sections.append(CommandSection(
                id: "quicklinks",
                title: L10n.t("快捷链接", "Quicklinks"),
                entries: Array(quicklinkEntries.prefix(5))
            ))
        }

        // 4. 笔记（标题 > 内容）
        let matchedNotes = context.notes.compactMap { note -> (Note, Int)? in
            guard let score = NotesSearch.score(query: trimmed, note: note) else { return nil }
            return (note, score)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(4)
        if !matchedNotes.isEmpty {
            hasResults = true
            sections.append(CommandSection(
                id: "notes",
                title: L10n.t("笔记", "Notes"),
                entries: matchedNotes.map { noteEntry($0.0) }
            ))
        }

        // 5. 系统动作（窗口动作受开关；AI 快捷动作受 aiEnabled）
        if context.systemActionsEnabled {
            let actions = SystemActionCatalog.search(trimmed).filter { def in
                if def.category == .window { return context.windowManagementEnabled }
                if SystemActionCatalog.isAIAction(def.id) { return context.aiEnabled }
                return true
            }
            if !actions.isEmpty {
                hasResults = true
                sections.append(CommandSection(
                    id: "system-actions",
                    title: L10n.t("系统动作", "System Actions"),
                    entries: actions.map(systemEntry)
                ))
            }
        }

        // 5.5 片段与自定义命令
        var snippetEntries: [CommandEntry] = []
        if let keywordMatch = SnippetQuery.keywordMatch(query: trimmed, snippets: context.snippets) {
            snippetEntries.append(snippetEntry(keywordMatch.snippet, argument: keywordMatch.argument,
                                               clipboard: context.quicklinkArgumentClipboard, now: context.now))
        }
        for snippet in SnippetQuery.search(trimmed, snippets: context.snippets)
        where !snippetEntries.contains(where: { $0.id == "snippet-\(snippet.id)" }) {
            snippetEntries.append(snippetEntry(snippet, argument: nil,
                                               clipboard: context.quicklinkArgumentClipboard, now: context.now))
        }
        if !snippetEntries.isEmpty {
            hasResults = true
            sections.append(CommandSection(
                id: "snippets",
                title: L10n.t("片段", "Snippets"),
                entries: snippetEntries
            ))
        }

        let matchedCommands = CustomCommandQuery.search(trimmed, commands: context.commands)
        if !matchedCommands.isEmpty {
            hasResults = true
            sections.append(CommandSection(
                id: "commands",
                title: L10n.t("命令", "Commands"),
                entries: matchedCommands.map(commandEntry)
            ))
        }

        // 6. 回退：没有任何结果时给出出口
        if !hasResults {
            var entries: [CommandEntry] = []
            if let url = URLOpener.normalize(trimmed) {
                entries.append(CommandEntry(
                    id: "fallback-open-url",
                    kind: .openURL(url: url),
                    title: L10n.t("打开 \(trimmed)", "Open \(trimmed)"),
                    subtitle: L10n.t("在浏览器中打开", "Open in browser"),
                    icon: .symbol("safari")
                ))
            }
            if context.aiEnabled {
                entries.append(CommandEntry(
                    id: "fallback-ask-ai",
                    kind: .askAI(query: trimmed),
                    title: L10n.t("询问 AI「\(trimmed)」", "Ask AI · \(trimmed)"),
                    subtitle: L10n.t("在面板内对话", "Chat inline"),
                    icon: .symbol("sparkles")
                ))
            }
            entries.append(CommandEntry(
                id: "fallback-search",
                kind: .webSearch(query: trimmed),
                title: L10n.t("Google 搜索「\(trimmed)」", "Google \(trimmed)"),
                subtitle: L10n.t("在浏览器中搜索", "Search in browser"),
                icon: .symbol("magnifyingglass")
            ))
            sections.append(CommandSection(id: "fallback", title: L10n.t("没有其他结果", "No other results"), entries: entries))
        }

        return sections
    }

    // MARK: - 行构建

    /// 应用匹配得分：名称 > 全拼 > 首字母；各层内叠加精确/前缀加分与 frecency。
    public static func appMatchScore(query: String, entry: AppEntry, context: Context) -> Int {
        let lowered = query.lowercased()
        let nameScore = FuzzyMatch.score(query: query, target: entry.name) ?? Int.min
        var best = nameScore
        if nameScore > Int.min {
            if entry.name.lowercased() == lowered { best += 50 }
        }
        if let pinyin = entry.pinyin {
            if pinyin == lowered { best = max(best, 150) }
            else if pinyin.hasPrefix(lowered) { best = max(best, nameScore > Int.min ? nameScore : 110) }
            else if let fuzzy = FuzzyMatch.score(query: query, target: pinyin) {
                best = max(best, min(fuzzy, 109))
            }
        }
        if let initials = entry.pinyinInitials {
            if initials == lowered { best = max(best, 130) }
            else if initials.hasPrefix(lowered) { best = max(best, 100) }
        }
        guard best > Int.min else { return Int.min }
        return best + context.frecency(entry.path)
    }

    public static func appEntry(_ app: AppEntry, running: Bool = false) -> CommandEntry {
        CommandEntry(
            id: "app-\(app.path)",
            kind: .app(path: app.path),
            title: app.name,
            subtitle: running ? L10n.t("正在运行", "Running") : nil,
            icon: .filePath(app.path)
        )
    }

    public static func snippetEntry(
        _ snippet: Snippet, argument: String?, clipboard: String?, now: Date
    ) -> CommandEntry {
        let rendered = SnippetTemplate.render(
            snippet.template, argument: argument,
            clipboardText: clipboard, date: now
        )
        let title: String
        let subtitle: String
        if let rendered {
            let preview = rendered.split(whereSeparator: \.isNewline).first.map(String.init) ?? rendered
            title = argument == nil ? snippet.name : (L10n.isChinese ? "\(snippet.name)「\(argument!)」" : "\(snippet.name) \"\(argument!)\"")
            subtitle = String(preview.prefix(80))
        } else {
            title = snippet.name
            subtitle = L10n.t("输入参数后回车", "Type query then ↵") + " · \(snippet.template)"
        }
        return CommandEntry(
            id: "snippet-\(snippet.id)",
            kind: .snippet(id: snippet.id, argument: argument),
            title: title,
            subtitle: subtitle,
            icon: .symbol("text.quote")
        )
    }

    public static func commandEntry(_ command: CustomCommand) -> CommandEntry {
        CommandEntry(
            id: "command-\(command.id)",
            kind: .customCommand(id: command.id),
            title: command.name,
            subtitle: command.script,
            icon: .symbol("terminal"),
            requiresConfirmation: command.requiresConfirmation
        )
    }

    public static func noteEntry(_ note: Note) -> CommandEntry {
        CommandEntry(
            id: "note-\(note.id)",
            kind: .note(id: note.id),
            title: note.title,
            subtitle: NotesSearchPreview(of: note.content),
            icon: .symbol("note.text")
        )
    }

    public static func systemEntry(_ def: SystemActionDef) -> CommandEntry {
        CommandEntry(
            id: "system-\(def.id.rawValue)",
            kind: .systemAction(def.id),
            title: def.title,
            subtitle: def.subtitle,
            icon: .symbol(def.symbol),
            requiresConfirmation: def.requiresConfirmation
        )
    }

    /// 带参数渲染结果的快捷链接行；渲染失败则提示模板无效。
    public static func argumentEntry(
        for link: Quicklink, argument: String?, clipboard: String?, now: Date
    ) -> CommandEntry {
        let rendered = QuicklinkTemplate.render(
            link.urlTemplate,
            argument: argument,
            clipboardText: clipboard,
            date: now
        )
        let title: String
        let subtitle: String
        switch rendered {
        case .url(let url):
            title = argument == nil ? link.name : (L10n.isChinese ? "\(link.name)「\(argument!)」" : "\(link.name) \"\(argument!)\"")
            subtitle = url
        case .needsArgument:
            title = link.name
            subtitle = L10n.t("输入参数后回车", "Type query then ↵") + " · \(link.urlTemplate)"
        case .invalid:
            title = link.name
            subtitle = L10n.t("链接模板无效", "Invalid template") + " · \(link.urlTemplate)"
        }
        return CommandEntry(
            id: "quicklink-\(link.id)",
            kind: .quicklink(id: link.id),
            title: title,
            subtitle: subtitle,
            icon: .symbol("link")
        )
    }
}

/// URL 识别与打开（浏览器/系统默认）。
public enum URLOpener {
    /// 识别查询是否是 URL/主机名；返回规范化后的完整 URL 字符串。
    public static func normalize(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2048 else { return nil }
        guard !trimmed.contains(where: \.isNewline) else { return nil }

        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme), url.host != nil {
            return trimmed
        }
        // 其他 scheme（ftp:// 等）不在此处理；裸主机名继续下探

        // 裸主机名：example.com、example.com/path?q=1、localhost:3000
        guard !trimmed.contains(" ") else { return nil }
        guard trimmed.range(of: #"^[\w-]+(\.[\w-]+)+(:\d+)?([/?#].*)?$"#, options: .regularExpression) != nil
            || trimmed.range(of: #"^localhost(:\d+)?([/?#].*)?$"#, options: .regularExpression) != nil
        else { return nil }
        return "https://" + trimmed
    }
}


/// 笔记内容预览（第二行起的非空文本，截断）。
public func NotesSearchPreview(of content: String) -> String {
    let lines = content.split(whereSeparator: \.isNewline).dropFirst()
    let preview = lines.first.map(String.init) ?? ""
    let trimmed = preview.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return L10n.t("笔记", "Note") }
    return trimmed.count > 60 ? String(trimmed.prefix(57)) + "…" : trimmed
}
