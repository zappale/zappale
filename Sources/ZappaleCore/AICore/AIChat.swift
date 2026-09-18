import Foundation

/// 一条对话消息。images 为关联图片文件路径（发送的附件或生成的结果）。
public struct AIChatMessage: Codable, Hashable {
    public let role: String // "user" / "assistant"
    public let content: String
    public init(role: String, content: String, images: [String]? = nil) {
        self.role = role
        self.content = content
        self.images = images
    }

    public var images: [String]? = nil
}

/// SSE 流事件。
public enum AIStreamEvent: @unchecked Sendable {
    case delta(String)
    case done
    case failed(String)
}

extension AIClient {

    /// 流式对话。SSE 逐行解析：OpenAI 兼容（delta.content）与
    /// Anthropic（content_block_delta.delta.text）两种格式。
    /// onEvent 在后台线程回调；UI 层自行切主线程。
    public func streamChat(
        messages: [AIChatMessage],
        systemPrompt: String? = nil,
        /// 附在最后一条用户消息上的图片（图片识别用）。
        image: (data: Data, mime: String)? = nil,
        onEvent: @escaping (AIStreamEvent) -> Void
    ) async {
        guard AIEndpointPolicy.validate(connection.endpoint) else {
            onEvent(.failed(AIError.invalidEndpoint.localizedDescription))
            return
        }

        var request = URLRequest(url: connection.endpoint.appendingPathComponent(chatPath))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let body: [String: Any]
        switch connection.provider {
        case .openAICompatible:
            request.setValue("Bearer \(apiKey ?? "")", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var payloadMessages: [[String: Any]] =
                messages.map { ["role": $0.role, "content": $0.content] }
            if let systemPrompt {
                payloadMessages.insert(["role": "system", "content": systemPrompt], at: 0)
            }
            if let image, let lastIndex = payloadMessages.lastIndex(where: { $0["role"] as? String == "user" }) {
                let text = payloadMessages[lastIndex]["content"] as? String ?? ""
                let content = Self.buildUserContent(
                    text: text, imageData: image.data,
                    imageMIME: image.mime, provider: .openAICompatible
                )
                payloadMessages[lastIndex] = [
                    "role": "user",
                    "content": Self.openAIContentParts(content),
                ]
            }
            body = [
                "model": connection.model,
                "messages": payloadMessages,
                "stream": true,
            ]
        case .anthropic:
            request.setValue(apiKey ?? "", forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var payloadMessages: [[String: Any]] =
                messages.map { ["role": $0.role, "content": [$0.content]] }
            if let image, let lastIndex = payloadMessages.lastIndex(where: { $0["role"] as? String == "user" }) {
                let text = messages[lastIndex].content
                let content = Self.buildUserContent(
                    text: text, imageData: image.data,
                    imageMIME: image.mime, provider: .anthropic
                )
                payloadMessages[lastIndex] = [
                    "role": "user",
                    "content": Self.anthropicContentBlocks(content),
                ]
            }
            var payload: [String: Any] = [
                "model": connection.model,
                "max_tokens": 4096,
                "messages": payloadMessages,
                "stream": true,
            ]
            if let systemPrompt {
                payload["system"] = systemPrompt
            }
            body = payload
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                onEvent(.failed(AIError.badResponse.localizedDescription))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                var text = ""
                for try await line in bytes.lines {
                    text += line
                    if text.count > 300 { break }
                }
                onEvent(.failed(AIError.http(status: http.statusCode, body: text).localizedDescription))
                return
            }

            for try await line in bytes.lines {
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" {
                    onEvent(.done)
                    return
                }
                guard let data = payload.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }
                if let text = Self.extractDelta(json, provider: connection.provider) {
                    if !text.isEmpty { onEvent(.delta(text)) }
                }
                // Anthropic: message_stop 事件
                if json["type"] as? String == "message_stop" {
                    onEvent(.done)
                    return
                }
                // OpenAI 兼容：finish_reason 出现即接近完成，等待 [DONE]
            }
            // 流结束仍未显式 done（部分网关不发 [DONE]）
            onEvent(.done)
        } catch {
            onEvent(.failed(error.localizedDescription))
        }
    }

    private var chatPath: String {
        switch connection.provider {
        case .openAICompatible: return "chat/completions"
        case .anthropic: return "messages"
        }
    }

    /// 从 SSE JSON 中抽取增量文本。
    public static func extractDelta(_ json: [String: Any], provider: AIProviderKind) -> String? {
        switch provider {
        case .openAICompatible:
            guard let choices = json["choices"] as? [[String: Any]],
                  let choice = choices.first else { return nil }
            if let delta = choice["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                return content
            }
            if let message = choice["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            }
            return nil
        case .anthropic:
            guard let type = json["type"] as? String else { return nil }
            if type == "content_block_delta",
               let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                return text
            }
            return nil
        }
    }
}
