import AppKit
import Foundation
import ZappaleCore

/// 剪贴板历史轮询器与系统粘贴板读写。
///
/// 行为规则（对齐 tinycast）：
/// - 0.5s Timer 观察 NSPasteboard.general.changeCount；
/// - 自有写入打 internalType 标记，轮询跳过，避免自捕获循环；
/// - 密码类（Concealed/Transient）与 App 内部类型永不入库；
/// - 文件 URL 先于文本读取——Finder 复制文件时 utf8-plain-string 里
///   只有显示名，先读文件才能得到真实路径；
/// - 易失目录（/tmp、/var/folders、~/Library/Caches）下的文件不入库；
/// - off = fully off：开关关闭即停轮询。
@MainActor
final class ClipboardManager: ObservableObject {
    /// 自有写入标记，同时用于轮询去重。
    static let internalType = NSPasteboard.PasteboardType("dev.zappale.internal.pasteboard")
    static let sensitiveTypes: [NSPasteboard.PasteboardType] = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
    ]
    /// 单次捕获的文件数上限，防止 Finder 全选造成海量入库。
    static let maxCapturedFiles = 20

    let store: ClipboardStore
    private let settings: AppSettings
    private var timer: Timer?
    private var lastChangeCount: Int
    private var saveTask: Task<Void, Never>?

    /// 图片 blob 目录的绝对路径（主线程外写入用）。
    private var blobsURL: URL?

    init(store: ClipboardStore, settings: AppSettings, directory: URL?) {
        self.store = store
        self.settings = settings
        self.lastChangeCount = NSPasteboard.general.changeCount
        if let directory {
            blobsURL = directory.appendingPathComponent("blobs", isDirectory: true)
        }
        applyEnabled(settings.clipboardEnabled)
    }

    // MARK: - 开关

    func applyEnabled(_ enabled: Bool) {
        if enabled {
            guard timer == nil else { return }
            lastChangeCount = NSPasteboard.general.changeCount
            let timer = Timer(timeInterval: 0.5, target: self, selector: #selector(poll),
                              userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    // MARK: - 轮询

    @objc private func poll() {
        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        let types = pasteboard.types ?? []
        guard !types.contains(Self.internalType) else { return }
        guard !Self.sensitiveTypes.contains(where: { types.contains($0) }) else { return }

        capture(from: pasteboard)
        scheduleSave()
    }

    private func capture(from pasteboard: NSPasteboard) {
        let types = pasteboard.types ?? []
        // 1. 文件优先（多选整批入库；text 存首个路径，完整列表在 filePaths）
        if let fileURLs = readFileURLs(from: pasteboard), !fileURLs.isEmpty {
            store.insert(
                kind: .file,
                text: fileURLs.first?.path ?? "",
                filePaths: fileURLs.map(\.path)
            )
            return
        }

        // 2. 图片（记录像素尺寸）
        if types.contains(.png) || types.contains(.tiff) {
            if let imageData = readImageData(from: pasteboard) {
                let name = writeBlob(imageData)
                let size = imagePixelSize(imageData)
                store.insert(kind: .image, text: "", imagePath: name, imageSize: size)
                return
            }
        }

        // 3. 文本
        if let text = pasteboard.pasteboardItems?.first?.string(forType: .string),
           !text.isEmpty {
            store.insert(kind: .text, text: text)
        }
    }

    /// 读取文件 URL；非文件内容返回 nil（走文本分支）。
    /// 易失目录下的文件被拒绝——返回 nil 让文本分支决定去留。
    private func readFileURLs(from pasteboard: NSPasteboard) -> [URL]? {
        guard let items = pasteboard.pasteboardItems else { return nil }
        var urls: [URL] = []
        for item in items.prefix(Self.maxCapturedFiles) {
            guard let data = item.data(forType: .fileURL),
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { continue }
            if isVolatile(url) { continue }
            urls.append(url)
        }
        return urls.isEmpty ? nil : urls
    }

    private func isVolatile(_ url: URL) -> Bool {
        let path = url.path
        let volatileRoots = [
            "/tmp/", "/private/tmp/", "/var/folders/",
            NSHomeDirectory() + "/Library/Caches/",
            NSTemporaryDirectory(),
        ]
        return volatileRoots.contains { path.hasPrefix($0) }
    }

    private func readImageData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        if let tiff = pasteboard.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        return nil
    }

    /// 图片像素尺寸（"1024×768"）。
    private func imagePixelSize(_ data: Data) -> String? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return "\(rep.pixelsWide)×\(rep.pixelsHigh)"
    }

    /// 把图片写进 blob 目录，返回相对文件名。
    private func writeBlob(_ data: Data) -> String? {
        guard let blobsURL else { return nil }
        try? FileManager.default.createDirectory(at: blobsURL, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".png"
        do {
            try data.write(to: blobsURL.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    /// 防抖落盘：0.8s 内多次捕获合并为一次写。
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = store.items
        let directory = blobsURL?.deletingLastPathComponent()
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            guard let directory else { return }
            let manifestURL = directory.appendingPathComponent("items.json")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(snapshot) {
                try? data.write(to: manifestURL, options: .atomic)
            }
        }
    }

    // MARK: - 自有写入（复制动作 / 粘贴回注）

    /// 写入系统粘贴板并打内部标记，跳过自身捕获。
    func writeToSystemPasteboard(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([Self.internalType, .string], owner: nil)
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    func writeToSystemPasteboard(imagePath: String) {
        guard let blobsURL,
              let image = NSImage(contentsOf: blobsURL.appendingPathComponent(imagePath)),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([Self.internalType, .png], owner: nil)
        pasteboard.setData(png, forType: .png)
        lastChangeCount = pasteboard.changeCount
    }

    func writeToSystemPasteboard(filePaths: [String]) {
        let urls = filePaths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) as NSURL }
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([Self.internalType, .fileURL], owner: nil)
        pasteboard.writeObjects(urls)
        lastChangeCount = pasteboard.changeCount
    }

    /// 当前剪贴板文本（快捷链接 {clipboard} 用）。
    var currentText: String? {
        NSPasteboard.general.string(forType: .string)
    }
}
