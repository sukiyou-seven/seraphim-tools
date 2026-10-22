import Foundation

// MARK: - 通用键值对

/// 界面里成对出现的输入。请求头、表单字段、文件字段、curl 参数都复用它。
struct NetPair: Identifiable, Sendable, Hashable {
    var id = UUID()
    var name: String = ""
    var value: String = ""
    var isEnabled: Bool = true

    init(name: String = "", value: String = "", isEnabled: Bool = true) {
        self.name = name
        self.value = value
        self.isEnabled = isEnabled
    }
}

/// 单纯的字符串对（展示用，比如响应头）
struct NetStringPair: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let value: String

    init(_ name: String, _ value: String) {
        self.id = "\(name)\u{1}\(value)"
        self.name = name
        self.value = value
    }
}

// MARK: - IP 查询

enum IPAddressFamily: String, CaseIterable, Identifiable, Sendable {
    case any
    case v4
    case v6

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "自动"
        case .v4: return "IPv4"
        case .v6: return "IPv6"
        }
    }
}

/// 查询结果里的一行（"归属地 · 中国 四川 成都"）
struct IPField: Identifiable, Sendable {
    let id: String
    let label: String
    let value: String
    var highlight: Bool

    init(_ label: String, _ value: String, highlight: Bool = false) {
        self.id = label
        self.label = label
        self.value = value
        self.highlight = highlight
    }
}

/// 一个接口的查询结果
struct IPReport: Identifiable, Sendable {
    let id: String
    let provider: String
    let providerNote: String
    let family: String
    let address: String
    let fields: [IPField]
    let elapsed: Double
    let isOwnAddress: Bool
}

/// 公网 IP / 归属地接口
struct IPProvider: Identifiable, Sendable {
    enum Scope: Sendable {
        case ownIP     // 只能查"我在公网上的地址"
        case geo       // 能查任意 IP 的归属地
    }

    let id: String
    let name: String
    let note: String
    let scope: Scope
    /// 该接口返回的地址族（iced 的是 IPv4/IPv6 专用通道）
    let familyHint: IPAddressFamily
    let chinese: Bool

    var canQueryOwn: Bool { scope == .ownIP || scope == .geo }
    var canQueryArbitrary: Bool { scope == .geo }
}

enum IPProviders {
    /// 查本机公网 IP 用的接口。默认按"快 + 中文"优先排序，界面里可单独勾选。
    static let ownIP: [IPProvider] = [
        IPProvider(id: "ipip", name: "ipip.net", note: "纯文本，最快要 0.2 秒，带中文归属地", scope: .ownIP, familyHint: .any, chinese: true),
        IPProvider(id: "ipapi", name: "ip-api.com", note: "中文 JSON，字段最全（含 ISP / ASN / 代理标记）", scope: .geo, familyHint: .any, chinese: true),
        IPProvider(id: "icanhazip4", name: "icanhazip · IPv4", note: "只问 IPv4 出口地址", scope: .ownIP, familyHint: .v4, chinese: false),
        IPProvider(id: "icanhazip6", name: "icanhazip · IPv6", note: "只问 IPv6 出口地址", scope: .ownIP, familyHint: .v6, chinese: false),
        IPProvider(id: "ipapiiis", name: "ipapi.is", note: "英文 JSON，ASN / 公司信息干净", scope: .geo, familyHint: .any, chinese: false),
        IPProvider(id: "ipinfo", name: "ipinfo.io", note: "英文 JSON，机房 / 代理字段", scope: .geo, familyHint: .any, chinese: false),
    ]

    /// 查指定 IP 归属地用的接口
    static let geo: [IPProvider] = [
        IPProvider(id: "ipapi", name: "ip-api.com", note: "中文，返回国家/省市/ISP/ASN", scope: .geo, familyHint: .any, chinese: true),
        IPProvider(id: "ipwho", name: "ipwho.is", note: "中文，带时区与连接信息", scope: .geo, familyHint: .any, chinese: true),
        IPProvider(id: "ipapiiis", name: "ipapi.is", note: "英文，公司 / ASN 最规范", scope: .geo, familyHint: .any, chinese: false),
    ]

    static func provider(id: String) -> IPProvider? {
        (ownIP + geo).first { $0.id == id }
    }
}

// MARK: - Ping

struct PingOptions: Sendable {
    var host: String
    var count: Int            // 0 表示一直 ping 到手动停止
    var interval: Double
    var packetSize: Int
    var waitTimeout: Double   // 单包等待上限（秒）
    var family: IPAddressFamily

    static let initial = PingOptions(
        host: "",
        count: 5,
        interval: 0.5,
        packetSize: 56,
        waitTimeout: 1.5,
        family: .any
    )
}

struct PingSample: Identifiable, Sendable {
    var id: Int { sequence }
    let sequence: Int
    let bytes: Int
    let time: Double
    let ttl: Int?
    let timeout: Bool
}

struct PingSummary: Sendable {
    var transmitted = 0
    var received = 0
    var lossPercent: Double = 0
    var minRTT: Double?
    var avgRTT: Double?
    var maxRTT: Double?
    var stddev: Double?

    var lost: Int { max(0, transmitted - received) }

    /// 用样本自己算一份统计。持续 ping 被中断时 ping 自己不会输出统计，
    /// 界面就靠这份数据兜底。
    static func from(samples: [PingSample]) -> PingSummary {
        var summary = PingSummary()
        summary.transmitted = samples.count
        let times = samples.filter { !$0.timeout }.map(\.time)
        summary.received = times.count
        summary.lossPercent = samples.isEmpty ? 0 : Double(samples.count - times.count) / Double(samples.count) * 100
        if !times.isEmpty {
            summary.minRTT = times.min()
            summary.maxRTT = times.max()
            summary.avgRTT = times.reduce(0, +) / Double(times.count)
            if times.count > 1, let avg = summary.avgRTT {
                let variance = times.reduce(0) { $0 + ($1 - avg) * ($1 - avg) } / Double(times.count)
                summary.stddev = variance.squareRoot()
            } else {
                summary.stddev = 0
            }
        }
        return summary
    }
}

enum PingEvent: Sendable {
    case started(command: String)
    case resolved(host: String, address: String)
    case sample(PingSample)
    case notice(String)
    case summary(PingSummary)
    case failure(String)
    case finished
}

// MARK: - Telnet

enum TelnetState: Equatable, Sendable {
    case idle
    case connecting
    case connected
    case closed
    case failed(String)

    var title: String {
        switch self {
        case .idle: return "未连接"
        case .connecting: return "连接中"
        case .connected: return "已连接"
        case .closed: return "已断开"
        case .failed: return "连接失败"
        }
    }
}

struct TelnetLine: Identifiable, Sendable {
    enum Kind: Sendable {
        case incoming      // 服务端发来的
        case outgoing      // 我发出去的
        case system        // 连接 / 断开 / 协商
        case error
    }

    let id = UUID()
    let kind: Kind
    let text: String
    let timestamp: Date
}

// MARK: - HTTP 请求

enum HTTPBodyMode: String, CaseIterable, Identifiable, Sendable {
    case none
    case json
    case form
    case raw
    case multipart

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "无"
        case .json: return "JSON"
        case .form: return "表单 (urlencoded)"
        case .raw: return "原始文本"
        case .multipart: return "文件上传 (multipart)"
        }
    }
}

struct HTTPRequestSpec: Sendable {
    var method: String = "GET"
    var url: String = ""
    var headers: [NetPair] = []
    var bodyMode: HTTPBodyMode = .none
    var rawBody: String = ""
    var formFields: [NetPair] = []
    var fileFields: [NetPair] = []
    var timeout: Double = 30
    var followRedirects = true
    var allowInsecureTLS = false
}

/// 一次请求的耗时分解（毫秒）
struct HTTPTimings: Sendable {
    var dns: Double?
    var connect: Double?
    var tls: Double?
    var send: Double?
    var waiting: Double?
    var download: Double?
    var total: Double?
    var reusedConnection = false

    var hasBreakdown: Bool {
        dns != nil || connect != nil || tls != nil || waiting != nil || download != nil
    }
}

struct HTTPExchange: Identifiable, Sendable {
    let id = UUID()
    let method: String
    let url: String
    let finalURL: String
    let requestHeaders: [NetStringPair]
    let requestBodyPreview: String
    let statusCode: Int
    let statusText: String
    let responseHeaders: [NetStringPair]
    let bodyText: String
    let bodyBytes: Int
    let contentType: String
    let timings: HTTPTimings
    let redirects: [String]
    let failure: String?
    let startedAt: Date

    var isSuccess: Bool { failure == nil && (200..<400).contains(statusCode) }
    var isJSON: Bool {
        let lowered = contentType.lowercased()
        return lowered.contains("json") || (bodyText.trimmingCharacters(in: .whitespaces).hasPrefix("{") && !bodyText.isEmpty)
    }
}

// MARK: - cURL

enum CurlBodyMode: String, CaseIterable, Identifiable, Sendable {
    case none
    case json
    case form
    case multipart
    case raw

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "无 body"
        case .json: return "JSON（-d）"
        case .form: return "表单（--data-urlencode）"
        case .multipart: return "multipart（-F）"
        case .raw: return "原始文本（--data-raw）"
        }
    }
}

enum CurlAuthMode: String, CaseIterable, Identifiable, Sendable {
    case none
    case basic
    case bearer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "无"
        case .basic: return "Basic（-u）"
        case .bearer: return "Bearer Token"
        }
    }
}

enum CurlStyle: String, CaseIterable, Identifiable, Sendable {
    case multiLine
    case singleLine
    case pretty      // 只保留必要参数，方便贴进文档

    var id: String { rawValue }

    var title: String {
        switch self {
        case .multiLine: return "多行（带续行）"
        case .singleLine: return "单行"
        case .pretty: return "精简"
        }
    }
}

struct CurlRequest: Sendable, Equatable {
    var url = ""
    var method = "GET"
    var headers: [NetPair] = []
    var bodyMode: CurlBodyMode = .none
    var rawBody = ""
    var dataFields: [NetPair] = []
    var fileFields: [NetPair] = []      // name = 表单字段名，value = 本地文件路径
    var authMode: CurlAuthMode = .none
    var username = ""
    var password = ""
    var bearerToken = ""
    var cookies = ""
    var userAgent = ""
    var referer = ""
    /// 默认关掉：curl 本身就不跟随重定向，想要 -L 得显式勾
    var followRedirects = false
    var insecure = false
    var compressed = false
    var includeHeaders = false
    var headOnly = false
    var silent = false
    var verbose = false
    var outputFile = ""
    var connectTimeout = ""
    var maxTime = ""
}

struct CurlParseResult: Sendable {
    var request: CurlRequest
    var warnings: [String]
    var unknown: [String]
}

// MARK: - DNS

enum DNSRecordType: String, CaseIterable, Identifiable, Sendable {
    case a = "A"
    case aaaa = "AAAA"
    case cname = "CNAME"
    case mx = "MX"
    case ns = "NS"
    case txt = "TXT"
    case soa = "SOA"
    case srv = "SRV"
    case caa = "CAA"
    case ptr = "PTR"
    case any = "ANY"

    var id: String { rawValue }

    var explanation: String {
        switch self {
        case .a: return "IPv4 地址"
        case .aaaa: return "IPv6 地址"
        case .cname: return "别名指向"
        case .mx: return "邮件服务器"
        case .ns: return "权威域名服务器"
        case .txt: return "文本记录（SPF / 验证）"
        case .soa: return "区域起始授权"
        case .srv: return "服务位置"
        case .caa: return "证书签发授权"
        case .ptr: return "反向解析（IP → 域名）"
        case .any: return "所有记录（很多服务器会拒绝）"
        }
    }
}

struct DNSRecord: Identifiable, Sendable {
    let id: Int
    let name: String
    let ttl: Int?
    let recordClass: String
    let type: String
    let value: String

    var ttlText: String { ttl.map { "\($0)s" } ?? "—" }

    /// TTL 的可读说法
    var ttlHint: String? {
        guard let ttl else { return nil }
        switch ttl {
        case 0..<60: return "不到 1 分钟"
        case 60..<3600: return "\(ttl / 60) 分钟"
        case 3600..<86400: return "\(ttl / 3600) 小时"
        default: return "\(ttl / 86400) 天"
        }
    }
}

struct DNSResult: Sendable {
    let query: String
    let type: DNSRecordType
    let server: String
    let status: String
    let flags: String
    let queryTime: Int?
    let answers: [DNSRecord]
    let authority: [DNSRecord]
    let additional: [DNSRecord]
    let raw: String
    let elapsed: Double
    let failure: String?
    let isTrace: Bool

    var succeeded: Bool { failure == nil && status.uppercased() == "NOERROR" }

    /// 状态码的白话解释。NXDOMAIN 之类是"有效答案但不是好消息"，不算失败，所以单独给一段说明。
    var statusHint: String? {
        switch status.uppercased() {
        case "NXDOMAIN":
            return "NXDOMAIN：权威服务器明确说这个域名不存在——可能拼错了，或者域名没注册 / 已过期。"
        case "SERVFAIL":
            return "SERVFAIL：上游解析失败，常见于 DNSSEC 校验不过关或权威服务器故障。"
        case "REFUSED":
            return "REFUSED：这台服务器拒绝为这个查询服务，很多公共 DNS 不接受 ANY 类型查询。"
        case "NOTIMP":
            return "NOTIMP：服务器不认这个查询类型。"
        case "NOERROR":
            return answers.isEmpty ? "NOERROR 但没有记录：域名存在，只是没有这个类型的记录。" : nil
        default:
            return nil
        }
    }
}

struct DNSResolverInfo: Identifiable, Sendable {
    let id: Int
    var servers: [String]
    var domains: [String]
    var interface: String?
    var flags: String?
}

struct DNSHostEntry: Identifiable, Sendable {
    var id: String { "\(ip)-\(names.joined(separator: ","))" }
    let ip: String
    let names: [String]
    var isLocal: Bool {
        ip.hasPrefix("127.") || ip == "::1" || ip.hasPrefix("fe80")
    }
}

struct LocalDNSConfig: Sendable {
    var resolvers: [DNSResolverInfo]
    var searchDomains: [String]
    var hosts: [DNSHostEntry]
}

// MARK: - 错误文案

/// 把 URLSession 那套错误码翻译成人话，顺带把 HTTP 状态码也翻译一遍
enum NetErrorText {
    static func friendly(_ error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return error.localizedDescription }

        switch nsError.code {
        case NSURLErrorTimedOut:
            return "超时：对方没有在时限内响应（-1001）"
        case NSURLErrorCannotFindHost:
            return "域名解析失败（-1003）：域名可能拼错了，或者 DNS 有问题"
        case NSURLErrorDNSLookupFailed:
            return "DNS 查询失败（-1006）"
        case NSURLErrorCannotConnectToHost:
            return "连不上主机（-1004）：端口没开、服务没起，或者被防火墙挡了"
        case NSURLErrorNetworkConnectionLost:
            return "连接中途断了（-1005）"
        case NSURLErrorNotConnectedToInternet:
            return "当前没有网络连接（-1009）"
        case NSURLErrorSecureConnectionFailed:
            return "TLS 握手失败（-1200）：如果是自签证书，打开「信任自签证书」再试"
        case NSURLErrorServerCertificateUntrusted:
            return "证书不被信任（-1202）：自签证书可以打开「信任自签证书」"
        case NSURLErrorServerCertificateHasBadDate:
            return "证书已过期或还没生效（-1201）"
        case NSURLErrorServerCertificateHasUnknownRoot:
            return "证书的根证书不认识（-1203）"
        case NSURLErrorAppTransportSecurityRequiresSecureConnection:
            return "被 ATS 拦下了（-1022）：这个明文 HTTP 请求需要放开 ATS 限制"
        case NSURLErrorHTTPTooManyRedirects:
            return "重定向次数过多（-1007）"
        case NSURLErrorCancelled:
            return "请求已取消（-999）"
        case NSURLErrorBadURL, NSURLErrorUnsupportedURL:
            return "地址不合法（\(nsError.code)）"
        case NSURLErrorUserAuthenticationRequired:
            return "服务器要求认证（-1013）"
        case NSURLErrorCannotParseResponse:
            return "响应解析不了（-1017）：对方返回的可能不是 HTTP"
        default:
            return "网络错误（\(nsError.code)）：\(nsError.localizedDescription)"
        }
    }

    /// HTTP 状态码的中文解释
    static func statusNote(_ code: Int) -> String {
        switch code {
        case 100...199: return "信息响应"
        case 200: return "成功"
        case 201: return "已创建"
        case 202: return "已接受"
        case 204: return "成功，无内容"
        case 206: return "部分内容（断点续传）"
        case 301: return "永久重定向"
        case 302, 303, 307: return "临时重定向"
        case 304: return "内容没变（走缓存）"
        case 308: return "永久重定向（保留方法）"
        case 400: return "请求有问题"
        case 401: return "未认证，需要凭据"
        case 403: return "被拒绝，权限不够"
        case 404: return "路径不存在"
        case 405: return "方法不被允许"
        case 406: return "内容类型不接受"
        case 408: return "请求超时"
        case 409: return "冲突"
        case 410: return "资源已删除"
        case 413: return "请求体太大"
        case 415: return "不支持的媒体类型"
        case 418: return "我是茶壶"
        case 422: return "参数校验不通过"
        case 429: return "请求太频繁，被限流"
        case 500: return "服务端内部错误"
        case 501: return "服务端不支持该方法"
        case 502: return "网关错误（后端挂了）"
        case 503: return "服务不可用（过载或维护）"
        case 504: return "网关超时"
        default: return code >= 500 ? "服务端错误" : "未知状态"
        }
    }
}

