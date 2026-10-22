import Foundation

/// 一次余额查询的原始返回
struct BalanceResponse: Sendable {
    var httpStatus: Int
    var body: String
    /// 网络层就失败了（连不上、超时、证书……），此时 httpStatus 是 0
    var error: String?
    var latencyMS: Int
}

/// 余额查询的请求层。
///
/// 刻意做得很薄：拼 header、发出去、把网络错误翻译成人话。不做重试、不记日志、
/// 不落盘——key 只在这一次请求的内存里存在。
enum BalanceHTTP {

    static func fetch(provider: BalanceProvider, key: String) async -> BalanceResponse {
        guard let endpoint = provider.effectiveEndpoint else {
            return BalanceResponse(httpStatus: 0, body: "", error: "这家没有配置可调用的接口", latencyMS: 0)
        }
        guard let url = endpoint.url(base: provider.baseURL, key: key, auth: provider.auth) else {
            return BalanceResponse(httpStatus: 0, body: "", error: "请求地址拼不出来，检查一下地址有没有写错", latencyMS: 0)
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.uppercased()
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SeraphimTools/1.0", forHTTPHeaderField: "User-Agent")

        if provider.auth == .bearer {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        } else if provider.auth == .xApiKey {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        }
        for (name, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        for (name, value) in provider.extraHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.waitsForConnectivity = false

        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let started = Date()
        do {
            let (data, response) = try await session.data(for: request)
            let latency = Int(Date().timeIntervalSince(started) * 1000)
            let http = response as? HTTPURLResponse
            return BalanceResponse(
                httpStatus: http?.statusCode ?? 0,
                body: String(data: data, encoding: .utf8) ?? "",
                error: nil,
                latencyMS: latency
            )
        } catch {
            let latency = Int(Date().timeIntervalSince(started) * 1000)
            return BalanceResponse(
                httpStatus: 0,
                body: "",
                error: friendly(error, provider: provider),
                latencyMS: latency
            )
        }
    }

    /// 网络错误翻译。比通用的那套多一层：这是个要连国外接口的工具场景，
    /// 连不上时最可能的原因就是没开代理，所以直接把这句说出来。
    /// 但本机 / 内网地址不在此列——给 localhost 提「开代理」是驴唇不对马嘴。
    static func friendly(_ error: Error, provider: BalanceProvider) -> String {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return error.localizedDescription }

        if isLocal(provider) {
            switch nsError.code {
            case NSURLErrorTimedOut:
                return "超时：15 秒内没响应（-1001）。本机地址超时，多半是那个服务卡住了"
            case NSURLErrorCannotConnectToHost:
                return "连不上本机服务（-1004）：确认这个端口上的服务起来没有、端口号对不对"
            case NSURLErrorCannotFindHost:
                return "localhost 都解析不出来（-1003）：本机 hosts 配置有问题"
            case NSURLErrorNotConnectedToInternet:
                return "当前没有网络连接（-1009）"
            default:
                return "本机请求失败（\(nsError.code)）：\(nsError.localizedDescription)"
            }
        }

        let hint = "（\(provider.name) 在国内直连可能不通，用工具箱里的 v2ray 开一下代理再试）"

        switch nsError.code {
        case NSURLErrorTimedOut:
            return "超时：15 秒内没响应（-1001）\(hint)"
        case NSURLErrorCannotFindHost:
            return "域名解析失败（-1003）：域名没解析出来，可能是 DNS 或代理的问题\(hint)"
        case NSURLErrorDNSLookupFailed:
            return "DNS 查询失败（-1006）\(hint)"
        case NSURLErrorCannotConnectToHost:
            return "连不上主机（-1004）\(hint)"
        case NSURLErrorNetworkConnectionLost:
            return "连接中途断了（-1005），重试一次看看"
        case NSURLErrorNotConnectedToInternet:
            return "当前没有网络连接（-1009）"
        case NSURLErrorSecureConnectionFailed:
            return "TLS 握手失败（-1200）：中间可能有东西在拦 HTTPS\(hint)"
        case NSURLErrorServerCertificateUntrusted:
            return "证书不被信任（-1202）：如果是自建中转站、用的自签证书，系统不认"
        case NSURLErrorServerCertificateHasBadDate:
            return "证书已过期或还没生效（-1201）"
        case NSURLErrorHTTPTooManyRedirects:
            return "重定向次数过多（-1007）：地址可能填错了"
        case NSURLErrorCancelled:
            return "请求已取消（-999）"
        case NSURLErrorBadURL, NSURLErrorUnsupportedURL:
            return "地址不合法（\(nsError.code)）：检查一下有没有多空格或者少了 https://"
        case NSURLErrorAppTransportSecurityRequiresSecureConnection:
            return "被 ATS 拦下了（-1022）：这个明文 HTTP 地址需要放开系统限制"
        default:
            return "网络错误（\(nsError.code)）：\(nsError.localizedDescription)\(hint)"
        }
    }

    /// 是不是本机 / 内网地址。判断依据是 baseURL 和两个端点里能解析出 host 的那些。
    static func isLocal(_ provider: BalanceProvider) -> Bool {
        let texts = [
            provider.baseURL,
            provider.balance?.path ?? "",
            provider.probe?.path ?? "",
        ]
        for text in texts {
            guard let host = URL(string: text)?.host else { continue }
            if host == "localhost" || host.hasPrefix("127.")
                || host.hasPrefix("10.") || host.hasPrefix("192.168.")
                || host.hasPrefix("172.16.") || host.hasPrefix("172.31.") || host == "::1" {
                return true
            }
        }
        return false
    }
}
