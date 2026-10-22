import Foundation

/// 时间戳 ⇄ 日期。所有换算都走这里，视图层只负责摆位置。
enum TimestampEngine {

    // MARK: - 单位

    /// 按数量级猜单位。
    /// 1e11 秒 ≈ 公元 5138 年，所以小于它的只可能是秒级；再往上依次是毫秒 / 微秒 / 纳秒。
    static func guessUnit(_ value: Double) -> TimestampUnit {
        let magnitude = abs(value)
        if magnitude < 1e11 { return .seconds }
        if magnitude < 1e14 { return .milliseconds }
        if magnitude < 1e17 { return .microseconds }
        return .nanoseconds
    }

    static func resolveUnit(_ unit: TimestampUnit, for value: Double) -> TimestampUnit {
        unit == .auto ? guessUnit(value) : unit
    }

    static func date(from value: Double, unit: TimestampUnit) -> Date {
        let resolved = resolveUnit(unit, for: value)
        return Date(timeIntervalSince1970: value / resolved.perSecond)
    }

    static func value(from date: Date, unit: TimestampUnit) -> Double {
        let resolved = unit == .auto ? .seconds : unit
        return (date.timeIntervalSince1970 * resolved.perSecond).rounded()
    }

    // MARK: - 输入解析

    enum InputKind: Sendable {
        case timestamp(TimestampUnit)
        case dateText(String)
    }

    struct ParsedInput: Sendable {
        let date: Date
        let kind: InputKind
        let detail: String
    }

    /// 智能解析：纯数字当时间戳，其余按一长串常见格式往下试。
    static func parse(_ raw: String, unit: TimestampUnit, timeZone: TimeZone) -> ParsedInput? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let numeric = text.replacingOccurrences(of: "_", with: "")
        let looksNumeric = !numeric.isEmpty && numeric.allSatisfy { $0.isNumber || $0 == "-" || $0 == "+" || $0 == "." }
        if looksNumeric, let value = Double(numeric), value.isFinite {
            let resolved = resolveUnit(unit, for: value)
            return ParsedInput(
                date: Date(timeIntervalSince1970: value / resolved.perSecond),
                kind: .timestamp(resolved),
                detail: "按毫秒/秒的位数特征识别为 \(resolved.title)级时间戳"
            )
        }

        if let (date, label) = dateFromText(text, timeZone: timeZone) {
            return ParsedInput(date: date, kind: .dateText(label), detail: "按「\(label)」格式解析")
        }
        return nil
    }

    /// 逐条尝试常见日期格式，返回命中的格式名
    private static func dateFromText(_ text: String, timeZone: TimeZone) -> (Date, String)? {
        for item in textFormats {
            let formatter = makeFormatter(item.pattern, timeZone: timeZone)
            guard let date = formatter.date(from: text) else { continue }
            if item.timeOnly {
                // 只有时分秒时，日期部分补今天
                let calendar = calendar(timeZone)
                let today = calendar.dateComponents([.year, .month, .day], from: Date())
                let time = calendar.dateComponents([.hour, .minute, .second], from: date)
                var merged = DateComponents()
                merged.year = today.year
                merged.month = today.month
                merged.day = today.day
                merged.hour = time.hour
                merged.minute = time.minute
                merged.second = time.second
                guard let combined = calendar.date(from: merged) else { continue }
                return (combined, item.label + "（补今天）")
            }
            return (date, item.label)
        }
        return nil
    }

    private static let textFormats: [(pattern: String, label: String, timeOnly: Bool)] = [
        ("yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX", "ISO 8601", false),
        ("yyyy-MM-dd'T'HH:mm:ssXXXXX", "ISO 8601", false),
        ("yyyy-MM-dd'T'HH:mm:ss.SSS", "ISO 8601 本地", false),
        ("yyyy-MM-dd'T'HH:mm:ss", "ISO 8601 本地", false),
        ("yyyy-MM-dd HH:mm:ss.SSS", "标准日期时间", false),
        ("yyyy-MM-dd HH:mm:ss", "标准日期时间", false),
        ("yyyy-MM-dd HH:mm", "日期 + 时分", false),
        ("yyyy-MM-dd", "日期", false),
        ("yyyy/MM/dd HH:mm:ss", "斜杠日期时间", false),
        ("yyyy/MM/dd", "斜杠日期", false),
        ("yyyy.MM.dd HH:mm:ss", "点号日期时间", false),
        ("yyyy.MM.dd", "点号日期", false),
        ("yyyy年MM月dd日 HH:mm:ss", "中文日期时间", false),
        ("yyyy年MM月dd日 HH:mm", "中文日期时间", false),
        ("yyyy年MM月dd日", "中文日期", false),
        ("MM/dd/yyyy HH:mm:ss", "美式日期时间", false),
        ("MM/dd/yyyy", "美式日期", false),
        ("dd/MM/yyyy HH:mm:ss", "欧式日期时间", false),
        ("dd/MM/yyyy", "欧式日期", false),
        ("EEE, dd MMM yyyy HH:mm:ss Z", "RFC 2822", false),
        ("EEE MMM d HH:mm:ss yyyy", "ctime", false),
        ("yyyyMMddHHmmss", "紧凑数字", false),
        ("yyyyMMdd", "紧凑日期", false),
        ("HH:mm:ss", "仅时间", true),
        ("HH:mm", "仅时间", true),
    ]

    // MARK: - 格式化

    private static func makeFormatter(_ pattern: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter
    }

    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }

    static func format(_ date: Date, pattern: String, timeZone: TimeZone) -> String {
        makeFormatter(pattern, timeZone: timeZone).string(from: date)
    }

    /// 按本地语言格式化（星期几、月份名这种）
    static func formatLocalized(_ date: Date, pattern: String, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    // MARK: - 描述一个时刻

    static func describe(_ date: Date, timeZone: TimeZone, unit: TimestampUnit = .auto) -> [TimestampDisplay] {
        var items: [TimestampDisplay] = []

        items.append(TimestampDisplay(
            id: "local",
            title: "本地时间",
            value: format(date, pattern: "yyyy-MM-dd HH:mm:ss", timeZone: timeZone),
            hint: timeZone.shortLabel,
            highlight: true
        ))

        items.append(TimestampDisplay(
            id: "readable",
            title: "中文可读",
            value: formatLocalized(date, pattern: "yyyy年M月d日 EEEE HH:mm:ss", timeZone: timeZone)
        ))

        items.append(TimestampDisplay(
            id: "tzname",
            title: "时区",
            value: "\(timeZone.identifier) · \(offsetText(date: date, timeZone: timeZone))"
        ))

        items.append(TimestampDisplay(
            id: "unix-seconds",
            title: "Unix 时间戳（秒）",
            value: String(Int64(value(from: date, unit: .seconds))),
            hint: "十进制"
        ))

        items.append(TimestampDisplay(
            id: "unix-millis",
            title: "Unix 时间戳（毫秒）",
            value: String(Int64(value(from: date, unit: .milliseconds))),
            hint: "JavaScript Date.now()"
        ))

        items.append(TimestampDisplay(
            id: "unix-micros",
            title: "Unix 时间戳（微秒）",
            value: String(Int64(value(from: date, unit: .microseconds))),
            hint: "Python / 部分数据库"
        ))

        items.append(TimestampDisplay(
            id: "unix-nanos",
            title: "Unix 时间戳（纳秒）",
            value: String(Int64(value(from: date, unit: .nanoseconds))),
            hint: "Go / Rust SystemTime"
        ))

        items.append(TimestampDisplay(
            id: "iso-utc",
            title: "ISO 8601（UTC）",
            value: format(date, pattern: "yyyy-MM-dd'T'HH:mm:ss'Z'", timeZone: utc)
        ))

        items.append(TimestampDisplay(
            id: "iso-local",
            title: "ISO 8601（带偏移）",
            value: format(date, pattern: "yyyy-MM-dd'T'HH:mm:ssXXXXX", timeZone: timeZone)
        ))

        items.append(TimestampDisplay(
            id: "rfc2822",
            title: "RFC 2822",
            value: format(date, pattern: "EEE, dd MMM yyyy HH:mm:ss Z", timeZone: timeZone),
            hint: "邮件头日期"
        ))

        items.append(TimestampDisplay(
            id: "http",
            title: "HTTP 日期",
            value: format(date, pattern: "EEE, dd MMM yyyy HH:mm:ss' GMT'", timeZone: utc),
            hint: "RFC 7231"
        ))

        items.append(TimestampDisplay(
            id: "sql",
            title: "SQL 时间戳",
            value: format(date, pattern: "yyyy-MM-dd HH:mm:ss.SSS", timeZone: utc),
            hint: "UTC"
        ))

        items.append(TimestampDisplay(
            id: "relative",
            title: "相对现在",
            value: relativeText(date)
        ))

        let cal = calendar(timeZone)
        let dayOfYear = cal.ordinality(of: .day, in: .year, for: date) ?? 0
        let weekOfYear = cal.component(.weekOfYear, from: date)
        let quarter = (cal.component(.month, from: date) - 1) / 3 + 1
        let isLeap = cal.range(of: .day, in: .year, for: date)?.count == 366

        items.append(TimestampDisplay(
            id: "calendar",
            title: "历法信息",
            value: "第 \(dayOfYear) 天 · 第 \(weekOfYear) 周 · 第 \(quarter) 季度 · \(isLeap ? "闰年" : "平年")"
        ))

        _ = unit
        return items
    }

    static let utc = TimeZone(identifier: "UTC")!

    static func offsetText(date: Date, timeZone: TimeZone) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "-" : "+"
        let absolute = abs(seconds)
        let hours = absolute / 3600
        let minutes = (absolute % 3600) / 60
        return String(format: "UTC%@%02d:%02d", sign, hours, minutes)
    }

    static func relativeText(_ date: Date, relativeTo now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    // MARK: - 时区对照

    static let cityZones: [(city: String, identifier: String)] = [
        ("北京", "Asia/Shanghai"),
        ("东京", "Asia/Tokyo"),
        ("新加坡", "Asia/Singapore"),
        ("迪拜", "Asia/Dubai"),
        ("伦敦", "Europe/London"),
        ("巴黎", "Europe/Paris"),
        ("莫斯科", "Europe/Moscow"),
        ("纽约", "America/New_York"),
        ("芝加哥", "America/Chicago"),
        ("洛杉矶", "America/Los_Angeles"),
        ("圣保罗", "America/Sao_Paulo"),
        ("悉尼", "Australia/Sydney"),
        ("奥克兰", "Pacific/Auckland"),
        ("UTC", "UTC"),
    ]

    static func timeZoneLines(for date: Date, base: TimeZone) -> [TimeZoneLine] {
        let baseStamp = dayStamp(date, timeZone: base)

        return cityZones.compactMap { item in
            guard let zone = TimeZone(identifier: item.identifier) else { return nil }
            let shift = Int(((dayStamp(date, timeZone: zone) - baseStamp) / 86_400).rounded())
            return TimeZoneLine(
                city: item.city,
                identifier: item.identifier,
                time: format(date, pattern: "MM-dd HH:mm:ss", timeZone: zone),
                offset: offsetText(date: date, timeZone: zone),
                dayShift: shift
            )
        }
    }

    /// 把"某时区下的年月日"抽出来当成一个中性日期。
    /// 直接拿两个时区的当日零点算差是不对的——它们可能只差几小时，`dateComponents` 会给出 0 天，
    /// 但日期明明跨了一天。
    private static func dayStamp(_ date: Date, timeZone: TimeZone) -> TimeInterval {
        var zoned = Calendar(identifier: .gregorian)
        zoned.timeZone = timeZone
        let components = zoned.dateComponents([.year, .month, .day], from: date)

        var neutral = Calendar(identifier: .gregorian)
        neutral.timeZone = utc
        guard let anchor = neutral.date(from: components) else { return 0 }
        return anchor.timeIntervalSince1970
    }

    /// 常用时区，给选择器打头用
    static let commonTimeZones: [String] = [
        "Asia/Shanghai",
        "Asia/Hong_Kong",
        "Asia/Taipei",
        "Asia/Tokyo",
        "Asia/Seoul",
        "Asia/Singapore",
        "Asia/Bangkok",
        "Asia/Kolkata",
        "Asia/Dubai",
        "Europe/London",
        "Europe/Paris",
        "Europe/Berlin",
        "Europe/Moscow",
        "America/New_York",
        "America/Chicago",
        "America/Denver",
        "America/Los_Angeles",
        "America/Sao_Paulo",
        "Australia/Sydney",
        "Pacific/Auckland",
        "UTC",
    ]

    static func timeZoneTitle(_ identifier: String) -> String {
        if identifier == "UTC" { return "UTC" }
        let city = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return city.replacingOccurrences(of: "_", with: " ")
    }

    // MARK: - 时间差

    /// 把两个时刻的差拆成人话
    static func durationText(from start: Date, to end: Date) -> String {
        let total = end.timeIntervalSince(start)
        let sign = total < 0 ? "早于" : "晚于"
        let seconds = abs(total)
        guard seconds >= 1 else {
            return String(format: "相差 %.3f 秒", seconds)
        }

        let days = Int(seconds) / 86_400
        let hours = (Int(seconds) % 86_400) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        var parts: [String] = []
        if days > 0 { parts.append("\(days) 天") }
        if hours > 0 { parts.append("\(hours) 小时") }
        if minutes > 0 { parts.append("\(minutes) 分") }
        if secs > 0 && days == 0 { parts.append("\(secs) 秒") }
        if parts.isEmpty { parts.append("0 秒") }

        return "\(sign)起点 " + parts.joined()
    }

    static func durationBreakdown(from start: Date, to end: Date) -> [TimestampDisplay] {
        let total = end.timeIntervalSince(start)
        let seconds = abs(total)
        return [
            TimestampDisplay(id: "d-days", title: "天", value: String(format: "%.6f", seconds / 86_400)),
            TimestampDisplay(id: "d-hours", title: "小时", value: String(format: "%.4f", seconds / 3600)),
            TimestampDisplay(id: "d-minutes", title: "分钟", value: String(format: "%.2f", seconds / 60)),
            TimestampDisplay(id: "d-seconds", title: "秒", value: String(format: "%.3f", seconds)),
            TimestampDisplay(id: "d-millis", title: "毫秒", value: String(Int64(seconds * 1000))),
            TimestampDisplay(id: "d-raw", title: "带符号秒数", value: String(format: "%.3f", total)),
        ]
    }
}

extension TimeZone {
    /// "Asia/Shanghai" → "Shanghai"，给结果行做补充说明用
    var shortLabel: String {
        TimestampEngine.timeZoneTitle(identifier)
    }
}
