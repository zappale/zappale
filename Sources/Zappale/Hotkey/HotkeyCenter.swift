import Carbon.HIToolbox
import Foundation
import ZappaleCore

// MARK: - 热键中心

/// Carbon 全局热键：一次安装处理器，多组绑定按 id 分发。
/// 回调由 HIToolbox 在主 runloop 投递，onTrigger 统一跳回主队列。
final class HotkeyCenter {
    enum HotkeyError: LocalizedError, Equatable {
        case installHandlerFailed(OSStatus)
        case registerFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .installHandlerFailed(let s): return "热键事件处理器安装失败（\(s)）"
            case .registerFailed(let s):
                return s == -9878 // hotKeyExistsErr
                    ? "该快捷键已被其他应用或本应用其他功能占用"
                    : "热键注册失败（\(s)）"
            }
        }
    }

    /// 触发回调（主线程）。参数是绑定 id，如 "palette"、"clipboard"、"app:/Applications/Safari.app"。
    var onTrigger: ((String) -> Void)?

    private var handlerRef: EventHandlerRef?
    /// 签名固定，EventHotKeyID.id 用绑定序号。
    private let signature: OSType = 0x5A_41_50_50 // 'ZAPP'
    private var bindings: [HotkeyBinding] = []
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private let queue = DispatchQueue(label: "dev.zappale.hotkey", qos: .userInteractive)

    deinit {
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
        for ref in hotKeyRefs where ref != nil {
            _ = ref.map { UnregisterEventHotKey($0) }
        }
    }

    /// 安装事件处理器。幂等；应用启动时调用一次。
    func installHandler() throws {
        guard handlerRef == nil else { return }
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
        ]

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
            center.dispatch()
            return noErr
        }

        var ref: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventTypes,
            selfPointer,
            &ref
        )
        guard status == noErr, let ref else {
            throw HotkeyError.installHandlerFailed(status)
        }
        handlerRef = ref
    }

    /// 全量重设绑定：注销旧的全部，注册新的全部。
    /// 返回注册失败的绑定及错误（其余仍生效）。
    @discardableResult
    func rebind(_ incoming: [HotkeyBinding]) -> [(HotkeyBinding, HotkeyError)] {
        for ref in hotKeyRefs.compactMap({ $0 }) {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs = []
        self.bindings = []

        guard handlerRef != nil else { return [] }

        var failures: [(HotkeyBinding, HotkeyError)] = []
        for (index, binding) in incoming.enumerated() {
            let id = EventHotKeyID(signature: signature, id: UInt32(index + 1))
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                binding.spec.keyCode,
                binding.spec.carbonModifiers,
                id,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr {
                hotKeyRefs.append(ref)
                self.bindings.append(binding)
            } else {
                failures.append((binding, .registerFailed(status)))
            }
        }
        return failures
    }

    private func dispatch() {
        let event = GetCurrentEvent()
        guard event != nil else { return }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return }
        let index = Int(hotKeyID.id) - 1
        guard bindings.indices.contains(index) else { return }
        let id = bindings[index].id
        DispatchQueue.main.async { [weak self] in
            self?.onTrigger?(id)
        }
    }
}
