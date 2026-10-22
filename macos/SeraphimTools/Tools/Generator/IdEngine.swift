import Foundation

// MARK: - 短 ID 风格

enum ShortIDStyle: String, CaseIterable, Identifiable, Sendable {
    case uuidStandard
    case uuidNoDash
    case uuidBase62
    case nanoID
    case base62
    case base36
    case numeric
    case inviteCode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .uuidStandard: return "UUID v4"
        case .uuidNoDash: return "UUID 去横线"
        case .uuidBase62: return "UUID 转 Base62"
        case .nanoID: return "NanoID"
        case .base62: return "Base62"
        case .base36: return "Base36"
        case .numeric: return "纯数字"
        case .inviteCode: return "邀请码风格"
        }
    }

    /// 该风格是否固定长度（固定的话界面就不显示长度输入）
    var fixedLength: Int? {
        switch self {
        case .uuidStandard: return 36
        case .uuidNoDash: return 32
        case .uuidBase62: return 22
        default: return nil
        }
    }

    var defaultLength: Int {
        switch self {
        case .uuidStandard: return 36
        case .uuidNoDash: return 32
        case .uuidBase62: return 22
        case .nanoID: return 21
        case .base62: return 12
        case .base36: return 16
        case .numeric: return 16
        case .inviteCode: return 8
        }
    }

    var lengthRange: ClosedRange<Int> {
        switch self {
        case .nanoID: return 4...64
        case .base62: return 4...64
        case .base36: return 4...48
        case .numeric: return 4...48
        case .inviteCode: return 4...32
        default: return defaultLength...defaultLength
        }
    }

    var note: String {
        switch self {
        case .uuidStandard: return "RFC 4122 标准写法，8-4-4-4-12"
        case .uuidNoDash: return "32 位十六进制，去掉连字符，常见于数据库主键"
        case .uuidBase62: return "128 位压到 62 进制，22 个字符，比十六进制短 1/3"
        case .nanoID: return "URL 安全字符集，默认 21 位约 126 bit 随机"
        case .base62: return "0-9A-Za-z 随机，长度自定"
        case .base36: return "0-9A-Z 随机，比 Base62 更保守"
        case .numeric: return "纯数字，适合订单号这类场景"
        case .inviteCode: return "去掉了 0/O/1/I/L 等易混字符，适合让人手抄"
        }
    }
}

// MARK: - 随机字母表

enum IDAlphabet {
    static let base62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    static let base36 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    static let digits = "0123456789"
    /// 去掉容易看错的字符（0/O、1/I/L）
    static let readable = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
    /// NanoID 官方默认字母表
    static let nanoID = "_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
}

// MARK: - Snowflake 配置

struct SnowflakeConfig: Sendable, Equatable {
    /// 起始纪元（毫秒）
    var epochMilliseconds: Int64
    /// 机器位宽
    var machineBits: Int
    /// 序列位宽
    var sequenceBits: Int
    /// 当前机器号
    var machineID: Int64

    /// 时间戳位宽（符号位固定占 1 位，永远为 0）
    var timeBits: Int { 63 - machineBits - sequenceBits }

    var maxMachine: Int64 { (1 << machineBits) - 1 }
    var maxSequence: Int64 { (1 << sequenceBits) - 1 }

    /// 每毫秒能出多少个 ID
    var idsPerMillisecond: Int64 { 1 << sequenceBits }

    /// 时间戳可覆盖的年数
    var lifespanYears: Double {
        let milliseconds = pow(2.0, Double(timeBits))
        return milliseconds / 1000 / 60 / 60 / 24 / 365.25
    }

    var epochDate: Date { Date(timeIntervalSince1970: Double(epochMilliseconds) / 1000) }

    static func standard(epoch: Int64 = 1_288_834_974_657) -> SnowflakeConfig {
        SnowflakeConfig(epochMilliseconds: epoch, machineBits: 10, sequenceBits: 12, machineID: 1)
    }

    static let twitter = SnowflakeConfig(
        epochMilliseconds: 1_288_834_974_657,
        machineBits: 10,
        sequenceBits: 12,
        machineID: 1
    )

    static let discord = SnowflakeConfig(
        epochMilliseconds: 1_420_070_400_000,
        machineBits: 10,
        sequenceBits: 12,
        machineID: 0
    )

    /// 百度 uid-generator 默认：28 位时间（秒）、22 位机器、13 位序列（实际是秒级）
    static let baidu = SnowflakeConfig(
        epochMilliseconds: 1_288_834_974_657,
        machineBits: 22,
        sequenceBits: 13,
        machineID: 0
    )

    static let unixEpoch = SnowflakeConfig(
        epochMilliseconds: 0,
        machineBits: 10,
        sequenceBits: 12,
        machineID: 1
    )
}

/// 解析出来的一段位
struct SnowflakeSegment: Identifiable, Sendable {
    let id: String
    let title: String
    let bits: String
    let value: Int64
    let meaning: String
    let startBit: Int
}

struct SnowflakeDecoded: Sendable {
    let raw: Int64
    let binary: String
    let timestampMilliseconds: Int64
    let date: Date
    let machineID: Int64
    let sequence: Int64
    let segments: [SnowflakeSegment]
    let config: SnowflakeConfig
}

enum SnowflakeError: LocalizedError {
    case invalidNumber
    case negative
    case machineOutOfRange
    case tooManyBits

    var errorDescription: String? {
        switch self {
        case .invalidNumber: return "这不是一个合法的整数 ID"
        case .negative: return "雪花 ID 是非负整数（最高位固定为 0）"
        case .machineOutOfRange: return "机器号超出当前位宽能表示的范围"
        case .tooManyBits: return "机器位 + 序列位不能超过 63 位"
        }
    }
}

// MARK: - 生成器

/// 雪花 ID 生成器。同一毫秒内靠序列号自增，序列用满就等到下一毫秒。
final class SnowflakeGenerator {
    private let lock = NSLock()
    private var config: SnowflakeConfig
    private var lastMilliseconds: Int64 = -1
    private var sequence: Int64 = 0

    init(config: SnowflakeConfig) {
        self.config = config
    }

    func update(config: SnowflakeConfig) {
        lock.lock()
        defer { lock.unlock() }
        self.config = config
        lastMilliseconds = -1
        sequence = 0
    }

    /// 生成一个雪花 ID。时间回拨时：小幅回拨就等一等，大幅回拨沿用上一次时间戳保证单调递增。
    func next() -> Int64 {
        lock.lock()
        defer { lock.unlock() }

        var now = Int64(Date().timeIntervalSince1970 * 1000)

        if now < lastMilliseconds {
            let drift = lastMilliseconds - now
            if drift <= 5 {
                while now < lastMilliseconds {
                    usleep(200)
                    now = Int64(Date().timeIntervalSince1970 * 1000)
                }
            } else {
                // 时钟被大幅往回拨，宁可让时间戳停在原地也不能发出重复 ID
                now = lastMilliseconds
            }
        }

        if now == lastMilliseconds {
            sequence = (sequence + 1) & config.maxSequence
            if sequence == 0 {
                // 这一毫秒的序列用完了，自旋到下一毫秒
                while now <= lastMilliseconds {
                    usleep(200)
                    now = Int64(Date().timeIntervalSince1970 * 1000)
                }
            }
        } else {
            sequence = 0
        }

        lastMilliseconds = now
        return compose(milliseconds: now, sequence: sequence, config: config)
    }

    /// 纯函数版本的拼装，测试和"指定时间戳生成"都走这里
    static func compose(milliseconds: Int64, sequence: Int64, config: SnowflakeConfig) -> Int64 {
        let elapsed = milliseconds - config.epochMilliseconds
        let timePart = elapsed << (config.machineBits + config.sequenceBits)
        let machinePart = (config.machineID & config.maxMachine) << config.sequenceBits
        let sequencePart = sequence & config.maxSequence
        return timePart | machinePart | sequencePart
    }

    private func compose(milliseconds: Int64, sequence: Int64, config: SnowflakeConfig) -> Int64 {
        SnowflakeGenerator.compose(milliseconds: milliseconds, sequence: sequence, config: config)
    }
}

// MARK: - 引擎

enum IdEngine {

    // MARK: 短 ID

    static func shortID(style: ShortIDStyle, length: Int) -> String {
        switch style {
        case .uuidStandard:
            return UUID().uuidString
        case .uuidNoDash:
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        case .uuidBase62:
            return paddedUUIDBase62()
        case .nanoID:
            return randomString(length: length, alphabet: IDAlphabet.nanoID)
        case .base62:
            return randomString(length: length, alphabet: IDAlphabet.base62)
        case .base36:
            return randomString(length: length, alphabet: IDAlphabet.base36)
        case .numeric:
            return randomString(length: length, alphabet: IDAlphabet.digits)
        case .inviteCode:
            return randomString(length: length, alphabet: IDAlphabet.readable)
        }
    }

    static func shortIDs(style: ShortIDStyle, length: Int, count: Int) -> [String] {
        var result: [String] = []
        result.reserveCapacity(count)
        var seen = Set<String>()
        var attempts = 0
        while result.count < count, attempts < count * 12 {
            attempts += 1
            let value = shortID(style: style, length: length)
            guard !seen.contains(value) else { continue }
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    /// 从字符表里等概率取字符。用 `randomElement` 底层的均匀采样，避免取模偏斜。
    static func randomString(length: Int, alphabet: String) -> String {
        let characters = Array(alphabet)
        guard !characters.isEmpty, length > 0 else { return "" }
        var generator = SystemRandomNumberGenerator()
        var result = ""
        result.reserveCapacity(length)
        for _ in 0..<length {
            result.append(characters.randomElement(using: &generator) ?? characters[0])
        }
        return result
    }

    /// UUID 的 16 字节，按大端当作一个 128 位无符号整数
    static func uuidBytes() -> [UInt8] {
        let uuid = UUID().uuid
        return withUnsafeBytes(of: uuid) { Array($0) }
    }

    /// UUID 转 Base62 并补齐到 22 位。
    /// 128 位最多用到 62^21 多一点，高位是 0 时会短一位，补齐后才好当定长主键用。
    static func paddedUUIDBase62() -> String {
        let encoded = base62(from: uuidBytes())
        guard encoded.count < 22 else { return encoded }
        return String(repeating: "0", count: 22 - encoded.count) + encoded
    }

    /// 大整数转 62 进制（学校竖式除法，逐位除、取余倒排）
    static func base62(from bytes: [UInt8]) -> String {
        let alphabet = Array(IDAlphabet.base62)
        var digits = bytes
        var output: [Character] = []

        while digits.contains(where: { $0 != 0 }) {
            var remainder = 0
            for index in digits.indices {
                let value = remainder * 256 + Int(digits[index])
                digits[index] = UInt8(value / 62)
                remainder = value % 62
            }
            output.append(alphabet[remainder])
        }

        while output.count > 1, output.last == alphabet[0] {
            output.removeLast()
        }
        return String(output.reversed())
    }

    // MARK: 雪花解析

    static func decode(_ raw: Int64, config: SnowflakeConfig) throws -> SnowflakeDecoded {
        guard raw >= 0 else { throw SnowflakeError.negative }
        guard config.machineBits + config.sequenceBits <= 63 else { throw SnowflakeError.tooManyBits }

        let sequenceMask = config.maxSequence
        let machineMask = config.maxMachine

        let sequence = raw & sequenceMask
        let machine = (raw >> config.sequenceBits) & machineMask
        let elapsed = raw >> (config.machineBits + config.sequenceBits)
        let milliseconds = elapsed + config.epochMilliseconds

        let binary = String(raw, radix: 2)
        let padded = String(repeating: "0", count: max(0, 63 - binary.count)) + binary

        // 按 [时间][机器][序列] 切段
        let timeBits = config.timeBits
        let timePart = String(padded.prefix(timeBits))
        let machineStart = padded.index(padded.startIndex, offsetBy: timeBits)
        let machineEnd = padded.index(machineStart, offsetBy: config.machineBits)
        let machinePart = String(padded[machineStart..<machineEnd])
        let sequencePart = String(padded[machineEnd...])

        let date = Date(timeIntervalSince1970: Double(milliseconds) / 1000)

        var segments: [SnowflakeSegment] = []
        segments.append(SnowflakeSegment(
            id: "time",
            title: "时间戳",
            bits: timePart,
            value: elapsed,
            meaning: "距纪元 \(formatDateTime(config.epochDate)) 过了 \(elapsed) ms",
            startBit: config.machineBits + config.sequenceBits
        ))
        segments.append(SnowflakeSegment(
            id: "machine",
            title: "机器 / 工作节点",
            bits: machinePart,
            value: machine,
            meaning: "机器号 \(machine)（上限 \(config.maxMachine)）",
            startBit: config.sequenceBits
        ))
        segments.append(SnowflakeSegment(
            id: "sequence",
            title: "序列号",
            bits: sequencePart,
            value: sequence,
            meaning: "同一毫秒内的第 \(sequence + 1) 个（上限 \(config.idsPerMillisecond) 个）",
            startBit: 0
        ))

        return SnowflakeDecoded(
            raw: raw,
            binary: padded,
            timestampMilliseconds: milliseconds,
            date: date,
            machineID: machine,
            sequence: sequence,
            segments: segments,
            config: config
        )
    }

    static func decode(text: String, config: SnowflakeConfig) throws -> SnowflakeDecoded {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int64(trimmed) else { throw SnowflakeError.invalidNumber }
        return try decode(value, config: config)
    }

    /// 从 ID 反推机器号 / 序列号是否落在合法范围，用来判断这套配置合不合理
    static func sanityCheck(_ decoded: SnowflakeDecoded) -> [String] {
        var notes: [String] = []
        let now = Date()
        if decoded.date > now.addingTimeInterval(60) {
            notes.append("解析出的时间在未来，纪元或位宽配置可能不对")
        }
        if decoded.date < Date(timeIntervalSince1970: 0) {
            notes.append("解析出的时间早于 1970 年，时间位宽多半配错了")
        }
        if decoded.config.machineBits + decoded.config.sequenceBits > 63 {
            notes.append("机器位与序列位之和超过 63，配置不合法")
        }
        if notes.isEmpty {
            notes.append("时间落点正常，位宽配置与 ID 自洽")
        }
        return notes
    }

    static func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}
