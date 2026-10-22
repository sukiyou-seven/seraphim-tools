import Foundation

// MARK: - 时间戳单位

enum TimestampUnit: String, CaseIterable, Identifiable, Sendable {
    case auto
    case seconds
    case milliseconds
    case microseconds
    case nanoseconds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "自动"
        case .seconds: return "秒"
        case .milliseconds: return "毫秒"
        case .microseconds: return "微秒"
        case .nanoseconds: return "纳秒"
        }
    }

    /// 一秒等于多少该单位
    var perSecond: Double {
        switch self {
        case .auto, .seconds: return 1
        case .milliseconds: return 1_000
        case .microseconds: return 1_000_000
        case .nanoseconds: return 1_000_000_000
        }
    }

    var digitHint: String {
        switch self {
        case .auto: return "10 / 13 / 16 / 19 位都认"
        case .seconds: return "10 位"
        case .milliseconds: return "13 位"
        case .microseconds: return "16 位"
        case .nanoseconds: return "19 位"
        }
    }
}

// MARK: - 时间戳展示行

/// 一条"时刻 → 某种表示"的结果行
struct TimestampDisplay: Identifiable, Sendable {
    let id: String
    let title: String
    let value: String
    var hint: String?
    var highlight: Bool = false

    init(id: String, title: String, value: String, hint: String? = nil, highlight: Bool = false) {
        self.id = id
        self.title = title
        self.value = value
        self.hint = hint
        self.highlight = highlight
    }
}

/// 时区对照的一行
struct TimeZoneLine: Identifiable, Sendable {
    var id: String { identifier }
    let city: String
    let identifier: String
    let time: String
    let offset: String
    let dayShift: Int   // 相对所选时区的日偏移，-1 / 0 / +1
}

// MARK: - 正则

struct RegexOptions: Sendable, Equatable {
    var ignoreCase = false
    var anchorsMatchLines = false
    var dotMatchesLineSeparators = false
    var allowCommentsAndWhitespace = false
    var unicodeWordBoundaries = false

    var nsOptions: NSRegularExpression.Options {
        var result: NSRegularExpression.Options = []
        if ignoreCase { result.insert(.caseInsensitive) }
        if anchorsMatchLines { result.insert(.anchorsMatchLines) }
        if dotMatchesLineSeparators { result.insert(.dotMatchesLineSeparators) }
        if allowCommentsAndWhitespace { result.insert(.allowCommentsAndWhitespace) }
        if unicodeWordBoundaries { result.insert(.useUnicodeWordBoundaries) }
        return result
    }

    /// 形如 "im" 的旗标字符串，没开任何选项时返回空串
    var flagLetters: String {
        var letters = ""
        if ignoreCase { letters += "i" }
        if anchorsMatchLines { letters += "m" }
        if dotMatchesLineSeparators { letters += "s" }
        if allowCommentsAndWhitespace { letters += "x" }
        if unicodeWordBoundaries { letters += "w" }
        return letters
    }

    /// 加旗标后的正则字面量，比如 /abc/im
    func literal(_ pattern: String) -> String {
        let letters = flagLetters
        return "/" + pattern + "/" + letters
    }
}

struct RegexGroupInfo: Identifiable, Sendable {
    let id: Int
    let name: String?
    let text: String?
    let location: Int
    let length: Int

    var isEmpty: Bool { text == nil }        // 未参与匹配
    var isVoid: Bool { (text ?? "").isEmpty } // 匹配到空串
}

struct RegexMatchInfo: Identifiable, Sendable {
    let id: Int          // 第几个匹配（从 1 开始）
    let text: String
    let location: Int    // UTF-16 偏移
    let length: Int
    let groups: [RegexGroupInfo]

    var rangeText: String { "\(location)…\(location + length)" }
}

/// 匹配文本里的一段（用于高亮渲染）
struct RegexSegment: Identifiable, Sendable {
    let id: Int
    let text: String
    let isMatch: Bool
    let matchIndex: Int?   // 命中的是第几个匹配
}

// MARK: - 正则模板

struct RegexSnippet: Identifiable, Sendable {
    let id: String
    let title: String
    let pattern: String
    let note: String
    let sample: String
    let category: String
}

/// 语法速查里的一行
struct RegexToken: Identifiable, Sendable {
    let id: String
    let token: String
    let meaning: String
}

// MARK: - 端口

enum PortState: String, Sendable {
    case open
    case closed
    case filtered   // 超时无响应，通常是防火墙丢包
    case failed     // 解析或系统错误

    var title: String {
        switch self {
        case .open: return "开放"
        case .closed: return "关闭"
        case .filtered: return "超时"
        case .failed: return "失败"
        }
    }
}

struct PortScanResult: Identifiable, Sendable {
    var id: UInt16 { port }
    let port: UInt16
    let state: PortState
    /// 握手耗时（毫秒），只有开放端口有
    let latency: Double?
    let note: String?

    var service: String { PortCatalog.serviceName(for: port) }
}

/// 预设端口组
struct PortGroup: Identifiable, Sendable {
    let id: String
    let title: String
    let ports: [UInt16]

    static let all: [PortGroup] = [
        PortGroup(id: "common", title: "常用", ports: [21, 22, 23, 25, 53, 80, 110, 143, 443, 465, 587, 993, 995, 1080, 3000, 3306, 3389, 5432, 6379, 8080, 8443, 9200, 27017]),
        PortGroup(id: "web", title: "Web / 前端", ports: [80, 443, 1313, 3000, 3001, 4200, 5000, 5173, 5174, 8000, 8001, 8080, 8081, 8443, 8888, 9000]),
        PortGroup(id: "db", title: "数据库", ports: [1433, 1521, 3306, 5432, 5984, 6379, 7000, 7199, 8086, 9042, 11211, 27017, 50000]),
        PortGroup(id: "remote", title: "远程 / 运维", ports: [22, 23, 873, 2375, 2376, 3389, 5900, 5985, 5986, 6443, 10250]),
        PortGroup(id: "mq", title: "消息 / 中间件", ports: [1883, 2181, 5672, 61616, 9092, 15672, 9090, 8083]),
        PortGroup(id: "game", title: "游戏 / 其他", ports: [25565, 19132, 7777, 7778, 27015, 34197, 51820]),
    ]
}

/// 端口 → 服务名，纯粹为了结果好看，不追求全量
enum PortCatalog {
    private static let names: [UInt16: String] = [
        20: "FTP-Data", 21: "FTP", 22: "SSH", 23: "Telnet", 25: "SMTP", 53: "DNS",
        67: "DHCP", 69: "TFTP", 80: "HTTP", 110: "POP3", 111: "RPC", 123: "NTP",
        135: "MSRPC", 137: "NetBIOS", 138: "NetBIOS", 139: "NetBIOS", 143: "IMAP",
        161: "SNMP", 389: "LDAP", 443: "HTTPS", 445: "SMB", 465: "SMTPS", 500: "ISAKMP",
        514: "Syslog", 515: "LPD", 548: "AFP", 554: "RTSP", 587: "SMTP", 631: "IPP",
        636: "LDAPS", 873: "rsync", 902: "VMware", 993: "IMAPS", 995: "POP3S",
        1080: "SOCKS", 1194: "OpenVPN", 1313: "Hugo", 1433: "SQL Server", 1521: "Oracle",
        1701: "L2TP", 1723: "PPTP", 1883: "MQTT", 2049: "NFS", 2181: "ZooKeeper",
        2375: "Docker", 2376: "Docker TLS", 3000: "Node / Rails", 3001: "Node",
        3128: "Squid", 3306: "MySQL", 3389: "RDP", 4200: "Angular", 5000: "Flask / UPnP",
        5060: "SIP", 5173: "Vite", 5222: "XMPP", 5353: "mDNS", 5432: "PostgreSQL",
        5566: "Jellyfin", 5672: "RabbitMQ", 5900: "VNC", 5984: "CouchDB",
        5985: "WinRM", 5986: "WinRM TLS", 6000: "X11", 6379: "Redis", 6443: "K8s API",
        7000: "Cassandra", 7199: "Cassandra JMX", 7777: "Game", 8000: "HTTP-alt",
        8001: "HTTP-alt", 8008: "HTTP-alt", 8080: "HTTP-alt", 8081: "HTTP-alt",
        8083: "InfluxDB", 8086: "InfluxDB", 8088: "Hadoop", 8443: "HTTPS-alt",
        8888: "HTTP-alt", 9000: "SonarQube / PHP-FPM", 9042: "Cassandra CQL",
        9090: "Prometheus", 9092: "Kafka", 9200: "Elasticsearch", 9300: "Elasticsearch",
        9418: "Git", 10250: "Kubelet", 11211: "Memcached", 15672: "RabbitMQ UI",
        19132: "Minecraft BE", 25565: "Minecraft", 27015: "Source Dedicated",
        27017: "MongoDB", 34197: "Factorio", 50000: "DB2", 51820: "WireGuard",
        61616: "ActiveMQ", 62078: "iPhone Sync",
    ]

    static func serviceName(for port: UInt16) -> String {
        names[port] ?? "—"
    }
}
