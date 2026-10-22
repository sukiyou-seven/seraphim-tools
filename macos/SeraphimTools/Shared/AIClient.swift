import Foundation

// MARK: - AI 驱动的厂商目录
//
// 「AI 驱动」开关打开后，提示词 / 原型助手的生成结果走这里调大模型 API。
// 厂商只收 OpenAI 兼容的 chat completions——这几家的 key 都能在「API 余额」
// 工具里填，这边直接读同一个钥匙串（service = SeraphimTools.balance），
// 用户不需要填第二次。

struct AIProviderOption: Identifiable, Hashable, Sendable {
    /// 与「API 余额」工具里的 provider id 一致，钥匙串按这个对上
    let id: String
    let name: String
    /// chat completions 完整 URL
    let endpoint: String
    /// 预置模型列表。列表可能过时，界面上永远允许手输模型 ID
    let models: [String]
}

enum AICatalog {
    static let chatProviders: [AIProviderOption] = [
        AIProviderOption(
            id: "deepseek",
            name: "DeepSeek",
            endpoint: "https://api.deepseek.com/chat/completions",
            models: ["deepseek-chat", "deepseek-reasoner"]
        ),
        AIProviderOption(
            id: "moonshot",
            name: "Kimi",
            endpoint: "https://api.moonshot.cn/v1/chat/completions",
            models: ["kimi-k2-0905-preview", "kimi-latest", "moonshot-v1-128k"]
        ),
        AIProviderOption(
            id: "siliconflow",
            name: "硅基流动",
            endpoint: "https://api.siliconflow.cn/v1/chat/completions",
            models: ["deepseek-ai/DeepSeek-V3.2-Exp", "Qwen/Qwen3-235B-A22B-Instruct", "Qwen/Qwen2.5-72B-Instruct"]
        ),
        AIProviderOption(
            id: "openrouter",
            name: "OpenRouter",
            endpoint: "https://openrouter.ai/api/v1/chat/completions",
            models: ["openrouter/auto", "anthropic/claude-sonnet-4.5", "openai/gpt-4o", "google/gemini-2.5-flash"]
        ),
        AIProviderOption(
            id: "zhipu",
            name: "智谱 GLM",
            endpoint: "https://open.bigmodel.cn/api/paas/v4/chat/completions",
            models: ["glm-4.6", "glm-4.5-air", "glm-4-flash"]
        ),
        AIProviderOption(
            id: "ppio",
            name: "PPIO 派欧云",
            endpoint: "https://api.ppinfra.com/v3/openai/chat/completions",
            models: ["qwen/qwen3-32b", "deepseek/deepseek-v3-community"]
        ),
    ]

    static func option(id: String) -> AIProviderOption? {
        chatProviders.first { $0.id == id }
    }
}

// MARK: - 全局配置（AppStorage 键的规范名）

/// 「AI 驱动」是全局配置：在哪个工具里开，所有接了它的工具都跟着开。
enum AIDriveKeys {
    static let enabled = "aiDriveEnabled"
    static let providerID = "aiProviderID"
    static let model = "aiModel"
}

// MARK: - 客户端

enum AIClient {

    enum AIError: LocalizedError {
        case noKey(providerName: String)
        case http(status: Int, body: String)
        case emptyContent
        case network(String)

        var errorDescription: String? {
            switch self {
            case .noKey(let name):
                return "\(name) 还没填 key。去「API 余额」工具把这家的 key 填上，回来直接用。"
            case .http(let status, let body):
                switch status {
                case 401, 403:
                    return "key 无效或没权限（\(status)）。去「API 余额」工具检查这家的 key 是否填对。"
                case 402:
                    return "账户余额不足（402）。去这家厂商的控制台充值，或换一家有余额的。"
                case 404:
                    return "接口或模型不存在（404）。多半是模型 ID 写错了，换一个或照官方文档手输。"
                case 429:
                    return "被限流了（429），等一会儿再试，或换个模型。"
                case 500...599:
                    return "服务端出错（\(status)），厂商那边的问题，稍后再试。"
                default:
                    let snippet = body.prefix(160)
                    return "请求失败（HTTP \(status)）：\(snippet)"
                }
            case .emptyContent:
                return "模型返回了空内容。换个模型或把需求写具体一点再试。"
            case .network(let message):
                return message
            }
        }
    }

    // MARK: key

    /// 这家有没有填过 key。钥匙串读的是子进程，必须丢后台。
    static func keyExists(for providerID: String) async -> Bool {
        let key = await apiKey(for: providerID)
        return key != nil
    }

    /// 取 key（返回 nil = 没填）。跟「API 余额」共用一个钥匙串 service。
    static func apiKey(for providerID: String) async -> String? {
        let service = "SeraphimTools.balance"
        let account = providerID
        return await Task.detached(priority: .userInitiated) {
            let value = Keychain.value(service: service, account: account) ?? ""
            return value.isEmpty ? nil : value
        }.value
    }

    // MARK: 配置解析

    struct ResolvedConfig {
        let provider: AIProviderOption
        let model: String
        let apiKey: String
    }

    /// 从全局 AppStorage 读出厂商与模型，顺手验 key。
    /// key 没填直接抛 .noKey——界面上的按钮爱点就点，能不能跑由这里说了算。
    static func resolveConfig(defaults: UserDefaults = .standard) async throws -> ResolvedConfig {
        let providerID = defaults.string(forKey: AIDriveKeys.providerID) ?? "deepseek"
        guard let provider = AICatalog.option(id: providerID) else {
            throw AIError.noKey(providerName: providerID)
        }
        var model = defaults.string(forKey: AIDriveKeys.model) ?? ""
        if model.isEmpty || !provider.models.contains(model) {
            // 模型键是全局的，换厂商后旧模型 ID 大概率对不上，落回列表第一个
            model = provider.models.first ?? ""
        }
        guard !model.isEmpty else {
            throw AIError.http(status: 404, body: "没有可用模型")
        }
        guard let key = await apiKey(for: provider.id) else {
            throw AIError.noKey(providerName: provider.name)
        }
        return ResolvedConfig(provider: provider, model: model, apiKey: key)
    }

    // MARK: 对话

    struct Message: Sendable {
        let role: String
        let content: String
    }

    static func chat(
        provider: AIProviderOption,
        model: String,
        messages: [Message],
        temperature: Double = 0.7,
        maxTokens: Int = 4096
    ) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": temperature,
            "max_tokens": maxTokens,
            "stream": false,
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else {
            throw AIError.http(status: 0, body: "请求体构造失败")
        }
        let key = await apiKey(for: provider.id) ?? ""

        var request = URLRequest(url: URL(string: provider.endpoint) ?? URL(fileURLWithPath: "/dev/null"))
        request.httpMethod = "POST"
        request.httpBody = payload
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIError.network(friendlyNetworkError(error))
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw AIError.http(status: status, body: text)
        }

        // choices[0].message.content；有的厂商失败也回 200 + error 对象，一并兜住
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let apiError = object["error"] as? [String: Any] {
            let message = apiError["message"] as? String ?? "未知错误"
            throw AIError.http(status: 0, body: message)
        }
        guard let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw AIError.emptyContent
        }
        return content
    }

    /// 便捷入口：system + 单条 user
    static func complete(
        provider: AIProviderOption,
        model: String,
        system: String,
        user: String,
        temperature: Double = 0.7,
        maxTokens: Int = 4096
    ) async throws -> String {
        try await chat(
            provider: provider,
            model: model,
            messages: [Message(role: "system", content: system), Message(role: "user", content: user)],
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    // MARK: 工具

    /// 模型爱把答案包进 ``` 围栏里（尤其是要代码的时候），剥掉外层围栏
    static func stripCodeFence(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return text }
        // 掉第一行（```mermaid 之类）和最后一行
        var lines = trimmed.components(separatedBy: "\n")
        lines.removeFirst()
        if let last = lines.last, last.trimmingCharacters(in: .whitespaces) == "```" {
            lines.removeLast()
        }
        trimmed = lines.joined(separator: "\n")
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func friendlyNetworkError(_ error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return error.localizedDescription }
        switch nsError.code {
        case NSURLErrorTimedOut:
            return "超时（120 秒没等到回复）。模型可能太慢，换个快的模型再试。"
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return "域名解析失败。国外厂商（OpenRouter 等）可能需要开代理。"
        case NSURLErrorCannotConnectToHost:
            return "连不上主机。国外厂商可能需要开代理（工具箱里的 v2ray）。"
        case NSURLErrorNotConnectedToInternet:
            return "当前没有网络连接。"
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
            return "TLS 握手失败或证书不受信任。"
        case NSURLErrorCancelled:
            return "请求已取消。"
        default:
            return "网络错误（\(nsError.code)）：\(nsError.localizedDescription)"
        }
    }
}
