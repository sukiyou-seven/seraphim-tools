import Foundation

// MARK: - 字段

/// Quartz 扩展写法：L / W / #
enum CronSpecial: Sendable, Equatable {
    case lastDay                    // L：当月最后一天（日字段）
    case lastDayMinus(Int)          // L-3：最后一天往前 3 天
    case lastWeekday                // LW：当月最后一个工作日
    case nearestWeekday(Int)        // 15W：离 15 号最近的工作日
    case lastWeekdayOf(Int)         // 5L：当月最后一个周五（周字段）
    case nthWeekday(weekday: Int, nth: Int)  // 3#2：当月第 2 个周三
}

struct CronField: Sendable {
    let raw: String
    let values: Set<Int>
    let wildcard: Bool
    /// 步长，比如 */5 里的 5
    let step: Int?
    /// L / W / # 这类扩展语义
    let special: CronSpecial?

    init(raw: String, values: Set<Int>, wildcard: Bool, step: Int? = nil, special: CronSpecial? = nil) {
        self.raw = raw
        self.values = values
        self.wildcard = wildcard
        self.step = step
        self.special = special
    }

    var sorted: [Int] { values.sorted() }

    /// 是否是一段连续区间（1-5 这种）
    func isRange(_ range: ClosedRange<Int>) -> Bool {
        !wildcard && special == nil && values.count > 2 && values.min() == range.lowerBound
            && values.max() == range.upperBound
            && values.count == range.upperBound - range.lowerBound + 1
    }

    var isSingle: Bool { values.count == 1 }

    /// 这个字段有没有实际约束（* 和 ? 都算没约束）
    var isRestricted: Bool { !wildcard || special != nil }
}

// MARK: - 表达式

struct CronSchedule: Sendable {
    let expression: String
    let hasSeconds: Bool
    let second: CronField?
    let minute: CronField
    let hour: CronField
    let day: CronField
    let month: CronField
    let weekday: CronField
    /// 命中的 @宏，比如 @daily
    let macro: String?

    /// 日和周哪个更"具体"，决定描述里用哪一个
    var dayIsRestricted: Bool { !day.wildcard }
    var weekdayIsRestricted: Bool { !weekday.wildcard }
}

enum CronError: LocalizedError {
    case empty
    case fieldCount(Int)
    case unknownMacro(String)
    case badValue(field: String, token: String, reason: String)
    case outOfRange(field: String, value: Int, range: ClosedRange<Int>)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "表达式是空的"
        case .fieldCount(let count):
            return "字段数量是 \(count)，标准 cron 是 5 段（分 时 日 月 周），带秒是 6 段"
        case .unknownMacro(let name):
            return "不认识这个宏：\(name)"
        case .badValue(let field, let token, let reason):
            return "\(field) 字段里的「\(token)」有问题：\(reason)"
        case .outOfRange(let field, let value, let range):
            return "\(field) 字段的 \(value) 超出范围 \(range.lowerBound)-\(range.upperBound)"
        }
    }
}

// MARK: - 常用模板

struct CronPreset: Identifiable, Sendable {
    let id: String
    let title: String
    let expression: String
    let note: String

    static let all: [CronPreset] = [
        CronPreset(id: "every-minute", title: "每分钟", expression: "* * * * *", note: "压测或本地调试常用"),
        CronPreset(id: "every-5", title: "每 5 分钟", expression: "*/5 * * * *", note: "轻量轮询"),
        CronPreset(id: "every-30", title: "每 30 分钟", expression: "*/30 * * * *", note: "半小时一次"),
        CronPreset(id: "hourly", title: "每小时", expression: "0 * * * *", note: "整点触发"),
        CronPreset(id: "daily-midnight", title: "每天 0 点", expression: "0 0 * * *", note: "日报、清缓存"),
        CronPreset(id: "daily-9", title: "每天 9 点", expression: "0 9 * * *", note: "早间任务"),
        CronPreset(id: "workday-9", title: "工作日 9 点", expression: "0 9 * * 1-5", note: "只在周一到周五"),
        CronPreset(id: "weekly-monday", title: "每周一 9 点", expression: "0 9 * * 1", note: "周会提醒"),
        CronPreset(id: "biweekly", title: "每两周一次", expression: "0 9 */14 * *", note: "按日期隔 14 天"),
        CronPreset(id: "monthly-first", title: "每月 1 日", expression: "0 0 1 * *", note: "月度结算"),
        CronPreset(id: "monthly-15", title: "每月 15 日", expression: "0 0 15 * *", note: "月中任务"),
        CronPreset(id: "quarterly", title: "每季度首日", expression: "0 0 1 1,4,7,10 *", note: "季度报表"),
        CronPreset(id: "yearly", title: "每年 1 月 1 日", expression: "0 0 1 1 *", note: "年度任务"),
        CronPreset(id: "nightly-3", title: "每天凌晨 3 点", expression: "0 3 * * *", note: "备份"),
    ]
}

// MARK: - 引擎

enum CronEngine {

    static let zone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    private static let monthNames = [
        "JAN": 1, "FEB": 2, "MAR": 3, "APR": 4, "MAY": 5, "JUN": 6,
        "JUL": 7, "AUG": 8, "SEP": 9, "OCT": 10, "NOV": 11, "DEC": 12,
    ]

    private static let weekdayNames = [
        "SUN": 0, "MON": 1, "TUE": 2, "WED": 3, "THU": 4, "FRI": 5, "SAT": 6,
    ]

    private static let macros: [String: String] = [
        "@yearly": "0 0 1 1 *",
        "@annually": "0 0 1 1 *",
        "@monthly": "0 0 1 * *",
        "@weekly": "0 0 * * 0",
        "@daily": "0 0 * * *",
        "@midnight": "0 0 * * *",
        "@hourly": "0 * * * *",
    ]

    // MARK: 解析

    static func parse(_ raw: String) throws -> CronSchedule {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { throw CronError.empty }

        var macroName: String?
        var body = text

        if text.hasPrefix("@") {
            let key = text.split(separator: " ").first.map(String.init) ?? text
            guard let expanded = macros[key] else { throw CronError.unknownMacro(String(key)) }
            macroName = key
            body = expanded
        }

        let parts = body.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        let hasSeconds: Bool
        let fields: [String]

        switch parts.count {
        case 5:
            hasSeconds = false
            fields = parts
        case 6:
            hasSeconds = true
            fields = parts
        default:
            throw CronError.fieldCount(parts.count)
        }

        var index = 0
        var second: CronField?
        if hasSeconds {
            second = try parseField(fields[index], name: "秒", range: 0...59)
            index += 1
        }
        let minute = try parseField(fields[index], name: "分", range: 0...59)
        let hour = try parseField(fields[index + 1], name: "时", range: 0...23)
        let day = try parseField(fields[index + 2], name: "日", range: 1...31)
        let month = try parseField(fields[index + 3], name: "月", range: 1...12, names: monthNames)
        let weekday = try parseField(fields[index + 4], name: "周", range: 0...7, names: weekdayNames, normalizeWeekday: true)

        return CronSchedule(
            expression: text,
            hasSeconds: hasSeconds,
            second: second,
            minute: minute,
            hour: hour,
            day: day,
            month: month,
            weekday: weekday,
            macro: macroName
        )
    }

    private static func parseField(
        _ raw: String,
        name: String,
        range: ClosedRange<Int>,
        names: [String: Int]? = nil,
        normalizeWeekday: Bool = false
    ) throws -> CronField {
        var text = raw.uppercased()

        // ? 在 Quartz 里就是"不指定"，语义等同 *
        if text == "?" { text = "*" }

        // L / W / # 这些扩展写法单独处理
        if let special = try parseSpecial(text, name: name, range: range, normalizeWeekday: normalizeWeekday) {
            return CronField(raw: raw, values: [], wildcard: false, step: nil, special: special)
        }

        // 名称替换
        if let names {
            for (key, value) in names {
                text = text.replacingOccurrences(of: key, with: "\(value)")
            }
        }

        var values = Set<Int>()
        var step: Int?
        let wildcard = text.hasPrefix("*")

        guard text != "*" || true else { throw CronError.badValue(field: name, token: raw, reason: "空字段") }

        for token in text.split(separator: ",").map(String.init) {
            var segment = token
            var segmentStep: Int?

            if let slashIndex = segment.firstIndex(of: "/") {
                let stepText = String(segment[segment.index(after: slashIndex)...])
                segment = String(segment[segment.startIndex..<slashIndex])
                guard let parsedStep = Int(stepText), parsedStep > 0 else {
                    throw CronError.badValue(field: name, token: token, reason: "步长得是正整数")
                }
                segmentStep = parsedStep
                step = parsedStep
            }

            let lower: Int
            let upper: Int

            if segment == "*" {
                lower = range.lowerBound
                upper = range.upperBound
            } else if let dashIndex = segment.firstIndex(of: "-"), dashIndex != segment.startIndex {
                let lowerText = String(segment[segment.startIndex..<dashIndex])
                let upperText = String(segment[segment.index(after: dashIndex)...])
                guard let parsedLower = Int(lowerText), let parsedUpper = Int(upperText) else {
                    throw CronError.badValue(field: name, token: token, reason: "区间得是数字")
                }
                lower = parsedLower
                upper = parsedUpper
            } else {
                guard let value = Int(segment) else {
                    throw CronError.badValue(field: name, token: token, reason: "认不出这个值")
                }
                lower = value
                upper = value
            }

            guard lower >= range.lowerBound, upper <= range.upperBound, lower <= upper else {
                throw CronError.outOfRange(field: name, value: lower < range.lowerBound ? lower : upper, range: range)
            }

            let stride = segmentStep ?? 1
            var value = lower
            while value <= upper {
                values.insert(value)
                value += stride
            }
        }

        guard !values.isEmpty else {
            throw CronError.badValue(field: name, token: raw, reason: "展开后没有任何取值")
        }

        if normalizeWeekday {
            // cron 里 0 和 7 都表示周日，统一成 0
            if values.contains(7) {
                values.remove(7)
                values.insert(0)
            }
        }

        return CronField(raw: raw, values: values, wildcard: wildcard, step: step)
    }

    /// 识别 L / W / # 扩展写法。不匹配时返回 nil，走普通解析。
    private static func parseSpecial(
        _ text: String,
        name: String,
        range: ClosedRange<Int>,
        normalizeWeekday: Bool
    ) throws -> CronSpecial? {
        let fail: (String) -> CronError = { reason in
            CronError.badValue(field: name, token: text, reason: reason)
        }

        // 周字段的两个扩展
        if normalizeWeekday {
            if let hashIndex = text.firstIndex(of: "#") {
                let left = String(text[text.startIndex..<hashIndex])
                let right = String(text[text.index(after: hashIndex)...])
                guard let weekday = Int(left), (0...7).contains(weekday) else {
                    throw fail("# 前面得是 0-7 的周几")
                }
                guard let nth = Int(right), (1...5).contains(nth) else {
                    throw fail("# 后面得是 1-5（当月第几个）")
                }
                return .nthWeekday(weekday: weekday == 7 ? 0 : weekday, nth: nth)
            }
            // 5L：当月最后一个周几
            if text.count > 1, text.hasSuffix("L"), let weekday = Int(text.dropLast()) {
                guard (0...7).contains(weekday) else { throw fail("L 前面得是 0-7 的周几") }
                return .lastWeekdayOf(weekday == 7 ? 0 : weekday)
            }
        }

        guard range.lowerBound >= 1 else { return nil }  // 剩下的是日字段的专属

        if text == "L" { return .lastDay }
        if text == "LW" { return .lastWeekday }
        if text.hasPrefix("L-"), let offset = Int(text.dropFirst(2)) {
            guard (0...30).contains(offset) else { throw fail("L- 后面的偏移得在 0-30") }
            return .lastDayMinus(offset)
        }
        if text.hasSuffix("W"), let day = Int(text.dropLast()) {
            guard (1...31).contains(day) else { throw fail("W 前面得是 1-31 的日期") }
            return .nearestWeekday(day)
        }
        return nil
    }

    // MARK: 每月的匹配日

    /// 日字段在指定月份里匹配到的「几号」集合；nil 表示不限定（* 或 ?）。
    /// 注意空集是有意义的：2 月 30 日会得到空集，表示当月永远不触发。
    static func dayValues(of field: CronField, year: Int, month: Int, calendar: Calendar) -> Set<Int>? {
        if let special = field.special {
            let lastDay = daysInMonth(year: year, month: month, calendar: calendar)
            switch special {
            case .lastDay:
                return [lastDay]
            case .lastDayMinus(let offset):
                return [max(1, lastDay - offset)]
            case .lastWeekday:
                return [nearestWeekday(lastDay, year: year, month: month, calendar: calendar)]
            case .nearestWeekday(let day):
                return [nearestWeekday(min(day, lastDay), year: year, month: month, calendar: calendar)]
            case .lastWeekdayOf, .nthWeekday:
                return nil  // 这两个是周字段的写法
            }
        }
        if field.wildcard { return nil }
        let total = daysInMonth(year: year, month: month, calendar: calendar)
        return Set(field.values.filter { $0 >= 1 && $0 <= total })
    }

    /// 周字段在指定月份里匹配到的「几号」集合；nil 表示不限定。
    static func weekdayValues(of field: CronField, year: Int, month: Int, calendar: Calendar) -> Set<Int>? {
        if let special = field.special {
            let lastDay = daysInMonth(year: year, month: month, calendar: calendar)
            switch special {
            case .lastWeekdayOf(let weekday):
                let weekdayOfLast = cronWeekday(of: lastDay, year: year, month: month, calendar: calendar)
                let back = (weekdayOfLast - weekday + 7) % 7
                return [lastDay - back]
            case .nthWeekday(let weekday, let nth):
                let weekdayOfFirst = cronWeekday(of: 1, year: year, month: month, calendar: calendar)
                let first = 1 + (weekday - weekdayOfFirst + 7) % 7 + (nth - 1) * 7
                return first <= lastDay ? [first] : []
            case .lastDay, .lastDayMinus, .lastWeekday, .nearestWeekday:
                return nil  // 这几个是日字段的写法
            }
        }
        if field.wildcard { return nil }
        let total = daysInMonth(year: year, month: month, calendar: calendar)
        var result = Set<Int>()
        for day in 1...total where field.values.contains(cronWeekday(of: day, year: year, month: month, calendar: calendar)) {
            result.insert(day)
        }
        return result
    }

    /// 当月天数
    static func daysInMonth(year: Int, month: Int, calendar: Calendar) -> Int {
        let components = DateComponents(year: year, month: month)
        guard let interval = calendar.dateInterval(of: .month, for: calendar.date(from: components) ?? Date()) else {
            return 30
        }
        return calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 30
    }

    /// 某天的 cron 周几（0 = 周日）
    static func cronWeekday(of day: Int, year: Int, month: Int, calendar: Calendar) -> Int {
        var components = DateComponents(year: year, month: month, day: day)
        components.calendar = calendar
        guard let date = components.date else { return 0 }
        return calendar.component(.weekday, from: date) - 1
    }

    /// Quartz 的 W 规则：离 day 最近的工作日。周六往前挪一天，周日往后挪一天，
    /// 挪出当月时往回修正（保持在本月内）。
    static func nearestWeekday(_ day: Int, year: Int, month: Int, calendar: Calendar) -> Int {
        let lastDay = daysInMonth(year: year, month: month, calendar: calendar)
        let weekday = cronWeekday(of: day, year: year, month: month, calendar: calendar)
        switch weekday {
        case 0:  // 周日 → 周一
            return day + 1 <= lastDay ? day + 1 : day - 2
        case 6:  // 周六 → 周五
            return day - 1 >= 1 ? day - 1 : day + 2
        default:
            return day
        }
    }

    // MARK: 匹配

    /// 日和周的匹配规则：两个都限定了就取"或"（Vixie cron 的行为），
    /// 只限定一个时按限定的来。这个细节很容易踩坑。
    /// L / W / # 这些写法依赖年月，所以每次都按当月重新算。
    static func dayMatches(
        _ schedule: CronSchedule,
        year: Int,
        month: Int,
        day: Int,
        weekday: Int,
        calendar: Calendar
    ) -> Bool {
        let daySet = dayValues(of: schedule.day, year: year, month: month, calendar: calendar)
        let weekSet = weekdayValues(of: schedule.weekday, year: year, month: month, calendar: calendar)
        let dayOK = daySet?.contains(day) ?? true
        let weekOK = weekSet?.contains(day) ?? true
        if daySet != nil, weekSet != nil { return dayOK || weekOK }
        return dayOK && weekOK
    }

    // MARK: 下次执行

    static func nextRuns(_ schedule: CronSchedule, after start: Date, count: Int, timeZone: TimeZone = zone) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let seconds = (schedule.second?.values ?? [0]).sorted()
        var results: [Date] = []
        results.reserveCapacity(count)

        // 从 start 所在的整分钟起步：同一分钟里可能还有没到的秒
        guard var cursor = calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start)) else {
            return []
        }

        var guardCounter = 0
        let guardLimit = 400_000

        while results.count < count, guardCounter < guardLimit {
            guardCounter += 1

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: cursor)
            guard let year = components.year,
                  let month = components.month,
                  let day = components.day,
                  let hour = components.hour,
                  let minute = components.minute,
                  let weekday = components.weekday else { break }

            if !schedule.month.values.contains(month) {
                cursor = startOfNextMonth(cursor, calendar: calendar)
                continue
            }
            if !dayMatches(schedule, year: year, month: month, day: day, weekday: weekday, calendar: calendar) {
                cursor = startOfNextDay(cursor, calendar: calendar)
                continue
            }
            if !schedule.hour.values.contains(hour) {
                cursor = startOfNextHour(cursor, calendar: calendar)
                continue
            }
            if !schedule.minute.values.contains(minute) {
                cursor = calendar.date(byAdding: .minute, value: 1, to: cursor) ?? cursor.addingTimeInterval(60)
                continue
            }

            // 分钟命中：把这一分钟里符合的秒都算出来
            for second in seconds {
                guard let moment = calendar.date(byAdding: .second, value: second, to: cursor) else { continue }
                guard moment > start else { continue }
                results.append(moment)
                if results.count >= count { break }
            }
            cursor = calendar.date(byAdding: .minute, value: 1, to: cursor) ?? cursor.addingTimeInterval(60)
        }

        return results
    }

    private static func startOfNextMonth(_ date: Date, calendar: Calendar) -> Date {
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let next = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else {
            return date.addingTimeInterval(86400 * 30)
        }
        return next
    }

    private static func startOfNextDay(_ date: Date, calendar: Calendar) -> Date {
        guard let startOfDay = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: date)),
              let next = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return date.addingTimeInterval(86400)
        }
        return next
    }

    private static func startOfNextHour(_ date: Date, calendar: Calendar) -> Date {
        guard let startOfHour = calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: date)),
              let next = calendar.date(byAdding: .hour, value: 1, to: startOfHour) else {
            return date.addingTimeInterval(3600)
        }
        return next
    }

    // MARK: 描述

    static func describe(_ schedule: CronSchedule) -> String {
        let timePart = describeTime(schedule)
        let datePart = describeDate(schedule)
        if datePart.isEmpty { return timePart }
        if timePart.isEmpty { return datePart }
        return datePart + " " + timePart
    }

    private static func describeDate(_ schedule: CronSchedule) -> String {
        var pieces: [String] = []

        if !schedule.month.wildcard {
            let names = schedule.month.sorted.map { "\($0) 月" }
            if schedule.month.isRange(1...12) {
                // 全部月份，等于没限制
            } else {
                pieces.append(names.joined(separator: "、"))
            }
        }

        // 周（含 5L / 3#2 这类扩展）
        if let special = schedule.weekday.special {
            switch special {
            case .lastWeekdayOf(let weekday):
                pieces.append("每月最后一个\(weekdayName(weekday))")
            case .nthWeekday(let weekday, let nth):
                pieces.append("每月第 \(nth) 个\(weekdayName(weekday))")
            default:
                break
            }
        } else if schedule.weekdayIsRestricted {
            if schedule.weekday.isRange(1...5) {
                pieces.append("周一到周五")
            } else {
                let names = schedule.weekday.sorted.map { weekdayName($0) }
                pieces.append(names.joined(separator: "、"))
            }
        } else if let special = schedule.day.special {
            switch special {
            case .lastDay:
                pieces.append("每月最后一天")
            case .lastDayMinus(let offset):
                pieces.append(offset == 0 ? "每月最后一天" : "每月最后一天往前 \(offset) 天")
            case .lastWeekday:
                pieces.append("每月最后一个工作日")
            case .nearestWeekday(let day):
                pieces.append("每月离 \(day) 号最近的工作日")
            default:
                break
            }
        } else if schedule.dayIsRestricted {
            let days = schedule.day.sorted.map { "\($0) 日" }
            if days.count > 6 {
                pieces.append("每月 \(days.prefix(3).joined(separator: "、")) 等 \(days.count) 天")
            } else {
                pieces.append("每月 " + days.joined(separator: "、"))
            }
        }

        if pieces.isEmpty { return "每天" }
        return pieces.joined(separator: " ")
    }

    private static func describeTime(_ schedule: CronSchedule) -> String {
        let minutes = schedule.minute.sorted
        let hours = schedule.hour.sorted

        if schedule.minute.wildcard, schedule.hour.wildcard {
            if let step = schedule.minute.step, step > 1 { return "每 \(step) 分钟" }
            return "每分钟"
        }

        if schedule.hour.wildcard {
            if let step = schedule.minute.step, step > 1 { return "每 \(step) 分钟" }
            if minutes == [0] { return "每小时整点" }
            if minutes.count == 1 { return "每小时的 \(minutes[0]) 分" }
            return "每小时的第 " + minutes.map(String.init).joined(separator: "、") + " 分"
        }

        if let step = schedule.hour.step, step > 1, schedule.minute.wildcard {
            return "每 \(step) 小时"
        }

        if schedule.minute.wildcard {
            let names = hours.map { String(format: "%02d:00", $0) }
            return timesText(names, total: hours.count * 60)
        }

        // 具体时刻：把小时和分钟做个笛卡尔积，太多就截断
        var moments: [String] = []
        for hour in hours {
            for minute in minutes {
                moments.append(String(format: "%02d:%02d", hour, minute))
                if moments.count >= 7 { break }
            }
            if moments.count >= 7 { break }
        }
        return timesText(moments, total: hours.count * minutes.count)
    }

    private static func timesText(_ moments: [String], total: Int) -> String {
        if moments.isEmpty { return "—" }
        if total <= moments.count {
            return moments.joined(separator: "、")
        }
        let head = moments.prefix(6).joined(separator: "、")
        return "\(head) 等 \(total) 个时刻"
    }

    static func weekdayName(_ cronWeekday: Int) -> String {
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        guard (0...6).contains(cronWeekday) else { return "周?" }
        return names[cronWeekday]
    }

    // MARK: 结构说明

    /// 把每个字段展开的样子列出来，方便对照
    static func breakdown(_ schedule: CronSchedule) -> [(field: String, raw: String, expanded: String, range: String)] {
        var rows: [(String, String, String, String)] = []
        if let second = schedule.second {
            rows.append(("秒", second.raw, expand(second, limit: 12), "0-59"))
        }
        rows.append(("分", schedule.minute.raw, expand(schedule.minute, limit: 12), "0-59"))
        rows.append(("时", schedule.hour.raw, expand(schedule.hour, limit: 12), "0-23"))
        rows.append(("日", schedule.day.raw, expand(schedule.day, limit: 12), "1-31"))
        rows.append(("月", schedule.month.raw, expand(schedule.month, limit: 12), "1-12"))
        rows.append(("周", schedule.weekday.raw, expand(schedule.weekday, limit: 12), "0-7（0 和 7 都是周日）"))
        return rows.map { (field: $0.0, raw: $0.1, expanded: $0.2, range: $0.3) }
    }

    /// 字段级的解析诊断：每一段各自解析，返回对应位置的错误描述（nil = 这段没问题）。
    /// 字段数不对时返回单元素数组。
    static func fieldErrors(of raw: String) -> [String?] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return [CronError.empty.localizedDescription] }

        var body = text
        if text.hasPrefix("@") {
            let key = text.split(separator: " ").first.map(String.init) ?? text
            guard let expanded = macros[key] else {
                return [CronError.unknownMacro(String(key)).localizedDescription]
            }
            body = expanded
        }

        let parts = body.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        switch parts.count {
        case 5, 6:
            break
        default:
            return [CronError.fieldCount(parts.count).localizedDescription]
        }

        let hasSeconds = parts.count == 6
        var specs: [(name: String, range: ClosedRange<Int>, weekday: Bool)] = []
        if hasSeconds { specs.append(("秒", 0...59, false)) }
        specs.append(("分", 0...59, false))
        specs.append(("时", 0...23, false))
        specs.append(("日", 1...31, false))
        specs.append(("月", 1...12, false))
        specs.append(("周", 0...7, true))

        return parts.enumerated().map { index, part in
            let spec = specs[index]
            do {
                _ = try parseField(part, name: spec.name, range: spec.range, normalizeWeekday: spec.weekday)
                return nil
            } catch {
                return error.localizedDescription
            }
        }
    }

    /// 特殊写法的人话解释，给展开列用
    private static func specialText(_ special: CronSpecial) -> String {
        switch special {
        case .lastDay: return "当月最后一天"
        case .lastDayMinus(let offset): return offset == 0 ? "当月最后一天" : "最后一天往前 \(offset) 天"
        case .lastWeekday: return "当月最后一个工作日"
        case .nearestWeekday(let day): return "离 \(day) 号最近的工作日"
        case .lastWeekdayOf(let weekday): return "当月最后一个\(weekdayName(weekday))"
        case .nthWeekday(let weekday, let nth): return "当月第 \(nth) 个\(weekdayName(weekday))"
        }
    }

    private static func expand(_ field: CronField, limit: Int) -> String {
        if let special = field.special { return specialText(special) }
        let values = field.sorted
        if field.wildcard && field.step == nil { return "全部" }
        if values.count > limit {
            return values.prefix(limit).map(String.init).joined(separator: " ") + " … 共 \(values.count) 个"
        }
        return values.map(String.init).joined(separator: " ")
    }

    // MARK: 反向生成

    enum Period: String, CaseIterable, Identifiable, Sendable {
        case everyNMinutes
        case hourly
        case daily
        case weekly
        case monthly
        case workdays

        var id: String { rawValue }

        var title: String {
            switch self {
            case .everyNMinutes: return "每 N 分钟"
            case .hourly: return "每小时"
            case .daily: return "每天"
            case .weekly: return "每周"
            case .monthly: return "每月"
            case .workdays: return "工作日"
            }
        }
    }

    /// 按选择的周期拼表达式
    static func build(
        period: Period,
        minute: Int,
        hour: Int,
        interval: Int,
        weekday: Int,
        dayOfMonth: Int
    ) -> String {
        switch period {
        case .everyNMinutes:
            return "*/\(max(1, interval)) * * * *"
        case .hourly:
            return "\(minute) * * * *"
        case .daily:
            return "\(minute) \(hour) * * *"
        case .weekly:
            return "\(minute) \(hour) * * \(weekday)"
        case .monthly:
            return "\(minute) \(hour) \(dayOfMonth) * *"
        case .workdays:
            return "\(minute) \(hour) * * 1-5"
        }
    }

    // MARK: 相对时间描述

    static func relativeText(_ date: Date, from now: Date = Date()) -> String {
        let interval = date.timeIntervalSince(now)
        let seconds = Int(interval.rounded())
        if seconds < 0 { return "刚刚" }
        if seconds < 60 { return "\(seconds) 秒后" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) 分钟后" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) 小时 \(minutes % 60) 分钟后" }
        let days = hours / 24
        if days < 31 { return "\(days) 天 \(hours % 24) 小时后" }
        let months = days / 30
        return "约 \(months) 个月后"
    }

    // MARK: 本机 crontab（只读）

    struct LocalCronEntry: Identifiable, Sendable {
        let id: Int
        let expression: String
        let command: String
        let raw: String
        let enabled: Bool
    }

    struct LocalCrontab: Sendable {
        let entries: [LocalCronEntry]
        let raw: String
        let error: String?
    }

    /// 读当前用户的 crontab。只读，不写不改。
    static func localCrontab() -> LocalCrontab {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/crontab")
        process.arguments = ["-l"]

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            return LocalCrontab(entries: [], raw: "", error: "跑不动 crontab 命令：\(error.localizedDescription)")
        }

        let outData = output.fileHandleForReading.readDataToEndOfFile()
        let errData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let text = String(data: outData, encoding: .utf8) ?? ""
        let errorText = String(data: errData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let hint = errorText.contains("no crontab")
                ? "这个用户还没有 crontab（很正常，macOS 上大多用 launchd）"
                : errorText.trimmingCharacters(in: .whitespacesAndNewlines)
            return LocalCrontab(entries: [], raw: text, error: hint.isEmpty ? "读取失败" : hint)
        }

        return LocalCrontab(entries: parseCrontab(text), raw: text, error: nil)
    }

    /// 从 crontab 文本里挑出真正是任务的行
    static func parseCrontab(_ text: String) -> [LocalCronEntry] {
        var entries: [LocalCronEntry] = []
        var index = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            index += 1

            // 环境变量赋值行不是任务
            if trimmed.contains("="), trimmed.range(of: #"^\w+\s*="#, options: .regularExpression) != nil {
                continue
            }

            var parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 6 else { continue }

            // 带 @ 的简写
            if parts[0].hasPrefix("@") {
                let expression = parts[0]
                let command = parts.dropFirst().joined(separator: " ")
                entries.append(LocalCronEntry(
                    id: entries.count,
                    expression: expression,
                    command: command,
                    raw: trimmed,
                    enabled: true
                ))
                continue
            }

            // 6 段（带秒）还是 5 段：看第 6 个 token 像不像表达式
            let firstFive = Array(parts.prefix(5))
            let looksFive = firstFive.allSatisfy { token in
                token.allSatisfy { $0.isNumber || "*,-/?".contains($0) }
            }
            let take = looksFive ? 5 : min(6, max(5, parts.count - 1))
            let expression = parts.prefix(take).joined(separator: " ")
            parts.removeFirst(take)
            let command = parts.joined(separator: " ")

            entries.append(LocalCronEntry(
                id: entries.count,
                expression: expression,
                command: command,
                raw: trimmed,
                enabled: true
            ))
        }
        return entries
    }
}
