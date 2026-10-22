import Foundation

// MARK: - 单位定义

/// 一个可换算的单位。
///
/// 统一用 `base = value * factor + offset` 归到该类别的基准单位，
/// 反向就是 `(base - offset) / factor`。温度这种带零点的量靠 `offset` 表达，
/// 其余类别 offset 都是 0，退化成纯倍率。
struct UnitDef: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let symbol: String
    let factor: Double
    var offset: Double = 0
    /// 额外的可识别写法（不带符号的常见中文/英文名）
    var aliases: [String] = []
    /// 是否属于最常用的一组（界面默认靠前显示）
    var common: Bool = false
    /// 需要额外说明时写一句，比如"海平面 15°C 声速"
    var note: String = ""

    /// 用其余写法做模糊匹配时的全部候选
    var searchKeys: [String] {
        [id, symbol, name] + aliases
    }
}

struct UnitCategory: Identifiable, Sendable {
    let id: String
    let name: String
    let systemImage: String
    /// 基准单位的 id
    let baseID: String
    let units: [UnitDef]

    var base: UnitDef {
        units.first { $0.id == baseID } ?? units[0]
    }

    func unit(id: String) -> UnitDef? {
        units.first { $0.id == id }
    }
}

/// 换算出的一行
struct UnitConversion: Identifiable, Sendable {
    var id: String { unit.id }
    let unit: UnitDef
    let value: Double
    let formatted: String
    let isBase: Bool
    let isSource: Bool
}

// MARK: - 换算引擎

enum UnitEngine {

    // MARK: 换算

    /// value 从 from 换到 to
    static func convert(_ value: Double, from: UnitDef, to: UnitDef) -> Double {
        let base = value * from.factor + from.offset
        return (base - to.offset) / to.factor
    }

    /// 一把算出该类别下的所有单位
    static func convertAll(_ value: Double, from: UnitDef, in category: UnitCategory) -> [UnitConversion] {
        category.units.map { unit in
            let result = convert(value, from: from, to: unit)
            return UnitConversion(
                unit: unit,
                value: result,
                formatted: format(result),
                isBase: unit.id == category.baseID,
                isSource: unit.id == from.id
            )
        }
    }

    // MARK: 数值格式化

    /// 太大或太小的值转科学计数法，其余去掉多余的尾零。
    /// 目标是"能一眼看懂，同时复制出去不别扭"，所以不加千分位。
    static func format(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if value == 0 { return "0" }

        let magnitude = abs(value)
        if magnitude >= 1e15 || magnitude < 1e-6 {
            return scientific(value)
        }

        var text = String(format: "%.10f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text.isEmpty ? "0" : text
    }

    /// 6 位有效数字的科学计数法，并把指数补成 e+15 / e-9 这种紧致写法
    static func scientific(_ value: Double) -> String {
        var text = String(format: "%.6e", value)
        guard let eIndex = text.firstIndex(of: "e") else { return text }
        var mantissa = String(text[text.startIndex..<eIndex])
        var exponent = String(text[text.index(after: eIndex)...])

        if mantissa.contains(".") {
            while mantissa.hasSuffix("0") { mantissa.removeLast() }
            if mantissa.hasSuffix(".") { mantissa.removeLast() }
        }

        var sign = "+"
        if exponent.hasPrefix("-") {
            sign = "-"
            exponent.removeFirst()
        } else if exponent.hasPrefix("+") {
            exponent.removeFirst()
        }
        while exponent.count > 1, exponent.hasPrefix("0") { exponent.removeFirst() }

        return "\(mantissa)e\(sign)\(exponent)"
    }

    // MARK: 输入解析

    /// 把 "3.5GB" / "100 Mbps" / "1e3 m" 拆成"数值 + 单位"
    static func parse(_ raw: String) -> (value: Double, unit: UnitDef, category: UnitCategory)? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // 数字在前，单位在后。数字允许 1e3 / -2.5 / .5
        let pattern = #"^([+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)\s*(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 3,
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }

        guard let value = Double(text[valueRange]) else { return nil }

        var unitText = ""
        if let tailRange = Range(match.range(at: 2), in: text) {
            unitText = String(text[tailRange]).trimmingCharacters(in: .whitespaces)
        }
        guard !unitText.isEmpty else { return nil }

        guard let hit = findUnit(unitText) else { return nil }
        return (value, hit.unit, hit.category)
    }

    /// 单位写法 → 具体单位。先按大小写敏感精确命中符号（`B` 是字节、`b` 是比特），
    /// 再退到不区分大小写、最后做前缀包含。
    static func findUnit(_ text: String) -> (unit: UnitDef, category: UnitCategory)? {
        let needle = text.trimmingCharacters(in: .whitespaces)

        // 1. 大小写敏感精确匹配：区分 B/b、L/l 这类只差大小写的单位
        for category in categories {
            for unit in category.units where unit.common {
                if unit.searchKeys.contains(needle) {
                    return (unit, category)
                }
            }
        }

        let lowered = needle.lowercased()

        // 2. 不区分大小写的精确匹配
        for category in categories {
            for unit in category.units where unit.common {
                if unit.searchKeys.contains(where: { $0.lowercased() == lowered }) {
                    return (unit, category)
                }
            }
        }
        for category in categories {
            for unit in category.units {
                if unit.searchKeys.contains(where: { $0.lowercased() == lowered }) {
                    return (unit, category)
                }
            }
        }

        // 3. 退一步做前缀包含：GB 能命中 GB/s 这类
        for category in categories {
            for unit in category.units where unit.common {
                if unit.searchKeys.contains(where: {
                    let key = $0.lowercased()
                    return key.hasPrefix(lowered) || lowered.hasPrefix(key)
                }) {
                    return (unit, category)
                }
            }
        }

        return nil
    }

    // MARK: 结果过滤

    /// 按关键字过滤结果（单位名 / 符号 / 数值）
    static func filter(_ rows: [UnitConversion], keyword: String) -> [UnitConversion] {
        let needle = keyword.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return rows }
        return rows.filter { row in
            row.unit.name.lowercased().contains(needle)
                || row.unit.symbol.lowercased().contains(needle)
                || row.unit.id.lowercased().contains(needle)
                || row.formatted.lowercased().contains(needle)
        }
    }

    // MARK: - 单位表

    static let categories: [UnitCategory] = [
        data, dataRate, time, angle, length, area, volume, mass,
        temperature, speed, pressure, energy, power, frequency
    ]

    static func category(id: String) -> UnitCategory? {
        categories.first { $0.id == id }
    }

    // MARK: 数据存储

    static let data = UnitCategory(
        id: "data",
        name: "数据存储",
        systemImage: "externaldrive",
        baseID: "byte",
        units: [
            UnitDef(id: "bit", name: "比特", symbol: "bit", factor: 0.125, aliases: ["b", "位"], common: true),
            UnitDef(id: "byte", name: "字节", symbol: "B", factor: 1, aliases: ["byte", "字节"], common: true),
            UnitDef(id: "kb", name: "千字节", symbol: "KB", factor: 1e3, aliases: ["kB"], common: true),
            UnitDef(id: "kib", name: "千字节(二进制)", symbol: "KiB", factor: 1024, note: "1 KiB = 1024 B"),
            UnitDef(id: "mb", name: "兆字节", symbol: "MB", factor: 1e6, common: true),
            UnitDef(id: "mib", name: "兆字节(二进制)", symbol: "MiB", factor: 1_048_576),
            UnitDef(id: "gb", name: "吉字节", symbol: "GB", factor: 1e9, common: true),
            UnitDef(id: "gib", name: "吉字节(二进制)", symbol: "GiB", factor: 1_073_741_824),
            UnitDef(id: "tb", name: "太字节", symbol: "TB", factor: 1e12, common: true),
            UnitDef(id: "tib", name: "太字节(二进制)", symbol: "TiB", factor: 1_099_511_627_776),
            UnitDef(id: "pb", name: "拍字节", symbol: "PB", factor: 1e15),
            UnitDef(id: "pib", name: "拍字节(二进制)", symbol: "PiB", factor: 1_125_899_906_842_624),
            UnitDef(id: "eb", name: "艾字节", symbol: "EB", factor: 1e18),
        ]
    )

    // MARK: 数据传输速率（带宽 / 流量）

    static let dataRate = UnitCategory(
        id: "dataRate",
        name: "带宽流量",
        systemImage: "antenna.radiowaves.left.and.right",
        baseID: "bps",
        units: [
            UnitDef(id: "bps", name: "比特每秒", symbol: "bps", factor: 1, aliases: ["bit/s"], common: true),
            UnitDef(id: "kbps", name: "千比特每秒", symbol: "Kbps", factor: 1e3, aliases: ["kbit/s", "kb/s"], common: true),
            UnitDef(id: "mbps", name: "兆比特每秒", symbol: "Mbps", factor: 1e6, aliases: ["mbit/s"], common: true),
            UnitDef(id: "gbps", name: "吉比特每秒", symbol: "Gbps", factor: 1e9, aliases: ["gbit/s"], common: true),
            UnitDef(id: "tbps", name: "太比特每秒", symbol: "Tbps", factor: 1e12),
            UnitDef(id: "kibps", name: "千比特每秒(二进制)", symbol: "Kibps", factor: 1024),
            UnitDef(id: "mibps", name: "兆比特每秒(二进制)", symbol: "Mibps", factor: 1_048_576),
            UnitDef(id: "gibps", name: "吉比特每秒(二进制)", symbol: "Gibps", factor: 1_073_741_824),
            UnitDef(id: "Bps", name: "字节每秒", symbol: "B/s", factor: 8, common: true),
            UnitDef(id: "kBs", name: "千字节每秒", symbol: "KB/s", factor: 8e3, common: true),
            UnitDef(id: "MBs", name: "兆字节每秒", symbol: "MB/s", factor: 8e6, common: true),
            UnitDef(id: "GBs", name: "吉字节每秒", symbol: "GB/s", factor: 8e9, common: true),
            UnitDef(id: "KiBs", name: "千字节每秒(二进制)", symbol: "KiB/s", factor: 8 * 1024),
            UnitDef(id: "MiBs", name: "兆字节每秒(二进制)", symbol: "MiB/s", factor: 8 * 1_048_576),
            UnitDef(id: "GiBs", name: "吉字节每秒(二进制)", symbol: "GiB/s", factor: 8 * 1_073_741_824),
        ]
    )

    // MARK: 时间

    static let time = UnitCategory(
        id: "time",
        name: "时间",
        systemImage: "clock",
        baseID: "second",
        units: [
            UnitDef(id: "nanosecond", name: "纳秒", symbol: "ns", factor: 1e-9, common: true),
            UnitDef(id: "microsecond", name: "微秒", symbol: "μs", factor: 1e-6, aliases: ["us", "µs"], common: true),
            UnitDef(id: "millisecond", name: "毫秒", symbol: "ms", factor: 1e-3, common: true),
            UnitDef(id: "second", name: "秒", symbol: "s", factor: 1, aliases: ["sec", "秒"], common: true),
            UnitDef(id: "minute", name: "分钟", symbol: "min", factor: 60, aliases: ["分"], common: true),
            UnitDef(id: "hour", name: "小时", symbol: "h", factor: 3600, aliases: ["小时", "时"], common: true),
            UnitDef(id: "day", name: "天", symbol: "d", factor: 86400, aliases: ["天", "日"], common: true),
            UnitDef(id: "week", name: "周", symbol: "wk", factor: 604_800, common: true),
            UnitDef(id: "month", name: "月(30天)", symbol: "mo", factor: 2_592_000),
            UnitDef(id: "year", name: "年(365天)", symbol: "yr", factor: 31_536_000, common: true),
            UnitDef(id: "leapYear", name: "闰年(366天)", symbol: "yr(闰)", factor: 31_622_400),
            UnitDef(id: "decade", name: "十年", symbol: "decade", factor: 315_576_000),
            UnitDef(id: "century", name: "世纪", symbol: "century", factor: 3_155_760_000),
        ]
    )

    // MARK: 角度

    static let angle = UnitCategory(
        id: "angle",
        name: "角度",
        systemImage: "angle",
        baseID: "degree",
        units: [
            UnitDef(id: "degree", name: "度", symbol: "°", factor: 1, aliases: ["deg", "度"], common: true),
            UnitDef(id: "radian", name: "弧度", symbol: "rad", factor: 180 / Double.pi, aliases: ["弧度"], common: true),
            UnitDef(id: "milliradian", name: "毫弧度", symbol: "mrad", factor: 180 / Double.pi / 1000),
            UnitDef(id: "gradian", name: "百分度", symbol: "gon", factor: 0.9, aliases: ["grad", "梯度"], common: true),
            UnitDef(id: "arcminute", name: "弧分", symbol: "′", factor: 1.0 / 60, aliases: ["arcmin"]),
            UnitDef(id: "arcsecond", name: "弧秒", symbol: "″", factor: 1.0 / 3600, aliases: ["arcsec"]),
            UnitDef(id: "turn", name: "圈", symbol: "turn", factor: 360, aliases: ["转", "rev"], common: true),
            UnitDef(id: "rightAngle", name: "直角", symbol: "∟", factor: 90),
            UnitDef(id: "mil", name: "密位", symbol: "mil", factor: 360.0 / 6400),
        ]
    )

    // MARK: 长度

    static let length = UnitCategory(
        id: "length",
        name: "长度",
        systemImage: "ruler",
        baseID: "meter",
        units: [
            UnitDef(id: "kilometer", name: "千米", symbol: "km", factor: 1000, aliases: ["公里"], common: true),
            UnitDef(id: "meter", name: "米", symbol: "m", factor: 1, aliases: ["米"], common: true),
            UnitDef(id: "decimeter", name: "分米", symbol: "dm", factor: 0.1),
            UnitDef(id: "centimeter", name: "厘米", symbol: "cm", factor: 0.01, aliases: ["公分"], common: true),
            UnitDef(id: "millimeter", name: "毫米", symbol: "mm", factor: 0.001, common: true),
            UnitDef(id: "micrometer", name: "微米", symbol: "μm", factor: 1e-6, aliases: ["um"]),
            UnitDef(id: "nanometer", name: "纳米", symbol: "nm", factor: 1e-9),
            UnitDef(id: "picometer", name: "皮米", symbol: "pm", factor: 1e-12),
            UnitDef(id: "mile", name: "英里", symbol: "mi", factor: 1609.344, aliases: ["迈"], common: true),
            UnitDef(id: "yard", name: "码", symbol: "yd", factor: 0.9144, common: true),
            UnitDef(id: "foot", name: "英尺", symbol: "ft", factor: 0.3048, aliases: ["呎"], common: true),
            UnitDef(id: "inch", name: "英寸", symbol: "in", factor: 0.0254, aliases: ["吋"], common: true),
            UnitDef(id: "nauticalMile", name: "海里", symbol: "nmi", factor: 1852),
            UnitDef(id: "li", name: "市里", symbol: "里", factor: 500),
            UnitDef(id: "chi", name: "市尺", symbol: "尺", factor: 1.0 / 3),
            UnitDef(id: "cun", name: "市寸", symbol: "寸", factor: 1.0 / 30),
            UnitDef(id: "zhang", name: "丈", symbol: "丈", factor: 10.0 / 3),
            UnitDef(id: "lightYear", name: "光年", symbol: "ly", factor: 9.4607304725808e15),
            UnitDef(id: "astronomicalUnit", name: "天文单位", symbol: "AU", factor: 1.495978707e11),
            UnitDef(id: "parsec", name: "秒差距", symbol: "pc", factor: 3.0856775814913673e16),
        ]
    )

    // MARK: 面积

    static let area = UnitCategory(
        id: "area",
        name: "面积",
        systemImage: "square.dashed",
        baseID: "squareMeter",
        units: [
            UnitDef(id: "squareKilometer", name: "平方千米", symbol: "km²", factor: 1e6, aliases: ["平方公里"], common: true),
            UnitDef(id: "hectare", name: "公顷", symbol: "ha", factor: 1e4, common: true),
            UnitDef(id: "are", name: "公亩", symbol: "a", factor: 100),
            UnitDef(id: "squareMeter", name: "平方米", symbol: "m²", factor: 1, aliases: ["平米", "平方"], common: true),
            UnitDef(id: "squareDecimeter", name: "平方分米", symbol: "dm²", factor: 0.01),
            UnitDef(id: "squareCentimeter", name: "平方厘米", symbol: "cm²", factor: 1e-4, common: true),
            UnitDef(id: "squareMillimeter", name: "平方毫米", symbol: "mm²", factor: 1e-6),
            UnitDef(id: "mu", name: "亩", symbol: "亩", factor: 2000.0 / 3, common: true),
            UnitDef(id: "acre", name: "英亩", symbol: "ac", factor: 4046.8564224),
            UnitDef(id: "squareMile", name: "平方英里", symbol: "mi²", factor: 2_589_988.110336),
            UnitDef(id: "squareYard", name: "平方码", symbol: "yd²", factor: 0.83612736),
            UnitDef(id: "squareFoot", name: "平方英尺", symbol: "ft²", factor: 0.09290304),
            UnitDef(id: "squareInch", name: "平方英寸", symbol: "in²", factor: 0.00064516),
            UnitDef(id: "squareChi", name: "平方尺", symbol: "尺²", factor: 1.0 / 9),
        ]
    )

    // MARK: 体积

    static let volume = UnitCategory(
        id: "volume",
        name: "体积",
        systemImage: "cube",
        baseID: "liter",
        units: [
            UnitDef(id: "cubicMeter", name: "立方米", symbol: "m³", factor: 1000, common: true),
            UnitDef(id: "liter", name: "升", symbol: "L", factor: 1, aliases: ["l", "升", "公升"], common: true),
            UnitDef(id: "deciliter", name: "分升", symbol: "dL", factor: 0.1),
            UnitDef(id: "centiliter", name: "厘升", symbol: "cL", factor: 0.01),
            UnitDef(id: "milliliter", name: "毫升", symbol: "mL", factor: 0.001, aliases: ["ml"], common: true),
            UnitDef(id: "cubicCentimeter", name: "立方厘米", symbol: "cm³", factor: 0.001),
            UnitDef(id: "cubicMillimeter", name: "立方毫米", symbol: "mm³", factor: 1e-6),
            UnitDef(id: "cubicFoot", name: "立方英尺", symbol: "ft³", factor: 28.316846592),
            UnitDef(id: "cubicInch", name: "立方英寸", symbol: "in³", factor: 0.016387064),
            UnitDef(id: "cubicYard", name: "立方码", symbol: "yd³", factor: 764.554857984),
            UnitDef(id: "gallonUS", name: "加仑(美)", symbol: "gal", factor: 3.785411784, common: true),
            UnitDef(id: "gallonUK", name: "加仑(英)", symbol: "gal(UK)", factor: 4.54609),
            UnitDef(id: "quartUS", name: "夸脱(美)", symbol: "qt", factor: 0.946352946),
            UnitDef(id: "pintUS", name: "品脱(美)", symbol: "pt", factor: 0.473176473),
            UnitDef(id: "fluidOunceUS", name: "液量盎司(美)", symbol: "fl oz", factor: 0.0295735295625),
            UnitDef(id: "cupUS", name: "杯(美)", symbol: "cup", factor: 0.2365882365),
            UnitDef(id: "tablespoon", name: "汤匙", symbol: "tbsp", factor: 0.01478676478125),
            UnitDef(id: "teaspoon", name: "茶匙", symbol: "tsp", factor: 0.00492892159375),
            UnitDef(id: "barrelOil", name: "桶(石油)", symbol: "bbl", factor: 158.987294928),
        ]
    )

    // MARK: 质量

    static let mass = UnitCategory(
        id: "mass",
        name: "质量",
        systemImage: "scalemass",
        baseID: "kilogram",
        units: [
            UnitDef(id: "tonne", name: "吨", symbol: "t", factor: 1000, aliases: ["公吨"], common: true),
            UnitDef(id: "quintal", name: "担", symbol: "担", factor: 50),
            UnitDef(id: "kilogram", name: "千克", symbol: "kg", factor: 1, aliases: ["公斤"], common: true),
            UnitDef(id: "jin", name: "斤", symbol: "斤", factor: 0.5, aliases: ["市斤"], common: true),
            UnitDef(id: "gram", name: "克", symbol: "g", factor: 0.001, common: true),
            UnitDef(id: "liang", name: "两", symbol: "两", factor: 0.05, common: true),
            UnitDef(id: "qian", name: "钱", symbol: "钱", factor: 0.005),
            UnitDef(id: "milligram", name: "毫克", symbol: "mg", factor: 1e-6, common: true),
            UnitDef(id: "microgram", name: "微克", symbol: "μg", factor: 1e-9, aliases: ["ug"]),
            UnitDef(id: "carat", name: "克拉", symbol: "ct", factor: 0.0002),
            UnitDef(id: "pound", name: "磅", symbol: "lb", factor: 0.45359237, common: true),
            UnitDef(id: "ounce", name: "盎司", symbol: "oz", factor: 0.028349523125, common: true),
            UnitDef(id: "stone", name: "英石", symbol: "st", factor: 6.35029318),
            UnitDef(id: "shortTon", name: "短吨", symbol: "ton(US)", factor: 907.18474),
            UnitDef(id: "longTon", name: "长吨", symbol: "ton(UK)", factor: 1016.0469088),
        ]
    )

    // MARK: 温度

    static let temperature = UnitCategory(
        id: "temperature",
        name: "温度",
        systemImage: "thermometer.medium",
        baseID: "kelvin",
        units: [
            UnitDef(id: "celsius", name: "摄氏度", symbol: "°C", factor: 1, offset: 273.15, aliases: ["c", "摄氏"], common: true),
            UnitDef(id: "fahrenheit", name: "华氏度", symbol: "°F", factor: 5.0 / 9, offset: 255.3722222222222, aliases: ["f", "华氏"], common: true),
            UnitDef(id: "kelvin", name: "开尔文", symbol: "K", factor: 1, offset: 0, aliases: ["开氏"], common: true),
            UnitDef(id: "rankine", name: "兰氏度", symbol: "°R", factor: 5.0 / 9, offset: 0, common: true),
            UnitDef(id: "reaumur", name: "列氏度", symbol: "°Ré", factor: 1.25, offset: 273.15),
        ]
    )

    // MARK: 速度

    static let speed = UnitCategory(
        id: "speed",
        name: "速度",
        systemImage: "speedometer",
        baseID: "meterPerSecond",
        units: [
            UnitDef(id: "meterPerSecond", name: "米每秒", symbol: "m/s", factor: 1, aliases: ["mps"], common: true),
            UnitDef(id: "kilometerPerHour", name: "千米每小时", symbol: "km/h", factor: 1.0 / 3.6, aliases: ["kph", "码(口语)"], common: true),
            UnitDef(id: "milePerHour", name: "英里每小时", symbol: "mph", factor: 0.44704, common: true),
            UnitDef(id: "knot", name: "节", symbol: "kn", factor: 1852.0 / 3600, aliases: ["节"], common: true),
            UnitDef(id: "footPerSecond", name: "英尺每秒", symbol: "ft/s", factor: 0.3048),
            UnitDef(id: "kilometerPerSecond", name: "千米每秒", symbol: "km/s", factor: 1000),
            UnitDef(id: "mach", name: "马赫", symbol: "Ma", factor: 340.3, note: "海平面 15°C 声速"),
            UnitDef(id: "lightSpeed", name: "真空光速", symbol: "光速", factor: 299_792_458),
        ]
    )

    // MARK: 压力

    static let pressure = UnitCategory(
        id: "pressure",
        name: "压力",
        systemImage: "gauge.with.needle",
        baseID: "pascal",
        units: [
            UnitDef(id: "pascal", name: "帕斯卡", symbol: "Pa", factor: 1, common: true),
            UnitDef(id: "kilopascal", name: "千帕", symbol: "kPa", factor: 1e3, common: true),
            UnitDef(id: "megapascal", name: "兆帕", symbol: "MPa", factor: 1e6, common: true),
            UnitDef(id: "bar", name: "巴", symbol: "bar", factor: 1e5, common: true),
            UnitDef(id: "millibar", name: "毫巴", symbol: "mbar", factor: 100),
            UnitDef(id: "atmosphere", name: "标准大气压", symbol: "atm", factor: 101325, common: true),
            UnitDef(id: "psi", name: "磅力每平方英寸", symbol: "psi", factor: 6894.757293168, common: true),
            UnitDef(id: "torr", name: "托", symbol: "Torr", factor: 101325.0 / 760),
            UnitDef(id: "mmHg", name: "毫米汞柱", symbol: "mmHg", factor: 133.322387415, common: true),
            UnitDef(id: "kgfcm2", name: "千克力每平方厘米", symbol: "kgf/cm²", factor: 98066.5),
        ]
    )

    // MARK: 能量

    static let energy = UnitCategory(
        id: "energy",
        name: "能量",
        systemImage: "bolt",
        baseID: "joule",
        units: [
            UnitDef(id: "joule", name: "焦耳", symbol: "J", factor: 1, common: true),
            UnitDef(id: "kilojoule", name: "千焦", symbol: "kJ", factor: 1000, common: true),
            UnitDef(id: "calorie", name: "卡路里", symbol: "cal", factor: 4.184, common: true),
            UnitDef(id: "kilocalorie", name: "千卡", symbol: "kcal", factor: 4184, aliases: ["大卡"], common: true),
            UnitDef(id: "wattHour", name: "瓦时", symbol: "Wh", factor: 3600, common: true),
            UnitDef(id: "kilowattHour", name: "千瓦时", symbol: "kWh", factor: 3.6e6, common: true),
            UnitDef(id: "electronVolt", name: "电子伏", symbol: "eV", factor: 1.602176634e-19),
            UnitDef(id: "btu", name: "英热单位", symbol: "BTU", factor: 1055.05585262),
            UnitDef(id: "erg", name: "尔格", symbol: "erg", factor: 1e-7),
            UnitDef(id: "footPound", name: "英尺磅", symbol: "ft·lb", factor: 1.3558179483314004),
        ]
    )

    // MARK: 功率

    static let power = UnitCategory(
        id: "power",
        name: "功率",
        systemImage: "powerplug",
        baseID: "watt",
        units: [
            UnitDef(id: "watt", name: "瓦特", symbol: "W", factor: 1, common: true),
            UnitDef(id: "kilowatt", name: "千瓦", symbol: "kW", factor: 1000, common: true),
            UnitDef(id: "megawatt", name: "兆瓦", symbol: "MW", factor: 1e6, common: true),
            UnitDef(id: "metricHorsepower", name: "公制马力", symbol: "PS", factor: 735.49875, aliases: ["匹"], common: true),
            UnitDef(id: "mechanicalHorsepower", name: "机械马力", symbol: "hp", factor: 745.6998715823, common: true),
            UnitDef(id: "btuPerHour", name: "英热单位每小时", symbol: "BTU/h", factor: 0.29307107017),
            UnitDef(id: "caloriePerSecond", name: "卡每秒", symbol: "cal/s", factor: 4.184),
            UnitDef(id: "kilocaloriePerHour", name: "千卡每小时", symbol: "kcal/h", factor: 1.163),
        ]
    )

    // MARK: 频率

    static let frequency = UnitCategory(
        id: "frequency",
        name: "频率",
        systemImage: "waveform.path.ecg",
        baseID: "hertz",
        units: [
            UnitDef(id: "hertz", name: "赫兹", symbol: "Hz", factor: 1, common: true),
            UnitDef(id: "kilohertz", name: "千赫兹", symbol: "kHz", factor: 1e3, common: true),
            UnitDef(id: "megahertz", name: "兆赫兹", symbol: "MHz", factor: 1e6, common: true),
            UnitDef(id: "gigahertz", name: "吉赫兹", symbol: "GHz", factor: 1e9, common: true),
            UnitDef(id: "terahertz", name: "太赫兹", symbol: "THz", factor: 1e12),
            UnitDef(id: "rpm", name: "转每分钟", symbol: "rpm", factor: 1.0 / 60, common: true),
        ]
    )
}
