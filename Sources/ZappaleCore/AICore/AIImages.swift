import Foundation

// MARK: - 多模态消息体构建（纯函数，可测）

extension AIClient {

    /// 构建带图片的用户消息 content。
    /// - OpenAI 兼容：[{type:text},{type:image_url,data URL}]
    /// - Anthropic：[{type:image,source base64},{type:text}]
    public static func buildUserContent(
        text: String,
        imageData: Data?,
        imageMIME: String?,
        provider: AIProviderKind
    ) -> [String: Any] {
        switch provider {
        case .openAICompatible:
            guard let imageData, let imageMIME else {
                return ["type": "text", "text": text]
            }
            let dataURL = "data:\(imageMIME);base64,\(imageData.base64EncodedString())"
            return ["parts": [
                ["type": "text", "text": text],
                ["type": "image_url", "image_url": ["url": dataURL]],
            ]]
        case .anthropic:
            guard let imageData, let imageMIME else {
                return ["type": "text", "text": text]
            }
            return ["blocks": [
                [
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": imageMIME,
                        "data": imageData.base64EncodedString(),
                    ],
                ],
                ["type": "text", "text": text],
            ]]
        }
    }

    /// 是否需要多模态包装（content 为数组）。
    public static func isMultimodal(_ content: [String: Any]) -> Bool {
        content.keys.contains("parts") || content.keys.contains("blocks")
    }

    /// OpenAI 兼容最终 content（数组形式）。
    public static func openAIContentParts(_ content: [String: Any]) -> [[String: Any]] {
        (content["parts"] as? [[String: Any]]) ?? [content]
    }

    /// Anthropic 最终 content blocks。
    public static func anthropicContentBlocks(_ content: [String: Any]) -> [[String: Any]] {
        (content["blocks"] as? [[String: Any]]) ?? [content]
    }
}

// MARK: - 生图 / 图生图

extension AIClient {

    public struct ImageGenerationError: LocalizedError {
        let message: String
        public var errorDescription: String? { message }
    }

    /// 生图响应解析（纯函数，可测）。返回 b64 数据或远程 URL。
    public static func parseImageResults(_ json: [String: Any]) -> [(base64: String?, url: String?)] {
        guard let items = json["data"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            let b64 = item["b64_json"] as? String
            let url = item["url"] as? String
            guard b64 != nil || url != nil else { return nil }
            return (b64, url)
        }
    }

    /// 文生图：POST images/generations。返回图片数据列表。
    public func generateImages(prompt: String) async throws -> [Data] {
        guard AIEndpointPolicy.validate(connection.endpoint) else {
            throw AIError.invalidEndpoint
        }
        guard connection.provider == .openAICompatible else {
            throw ImageGenerationError(
                message: L10n.t(
                    "当前服务类型暂不支持生图，请使用 OpenAI 兼容服务（如 gpt-image-1）",
                    "Image generation needs an OpenAI-compatible provider (e.g. gpt-image-1)"
                )
            )
        }

        var request = URLRequest(url: connection.endpoint.appendingPathComponent("images/generations"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(apiKey ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": connection.model,
            "prompt": prompt,
            "n": 1,
            "size": "1024x1024",
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return try await performImageRequest(request)
    }

    /// 图生图：multipart POST images/edits。
    public func editImage(prompt: String, imageData: Data, mime: String) async throws -> [Data] {
        guard AIEndpointPolicy.validate(connection.endpoint) else {
            throw AIError.invalidEndpoint
        }
        guard connection.provider == .openAICompatible else {
            throw ImageGenerationError(
                message: L10n.t(
                    "当前服务类型暂不支持图生图，请使用 OpenAI 兼容服务",
                    "Image editing needs an OpenAI-compatible provider"
                )
            )
        }

        let boundary = "zappale-\(UUID().uuidString)"
        var request = URLRequest(url: connection.endpoint.appendingPathComponent("images/edits"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(apiKey ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let ext = mime.contains("jpeg") ? "jpg" : "png"
        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        appendField("model", connection.model)
        appendField("prompt", prompt)
        appendField("n", "1")
        appendField("size", "1024x1024")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"input.\(ext)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8))
        body.append(imageData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        return try await performImageRequest(request)
    }

    private func performImageRequest(_ request: URLRequest) async throws -> [Data] {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw AIError.http(status: http.statusCode, body: body)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.badResponse
        }
        let results = Self.parseImageResults(json)
        guard !results.isEmpty else {
            throw ImageGenerationError(message: L10n.t("生图响应为空", "Empty image response"))
        }
        var images: [Data] = []
        for item in results {
            if let base64 = item.base64, let decoded = Data(base64Encoded: base64) {
                images.append(decoded)
            } else if let urlString = item.url, let url = URL(string: urlString) {
                let (downloaded, _) = try await session.data(from: url) // session 已失效？
                // 使用新临时会话下载（上面的 defer 在函数返回才生效，可用）
                images.append(downloaded)
            }
        }
        guard !images.isEmpty else {
            throw ImageGenerationError(message: L10n.t("未能取得图片数据", "No image data"))
        }
        return images
    }
}
