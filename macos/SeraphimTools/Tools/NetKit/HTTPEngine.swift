import Foundation
import UniformTypeIdentifiers

/// 简易 HTTP 请求器。
///
/// 用 URLSession，但不是"发出去拿到 body 就完事"：这里把每一段耗时（DNS / TCP / TLS / 等待 /
/// 下载）从 URLSessionTaskMetrics 里挖出来，还记录了每一跳重定向——调接口的时候这些数字比
/// 返回体更能说明问题。
enum HTTPEngine {

    // MARK: - 发送

    static func send(_ spec: HTTPRequestSpec) async -> HTTPExchange {
        let started = Date()
        let trimmed = spec.url.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return failure(spec: spec, url: "", message: "请先填请求地址", started: started)
        }
        guard let url = normalizeURL(trimmed) else {
            return failure(spec: spec, url: trimmed, message: "这个地址不合法", started: started)
        }

        var request = URLRequest(url: url)
        request.httpMethod = spec.method.uppercased()
        request.timeoutInterval = spec.timeout

        var appliedHeaders: [NetStringPair] = []
        for header in spec.headers where header.isEnabled {
            let name = header.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            request.setValue(header.value, forHTTPHeaderField: name)
            appliedHeaders.append(NetStringPair(name, header.value))
        }

        var bodyPreview = ""
        do {
            if let body = try makeBody(spec: spec) {
                request.httpBody = body.data
                bodyPreview = body.preview
                if let contentType = body.contentType, !appliedHeaders.contains(where: { $0.name.lowercased() == "content-type" }) {
                    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
                    appliedHeaders.append(NetStringPair("Content-Type", contentType))
                }
            }
        } catch {
            return failure(spec: spec, url: url.absoluteString, message: error.localizedDescription, started: started)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = spec.timeout
        configuration.timeoutIntervalForResource = max(60, spec.timeout * 2)
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.waitsForConnectivity = false

        let observer = HTTPTaskObserver(
            allowInsecure: spec.allowInsecureTLS,
            followRedirects: spec.followRedirects
        )
        let session = URLSession(configuration: configuration, delegate: observer, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        do {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            let contentType = http?.value(forHTTPHeaderField: "Content-Type") ?? ""
            let headers = (http?.allHeaderFields ?? [:])
                .compactMap { key, value -> NetStringPair? in
                    guard let name = key as? String else { return nil }
                    return NetStringPair(name, "\(value)")
                }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            var timings = observer.timings ?? HTTPTimings()
            if timings.total == nil {
                timings.total = Date().timeIntervalSince(started) * 1000
            }

            // 这里给原始文本，美化交给界面（用户可以切换看原文）
            let bodyText = decodeBody(data, contentType: contentType)

            return HTTPExchange(
                method: request.httpMethod ?? spec.method,
                url: url.absoluteString,
                finalURL: response.url?.absoluteString ?? url.absoluteString,
                requestHeaders: appliedHeaders,
                requestBodyPreview: bodyPreview,
                statusCode: http?.statusCode ?? 0,
                statusText: http.map { HTTPURLResponse.localizedString(forStatusCode: $0.statusCode) } ?? "无响应",
                responseHeaders: headers,
                bodyText: bodyText,
                bodyBytes: data.count,
                contentType: contentType,
                timings: timings,
                redirects: observer.redirects,
                failure: nil,
                startedAt: started
            )
        } catch {
            var timings = observer.timings ?? HTTPTimings()
            if timings.total == nil {
                timings.total = Date().timeIntervalSince(started) * 1000
            }
            return HTTPExchange(
                method: request.httpMethod ?? spec.method,
                url: url.absoluteString,
                finalURL: url.absoluteString,
                requestHeaders: appliedHeaders,
                requestBodyPreview: bodyPreview,
                statusCode: 0,
                statusText: "失败",
                responseHeaders: [],
                bodyText: "",
                bodyBytes: 0,
                contentType: "",
                timings: timings,
                redirects: observer.redirects,
                failure: NetErrorText.friendly(error),
                startedAt: started
            )
        }
    }

    private static func failure(spec: HTTPRequestSpec, url: String, message: String, started: Date) -> HTTPExchange {
        HTTPExchange(
            method: spec.method,
            url: url,
            finalURL: url,
            requestHeaders: [],
            requestBodyPreview: "",
            statusCode: 0,
            statusText: "未发送",
            responseHeaders: [],
            bodyText: "",
            bodyBytes: 0,
            contentType: "",
            timings: HTTPTimings(total: Date().timeIntervalSince(started) * 1000),
            redirects: [],
            failure: message,
            startedAt: started
        )
    }

    // MARK: - 地址

    static func normalizeURL(_ text: String) -> URL? {
        var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.isEmpty { return nil }
        if !candidate.lowercased().hasPrefix("http://"), !candidate.lowercased().hasPrefix("https://") {
            candidate = "http://" + candidate
        }
        guard let url = URL(string: candidate), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    // MARK: - 请求体

    private struct PreparedBody {
        let data: Data
        let contentType: String?
        let preview: String
    }

    private static func makeBody(spec: HTTPRequestSpec) throws -> PreparedBody? {
        switch spec.bodyMode {
        case .none:
            return nil

        case .json:
            let text = spec.rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return PreparedBody(
                data: Data(text.utf8),
                contentType: "application/json; charset=utf-8",
                preview: text
            )

        case .raw:
            let text = spec.rawBody
            guard !text.isEmpty else { return nil }
            return PreparedBody(data: Data(text.utf8), contentType: nil, preview: text)

        case .form:
            let fields = spec.formFields.filter { $0.isEnabled && !$0.name.isEmpty }
            guard !fields.isEmpty else { return nil }
            let encoded = fields
                .map { "\(formEncode($0.name))=\(formEncode($0.value))" }
                .joined(separator: "&")
            return PreparedBody(
                data: Data(encoded.utf8),
                contentType: "application/x-www-form-urlencoded; charset=utf-8",
                preview: encoded
            )

        case .multipart:
            let boundary = "----SeraphimToolsBoundary\(UUID().uuidString.prefix(12))"
            var data = Data()
            var summary: [String] = []

            for field in spec.formFields where field.isEnabled && !field.name.isEmpty {
                data.append(Data("--\(boundary)\r\n".utf8))
                data.append(Data("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n".utf8))
                data.append(Data("\(field.value)\r\n".utf8))
                summary.append("\(field.name)=\(field.value)")
            }

            for field in spec.fileFields where field.isEnabled && !field.name.isEmpty {
                let path = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !path.isEmpty else { continue }
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                guard let fileData = try? Data(contentsOf: url) else {
                    throw HTTPPreparationError.message("读不到文件：\(path)")
                }
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                data.append(Data("--\(boundary)\r\n".utf8))
                data.append(Data("Content-Disposition: form-data; name=\"\(field.name)\"; filename=\"\(url.lastPathComponent)\"\r\n".utf8))
                data.append(Data("Content-Type: \(mime)\r\n\r\n".utf8))
                data.append(fileData)
                data.append(Data("\r\n".utf8))
                summary.append("\(field.name)=@\(url.lastPathComponent) (\(fileData.count) 字节, \(mime))")
            }

            data.append(Data("--\(boundary)--\r\n".utf8))
            guard !summary.isEmpty else { return nil }
            return PreparedBody(
                data: data,
                contentType: "multipart/form-data; boundary=\(boundary)",
                preview: summary.joined(separator: "\n")
            )
        }
    }

    private enum HTTPPreparationError: LocalizedError {
        case message(String)

        var errorDescription: String? {
            switch self {
            case .message(let text): return text
            }
        }
    }

    /// application/x-www-form-urlencoded 的编码：空格按传统用 `+`
    static func formEncode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text
            .addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%20", with: "+") ?? text
    }

    // MARK: - 响应体解码

    static func decodeBody(_ data: Data, contentType: String) -> String {
        if data.isEmpty { return "" }

        if let charset = charsetName(in: contentType),
           let encoding = encoding(named: charset),
           let text = String(data: data, encoding: encoding) {
            return text
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))) {
            return text
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func charsetName(in contentType: String) -> String? {
        guard let range = contentType.range(of: "charset=", options: .caseInsensitive) else { return nil }
        var value = String(contentType[range.upperBound...])
        if let semicolon = value.firstIndex(of: ";") { value = String(value[..<semicolon]) }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        return value.isEmpty ? nil : value
    }

    private static func encoding(named name: String) -> String.Encoding? {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
    }
}

// MARK: - URLSession 观察者

/// 收集耗时拆解、重定向链，并在需要时放行自签证书。
final class HTTPTaskObserver: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let allowInsecure: Bool
    private let followRedirects: Bool
    private let lock = NSLock()
    private var collected: HTTPTimings?
    private var chain: [String] = []

    init(allowInsecure: Bool, followRedirects: Bool) {
        self.allowInsecure = allowInsecure
        self.followRedirects = followRedirects
    }

    var timings: HTTPTimings? {
        lock.lock()
        defer { lock.unlock() }
        return collected
    }

    var redirects: [String] {
        lock.lock()
        defer { lock.unlock() }
        return chain
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let transaction = metrics.transactionMetrics.last else { return }

        func milliseconds(_ from: Date?, _ to: Date?) -> Double? {
            guard let from, let to, to > from else { return nil }
            return to.timeIntervalSince(from) * 1000
        }

        var timings = HTTPTimings()
        timings.reusedConnection = transaction.isReusedConnection
        timings.dns = milliseconds(transaction.domainLookupStartDate, transaction.domainLookupEndDate)
        timings.connect = milliseconds(transaction.connectStartDate, transaction.connectEndDate)
        timings.tls = milliseconds(transaction.secureConnectionStartDate, transaction.secureConnectionEndDate)
        timings.send = milliseconds(transaction.requestStartDate, transaction.requestEndDate)
        timings.waiting = milliseconds(transaction.requestEndDate, transaction.responseStartDate)
        timings.download = milliseconds(transaction.responseStartDate, transaction.responseEndDate)
        timings.total = milliseconds(transaction.fetchStartDate, transaction.responseEndDate)

        lock.lock()
        collected = timings
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let destination = request.url?.absoluteString ?? ""
        lock.lock()
        chain.append("\(response.statusCode) \(response.url?.absoluteString ?? "") → \(destination)")
        lock.unlock()

        // 关掉"跟随重定向"时，把重定向响应本身当结果交回去
        completionHandler(followRedirects ? request : nil)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard allowInsecure,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

// MARK: - JSON 美化

/// 一个手写的 JSON 缩进器。
///
/// 为什么不用 JSONSerialization 再输出：那样会走字典，**键顺序会被打乱**。
/// 看接口返回时键顺序变了很别扭，所以这里只做词法层面的缩进，一个字节的顺序都不动。
