import Foundation
import ZappaleCore

/// 命令执行器：/bin/zsh -c，后台线程，超时保护，输出截取。
enum CustomCommandRunner {
    struct Outcome {
        let exitCode: Int32
        let output: String
        var succeeded: Bool { exitCode == 0 }
    }

    static let timeout: TimeInterval = 10

    static func run(_ script: String) async -> Outcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", script]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: Outcome(
                        exitCode: 127,
                        output: L10n.t("无法启动：", "Failed to start: ") + error.localizedDescription
                    ))
                    return
                }

                // 超时强杀
                let killTimer = DispatchWorkItem {
                    if process.isRunning {
                        process.terminate()
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killTimer)
                process.waitUntilExit()
                killTimer.cancel()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                var text = String(data: data, encoding: .utf8) ?? ""
                if text.count > 2000 { text = String(text.prefix(2000)) + "…"
                }
                continuation.resume(returning: Outcome(exitCode: process.terminationStatus, output: text))
            }
        }
    }
}
