import AppKit
import Foundation
import Network

// MARK: - 数据模型

struct WebhookHeader: Identifiable, Sendable {
    let name: String
    let value: String
    var id: String { "\(name)=\(value)" }
}

/// 一条被捕获的请求
struct WebhookRequest: Identifiable, Sendable {
    let id: Int
    let method: String
    let path: String
    let query: String?
    let headers: [WebhookHeader]
    let body: Data
    let remote: String
    let timestamp: Date
    /// 服务器回的状态码
    let replyStatus: Int
    /// 监听端口（拼 curl 用）
    let port: UInt16

    var bodyCount: Int { body.count }

    /// body 的体检结果：格式名 + 美化后的文本
    var bodyInspection: (format: String, pretty: String?) { WebhookServer.inspectBody(body) }

    /// 用 curl 重放这条请求的命令
    var curlCommand: String {
        var parts: [String] = ["curl", "-sv"]
        parts.append("-X \(method)")
        for header in headers where header.name.lowercased() != "content-length" {
            let escaped = header.value.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("-H '\(header.name): \(escaped)'")
        }
        if let text = String(data: body, encoding: .utf8), !text.isEmpty {
            let escaped = text.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("--data-raw '\(escaped)'")
        } else if !body.isEmpty {
            parts.append("--data-binary @request.bin")
        }
        let target = query.map { "http://localhost:\(port)\(path)?\($0)" } ?? "http://localhost:\(port)\(path)"
        parts.append("'\(target)'")
        return parts.joined(separator: " ")
    }

    /// 摘要里的一行（列表用）
    var summary: String {
        var text = "\(method) \(path)"
        if let query, !query.isEmpty { text += "?\(query)" }
        return text
    }
}

// MARK: - 服务器

/// 本地临时 Webhook 接收器。
///
/// 用 NWListener 起一个极简 HTTP 服务：什么路径都收，方法都收，
/// 把请求头和 body 完整记下来给人看，回一段可配置的 JSON。够调试 webhook 用。
final class WebhookServer: ObservableObject {

    enum State: Equatable, Sendable {
        case idle
        case starting
        case running(UInt16)
        case failed(String)

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }

        var isBusy: Bool { self == .starting }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var requests: [WebhookRequest] = []
    @Published private(set) var bytesReceived = 0

    /// 请求到达时的哨声开关（调试时挺提神）
    @Published var chimeOnRequest = false

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "com.seraphim.tools.webhook")
    private let maxRequests = 200
    private let maxBodySize = 2 * 1024 * 1024
    private var nextID = 1
    /// 回给客户端的状态码和响应体
    private var replyStatus = 200
    private var replyBody = "{\n  \"ok\": true\n}"
    /// 当前监听端口（记录到每条请求里，curl 重放要拼 URL）
    private var currentPort: UInt16 = 8765

    var requestCount: Int { requests.count }

    deinit {
        listener?.cancel()
        connections.forEach { $0.cancel() }
    }

    // MARK: 启停

    func start(port: UInt16, status: Int, body: String) {
        stop(quiet: true)
        state = .starting
        replyStatus = status
        replyBody = body
        currentPort = port

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port) ?? 8765) else {
            state = .failed("端口 \(port) 起不来（被占用或没有权限）")
            return
        }
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] newState in
            self?.onMain {
                guard let self else { return }
                switch newState {
                case .ready:
                    self.state = .running(port)
                case .failed(let error):
                    self.state = .failed("监听失败：\(error.localizedDescription)")
                    self.listener?.cancel()
                    self.listener = nil
                case .cancelled:
                    if self.state == .starting { self.state = .idle }
                default:
                    break
                }
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }

        listener.start(queue: queue)
    }

    func stop(quiet: Bool = false) {
        listener?.cancel()
        listener = nil
        queue.async { [connections] in
            connections.forEach { $0.cancel() }
        }
        connections.removeAll()
        if !quiet { state = .idle }
    }

    func clear() {
        requests.removeAll()
        bytesReceived = 0
    }

    func remove(_ id: Int) {
        requests.removeAll { $0.id == id }
    }

    // MARK: 连接处理

    private func handle(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var accumulated = buffer
            if let data {
                accumulated.append(data)
                self.onMain { self.bytesReceived += data.count }
            }

            // 超长保护：body 顶到上限就直接截断收尾
            if accumulated.count > self.maxBodySize + 16 * 1024 {
                self.finish(connection, request: accumulated, truncated: true)
                return
            }

            if error != nil {
                // 客户端异常断开，能解析多少解析多少
                if !accumulated.isEmpty {
                    self.finish(connection, request: accumulated, truncated: true)
                }
                connection.cancel()
                return
            }
            if isComplete {
                if !accumulated.isEmpty {
                    self.finish(connection, request: accumulated, truncated: false)
                }
                connection.cancel()
                return
            }
            // 头已经完整、body 也读够了就直接收尾（keep-alive 的后续请求不伺候）
            if let (headersEnd, contentLength) = self.requestBounds(accumulated),
               accumulated.count >= headersEnd + contentLength {
                self.finish(connection, request: accumulated, truncated: false)
                return
            }
            self.receive(connection, buffer: accumulated)
        }
    }

    /// 返回 header 结束位置（含 \r\n\r\n）和期望的 body 长度
    private func requestBounds(_ data: Data) -> (Int, Int)? {
        guard let range = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerPart = String(data: data[..<range.lowerBound], encoding: .utf8) ?? ""
        let lengthLine = headerPart
            .split(separator: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
        let length = lengthLine.flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
        return (range.upperBound, length)
    }

    private func finish(_ connection: NWConnection, request raw: Data, truncated: Bool) {
        let remote = remoteDescription(connection) ?? "未知来源"
        let status = replyStatus
        let body = replyBody
        let port = currentPort
        let identifier = nextID
        nextID += 1
        let record = Self.parse(raw, id: identifier, remote: remote, replyStatus: status, port: port, truncated: truncated)
        let response = Self.response(status: status, body: body)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })

        guard let record else { return }
        onMain { [weak self] in
            guard let self else { return }
            self.requests.insert(record, at: 0)
            if self.requests.count > self.maxRequests {
                self.requests.removeLast()
            }
            if self.chimeOnRequest { NSSound.beep() }
        }
    }

    private func remoteDescription(_ connection: NWConnection) -> String? {
        guard let endpoint = connection.currentPath?.remoteEndpoint else { return nil }
        let text = "\(endpoint)"
        // NWEndpoint 把 IPv6 描述成 "::1.62944" 这种裸拼，加方括号改成 [::1]:62944 好认
        if text.contains(":"),
           let lastDot = text.lastIndex(of: "."),
           text[text.index(after: lastDot)...].allSatisfy({ $0.isNumber }) {
            return "[\(text[..<lastDot])]:\(text[text.index(after: lastDot)...])"
        }
        return text
    }

    // MARK: 解析

    /// 把原始字节流解析成一条记录。解析不出请求行就返回 nil。
    static func parse(_ raw: Data, id: Int, remote: String, replyStatus: Int, port: UInt16, truncated: Bool) -> WebhookRequest? {
        guard let range = raw.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let headerText = String(data: raw[..<range.lowerBound], encoding: .utf8) else { return nil }
        let bodyData = Data(raw[range.upperBound...])
        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: true).map(String.init)
        guard let requestLine = lines.first else { return nil }

        let pieces = requestLine.split(separator: " ").map(String.init)
        guard pieces.count >= 2 else { return nil }
        let method = pieces[0].uppercased()
        let target = pieces[1]
        let path: String
        let query: String?
        if let question = target.firstIndex(of: "?") {
            path = String(target[..<question])
            query = String(target[target.index(after: question)...])
        } else {
            path = target
            query = nil
        }

        var headers: [WebhookHeader] = []
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            headers.append(WebhookHeader(name: name, value: value))
        }
        if truncated {
            headers.append(WebhookHeader(name: "⚠️ SeraphimTools", value: "body 超过上限被截断"))
        }

        return WebhookRequest(
            id: id,
            method: method,
            path: path,
            query: query,
            headers: headers,
            body: bodyData,
            remote: remote,
            timestamp: Date(),
            replyStatus: replyStatus,
            port: port
        )
    }

    private static func response(status: Int, body: String) -> Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 201: reason = "Created"
        case 202: reason = "Accepted"
        case 204: reason = "No Content"
        case 400: reason = "Bad Request"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        case 500: reason = "Internal Server Error"
        default: reason = "Status \(status)"
        }
        let payload = status == 204 ? Data() : Data(body.utf8)
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: application/json; charset=utf-8\r\n"
        head += "Content-Length: \(payload.count)\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + payload
    }

    // MARK: body 体检

    /// 判断 body 是什么并给出适合展示的文本
    static func inspectBody(_ data: Data) -> (format: String, pretty: String?) {
        guard !data.isEmpty else { return ("空", nil) }
        guard let text = String(data: data, encoding: .utf8) else {
            return ("二进制 \(data.count) 字节", data.prefix(256).map { String(format: "%02x", $0) }.joined(separator: " "))
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return ("空", nil) }

        if JSONBeautifier.isJSONLike(trimmed) {
            return ("JSON", JSONBeautifier.pretty(trimmed) ?? trimmed)
        }

        // 表单：a=1&b=2
        if !trimmed.contains("\n"), trimmed.contains("="), trimmed.contains("&") || trimmed.contains("%") {
            let pairs = trimmed.split(separator: "&").map { pair -> String in
                guard let eq = pair.firstIndex(of: "=") else {
                    return "\(decodeComponent(String(pair)))（没值）"
                }
                let key = decodeComponent(String(pair[..<eq]))
                let value = decodeComponent(String(pair[pair.index(after: eq)...]))
                return "\(key) = \(value)"
            }
            return ("表单", pairs.joined(separator: "\n"))
        }

        if trimmed.hasPrefix("<") {
            return (trimmed.hasPrefix("<?xml") ? "XML" : "HTML/Markup", trimmed)
        }

        // 长纯文本也美化一下换行
        return ("文本", trimmed)
    }

    private static func decodeComponent(_ text: String) -> String {
        text.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? text
    }
}

// MARK: - 便利

extension WebhookServer {
    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}
