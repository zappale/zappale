import AppKit
import AudioToolbox
import Foundation
import ZappaleCore

/// 系统动作执行器。只做"执行"；"是否确认"由面板协调层负责，
/// 因此这里保持可单测的薄封装。
@MainActor
enum SystemActionRunner {

    enum Outcome {
        case done
        case failed(String)
    }

    static func run(_ id: SystemActionID) -> Outcome {
        switch id {
        case .lockScreen: appleScript(#"tell application "loginwindow" to «event aevtrlgo»"#)
        case .sleep: shell("/usr/bin/pmset", "sleepnow")
        case .displaySleep: shell("/usr/bin/pmset", "displaysleepnow")
        case .startScreenSaver: startScreenSaver()
        case .restart: appleScript(#"tell application "System Events" to restart"#)
        case .shutdown: appleScript(#"tell application "System Events" to shut down"#)
        case .emptyTrash: appleScript(#"tell application "Finder" to empty trash"#)
        case .quitAllApps: quitAllApps()
        case .toggleAppearance:
            appleScript(
                #"tell application "System Events" to tell appearance preferences to set dark mode to not dark mode"#
            )
        case .toggleHiddenFiles: toggleHiddenFiles()
        case .toggleMute: setMute(toggle: true)
        case .volumeUp: adjustVolume(+0.125)
        case .volumeDown: adjustVolume(-0.125)
        case .restartFinder: shell("/usr/bin/killall", "Finder")
        case .restartDock: shell("/usr/bin/killall", "Dock")
        case .newNote: .done // 新建笔记由面板协调层打开编辑器，不进 Runner
        case .windowLeft, .windowRight, .windowTop, .windowBottom,
             .windowTopLeft, .windowTopRight, .windowBottomLeft, .windowBottomRight,
             .windowLeftTwoThirds, .windowRightTwoThirds,
             .windowCenter, .windowMaximize, .windowAlmostMaximize, .windowRestore,
             .windowNextDisplay, .windowPrevDisplay:
            .done // 窗口动作由面板协调层走 AX 服务，不进 Runner
        case .aiTranslate, .aiPolish, .aiSummarize:
            .done // AI 快捷动作由面板协调层处理，不进 Runner
        }
    }

    // MARK: - 基础执行

    private static func appleScript(_ source: String) -> Outcome {
        var errorInfo: NSDictionary?
        let script = NSAppleScript(source: source)
        _ = script?.executeAndReturnError(&errorInfo)
        if let errorInfo, let message = errorInfo[NSAppleScript.errorMessage] as? String {
            return .failed(message)
        }
        return .done
    }

    private static func shell(_ path: String, _ arguments: String...) -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
            return .done
        } catch {
            return .failed("\((path as NSString).lastPathComponent): \(error.localizedDescription)")
        }
    }

    private static func startScreenSaver() -> Outcome {
        let engineURL = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        if FileManager.default.fileExists(atPath: engineURL.path) {
            NSWorkspace.shared.openApplication(
                at: engineURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
            return .done
        }
        return .failed("找不到屏幕保护引擎")
    }

    private static func quitAllApps() -> Outcome {
        let ownBundle = Bundle.main.bundleIdentifier
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isTerminated
              && app.bundleIdentifier != ownBundle && app.bundleIdentifier != "com.apple.finder" {
            app.terminate()
        }
        return .done
    }

    private static func toggleHiddenFiles() -> Outcome {
        let read = Process()
        read.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        read.arguments = ["read", "com.apple.finder", "AppleShowAllFiles"]
        let pipe = Pipe()
        read.standardOutput = pipe
        read.standardError = FileHandle.nullDevice
        do { try read.run(); read.waitUntilExit() } catch {
            return .failed("无法读取 Finder 设置")
        }
        let current = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
        let next = (current == "1") ? "0" : "1"
        let write = shell("/usr/bin/defaults", "write", "com.apple.finder", "AppleShowAllFiles", "-bool", next)
        guard case .done = write else { return write }
        return shell("/usr/bin/killall", "Finder")
    }

    // MARK: - CoreAudio

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        return status == noErr ? deviceID : nil
    }

    private static func volumeScalar(on device: AudioDeviceID, channel: UInt32) -> Float32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: channel
        )
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private static func setVolumeScalar(on device: AudioDeviceID, channel: UInt32, value: Float32) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: channel
        )
        guard AudioObjectHasProperty(device, &address) else { return false }
        var mutable = value
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &mutable)
        return status == noErr
    }

    private static func isMuted(on device: AudioDeviceID) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value == 1 : nil
    }

    private static func setMuteState(on device: AudioDeviceID, muted: Bool) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return false }
        var value = muted ? UInt32(1) : UInt32(0)
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        return status == noErr
    }

    /// 静音切换。返回文案供提示。
    private static func setMute(toggle: Bool) -> Outcome {
        guard let device = defaultOutputDevice() else { return .failed("找不到输出设备") }
        guard let muted = isMuted(on: device) else {
            return .failed("当前设备不支持静音控制")
        }
        let target = toggle ? !muted : muted
        return setMuteState(on: device, muted: target) ? .done : .failed("设置静音失败")
    }

    private static func adjustVolume(_ delta: Float32) -> Outcome {
        guard let device = defaultOutputDevice() else { return .failed("找不到输出设备") }
        // 取左右声道当前值的最大者作为基准
        let channels: [UInt32] = [0, 1]
        let current = channels
            .compactMap { volumeScalar(on: device, channel: $0) }
            .max() ?? 0
        let target = min(max(current + delta, 0), 1)
        // 静音状态下调节音量先取消静音
        if target > 0, isMuted(on: device) == true {
            _ = setMuteState(on: device, muted: false)
        }
        var succeeded = false
        for channel in channels {
            succeeded = setVolumeScalar(on: device, channel: channel, value: target) || succeeded
        }
        return succeeded ? .done : .failed("当前设备不支持音量调节")
    }
}
