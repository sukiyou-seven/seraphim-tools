import CryptoKit
import Foundation

// MARK: - 版本与命名空间

/// 工具箱支持的 UUID 版本。v2（DCE Security）早就没人用了，不做。
enum UUIDVersion: String, CaseIterable, Identifiable, Sendable {
    case v1, v3, v4, v5, v6, v7

    var id: String { rawValue }

    var number: Int { Int(rawValue.dropFirst()) ?? 4 }

    var title: String { rawValue.uppercased() }

    var note: String {
        switch self {
        case .v1: return "时间 + MAC：能看出生成时刻和网卡，但会泄露机器信息"
        case .v3: return "MD5 名字散列：同一个名字永远得到同一个 UUID，不可逆"
        case .v4: return "纯随机：最常用，122 位随机数"
        case .v5: return "SHA-1 名字散列：和 v3 一个思路，散列更强"
        case .v6: return "v1 的重新排列：把时间放前面，能按时间排序了"
        case .v7: return "Unix 毫秒 + 随机：现代首选，天然有序（数据库主键友好）"
        }
    }

    var isNamed: Bool { self == .v3 || self == .v5 }

    var systemImage: String {
        switch self {
        case .v1: return "clock.badge.checkmark"
        case .v3: return "number.square"
        case .v4: return "dice"
        case .v5: return "number.square.fill"
        case .v6: return "arrow.up.arrow.down"
        case .v7: return "chart.line.uptrend.xyaxis"
        }
    }
}

/// RFC 4122 预定义的四个命名空间
enum UUIDNamespaceKind: String, CaseIterable, Identifiable, Sendable {
    case dns, url, oid, x500

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dns: return "DNS"
        case .url: return "URL"
        case .oid: return "OID"
        case .x500: return "X.500"
        }
    }

    var uuid: UUID {
        switch self {
        case .dns: return UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!
        case .url: return UUID(uuidString: "6ba7b811-9dad-11d1-80b4-00c04fd430c8")!
        case .oid: return UUID(uuidString: "6ba7b812-9dad-11d1-80b4-00c04fd430c8")!
        case .x500: return UUID(uuidString: "6ba7b814-9dad-11d1-80b4-00c04fd430c8")!
        }
    }

    var note: String {
        switch self {
        case .dns: return "域名（example.com）"
        case .url: return "网址（https://example.com/）"
        case .oid: return "对象标识符"
        case .x500: return "X.500 专有名称"
        }
    }
}

// MARK: - 解析结果

enum UUIDVariant: Sendable {
    case ncs            // 0xx —— 早期 Apollo NCS 兼容
    case rfc4122        // 10x —— 现在说的 UUID 基本都是这个
    case microsoft      // 110 —— 微软 GUID 变体
    case future         // 111 —— 保留

    var title: String {
        switch self {
        case .ncs: return "NCS（老 Apollo）"
        case .rfc4122: return "RFC 4122 / 9562"
        case .microsoft: return "Microsoft GUID"
        case .future: return "保留（未来定义）"
        }
    }

    var isStandard: Bool { self == .rfc4122 }
}

/// UUID 里的一段（按版本切分展示）
struct UUIDField: Sendable, Identifiable {
    let name: String
    let bits: String
    let hex: String
    let meaning: String

    var id: String { name }
}

struct UUIDParseResult: Sendable {
    var canonical: String
    var compact: String
    var urn: String
    var version: Int
    var variant: UUIDVariant
    var fields: [UUIDField]
    var timestamp: Date?
    var timestampDetail: String?
    var clockSequence: Int?
    var node: String?
    var nodeDetail: String?
    var warnings: [String]

    var versionTitle: String {
        version == 0 ? "未指定（Nil UUID）" : "v\(version)"
    }

    var versionNote: String {
        switch version {
        case 1: return "时间戳 + MAC 地址"
        case 2: return "DCE Security（已废弃，很少见）"
        case 3: return "MD5 名字散列"
        case 4: return "随机数"
        case 5: return "SHA-1 名字散列"
        case 6: return "v1 重排（可排序）"
        case 7: return "Unix 毫秒 + 随机（可排序）"
        case 8: return "自定义（RFC 9562 实验位）"
        default: return "未指定"
        }
    }
}

enum UUIDError: LocalizedError {
    case empty
    case badLength(Int)
    case badCharacter(String)
    case notUUID

    var errorDescription: String? {
        switch self {
        case .empty: return "先把 UUID 贴进来"
        case .badLength(let count): return "长度不对：去掉分隔符后应该是 32 个十六进制字符，现在是 \(count) 个"
        case .badCharacter(let text): return "\"\(text)\" 不是十六进制字符（只认 0-9 a-f）"
        case .notUUID: return "这不是一个合法的 UUID"
        }
    }
}

// MARK: - 引擎

enum UUIDEngine {

    /// 1582-10-15 00:00:00 UTC 到 1970-01-01 的秒数，v1/v6 的时间基准
    static let gregorianOffset: UInt64 = 12_219_292_800

    // MARK: 解析

    /// 宽容地把各种写法收敛成 16 字节。
    /// 认：带连字符、不带连字符、`{}` 包着、`urn:uuid:` 前缀、全大写。
    static func bytes(from text: String) throws -> [UInt8] {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw UUIDError.empty }

        let lower = raw.lowercased()
        if lower.hasPrefix("urn:uuid:") { raw = String(raw.dropFirst(9)) }
        raw = raw.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
        raw = raw.replacingOccurrences(of: "-", with: "")
        raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        guard raw.count == 32 else { throw UUIDError.badLength(raw.count) }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(16)
        var index = raw.startIndex
        while index < raw.endIndex {
            let next = raw.index(index, offsetBy: 2)
            let pair = String(raw[index..<next])
            guard let value = UInt8(pair, radix: 16) else {
                throw UUIDError.badCharacter(pair)
            }
            bytes.append(value)
            index = next
        }
        return bytes
    }

    static func normalize(_ text: String) -> String? {
        guard let bytes = try? bytes(from: text) else { return nil }
        return canonical(bytes)
    }

    /// 16 字节 → 8-4-4-4-12。多退少补，避免误用时直接崩
    static func canonical(_ bytes: [UInt8]) -> String {
        var normalized = Array(bytes.prefix(16))
        while normalized.count < 16 { normalized.append(0) }
        let hex = normalized.map { String(format: "%02x", $0) }.joined()
        func slice(_ start: Int, _ length: Int) -> String {
            let from = hex.index(hex.startIndex, offsetBy: start)
            let to = hex.index(from, offsetBy: length)
            return String(hex[from..<to])
        }
        return [slice(0, 8), slice(8, 4), slice(12, 4), slice(16, 4), slice(20, 12)]
            .joined(separator: "-")
    }

    static func parse(_ text: String) throws -> UUIDParseResult {
        let bytes = try bytes(from: text)
        return parse(bytes: bytes)
    }

    static func parse(bytes: [UInt8]) -> UUIDParseResult {
        precondition(bytes.count == 16)
        let version = Int((bytes[6] >> 4) & 0x0F)
        let variant = variant(of: bytes[8])

        var fields: [UUIDField] = []
        var timestamp: Date?
        var timestampDetail: String?
        var clockSequence: Int?
        var node: String?
        var nodeDetail: String?
        var warnings: [String] = []

        func hex(_ range: Range<Int>) -> String {
            range.map { String(format: "%02x", bytes[$0]) }.joined()
        }

        let timeLow = hex(0..<4)
        let timeMid = hex(4..<6)
        let versionNibble = String(format: "%x", version)
        // bytes[6] 低 4 位 + bytes[7] = time_high 的 12 位
        let timeHigh12 = (UInt16(bytes[6] & 0x0F) << 8) | UInt16(bytes[7])
        let timeHigh = String(format: "%03x", timeHigh12)
        // 变体由字节 8 的最高位模式决定：0xx / 10x / 110 / 111
        let variantTop = (bytes[8] >> 6) & 0x03
        let variantRaw = String(variantTop, radix: 2)
        let variantBits = String(repeating: "0", count: max(0, 2 - variantRaw.count)) + variantRaw
        let variantLabel = "\(variantBits)（\(variant.title)）"
        let clockSeq = (UInt16(bytes[8] & 0x3F) << 8) | UInt16(bytes[9])
        let nodeHex = hex(10..<16)

        switch version {
        case 1, 6:
            // 60 位时间戳，v1 和 v6 只是摆放顺序不同
            let ts: UInt64
            if version == 1 {
                let low = UInt64(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16
                    | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
                let mid = UInt64(UInt16(bytes[4]) << 8 | UInt16(bytes[5]))
                ts = (UInt64(timeHigh12) << 48) | (mid << 32) | low
            } else {
                let high = UInt64(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16
                    | UInt32(bytes[2]) << 8 | UInt32(bytes[3])) << 28
                let mid = UInt64(UInt16(bytes[4]) << 8 | UInt16(bytes[5])) << 12
                let low = UInt64(timeHigh12)
                ts = high | mid | low
            }
            let seconds = Double(ts) / 10_000_000
            timestamp = Date(timeIntervalSince1970: seconds - Double(gregorianOffset))
            timestampDetail = "100 纳秒计数 \(ts)（起点 1582-10-15 00:00:00 UTC）"
            clockSequence = Int(clockSeq)
            node = nodeHex
            nodeDetail = nodeDescription(nodeHex)
            if version == 1 {
                warnings.append("v1 会暴露生成时间与网卡信息，对外接口里最好用 v4 或 v7")
            }
            fields = version == 1
                ? [
                    UUIDField(name: "time_low", bits: "32 位", hex: timeLow, meaning: "时间戳最低 32 位"),
                    UUIDField(name: "time_mid", bits: "16 位", hex: timeMid, meaning: "时间戳中间 16 位"),
                    UUIDField(name: "version", bits: "4 位", hex: versionNibble, meaning: "版本号 = 1"),
                    UUIDField(name: "time_high", bits: "12 位", hex: timeHigh, meaning: "时间戳最高 12 位"),
                    UUIDField(name: "variant", bits: "2 位", hex: variantBits, meaning: "变体：\(variantLabel)"),
                    UUIDField(name: "clock_seq", bits: "14 位", hex: hex(8..<10), meaning: "变体位 \(variantBits) ＋ 时钟序列 \(clockSeq)，防同一时刻重复"),
                    UUIDField(name: "node", bits: "48 位", hex: nodeHex, meaning: nodeDetail ?? "节点")
                ]
                : [
                    UUIDField(name: "time_high", bits: "32 位", hex: hex(0..<4), meaning: "时间戳最高 32 位"),
                    UUIDField(name: "time_mid", bits: "16 位", hex: hex(4..<6), meaning: "时间戳中间 16 位"),
                    UUIDField(name: "version", bits: "4 位", hex: versionNibble, meaning: "版本号 = 6"),
                    UUIDField(name: "time_low", bits: "12 位", hex: timeHigh, meaning: "时间戳最低 12 位"),
                    UUIDField(name: "variant", bits: "2 位", hex: variantBits, meaning: "变体：\(variantLabel)"),
                    UUIDField(name: "clock_seq", bits: "14 位", hex: hex(8..<10), meaning: "变体位 \(variantBits) ＋ 时钟序列 \(clockSeq)，防同一时刻重复"),
                    UUIDField(name: "node", bits: "48 位", hex: nodeHex, meaning: nodeDetail ?? "节点")
                ]

        case 7:
            let millis = (UInt64(bytes[0]) << 40) | (UInt64(bytes[1]) << 32) | (UInt64(bytes[2]) << 24)
                | (UInt64(bytes[3]) << 16) | (UInt64(bytes[4]) << 8) | UInt64(bytes[5])
            timestamp = Date(timeIntervalSince1970: Double(millis) / 1000)
            timestampDetail = "Unix 毫秒 \(millis)，前 48 位就是它，所以按字符串排序=按时间排序"
            fields = [
                UUIDField(name: "unix_ts_ms", bits: "48 位", hex: hex(0..<6), meaning: "Unix 毫秒时间戳"),
                UUIDField(name: "ver + rand_a", bits: "16 位", hex: timeMid + versionNibble, meaning: "版本号 7 + 12 位随机数"),
                UUIDField(name: "variant + rand_b", bits: "16 位", hex: hex(8..<10), meaning: "变体 + 62 位随机数开头"),
                UUIDField(name: "rand_b", bits: "48 位", hex: nodeHex, meaning: "剩余随机数"),
            ]

        case 3, 5:
            let algorithm = version == 3 ? "MD5" : "SHA-1"
            fields = [
                UUIDField(name: "digest[0..6]", bits: "48 位", hex: hex(0..<6), meaning: "\(algorithm) 摘要前 6 字节，原样保留"),
                UUIDField(name: "version", bits: "4 位", hex: versionNibble, meaning: "版本号 = \(version)"),
                UUIDField(name: "digest[6].low", bits: "4 位", hex: String(format: "%x", bytes[6] & 0x0F), meaning: "摘要第 7 字节的低 4 位"),
                UUIDField(name: "digest[7]", bits: "8 位", hex: hex(7..<8), meaning: "摘要第 8 字节"),
                UUIDField(name: "variant", bits: "2 位", hex: variantBits, meaning: "变体：\(variantLabel)"),
                UUIDField(name: "digest[8..16]", bits: "54 位", hex: String(format: "%02x", bytes[8] & 0x3F) + hex(9..<16),
                          meaning: "摘要剩余部分"),
            ]
            warnings.append("名字散列不可逆：从这个 UUID 反推不出原始名字，只能拿同样的名字重新算一遍比对")

        case 4:
            fields = [
                UUIDField(name: "random_a", bits: "48 位", hex: timeLow + timeMid, meaning: "随机数"),
                UUIDField(name: "version", bits: "4 位", hex: versionNibble, meaning: "版本号 = 4"),
                UUIDField(name: "random_b", bits: "12 位", hex: timeHigh, meaning: "随机数"),
                UUIDField(name: "variant", bits: "2 位", hex: variantBits, meaning: "变体：\(variantLabel)"),
                UUIDField(name: "random_c", bits: "62 位", hex: hex(9..<10) + nodeHex, meaning: "随机数"),
            ]

        default:
            fields = [
                UUIDField(name: "前 48 位", bits: "48 位", hex: hex(0..<6), meaning: "按版本自定义"),
                UUIDField(name: "version", bits: "4 位", hex: versionNibble, meaning: version == 0 ? "未指定" : "版本号 = \(version)"),
                UUIDField(name: "后 60 位", bits: "60 位", hex: timeHigh + variantBits + hex(9..<16), meaning: "按版本自定义"),
            ]
            if version == 2 {
                warnings.append("v2 是 DCE Security，早就废弃了；还能见到多半是历史数据")
            }
        }

        if !variant.isStandard {
            warnings.append("变体是 \(variant.title)，不是常规的 RFC 4122 变体，可能有兼容问题")
        }
        if bytes.allSatisfy({ $0 == 0 }) {
            warnings.append("这是全零的 Nil UUID，一般表示\"没有值\"")
        } else if bytes == Array(repeating: 0xFF, count: 16) {
            warnings.append("这是全 F 的 Max UUID（RFC 9562 新增），一般表示\"最大值/哨兵\"")
        }

        return UUIDParseResult(
            canonical: canonical(bytes),
            compact: bytes.map { String(format: "%02x", $0) }.joined(),
            urn: "urn:uuid:" + canonical(bytes),
            version: version,
            variant: variant,
            fields: fields,
            timestamp: timestamp,
            timestampDetail: timestampDetail,
            clockSequence: clockSequence,
            node: node,
            nodeDetail: nodeDetail,
            warnings: warnings
        )
    }

    private static func variant(of byte: UInt8) -> UUIDVariant {
        if byte & 0x80 == 0 { return .ncs }
        if byte & 0xC0 == 0x80 { return .rfc4122 }
        if byte & 0xE0 == 0xC0 { return .microsoft }
        return .future
    }

    private static func nodeDescription(_ hex: String) -> String {
        guard hex.count == 12 else { return "节点" }
        guard let first = UInt8(hex.prefix(2), radix: 16) else { return "节点" }

        let text = stride(from: 0, to: 12, by: 2).map { offset -> String in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 2)
            return String(hex[start..<end])
        }.joined(separator: ":").uppercased()

        // 多播位（第一个字节最低位）被置 1 = 节点是随机生成的，不是真网卡
        if first & 0x01 == 1 {
            return "\(text)（随机生成的节点，多播位置 1，不泄露网卡）"
        }
        return "\(text)（看起来是真实网卡的 MAC）"
    }

    // MARK: 生成

    /// v4 / v1 / v6 / v7 直接生成；命名版本走 generateNamed
    static func generate(version: UUIDVersion, count: Int, useRealNode: Bool = false) -> [String] {
        switch version {
        case .v4:
            return (0..<count).map { _ in canonical(randomBytes()) }
        case .v1:
            return (0..<count).map { _ in canonical(UUIDV1Clock.shared.next(version: 1, useRealNode: useRealNode)) }
        case .v6:
            return (0..<count).map { _ in canonical(UUIDV1Clock.shared.next(version: 6, useRealNode: useRealNode)) }
        case .v7:
            return (0..<count).map { _ in canonical(makeV7()) }
        case .v3:
            return []
        case .v5:
            return []
        }
    }

    /// v3 / v5：名字 + 命名空间 → 确定性 UUID。同样的输入永远得到同样的结果。
    static func generateNamed(version: UUIDVersion, namespace: UUID, name: String) -> String {
        var data = withUnsafeBytes(of: namespace.uuid) { Data($0) }
        data.append(contentsOf: Array(name.utf8))

        var digest: [UInt8]
        if version == .v3 {
            digest = Array(Insecure.MD5.hash(data: data))
        } else {
            digest = Array(Insecure.SHA1.hash(data: data))
        }
        digest = Array(digest.prefix(16))
        digest[6] = (digest[6] & 0x0F) | (UInt8(version.number) << 4)
        digest[8] = (digest[8] & 0x3F) | 0x80
        return canonical(digest)
    }

    private static func randomBytes() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<16 { bytes[index] = UInt8.random(in: 0...255) }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return bytes
    }

    /// v7：48 位 Unix 毫秒 + 12 位计数 + 62 位随机。
    ///
    /// 同一毫秒内 rand_a 当计数器用（RFC 9562 推荐做法），这样连发出来的 v7 仍然是
    /// 严格递增的——不然一个毫秒里生成一批，字符串排序会乱掉，做数据库主键就失去意义了。
    private static func makeV7() -> [UInt8] {
        let millis = UInt64(Date().timeIntervalSince1970 * 1000)

        v7Lock.lock()
        if millis == v7LastMillis {
            v7Counter = (v7Counter + 1) & 0x0FFF
        } else {
            v7LastMillis = millis
            v7Counter = UInt16.random(in: 0..<0x0400)   // 换毫秒时随机起点，避免有规律
        }
        let counter = v7Counter
        v7Lock.unlock()

        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<6 { bytes[index] = UInt8((millis >> (8 * (5 - index))) & 0xFF) }
        bytes[6] = 0x70 | UInt8((counter >> 8) & 0x0F)
        bytes[7] = UInt8(counter & 0xFF)
        for index in 8..<16 { bytes[index] = UInt8.random(in: 0...255) }
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return bytes
    }

    /// v7 的毫秒内计数器状态
    private static let v7Lock = NSLock()
    private static var v7LastMillis: UInt64 = 0
    private static var v7Counter: UInt16 = 0

    /// 本机网卡 MAC（v1/v6 想用真节点时用；默认还是随机节点，更保护隐私）
    static func localMACAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let interface = current.pointee
            let family = interface.ifa_addr.pointee.sa_family
            if family == UInt8(AF_LINK) {
                let name = String(cString: interface.ifa_name)
                if name != "lo0", let data = interface.ifa_addr {
                    var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                   &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let mac = String(cString: buffer)
                        let parts = mac.split(separator: ":")
                        if parts.count == 6, mac != "00:00:00:00:00:00",
                           !mac.hasPrefix("02:00:00") {
                            address = mac.uppercased()
                            break
                        }
                    }
                }
            }
            pointer = interface.ifa_next
        }
        return address
    }
}

// MARK: - v1 / v6 的时钟状态

/// v1/v6 需要一个不会重复的时钟序列，还要防时钟回拨。
final class UUIDV1Clock {
    static let shared = UUIDV1Clock()

    private let lock = NSLock()
    /// 上一次的墙钟读数。和 lastTimestamp 分开：跑得快时生成的时间戳会略微领先墙钟，
    /// 拿它当"回拨判据"会误判
    private var lastWall: UInt64 = 0
    private var lastTimestamp: UInt64 = 0
    private var clockSequence: UInt16 = UInt16.random(in: 0..<0x4000)
    private lazy var randomNode: [UInt8] = {
        var node = (0..<6).map { _ in UInt8.random(in: 0...255) }
        node[0] |= 0x01     // 多播位置 1，标明这是随机节点而不是真网卡
        return node
    }()

    private init() {}

    /// 重置时钟序列（界面上换一种节点来源时调用，避免继续用旧序列）
    func reseed() {
        lock.lock(); defer { lock.unlock() }
        clockSequence = UInt16.random(in: 0..<0x4000)
    }

    func next(version: Int, useRealNode: Bool = false) -> [UInt8] {
        lock.lock(); defer { lock.unlock() }

        let wall = wallTimestamp()
        let timestamp: UInt64

        if wall <= lastWall {
            // 墙钟没往前走（本机时钟粒度 1 微秒，连发生成时很常见）或者真的回拨了。
            // 两种都接着上一个生成的时间戳往后推，保证严格递增不重复。
            if wall < lastWall {
                // 只有墙钟真的退回去了才换时钟序列（RFC 4122 的做法）
                clockSequence = (clockSequence + 1) & 0x3FFF
            }
            timestamp = lastTimestamp + 1
        } else {
            // 墙钟正常往前走。注意要把"上一次生成时往前推的那点零头"带上，
            // 否则跑得快的时候会生成出比上一个还小的时间戳。
            timestamp = max(wall, lastTimestamp + 1)
        }

        lastWall = wall
        lastTimestamp = timestamp

        let node = nodeBytes(useRealNode: useRealNode)
        return compose(timestamp: timestamp, clockSequence: clockSequence, node: node, version: version)
    }

    /// 当前墙钟换算成 100 纳秒计数（起点 1582-10-15 00:00:00 UTC）
    private func wallTimestamp() -> UInt64 {
        let now = Date().timeIntervalSince1970
        let seconds = UInt64(now)
        let fraction = now - Double(seconds)
        return (seconds + UUIDEngine.gregorianOffset) * 10_000_000 + UInt64(fraction * 10_000_000)
    }

    private func nodeBytes(useRealNode: Bool) -> [UInt8] {
        guard useRealNode, let mac = UUIDEngine.localMACAddress() else { return randomNode }
        let parts = mac.split(separator: ":")
        guard parts.count == 6 else { return randomNode }
        return parts.compactMap { UInt8($0, radix: 16) }
    }

    /// 按版本摆放 60 位时间戳、时钟序列和节点
    private func compose(timestamp: UInt64, clockSequence: UInt16, node: [UInt8], version: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 16)
        let timeLow = UInt32(timestamp & 0xFFFF_FFFF)
        let timeMid = UInt16((timestamp >> 32) & 0xFFFF)
        let timeHigh = UInt16((timestamp >> 48) & 0x0FFF)

        if version == 1 {
            bytes[0] = UInt8((timeLow >> 24) & 0xFF)
            bytes[1] = UInt8((timeLow >> 16) & 0xFF)
            bytes[2] = UInt8((timeLow >> 8) & 0xFF)
            bytes[3] = UInt8(timeLow & 0xFF)
            bytes[4] = UInt8((timeMid >> 8) & 0xFF)
            bytes[5] = UInt8(timeMid & 0xFF)
            bytes[6] = 0x10 | UInt8((timeHigh >> 8) & 0x0F)
            bytes[7] = UInt8(timeHigh & 0xFF)
        } else {
            // v6：整个 60 位时间戳大端摆放，字符串排序即时间排序
            bytes[0] = UInt8((timestamp >> 52) & 0xFF)
            bytes[1] = UInt8((timestamp >> 44) & 0xFF)
            bytes[2] = UInt8((timestamp >> 36) & 0xFF)
            bytes[3] = UInt8((timestamp >> 28) & 0xFF)
            bytes[4] = UInt8((timestamp >> 20) & 0xFF)
            bytes[5] = UInt8((timestamp >> 12) & 0xFF)
            bytes[6] = 0x60 | UInt8((timestamp >> 8) & 0x0F)
            bytes[7] = UInt8(timestamp & 0xFF)
        }

        bytes[8] = 0x80 | UInt8((clockSequence >> 8) & 0x3F)
        bytes[9] = UInt8(clockSequence & 0xFF)
        for index in 0..<6 { bytes[10 + index] = node[index] }
        return bytes
    }
}
