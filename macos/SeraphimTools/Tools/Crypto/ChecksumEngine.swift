import Foundation

// MARK: - 家族

/// CRC 的宽度分组。
///
/// 光知道「算个 CRC-16」是不够的——同一个 16 位多项式在不同协议里
/// 初值、反射、末异或都可能不一样，算出来的值完全不同。
/// 所以选完宽度还得选具体变体。
enum CRCFamily: String, CaseIterable, Identifiable {
    case crc8
    case crc16
    case crc32
    case crc64
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crc8: return "CRC-8"
        case .crc16: return "CRC-16"
        case .crc32: return "CRC-32"
        case .crc64: return "CRC-64"
        case .custom: return "自定义"
        }
    }

    /// 该家族固定宽度；自定义由用户填
    var width: Int? {
        switch self {
        case .crc8: return 8
        case .crc16: return 16
        case .crc32: return 32
        case .crc64: return 64
        case .custom: return nil
        }
    }

    var hint: String {
        switch self {
        case .crc8: return "短报文、总线设备"
        case .crc16: return "工业协议主力，参数最杂"
        case .crc32: return "文件与网络校验，平时说的 CRC32 就是它"
        case .crc64: return "超大文件与文件系统"
        case .custom: return "自己填参数，或者拿已有模型改"
        }
    }
}

// MARK: - 参数集

/// 一个 CRC 的完整定义，用的是 Rocksoft™ Model 的六个参数。
///
/// 只给多项式是算不出结果的，别的地方抄来个多项式对不上，
/// 十有八九是初值或反射位没对齐——所以这里把六个参数全摆出来。
struct CRCSpec: Identifiable, Equatable, Sendable {
    let name: String
    let width: Int
    let poly: UInt64
    let initial: UInt64
    /// 输入反射：每个字节按位倒过来再参与运算
    let refin: Bool
    /// 输出反射：算完把结果按位倒过来
    let refout: Bool
    let xorOut: UInt64
    /// 对 "123456789" 的标准结果，拿来验证参数有没有抄错
    let check: UInt64
    /// 协议里的常见别名
    let alias: String
    /// 哪儿在用它
    let note: String
    let isCustom: Bool

    var id: String { name }

    init(
        name: String,
        width: Int,
        poly: UInt64,
        initial: UInt64,
        refin: Bool,
        refout: Bool,
        xorOut: UInt64,
        check: UInt64,
        alias: String = "",
        note: String = "",
        isCustom: Bool = false
    ) {
        self.name = name
        self.width = width
        self.poly = poly
        self.initial = initial
        self.refin = refin
        self.refout = refout
        self.xorOut = xorOut
        self.check = check
        self.alias = alias
        self.note = note
        self.isCustom = isCustom
    }

    var family: CRCFamily {
        CRCFamily.allCases.first { $0.width == width } ?? .custom
    }

    /// 结果占几个字节
    var byteCount: Int { max(1, width / 8) }

    var hexDigits: Int { width / 4 }

    /// 一行摆完六个参数，方便和别处的文档对照
    var parameterLine: String {
        var parts = [
            "poly 0x\(ChecksumEngine.hex(poly, width: width))",
            "init 0x\(ChecksumEngine.hex(initial, width: width))",
        ]
        if refin { parts.append("refin") }
        if refout { parts.append("refout") }
        if xorOut != 0 {
            parts.append("xorout 0x\(ChecksumEngine.hex(xorOut, width: width))")
        }
        return parts.joined(separator: " · ")
    }

    /// 所有预置模型，按宽度排好
    static let presets: [CRCSpec] = [
        // ——— CRC-8 ———
        CRCSpec(name: "CRC-8/SMBUS", width: 8, poly: 0x07, initial: 0x00,
                refin: false, refout: false, xorOut: 0x00, check: 0xF4,
                alias: "CRC-8", note: "SMBus / I²C 总线报文尾"),
        CRCSpec(name: "CRC-8/MAXIM", width: 8, poly: 0x31, initial: 0x00,
                refin: true, refout: true, xorOut: 0x00, check: 0xA1,
                alias: "MAXIM-DOW、DOW-CRC", note: "1-Wire 总线，DS18B20 温度传感器用它"),
        CRCSpec(name: "CRC-8/AUTOSAR", width: 8, poly: 0x2F, initial: 0xFF,
                refin: false, refout: false, xorOut: 0xFF, check: 0xDF,
                note: "AUTOSAR 车载网络"),
        CRCSpec(name: "CRC-8/SAE-J1850", width: 8, poly: 0x1D, initial: 0xFF,
                refin: false, refout: false, xorOut: 0xFF, check: 0x4B,
                note: "SAE J1850 车载总线"),
        CRCSpec(name: "CRC-8/BLUETOOTH", width: 8, poly: 0xA7, initial: 0x00,
                refin: true, refout: true, xorOut: 0x00, check: 0x26,
                note: "蓝牙包头校验"),
        CRCSpec(name: "CRC-8/ROHC", width: 8, poly: 0x07, initial: 0xFF,
                refin: true, refout: true, xorOut: 0x00, check: 0xD0,
                note: "ROHC 头部压缩"),
        CRCSpec(name: "CRC-8/CDMA2000", width: 8, poly: 0x9B, initial: 0xFF,
                refin: false, refout: false, xorOut: 0x00, check: 0xDA,
                note: "cdma2000 寻呼信道"),
        CRCSpec(name: "CRC-8/ITU", width: 8, poly: 0x07, initial: 0x00,
                refin: false, refout: false, xorOut: 0x55, check: 0xA1,
                alias: "I-432-1、CRC-8/ATM", note: "和 SMBUS 只差最后一步异或"),

        // ——— CRC-16 ———
        CRCSpec(name: "CRC-16/ARC", width: 16, poly: 0x8005, initial: 0x0000,
                refin: true, refout: true, xorOut: 0x0000, check: 0xBB3D,
                alias: "IBM、LHA", note: "早期协议通用，LHA 压缩包用它"),
        CRCSpec(name: "CRC-16/MODBUS", width: 16, poly: 0x8005, initial: 0xFFFF,
                refin: true, refout: true, xorOut: 0x0000, check: 0x4B37,
                note: "Modbus RTU 报文尾，发出去时低字节在前"),
        CRCSpec(name: "CRC-16/USB", width: 16, poly: 0x8005, initial: 0xFFFF,
                refin: true, refout: true, xorOut: 0xFFFF, check: 0xB4C8,
                note: "USB 令牌包"),
        CRCSpec(name: "CRC-16/MAXIM", width: 16, poly: 0x8005, initial: 0x0000,
                refin: true, refout: true, xorOut: 0xFFFF, check: 0x44C2,
                note: "1-Wire 长报文"),
        CRCSpec(name: "CRC-16/CCITT-FALSE", width: 16, poly: 0x1021, initial: 0xFFFF,
                refin: false, refout: false, xorOut: 0x0000, check: 0x29B1,
                note: "网上抄来的「CRC-16-CCITT」九成是它"),
        CRCSpec(name: "CRC-16/XMODEM", width: 16, poly: 0x1021, initial: 0x0000,
                refin: false, refout: false, xorOut: 0x0000, check: 0x31C3,
                alias: "ZMODEM、ACORN", note: "XMODEM 文件传输"),
        CRCSpec(name: "CRC-16/X-25", width: 16, poly: 0x1021, initial: 0xFFFF,
                refin: true, refout: true, xorOut: 0xFFFF, check: 0x906E,
                alias: "IBM-SDLC、ISO-HDLC", note: "HDLC / PPP 帧校验序列"),
        CRCSpec(name: "CRC-16/KERMIT", width: 16, poly: 0x1021, initial: 0x0000,
                refin: true, refout: true, xorOut: 0x0000, check: 0x2189,
                alias: "V-41", note: "Kermit 文件传输"),
        CRCSpec(name: "CRC-16/DNP", width: 16, poly: 0x3D65, initial: 0x0000,
                refin: true, refout: true, xorOut: 0xFFFF, check: 0xEA82,
                note: "DNP3 电力规约"),
        CRCSpec(name: "CRC-16/EN-13757", width: 16, poly: 0x3D65, initial: 0x0000,
                refin: false, refout: false, xorOut: 0xFFFF, check: 0xC2B7,
                note: "欧洲仪表总线 M-Bus"),
        CRCSpec(name: "CRC-16/T10-DIF", width: 16, poly: 0x8BB7, initial: 0x0000,
                refin: false, refout: false, xorOut: 0x0000, check: 0xD0DB,
                note: "SCSI 端到端数据完整性"),
        CRCSpec(name: "CRC-16/DECT-R", width: 16, poly: 0x0589, initial: 0x0000,
                refin: false, refout: false, xorOut: 0x0001, check: 0x007E,
                alias: "R-CRC-16", note: "DECT 无绳电话"),
        CRCSpec(name: "CRC-16/TELEDISK", width: 16, poly: 0xA097, initial: 0x0000,
                refin: false, refout: false, xorOut: 0x0000, check: 0x0FB3,
                note: "Teledisk 磁盘镜像"),

        // ——— CRC-32 ———
        CRCSpec(name: "CRC-32/ISO-HDLC", width: 32, poly: 0x04C11DB7, initial: 0xFFFF_FFFF,
                refin: true, refout: true, xorOut: 0xFFFF_FFFF, check: 0xCBF4_3926,
                alias: "CRC-32、PKZIP、ADCCP",
                note: "ZIP / RAR / PNG / 以太网帧尾，平时说的 CRC32 就是它"),
        CRCSpec(name: "CRC-32C", width: 32, poly: 0x1EDC6F41, initial: 0xFFFF_FFFF,
                refin: true, refout: true, xorOut: 0xFFFF_FFFF, check: 0xE306_9283,
                alias: "Castagnoli、CRC-32/ISCSI",
                note: "iSCSI、SSE4.2 有硬件指令、ext4/Btrfs 元数据"),
        CRCSpec(name: "CRC-32/BZIP2", width: 32, poly: 0x04C11DB7, initial: 0xFFFF_FFFF,
                refin: false, refout: false, xorOut: 0xFFFF_FFFF, check: 0xFC89_1918,
                alias: "AAL5", note: "bzip2 压缩块、ATM AAL5"),
        CRCSpec(name: "CRC-32/MPEG-2", width: 32, poly: 0x04C11DB7, initial: 0xFFFF_FFFF,
                refin: false, refout: false, xorOut: 0x0000_0000, check: 0x0376_E6E7,
                note: "MPEG-2 传输流"),
        CRCSpec(name: "CRC-32/POSIX", width: 32, poly: 0x04C11DB7, initial: 0x0000_0000,
                refin: false, refout: false, xorOut: 0xFFFF_FFFF, check: 0x765E_7680,
                alias: "CKSUM", note: "Unix cksum 命令"),
        CRCSpec(name: "CRC-32/JAMCRC", width: 32, poly: 0x04C11DB7, initial: 0xFFFF_FFFF,
                refin: true, refout: true, xorOut: 0x0000_0000, check: 0x340B_C6D9,
                note: "和 ISO-HDLC 只差最后取反那一步"),
        CRCSpec(name: "CRC-32/AUTOSAR", width: 32, poly: 0xF4ACFB13, initial: 0xFFFF_FFFF,
                refin: true, refout: true, xorOut: 0xFFFF_FFFF, check: 0x1697_D06A,
                note: "AUTOSAR 车载网络"),
        CRCSpec(name: "CRC-32/CD-ROM-EDC", width: 32, poly: 0x8001801B, initial: 0x0000_0000,
                refin: true, refout: true, xorOut: 0x0000_0000, check: 0x6EC2_EDC4,
                note: "CD-ROM 扇区纠错码"),
        CRCSpec(name: "CRC-32/XFER", width: 32, poly: 0x000000AF, initial: 0x0000_0000,
                refin: false, refout: false, xorOut: 0x0000_0000, check: 0xBD0B_E338,
                note: "XFER 传输协议"),

        // ——— CRC-64 ———
        CRCSpec(name: "CRC-64/ECMA-182", width: 64, poly: 0x42F0_E1EB_A9EA_3693,
                initial: 0x0000_0000_0000_0000, refin: false, refout: false,
                xorOut: 0x0000_0000_0000_0000, check: 0x6C40_DF5F_0B49_7347,
                note: "ECMA-182、DECT"),
        CRCSpec(name: "CRC-64/XZ", width: 64, poly: 0x42F0_E1EB_A9EA_3693,
                initial: 0xFFFF_FFFF_FFFF_FFFF, refin: true, refout: true,
                xorOut: 0xFFFF_FFFF_FFFF_FFFF, check: 0x995D_C9BB_DF19_39FA,
                alias: "GO-ECMA", note: ".xz 压缩包、Go 的 hash/crc64 默认"),
        CRCSpec(name: "CRC-64/WE", width: 64, poly: 0x42F0_E1EB_A9EA_3693,
                initial: 0xFFFF_FFFF_FFFF_FFFF, refin: false, refout: false,
                xorOut: 0xFFFF_FFFF_FFFF_FFFF, check: 0x62EC_59E3_F1A4_F00A,
                note: "和 XZ 同多项式，差别全在参数上"),
        CRCSpec(name: "CRC-64/ISO", width: 64, poly: 0x0000_0000_0000_001B,
                initial: 0xFFFF_FFFF_FFFF_FFFF, refin: true, refout: true,
                xorOut: 0xFFFF_FFFF_FFFF_FFFF, check: 0xB909_56C7_75A4_1001,
                alias: "CRC-64/GO-ISO", note: "ISO 3309 高速传输"),
    ]

    static let checkText = Data("123456789".utf8)

    static func presets(of family: CRCFamily) -> [CRCSpec] {
        guard let width = family.width else { return [] }
        return presets.filter { $0.width == width }
    }

    static func preset(named name: String) -> CRCSpec? {
        presets.first { $0.name == name }
    }

    /// 找不到就退回最常用的那个，避免界面因偏好里的旧名字开天窗
    static func preset(orDefault name: String) -> CRCSpec {
        preset(named: name) ?? presets.first { $0.name == "CRC-32/ISO-HDLC" } ?? presets[0]
    }
}

// MARK: - 引擎

/// CRC 计算。两套实现：按定义逐位算的（慢、但一眼能核对对不对）
/// 和查表算的（快、天天用的）。测试里会互相验证。
enum ChecksumEngine {

    // MARK: 位工具

    static func mask(_ width: Int) -> UInt64 {
        width >= 64 ? .max : (UInt64(1) << UInt64(width)) - 1
    }

    /// 只反转低 width 位
    static func reverseBits(_ value: UInt64, width: Int) -> UInt64 {
        guard width > 0 else { return 0 }
        var result: UInt64 = 0
        var source = value
        for _ in 0..<width {
            result = (result << 1) | (source & 1)
            source >>= 1
        }
        return result
    }

    // MARK: 按定义算

    /// 教科书写法：逐位处理，六个参数怎么写的就怎么算。
    /// 慢，但改起来不容易错，表驱动那套的正确性靠它兜底。
    static func compute(_ data: Data, spec: CRCSpec) -> UInt64 {
        var crc = spec.initial & mask(spec.width)
        crc = process(crc, data: data, spec: spec)
        return finish(crc, spec: spec)
    }

    /// 增量版本用这个：只跑数据，收尾（反射 + 末异或）单独做
    static func process(_ start: UInt64, data: Data, spec: CRCSpec) -> UInt64 {
        let width = spec.width
        let bits = mask(width)
        let top = UInt64(1) << UInt64(width - 1)
        var crc = start & bits

        for byte in data {
            // 输入反射就是把整个字节的位序倒过来再异或进去
            let input = spec.refin ? reverseBits(UInt64(byte), width: 8) : UInt64(byte)
            crc ^= (input << UInt64(width - 8)) & bits
            for _ in 0..<8 {
                crc = (crc & top) != 0 ? ((crc << 1) ^ spec.poly) & bits : (crc << 1) & bits
            }
        }
        return crc
    }

    static func finish(_ value: UInt64, spec: CRCSpec) -> UInt64 {
        var crc = value & mask(spec.width)
        if spec.refout { crc = reverseBits(crc, width: spec.width) }
        return (crc ^ spec.xorOut) & mask(spec.width)
    }

    // MARK: 查表算

    /// 256 项查找表。反射型模型用反射多项式，索引也跟着反射方向走。
    static func makeTable(_ spec: CRCSpec) -> [UInt64] {
        let bits = mask(spec.width)
        let top = UInt64(1) << UInt64(spec.width - 1)
        var table = [UInt64](repeating: 0, count: 256)

        if spec.refin {
            let reflectedPoly = reverseBits(spec.poly, width: spec.width)
            for index in 0..<256 {
                var crc = UInt64(index)
                for _ in 0..<8 {
                    crc = (crc & 1) != 0 ? (crc >> 1) ^ reflectedPoly : crc >> 1
                }
                table[index] = crc & bits
            }
        } else {
            for index in 0..<256 {
                var crc = UInt64(index) << UInt64(spec.width - 8)
                for _ in 0..<8 {
                    crc = (crc & top) != 0 ? ((crc << 1) ^ spec.poly) & bits : (crc << 1) & bits
                }
                table[index] = crc & bits
            }
        }
        return table
    }

    /// 查表版。只在输入输出反射方向一致时成立——绝大多数模型都是，
    /// 参数不寻常的时候退回逐位算，别为了快把结果算歪。
    static func computeFast(_ data: Data, spec: CRCSpec) -> UInt64 {
        guard spec.refin == spec.refout else { return compute(data, spec: spec) }
        var calculator = CRCCalculator(spec: spec)
        calculator.update(data)
        return calculator.value
    }

    // MARK: 增量计算器

    /// 分块喂数据用，算大文件不会一次性把内容读进内存。
    struct CRCCalculator {
        let spec: CRCSpec

        private let table: [UInt64]
        private let bits: UInt64
        private let shift: Int
        private let fastPath: Bool
        private var crc: UInt64

        init(spec: CRCSpec) {
            self.spec = spec
            self.bits = ChecksumEngine.mask(spec.width)
            self.shift = spec.width - 8
            self.fastPath = spec.refin == spec.refout
            self.table = fastPath ? ChecksumEngine.makeTable(spec) : []
            self.crc = spec.initial & ChecksumEngine.mask(spec.width)
        }

        mutating func update(_ data: Data) {
            guard !data.isEmpty else { return }
            guard fastPath else {
                crc = ChecksumEngine.process(crc, data: data, spec: spec)
                return
            }

            if spec.refin {
                for byte in data {
                    crc = (crc >> 8) ^ table[Int((crc ^ UInt64(byte)) & 0xFF)]
                }
            } else {
                for byte in data {
                    let index = Int(((crc >> UInt64(shift)) ^ UInt64(byte)) & 0xFF)
                    crc = ((crc << 8) & bits) ^ table[index]
                }
            }
        }

        /// 收尾后的最终值。多次读没副作用。
        var value: UInt64 {
            guard fastPath else {
                // 逐位路径的内部值朝非反射方向，正常走收尾
                return ChecksumEngine.finish(crc, spec: spec)
            }
            // 查表路径的内部值已经是收尾方向了（反射型模型走在反射方向），
            // 这里只差末异或——再交给 finish 会被多反射一次
            return (crc ^ spec.xorOut) & bits
        }
    }

    // MARK: 展示

    static func hex(_ value: UInt64, width: Int, uppercase: Bool = true) -> String {
        let digits = max(1, width / 4)
        let text = String(value, radix: 16, uppercase: uppercase)
        guard text.count < digits else { return text }
        return String(repeating: "0", count: digits - text.count) + text
    }

    /// 把结果摆成字节序列。协议里往报文尾塞的时候，
    /// 一半的坑就是大小端摆反了。
    static func byteText(_ value: UInt64, width: Int, bigEndian: Bool) -> String {
        let count = max(1, width / 8)
        var parts: [String] = []
        for index in 0..<count {
            let offset = bigEndian ? (count - 1 - index) * 8 : index * 8
            parts.append(hex((value >> UInt64(offset)) & 0xFF, width: 8))
        }
        return parts.joined(separator: " ")
    }

    /// 拿十进制展示时 CRC-64 会超 Int64，所以走字符串
    static func decimalText(_ value: UInt64) -> String {
        String(value)
    }
}

// MARK: - 期望值比对

/// 用户手里那个已知的 CRC 和算出来的对不对得上。
enum CRCCompareResult: Equatable {
    case empty
    case invalid
    case match
    /// 字节序反了才对得上——协议文档写的是小端字节序列时很常见
    case matchSwapped
    case mismatch(expected: UInt64)

    var isMatch: Bool {
        self == .match || self == .matchSwapped
    }
}

extension ChecksumEngine {

    /// 宽松解析：0x4B37 / 4b37 / 4B 37 / 37 4B 都收
    static func parseExpected(_ text: String, width: Int) -> UInt64? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: "[\\s:_\\-]", with: "", options: .regularExpression)
        guard !cleaned.isEmpty, cleaned.count <= width / 4 else { return nil }
        guard cleaned.allSatisfy({ $0.isHexDigit }) else { return nil }
        return UInt64(cleaned, radix: 16)
    }

    /// 逐字节倒过来读那个值（把「34 12」当成 0x3412 时反查 0x1234）
    static func swapped(_ value: UInt64, width: Int) -> UInt64 {
        let count = max(1, width / 8)
        var result: UInt64 = 0
        for index in 0..<count {
            let byte = (value >> UInt64(index * 8)) & 0xFF
            result |= byte << UInt64((count - 1 - index) * 8)
        }
        return result & mask(width)
    }

    static func compare(_ text: String, actual: UInt64, spec: CRCSpec) -> CRCCompareResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard let expected = parseExpected(trimmed, width: spec.width) else { return .invalid }

        if expected == actual { return .match }
        if swapped(expected, width: spec.width) == actual { return .matchSwapped }
        return .mismatch(expected: expected)
    }
}
