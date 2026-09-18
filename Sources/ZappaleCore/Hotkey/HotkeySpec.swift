import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(Carbon.HIToolbox)
import Carbon.HIToolbox
#endif

/// Carbon 修饰键位掩码（跨平台常量；Carbon 框架仅 macOS 可用，这里用裸值）。
public enum CarbonModifierFlags {
    public static let command: UInt32 = 0x0100  // cmdKey
    public static let shift: UInt32 = 0x0200    // shiftKey
    public static let option: UInt32 = 0x0800   // optionKey
    public static let control: UInt32 = 0x1000  // controlKey
}

// MARK: - 热键描述

/// 一个热键的持久化描述：虚拟键码 + Carbon 修饰键位掩码 + 显示名。
/// 纯值类型，直接存 UserDefaults（JSON）。
public struct HotkeySpec: Codable, Hashable {
    public var keyCode: UInt32
    /// Carbon 修饰键：cmdKey | shiftKey | optionKey | controlKey
    public var carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// 出厂默认：⌥Space
    public static let defaultPalette = HotkeySpec(
        keyCode: 49, carbonModifiers: CarbonModifierFlags.option
    )

    /// 是否是可用的组合：至少一个功能修饰键（纯字母键会干扰正常打字）。
    public var isValid: Bool {
        let mask = CarbonModifierFlags.command | CarbonModifierFlags.shift
            | CarbonModifierFlags.option | CarbonModifierFlags.control
        return (carbonModifiers & mask) != 0
    }

    /// 显示文本，如 "⌥Space"、"⌘⇧G"。键名来自 NSEvent 字符或虚拟键码表。
    public var display: String {
        var text = ""
        if carbonModifiers & CarbonModifierFlags.control != 0 { text += "⌃" }
        if carbonModifiers & CarbonModifierFlags.option != 0 { text += "⌥" }
        if carbonModifiers & CarbonModifierFlags.shift != 0 { text += "⇧" }
        if carbonModifiers & CarbonModifierFlags.command != 0 { text += "⌘" }
        return text + Self.keyName(for: keyCode)
    }

    /// 虚拟键码 → 键名（HIToolbox 键码裸值，跨平台稳定）。
    public static func keyName(for keyCode: UInt32) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "↵"
        case 48: return "⇥"
        case 51: return "⌫"
        case 53: return "esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 115: return "↖"
        case 119: return "↘"
        case 116: return "⇞"
        case 121: return "⇟"
        case 122: return "F1"; case 120: return "F2"; case 99: return "F3"
        case 118: return "F4"; case 96: return "F5"; case 97: return "F6"
        case 98: return "F7"; case 100: return "F8"; case 101: return "F9"
        case 109: return "F10"; case 103: return "F11"; case 111: return "F12"
        default:
            return Self.translateKeyCode(keyCode) ?? "Key\(keyCode)"
        }
    }

    /// 用当前键盘布局把虚拟键码翻译成无修饰字符（仅 macOS；iOS 回退 Key<码>）。
    #if canImport(Carbon.HIToolbox)
    public static func translateKeyCode(_ keyCode: UInt32) -> String? {
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let layoutData = TISGetInputSourceProperty(
            TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue(),
            kTISPropertyUnicodeKeyLayoutData
        )
        guard let layoutData else { return nil }
        let cfData = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue()
        guard let keyboardLayout = CFDataGetBytePtr(cfData) else { return nil }
        let error = UCKeyTranslate(
            UnsafeRawPointer(keyboardLayout).assumingMemoryBound(to: UCKeyboardLayout.self),
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0, // 无修饰
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            4,
            &length,
            &characters
        )
        guard error == noErr, length > 0 else { return nil }
        let string = String(utf16CodeUnits: characters, count: length)
        return string.uppercased()
    }
    #else
    public static func translateKeyCode(_ keyCode: UInt32) -> String? { nil }
    #endif

    /// NSEvent 修饰键 → Carbon 修饰键（仅 macOS）。
    #if canImport(AppKit)
    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= CarbonModifierFlags.command }
        if flags.contains(.option) { result |= CarbonModifierFlags.option }
        if flags.contains(.control) { result |= CarbonModifierFlags.control }
        if flags.contains(.shift) { result |= CarbonModifierFlags.shift }
        return result
    }
    #endif

    /// 反向：Carbon → NSEvent（仅 macOS；UI 层修饰键高亮用）。
    #if canImport(AppKit)
    public var cocoaModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & CarbonModifierFlags.command != 0 { flags.insert(.command) }
        if carbonModifiers & CarbonModifierFlags.option != 0 { flags.insert(.option) }
        if carbonModifiers & CarbonModifierFlags.control != 0 { flags.insert(.control) }
        if carbonModifiers & CarbonModifierFlags.shift != 0 { flags.insert(.shift) }
        return flags
    }
    #endif
}



/// 一条热键绑定：分发 id + 热键描述。平台无关（注册由 macOS 层完成）。
public struct HotkeyBinding {
    public let id: String
    public let spec: HotkeySpec
}
