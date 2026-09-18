import AppKit
import Combine
import SwiftUI
import ZappaleCore

/// 笔记编辑器窗口管理：一笔记一窗口；自动保存防抖；标题=首行。
@MainActor
final class NotesEditorController {
    private let store: NotesStore
    private var windows: [String: NSWindow] = [:]
    private var saveTasks: [String: Task<Void, Never>] = [:]

    init(store: NotesStore) {
        self.store = store
    }

    func show(noteID: String) {
        guard let note = store.note(noteID) else { return }
        if let window = windows[noteID] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = note.title
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()

        let editor = NotesEditorView(
            noteID: noteID,
            initialContent: note.content,
            store: store,
            onTextChange: { [weak self] text in
                self?.scheduleSave(noteID: noteID, text: text)
            },
            onNewNote: { [weak self] in
                self?.createAndShow()
            },
            onClose: { [weak self] in
                self?.close(noteID: noteID)
            }
        )
        window.contentView = NSHostingView(rootView: editor)
        window.delegate = self.coordinator
        windows[noteID] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 新建并打开。
    func createAndShow() {
        let note = store.create()
        show(noteID: note.id)
    }

    /// 关闭指定笔记窗口（工具栏删除用）。
    func close(noteID: String) {
        if let window = windows[noteID] {
            window.close()
        }
    }

    private func scheduleSave(noteID: String, text: String) {
        saveTasks[noteID]?.cancel()
        saveTasks[noteID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.store.save(id: noteID, content: text)
            self?.windows[noteID]?.title = self?.store.note(noteID)?.title ?? ""
        }
    }

    /// 窗口关闭回调持有者。
    private lazy var coordinator = WindowCloseCoordinator { [weak self] noteID in
        self?.saveTasks[noteID]?.cancel()
        self?.windows[noteID] = nil
    }
}

/// NSWindowDelegate 不能是 @MainActor 类的顺滑实现：小协调器记录窗口关闭。
private final class WindowCloseCoordinator: NSObject, NSWindowDelegate {
    let onClose: (String) -> Void

    init(onClose: @escaping (String) -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let noteID = window.identifier?.rawValue else { return }
        onClose(noteID)
    }
}

// MARK: - 编辑器视图

struct NotesEditorView: View {
    let noteID: String
    @State private var text: String
    let store: NotesStore
    let onTextChange: (String) -> Void
    var onNewNote: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil

    init(noteID: String, initialContent: String, store: NotesStore,
         onTextChange: @escaping (String) -> Void,
         onNewNote: (() -> Void)? = nil,
         onClose: (() -> Void)? = nil) {
        self.noteID = noteID
        _text = State(initialValue: initialContent)
        self.store = store
        self.onTextChange = onTextChange
        self.onNewNote = onNewNote
        self.onClose = onClose
    }

    /// 编辑 / 预览
    @State private var previewing = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.4)
            if previewing {
                ScrollView {
                    MarkdownView(source: text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            } else {
                TextEditor(text: $text)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
                    .onChange(of: text) { _, newValue in
                        onTextChange(newValue)
                    }
            }
            footer
        }
        .frame(minWidth: 420, minHeight: 360)
        .onAppear {
            // 窗口标识：关闭时能映射回笔记
            NSApp.keyWindow?.identifier = NSUserInterfaceItemIdentifier(noteID)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $previewing) {
                Text(L10n.t("编辑", "Edit")).tag(false)
                Text(L10n.t("预览", "Preview")).tag(true)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 150)
            Spacer()
            Button {
                store.save(id: noteID, content: text)
                onNewNote?()
            } label: {
                Label(L10n.t("新建", "New"), systemImage: "plus")
            }
            Button(role: .destructive) {
                store.delete(id: noteID)
                onClose?()
            } label: {
                Label(L10n.t("删除", "Delete"), systemImage: "trash")
            }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Text(L10n.t("自动保存 · Markdown", "Autosave · Markdown"))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
            Text(L10n.t("\(text.count) 字", "\(text.count) chars"))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
