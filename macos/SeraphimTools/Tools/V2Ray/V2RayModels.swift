import Foundation

// MARK: - 协议 / 传输 / 安全

enum V2RayProtocol: String, CaseIterable, Identifiable, Codable, Sendable {
    case vmess
    case vless
    case trojan
    case shadowsocks
    case socks
    case http

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vmess: return "VMess"
        case .vless: return "VLESS"
        case .trojan: return "Trojan"
        case .shadowsocks: return "Shadowsocks"
        case .socks: return "SOCKS"
        case .http: return "HTTP"
        }
    }

    var scheme: String {
        switch self {
        case .vmess: return "vmess"
        case .vless: return "vless"
        case .trojan: return "trojan"
        case .shadowsocks: return "ss"
        case .socks: return "socks"
        case .http: return "http"
        }
    }

    var defaultPort: Int {
        switch self {
        case .vmess, .vless: return 443
        case .trojan: return 443
        case .shadowsocks: return 8388
        case .socks: return 1080
        case .http: return 8080
        }
    }

    /// Xray 出站协议名
    var outboundName: String {
        switch self {
        case .vmess: return "vmess"
        case .vless: return "vless"
        case .trojan: return "trojan"
        case .shadowsocks: return "shadowsocks"
        case .socks: return "socks"
        case .http: return "http"
        }
    }

    var supportsStream: Bool {
        switch self {
        case .vmess, .vless, .trojan: return true
        case .shadowsocks, .socks, .http: return false
        }
    }

    var supportsTLS: Bool {
        switch self {
        case .vmess, .vless, .trojan, .http: return true
        case .shadowsocks, .socks: return false
        }
    }
}

enum V2RayNetwork: String, CaseIterable, Identifiable, Codable, Sendable {
    case tcp
    case ws
    case grpc
    case http
    case h2
    case quic
    case kcp
    case httpupgrade
    case xhttp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tcp: return "TCP"
        case .ws: return "WebSocket"
        case .grpc: return "gRPC"
        case .http: return "HTTP/1.1"
        case .h2: return "HTTP/2"
        case .quic: return "QUIC"
        case .kcp: return "mKCP"
        case .httpupgrade: return "HTTPUpgrade"
        case .xhttp: return "XHTTP"
        }
    }

    /// 分享链接里的写法，个别协议用的是别名
    static func fromLink(_ raw: String) -> V2RayNetwork {
        switch raw.lowercased() {
        case "ws", "websocket": return .ws
        case "grpc": return .grpc
        case "h2", "http/2": return .h2
        case "http": return .http
        case "quic": return .quic
        case "kcp", "mkcp": return .kcp
        case "httpupgrade": return .httpupgrade
        case "xhttp", "splithttp": return .xhttp
        default: return .tcp
        }
    }

    /// 回写分享链接时用标准写法
    var linkName: String {
        switch self {
        case .http: return "http"
        case .xhttp: return "xhttp"
        default: return rawValue
        }
    }
}

enum V2RaySecurity: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case tls
    case reality

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "不加密"
        case .tls: return "TLS"
        case .reality: return "REALITY"
        }
    }

    static func fromLink(_ raw: String) -> V2RaySecurity {
        switch raw.lowercased() {
        case "tls": return .tls
        case "reality": return .reality
        default: return .none
        }
    }
}

enum V2RayFingerprint: String, CaseIterable, Identifiable, Sendable {
    case chrome
    case firefox
    case safari
    case ios
    case android
    case edge
    case randomized
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "不伪造"
        case .randomized: return "随机"
        default: return rawValue.capitalized
        }
    }
}

// MARK: - 节点

struct V2RayNode: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var remark: String = ""
    var proto: V2RayProtocol = .vmess
    var address: String = ""
    var port: Int = 443

    // 凭据
    var uuid: String = ""            // VMess / VLESS
    var password: String = ""        // Trojan / SS / SOCKS / HTTP
    var method: String = "aes-256-gcm"  // SS 加密方式
    var alterId: Int = 0             // VMess 老版本
    var cipher: String = "auto"      // VMess 加密（auto / none / aes-128-gcm …）
    var flow: String = ""            // VLESS（xtls-rprx-vision）

    // 传输层
    var network: V2RayNetwork = .tcp
    var security: V2RaySecurity = .none
    var sni: String = ""
    var host: String = ""
    var path: String = ""
    var serviceName: String = ""
    var alpn: String = ""
    var fingerprint: String = ""
    var publicKey: String = ""
    var shortId: String = ""
    var spiderX: String = ""
    var allowInsecure: Bool = false
    var headerType: String = "none"

    var isLocal: Bool { proto == .socks || proto == .http }

    /// 节点去重用的指纹（同协议同地址同端口同凭据算同一个）
    var fingerprintKey: String {
        "\(proto.rawValue)|\(address)|\(port)|\(uuid)\(password)"
    }

    var displayName: String {
        if !remark.isEmpty { return remark }
        return "\(address):\(port)"
    }

    var endpoint: String {
        address.contains(":") ? "[\(address)]:\(port)" : "\(address):\(port)"
    }

    /// 一句话摘要，列表里用
    var summary: String {
        var parts = [proto.title, endpoint]
        if network != .tcp, proto.supportsStream { parts.append(network.title) }
        if security != .none { parts.append(security.title) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 分享链接

enum ShareLinkError: LocalizedError {
    case empty
    case badScheme(String)
    case badBody(String)
    case missingField(String)

    var errorDescription: String? {
        switch self {
        case .empty: return "内容为空"
        case .badScheme(let scheme): return "不认识的协议：\(scheme)"
        case .badBody(let detail): return "链接格式不对：\(detail)"
        case .missingField(let field): return "缺少必要字段：\(field)"
        }
    }
}

/// 节点分享链接的解析与导出
enum ShareLink {
    // MARK: 解析

    /// 一次解析多行，返回成功的节点和失败的原文
    static func parseLines(_ text: String) -> (nodes: [V2RayNode], failures: [(String, String)]) {
        var nodes: [V2RayNode] = []
        var failures: [(String, String)] = []

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("//"), !line.hasPrefix("#") else { continue }
            do {
                nodes.append(try parse(line))
            } catch {
                failures.append((line, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription))
            }
        }
        return (nodes, failures)
    }

    static func parse(_ link: String) throws -> V2RayNode {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ShareLinkError.empty }
        guard let schemeEnd = trimmed.range(of: "://") else {
            throw ShareLinkError.badBody("没有找到 ://")
        }

        let scheme = String(trimmed[trimmed.startIndex..<schemeEnd.lowerBound]).lowercased()
        let body = String(trimmed[schemeEnd.upperBound...])

        switch scheme {
        case "vmess":
            return try parseVMess(body)
        case "vless", "vless+reality":
            return try parseURLStyle(body, proto: .vless, ink: link)
        case "trojan", "trojan-go":
            return try parseURLStyle(body, proto: .trojan, ink: link)
        case "ss", "shadowsocks":
            return try parseShadowsocks(body)
        case "socks", "socks5":
            return try parseSocksStyle(body, proto: .socks, ink: link)
        case "http", "https":
            // 只在明确带认证信息时才当节点，免得把普通网址也吸进来
            guard body.contains("@") else {
                throw ShareLinkError.badBody("http 链接不带 用户名@主机 时不当节点处理")
            }
            return try parseSocksStyle(body, proto: .http, ink: link)
        default:
            throw ShareLinkError.badScheme(scheme)
        }
    }

    /// vmess://base64(json)
    private static func parseVMess(_ body: String) throws -> V2RayNode {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // 也认 vmess://uuid@host:port?… 这种新写法
        if trimmed.contains("@"), !trimmed.hasPrefix("ey"), looksLikeURLLikeBody(trimmed) {
            return try parseURLStyle(trimmed, proto: .vmess, ink: "vmess://" + trimmed)
        }

        guard let data = Base64Flex.decode(trimmed), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ShareLinkError.badBody("VMess 链接主体不是合法的 Base64 JSON")
        }

        func str(_ key: String) -> String {
            if let value = json[key] as? String { return value }
            if let value = json[key] as? NSNumber { return value.stringValue }
            if let value = json[key] as? Int { return String(value) }
            return ""
        }

        var node = V2RayNode()
        node.proto = .vmess
        node.remark = str("ps").isEmpty ? str("remarks") : str("ps")
        node.address = str("add").trimmingCharacters(in: .whitespaces)
        node.port = Int(str("port")) ?? 443
        node.uuid = str("id")
        node.alterId = Int(str("aid")) ?? 0
        node.cipher = str("scy").isEmpty ? "auto" : str("scy")
        node.network = V2RayNetwork.fromLink(str("net"))
        node.headerType = str("type").isEmpty ? "none" : str("type")
        node.host = str("host")
        node.path = str("path")
        node.serviceName = str("path").isEmpty ? str("serviceName") : str("path")
        node.sni = str("sni").isEmpty ? str("peer") : str("sni")
        node.alpn = str("alpn")
        node.fingerprint = str("fp")
        node.publicKey = str("pbk")
        node.shortId = str("sid")
        node.spiderX = str("spx")
        let tlsValue = str("tls").lowercased()
        if tlsValue == "tls" {
            node.security = .tls
        } else if tlsValue == "reality" {
            node.security = .reality
        }
        if str("allowInsecure") == "1" || str("allowInsecure").lowercased() == "true" {
            node.allowInsecure = true
        }

        guard !node.address.isEmpty else { throw ShareLinkError.missingField("add") }
        guard !node.uuid.isEmpty else { throw ShareLinkError.missingField("id") }
        if node.sni.isEmpty, node.security != .none { node.sni = node.host }
        return node
    }

    /// vless:// / trojan:// 这类标准 URL 写法
    private static func parseURLStyle(_ body: String, proto: V2RayProtocol, ink: String) throws -> V2RayNode {
        let full = "scheme://" + body
        guard let components = URLComponents(string: full) else {
            throw ShareLinkError.badBody("URL 解析失败")
        }
        guard let host = components.host, !host.isEmpty else {
            throw ShareLinkError.missingField("主机")
        }
        // URLComponents 对 IPv6 会把方括号一起给出来，这里剥掉
        let cleanHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))

        var node = V2RayNode()
        node.proto = proto
        node.address = cleanHost
        node.port = components.port ?? proto.defaultPort

        let user = components.user?.removingPercentEncoding ?? components.user ?? ""
        if proto == .trojan || proto == .vmess && !user.isEmpty {
            if proto == .trojan {
                node.password = user
            } else {
                node.uuid = user
            }
        } else {
            node.uuid = user
        }
        if proto == .vmess, node.uuid.isEmpty { node.uuid = user }

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            if let value = item.value { query[item.name.lowercased()] = value }
        }

        node.network = V2RayNetwork.fromLink(query["type"] ?? "tcp")
        node.security = V2RaySecurity.fromLink(query["security"] ?? query["tls"] ?? "none")
        node.sni = query["sni"] ?? query["peer"] ?? ""
        node.host = query["host"] ?? ""
        node.path = query["path"] ?? ""
        node.serviceName = query["servicename"] ?? ""
        node.alpn = query["alpn"] ?? ""
        node.fingerprint = query["fp"] ?? ""
        node.publicKey = query["pbk"] ?? ""
        node.shortId = query["sid"] ?? ""
        node.spiderX = query["spx"] ?? ""
        node.flow = query["flow"] ?? ""
        node.headerType = query["headertype"] ?? "none"
        if let insecure = query["allowinsecure"], insecure == "1" || insecure.lowercased() == "true" {
            node.allowInsecure = true
        }
        if node.network == .grpc, node.serviceName.isEmpty {
            node.serviceName = node.path
        }
        if node.sni.isEmpty, node.security != .none {
            node.sni = node.host.isEmpty ? cleanHost : node.host
        }

        node.remark = decorateRemark(components.fragment)
        if proto == .vmess {
            guard !node.uuid.isEmpty else { throw ShareLinkError.missingField("uuid") }
        }
        if proto == .trojan, node.password.isEmpty {
            throw ShareLinkError.missingField("密码")
        }
        _ = ink
        return node
    }

    /// ss:// 三种写法都认
    private static func parseShadowsocks(_ body: String) throws -> V2RayNode {
        var work = body
        var remark = ""
        if let hash = work.firstIndex(of: "#") {
            remark = String(work[work.index(after: hash)...])
            work = String(work[work.startIndex..<hash])
        }

        // 去掉 plugin 参数（Xray 的 shadowsocks 出站不支持 plugin，解析时保留但不使用）
        var query = ""
        if let mark = work.firstIndex(of: "?") {
            query = String(work[work.index(after: mark)...])
            work = String(work[work.startIndex..<mark])
        }
        _ = query

        var node = V2RayNode()
        node.proto = .shadowsocks
        node.remark = decorateRemark(remark)

        if let at = work.lastIndex(of: "@") {
            let userPart = String(work[work.startIndex..<at])
            let hostPart = String(work[work.index(after: at)...])
            guard let (host, port) = splitHostPort(hostPart) else {
                throw ShareLinkError.badBody("主机端口解不出来")
            }
            node.address = host
            node.port = port

            let decodedUser: String
            if userPart.contains(":") {
                decodedUser = userPart
            } else if let data = Base64Flex.decode(userPart), let text = String(data: data, encoding: .utf8) {
                decodedUser = text
            } else {
                throw ShareLinkError.badBody("Base64 用户名解不出来")
            }
            guard let colon = decodedUser.firstIndex(of: ":") else {
                throw ShareLinkError.badBody("用户名里没有冒号")
            }
            node.method = String(decodedUser[decodedUser.startIndex..<colon])
            node.password = String(decodedUser[decodedUser.index(after: colon)...])
        } else {
            guard let data = Base64Flex.decode(work), let text = String(data: data, encoding: .utf8) else {
                throw ShareLinkError.badBody("整段 Base64 解不出来")
            }
            guard let at = text.lastIndex(of: "@") else {
                throw ShareLinkError.badBody("正文里没有 @")
            }
            let userPart = String(text[text.startIndex..<at])
            let hostPart = String(text[text.index(after: at)...])
            guard let colon = userPart.firstIndex(of: ":"), let (host, port) = splitHostPort(hostPart) else {
                throw ShareLinkError.badBody("字段拆不开")
            }
            node.method = String(userPart[userPart.startIndex..<colon])
            node.password = String(userPart[userPart.index(after: colon)...])
            node.address = host
            node.port = port
        }

        guard !node.method.isEmpty else { throw ShareLinkError.missingField("加密方式") }
        if node.password.isEmpty { throw ShareLinkError.missingField("密码") }
        return node
    }

    /// socks:// / http:// 写法
    private static func parseSocksStyle(_ body: String, proto: V2RayProtocol, ink: String) throws -> V2RayNode {
        var work = body
        var remark = ""
        if let hash = work.firstIndex(of: "#") {
            remark = String(work[work.index(after: hash)...])
            work = String(work[work.startIndex..<hash])
        }
        var auth = ""
        if let at = work.lastIndex(of: "@") {
            auth = String(work[work.startIndex..<at])
            work = String(work[work.index(after: at)...])
        }

        // base64(user:pass)@host:port 或 user:pass@host:port
        if !auth.isEmpty, !auth.contains(":"), let data = Base64Flex.decode(auth), let text = String(data: data, encoding: .utf8) {
            auth = text
        }

        guard let (host, port) = splitHostPort(work) else {
            throw ShareLinkError.badBody("主机端口解不出来")
        }

        var node = V2RayNode()
        node.proto = proto
        node.address = host
        node.port = port
        node.remark = decorateRemark(remark)
        if let colon = auth.firstIndex(of: ":") {
            node.uuid = String(auth[auth.startIndex..<colon])
            node.password = String(auth[auth.index(after: colon)...])
        }
        _ = ink
        return node
    }

    // MARK: 导出

    static func link(for node: V2RayNode) -> String {
        switch node.proto {
        case .vmess:
            var payload: [String: Any] = [
                "v": "2",
                "ps": node.remark,
                "add": node.address,
                "port": String(node.port),
                "id": node.uuid,
                "aid": String(node.alterId),
                "scy": node.cipher.isEmpty ? "auto" : node.cipher,
                "net": node.network.linkName,
                "type": node.headerType,
                "host": node.host,
                "path": node.path
            ]
            if node.security != .none { payload["tls"] = node.security == .reality ? "reality" : "tls" }
            if !node.sni.isEmpty { payload["sni"] = node.sni }
            if !node.alpn.isEmpty { payload["alpn"] = node.alpn }
            if !node.fingerprint.isEmpty { payload["fp"] = node.fingerprint }
            if !node.publicKey.isEmpty { payload["pbk"] = node.publicKey }
            if !node.shortId.isEmpty { payload["sid"] = node.shortId }
            if !node.spiderX.isEmpty { payload["spx"] = node.spiderX }
            if node.allowInsecure { payload["allowInsecure"] = "1" }
            let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
            return "vmess://" + Base64Flex.encode(data)
        case .vless, .trojan:
            var items: [String] = []
            if node.proto == .vless {
                items.append("encryption=none")
                if !node.flow.isEmpty { items.append("flow=\(node.flow)") }
            }
            items.append("security=\(node.security == .none ? "none" : node.security.rawValue)")
            items.append("type=\(node.network.linkName)")
            if !node.sni.isEmpty { items.append("sni=\(encode(node.sni))") }
            if !node.host.isEmpty { items.append("host=\(encode(node.host))") }
            if node.network == .grpc {
                if !node.serviceName.isEmpty { items.append("serviceName=\(encode(node.serviceName))") }
            } else if !node.path.isEmpty {
                items.append("path=\(encode(node.path))")
            }
            if !node.alpn.isEmpty { items.append("alpn=\(encode(node.alpn))") }
            if !node.fingerprint.isEmpty { items.append("fp=\(node.fingerprint)") }
            if !node.publicKey.isEmpty { items.append("pbk=\(encode(node.publicKey))") }
            if !node.shortId.isEmpty { items.append("sid=\(encode(node.shortId))") }
            if !node.spiderX.isEmpty { items.append("spx=\(encode(node.spiderX))") }
            if node.allowInsecure { items.append("allowInsecure=1") }
            let credential = node.proto == .vless ? node.uuid : node.password
            let user = credential.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? credential
            let fragment = node.remark.isEmpty ? "" : "#" + encode(node.remark)
            return "\(node.proto.scheme)://\(user)@\(node.endpoint)?\(items.joined(separator: "&"))\(fragment)"
        case .shadowsocks:
            let credential = "\(node.method):\(node.password)"
            let encoded = Base64Flex.encode(Data(credential.utf8))
                .replacingOccurrences(of: "=", with: "")
            let fragment = node.remark.isEmpty ? "" : "#" + encode(node.remark)
            return "ss://\(encoded)@\(node.endpoint)\(fragment)"
        case .socks, .http:
            var auth = ""
            if !node.password.isEmpty || !node.uuid.isEmpty {
                let credential = "\(node.uuid):\(node.password)"
                auth = Base64Flex.encode(Data(credential.utf8)).replacingOccurrences(of: "=", with: "") + "@"
            }
            let fragment = node.remark.isEmpty ? "" : "#" + encode(node.remark)
            return "\(node.proto.scheme)://\(auth)\(node.endpoint)\(fragment)"
        }
    }

    // MARK: 小工具

    private static func looksLikeURLLikeBody(_ body: String) -> Bool {
        // uuid@host:port 形式：@ 前是 36 位左右的 uuid
        guard let at = body.firstIndex(of: "@") else { return false }
        let head = String(body[body.startIndex..<at])
        return head.count >= 32 && !head.contains(":")
    }

    private static func splitHostPort(_ text: String) -> (String, Int)? {
        var work = text
        if let slash = work.firstIndex(of: "/") { work = String(work[work.startIndex..<slash]) }
        guard !work.isEmpty else { return nil }

        if work.hasPrefix("[") {
            guard let close = work.firstIndex(of: "]") else { return nil }
            let host = String(work[work.index(after: work.startIndex)..<close])
            let rest = String(work[work.index(after: close)...])
            let port = Int(rest.replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
            guard port > 0 else { return nil }
            return (host, port)
        }

        guard let colon = work.lastIndex(of: ":") else { return nil }
        let host = String(work[work.startIndex..<colon])
        let portText = String(work[work.index(after: colon)...])
        guard let port = Int(portText), port > 0, port <= 65535, !host.isEmpty else { return nil }
        return (host, port)
    }

    private static func decorateRemark(_ text: String?) -> String {
        guard let text, !text.isEmpty else { return "" }
        return text.removingPercentEncoding ?? text
    }

    private static func encode(_ text: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=#?+")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}

// MARK: - Base64 宽容编解码

enum Base64Flex {
    static func decode(_ text: String) -> Data? {
        var work = text.trimmingCharacters(in: .whitespacesAndNewlines)
        work = work.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while work.hasSuffix("=") { work.removeLast() }
        let remainder = work.count % 4
        if remainder > 0 { work += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: work, options: [.ignoreUnknownCharacters])
    }

    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
    }
}

// MARK: - 有序 JSON（配置生成用，保证键顺序可读）

indirect enum JSONValue {
    case string(String)
    case int(Int)
    case bool(Bool)
    case array([JSONValue])
    case object([(String, JSONValue)])

    func render(indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        let inner = String(repeating: "  ", count: indent + 1)

        switch self {
        case .string(let value):
            return JSONValue.quote(value)
        case .int(let value):
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .array(let items):
            if items.isEmpty { return "[]" }
            let body = items.map { inner + $0.render(indent: indent + 1) }.joined(separator: ",\n")
            return "[\n\(body)\n\(pad)]"
        case .object(let pairs):
            if pairs.isEmpty { return "{}" }
            let body = pairs.map { inner + JSONValue.quote($0.0) + ": " + $0.1.render(indent: indent + 1) }
                .joined(separator: ",\n")
            return "{\n\(body)\n\(pad)}"
        }
    }

    static func quote(_ text: String) -> String {
        var out = "\""
        for character in text.unicodeScalars {
            switch character {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if character.value < 0x20 {
                    out += String(format: "\\u%04x", character.value)
                } else {
                    out.unicodeScalars.append(character)
                }
            }
        }
        return out + "\""
    }

    static func stringOrNil(_ text: String) -> JSONValue? {
        text.isEmpty ? nil : .string(text)
    }
}
