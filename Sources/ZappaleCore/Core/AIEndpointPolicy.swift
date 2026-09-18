import Foundation

/// Endpoint 安全策略（借鉴 tinycast 的不变量）：
/// 远程端点必须 HTTPS；明文 HTTP 仅接受 loopback 主机；
/// 其他 scheme 一律拒绝——loopback 也不豁免 ftp:// 之类的怪东西。
public enum AIEndpointPolicy {
    public static func validate(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased() else { return false }
        switch scheme {
        case "https":
            return true
        case "http":
            return ["localhost", "127.0.0.1", "::1"].contains(host)
        default:
            return false
        }
    }

    public static func validate(_ text: String) -> Bool {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.host != nil else { return false }
        return validate(url)
    }
}
