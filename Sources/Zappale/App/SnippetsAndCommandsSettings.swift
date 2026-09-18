import AppKit
import SwiftUI
import ZappaleCore

// MARK: - 片段设置页

struct SnippetsSettingsPane: View {
    let core: AppCore
    @ObservedObject private var store: SnippetStore
    @State private var editing: Snippet?

    init(core: AppCore) {
        self.core = core
        self.store = core.snippets ?? SnippetStore(directory: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: L10n.t("片段", "Snippets"))
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t(
                    "可复用文本模板。占位符：{query} 参数、{clipboard} 剪贴板、{date} 今天；keyword 用于参数模式。",
                    "Reusable text templates. Placeholders: {query}, {clipboard}, {date}; keyword enables argument mode."
                ))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

                if let binding = Binding($editing) {
                    SnippetEditor(link: binding) { final in
                        if let final { store.upsert(final) }
                        editing = nil
                    }
                    .padding(.bottom, 10)
                }

                VStack(spacing: 0) {
                    ForEach(store.snippets) { snippet in
                        row(snippet)
                        if snippet.id != store.snippets.last?.id {
                            Divider().padding(.leading, 12)
                        }
                    }
                    if store.snippets.isEmpty {
                        Text(L10n.t("还没有片段", "No snippets yet"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5))

                HStack {
                    Button {
                        editing = Snippet(name: "", template: "")
                    } label: {
                        Label(L10n.t("添加片段", "Add Snippet"), systemImage: "plus")
                    }
                    Spacer()
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 16)
    }

    private func row(_ snippet: Snippet) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "text.quote")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(snippet.name.isEmpty ? L10n.t("未命名", "Untitled") : snippet.name)
                        .font(.system(size: 13, weight: .medium))
                    if !snippet.keyword.isEmpty {
                        Text(snippet.keyword)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    }
                }
                Text(snippet.template)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(L10n.t("编辑", "Edit")) { editing = snippet }
            Button(role: .destructive) {
                store.delete(ids: [snippet.id])
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

struct SnippetEditor: View {
    @Binding var link: Snippet
    var onCommit: (Snippet?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                field(title: L10n.t("名称", "Name"), text: $link.name, placeholder: L10n.t("邮件签名", "Email signature"))
                field(title: "Keyword", text: $link.keyword, placeholder: L10n.t("sig（可选）", "sig (optional)"))
            }
            HStack(spacing: 8) {
                Text(L10n.t("模板", "Template"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                TextEditor(text: $link.template)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 72)
                    .scrollContentBackground(.hidden)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor).opacity(0.5)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
            }
            HStack {
                Label(L10n.t("回车复制，⌘↵ 粘贴到前一个应用", "↵ copies, ⌘↵ pastes to previous app"),
                      systemImage: "lightbulb")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.t("取消", "Cancel")) { onCommit(nil) }
                Button(L10n.t("保存", "Save")) { onCommit(link) }
                    .disabled(link.name.trimmingCharacters(in: .whitespaces).isEmpty
                              || link.template.isEmpty)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5))
    }

    private func field(title: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - 自定义命令设置页

struct CommandsSettingsPane: View {
    let core: AppCore
    @ObservedObject private var store: CustomCommandStore
    @ObservedObject private var settings: AppSettings
    @State private var editing: CustomCommand?

    init(core: AppCore) {
        self.core = core
        self.store = core.commands ?? CustomCommandStore(directory: nil)
        self.settings = core.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: L10n.t("自定义命令", "Commands"))
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t(
                    "命名 shell 命令，/bin/zsh -c 执行，10 秒超时。可选确认与独立热键。",
                    "Named shell commands via /bin/zsh -c, 10s timeout. Optional confirmation and hotkey."
                ))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

                if let binding = Binding($editing) {
                    CommandEditor(link: binding) { final in
                        if let final { store.upsert(final) }
                        editing = nil
                    }
                    .padding(.bottom, 10)
                }

                VStack(spacing: 0) {
                    ForEach(store.commands) { command in
                        row(command)
                        if command.id != store.commands.last?.id {
                            Divider().padding(.leading, 12)
                        }
                    }
                    if store.commands.isEmpty {
                        Text(L10n.t("还没有命令", "No commands yet"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5))

                HStack {
                    Button {
                        editing = CustomCommand(name: "", script: "")
                    } label: {
                        Label(L10n.t("添加命令", "Add Command"), systemImage: "plus")
                    }
                    Spacer()
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 16)
    }

    private func row(_ command: CustomCommand) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(command.name.isEmpty ? L10n.t("未命名", "Untitled") : command.name)
                    .font(.system(size: 13, weight: .medium))
                Text(command.script)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            HotkeyRecorder(spec: command.hotkey) { spec in
                var updated = command
                updated.hotkey = spec
                store.upsert(updated)
            }
            Button(L10n.t("编辑", "Edit")) { editing = command }
            Button(role: .destructive) {
                store.delete(ids: [command.id])
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

struct CommandEditor: View {
    @Binding var link: CustomCommand
    var onCommit: (CustomCommand?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L10n.t("名称", "Name"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                TextField(L10n.t("清理缓存", "Clear caches"), text: $link.name)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 8) {
                Text(L10n.t("脚本", "Script"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                TextField("echo hello", text: $link.script)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }
            HStack {
                Toggle(L10n.t("运行前确认", "Confirm before run"), isOn: $link.requiresConfirmation)
                    .font(.system(size: 12))
                Spacer()
                Button(L10n.t("取消", "Cancel")) { onCommit(nil) }
                Button(L10n.t("保存", "Save")) { onCommit(link) }
                    .disabled(link.name.trimmingCharacters(in: .whitespaces).isEmpty
                              || link.script.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5))
    }
}
