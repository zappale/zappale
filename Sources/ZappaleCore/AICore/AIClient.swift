import Foundation

/// 一条模型服务连接。key 不在其中——永远按账户名去 Keychain 取。
public struct AIConnection: Hashable {
    public var provider: AIProviderKind
    public var endpoint: URL
    public var model: String

    public init(provider: AIProviderKind, endpoint: URL, model: String) {
        self.provider = provider
        self.endpoint = endpoint
        self.model = model
    }
}

public enum AIError: LocalizedError {
    case invalidEndpoint
    case badResponse
    case http(status: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "API 地址无效：远程端点必须为 HTTPS（仅 loopback 允许 HTTP）"
        case .badResponse:
            return "服务端返回了无法识别的响应"
        case .http(let status, let body):
            let snippet = body.isEmpty ? "" : "：\(body)"
            return "服务端返回 HTTP \(status)\(snippet)"
        }
    }
}

/// M1 阶段的客户端：只做连通性测试。M2 在此之上加 chat completions + 工具循环。
public struct AIClient {
    public var connection: AIConnection
    public var apiKey: String?

    public init(connection: AIConnection, apiKey: String?) {
        self.connection = connection
        self.apiKey = apiKey
    }

    /// 测试连通性，返回可用模型数量。
    public func testConnection() async throws -> Int {
        guard AIEndpointPolicy.validate(connection.endpoint) else {
            throw AIError.invalidEndpoint
        }

        var request = URLRequest(url: connection.endpoint.appendingPathComponent("models"))
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        switch connection.provider {
        case .openAICompatible:
            request.setValue("Bearer \(apiKey ?? "")", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(apiKey ?? "", forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }

        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.http(
                status: http.statusCode,
                body: String(data: data.prefix(300), encoding: .utf8) ?? ""
            )
        }

        struct ModelsResponse: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.data.count
    }
}
