import AppKit
import SwiftUI
import ZappaleCore

/// 文件搜索设置页：作用域目录管理。
struct FileSearchSettingsPane: View {
    let core: AppCore
    @ObservedObject private var settings: AppSettings

    init(core: AppCore) {
        self.core = core
        self.settings = core.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: L10n.t("文件搜索", "File Search"))
            SettingsGroup(title: L10n.t("搜索作用域", "Scopes")) {
                ForEach(settings.fileSearchScopes, id: \.self) { scope in
                    SettingsRow(title: scope) {
                        Button(role: .destructive) {
                            settings.fileSearchScopes.removeAll { $0 == scope }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                    if scope != settings.fileSearchScopes.last {
                        Divider().padding(.horizontal, 8)
                    }
                }
                if settings.fileSearchScopes.isEmpty {
                    Text(L10n.t("没有作用域，文件搜索不可用", "No scopes, file search unavailable"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                Divider().padding(.horizontal, 8)
                HStack {
                    Button {
                        addScope()
                    } label: {
                        Label(L10n.t("添加文件夹", "Add Folder…"), systemImage: "plus")
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            SettingsGroup(title: L10n.t("关于", "About")) {
                SettingsRow(
                    title: L10n.t("索引来源", "Index"),
                    subtitle: L10n.t("借系统 Spotlight 索引，zappale 不自建索引；新文件夹需等待系统索引", "Uses the system Spotlight index; new folders need time to index.")
                ) {
                    EmptyView()
                }
            }
        }
        .padding(.top, 16)
    }

    private func addScope() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = L10n.t("选择要纳入文件搜索的文件夹", "Pick a folder to search")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let scope = FileSearchScope.abbreviate(url.path)
        guard !settings.fileSearchScopes.contains(scope) else { return }
        settings.fileSearchScopes.append(scope)
    }
}
