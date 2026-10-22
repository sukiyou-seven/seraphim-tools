import Foundation

// MARK: - 日期

/// 纯年月日，不带时间也不带时区，避开 Date 在时区上的各种坑
struct SolarDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    var year: Int
    var month: Int
    var day: Int

    var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    var cjk: String { "\(year) 年 \(month) 月 \(day) 日" }

    static func < (lhs: SolarDate, rhs: SolarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// 星期几，1 = 周日 … 7 = 周六
    var weekday: Int { CalendarEngine.weekday(of: self) }

    var weekdayName: String { CalendarEngine.weekdayName(weekday) }

    var julianDay: Int { CalendarEngine.julianDay(year: year, month: month, day: day) }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init?(text: String) {
        let parts = text
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
            .split(separator: "-")
            .map(String.init)
        guard parts.count >= 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        guard CalendarEngine.isValid(year: year, month: month, day: day) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    init(date: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = CalendarEngine.zone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }

    var date: Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = CalendarEngine.zone
        return calendar.date(from: components) ?? Date()
    }
}

// MARK: - 农历日期

struct LunarDate: Hashable, Sendable {
    let year: Int
    let month: Int        // 1-12
    let day: Int          // 1-30
    let isLeap: Bool

    var monthName: String {
        let names = ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊"]
        guard (1...12).contains(month) else { return "\(month)月" }
        return (isLeap ? "闰" : "") + names[month - 1] + "月"
    }

    var dayName: String { CalendarEngine.lunarDayName(day) }

    var yearGanZhi: String { CalendarEngine.ganZhi(year: year) }

    var zodiac: String { CalendarEngine.zodiac(year: year) }

    /// 例：丙午年 正月初一
    var shortText: String { "\(yearGanZhi)年 \(monthName)\(dayName)" }

    /// 例：2026 年 正月初一（丙午 马年）
    var displayText: String {
        "\(year) 年 \(monthName)\(dayName)（\(yearGanZhi) \(zodiac)年）"
    }

    var lunarMonthsInYear: Int { CalendarEngine.leapMonth(year: year) > 0 ? 13 : 12 }
}

// MARK: - 节气

struct SolarTerm: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let date: SolarDate
    let index: Int
}

// MARK: - 工作日配置

struct WorkdayOptions: Sendable, Equatable {
    /// 一周里哪几天算休息，1 = 周日 … 7 = 周六
    var weekendDays: Set<Int> = [1, 7]
    /// 额外的放假日（调休之外的法定假日）
    var holidays: Set<String> = []
    /// 周末但要上班的日子（调休）
    var makeupWorkdays: Set<String> = []

    static let standardWeekend: Set<Int> = [1, 7]

    func isRestDay(_ date: SolarDate) -> Bool {
        let key = date.description
        if holidays.contains(key) { return true }
        if makeupWorkdays.contains(key) { return false }
        return weekendDays.contains(date.weekday)
    }

    func isWorkday(_ date: SolarDate) -> Bool { !isRestDay(date) }
}

// MARK: - 日期差结果

struct DateDifference: Sendable {
    let totalDays: Int
    let years: Int
    let months: Int
    let days: Int
    let weeks: Int
    let remainderDays: Int
    let totalHours: Int
    let totalMinutes: Int
    let totalSeconds: Int
    let workdays: Int
    let restDays: Int
    /// 终点相对起点是往后还是往前
    let forward: Bool
}

// MARK: - 引擎

enum CalendarEngine {

    static let zone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    // MARK: - 公历基础

    static func isValid(year: Int, month: Int, day: Int) -> Bool {
        guard (1...12).contains(month), day >= 1 else { return false }
        return day <= daysInMonth(year: year, month: month)
    }

    static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeapYear(year) ? 29 : 28
        default: return 30
        }
    }

    /// 标准 JDN 公式（格里高利历）。用它做天数差不会掉进时区/夏令时的坑。
    static func julianDay(year: Int, month: Int, day: Int) -> Int {
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    static func solarDate(fromJulianDay jdn: Int) -> SolarDate {
        var a = jdn + 32044
        let b = (4 * a + 3) / 146097
        let c = a - 146097 * b / 4
        var d = (4 * c + 3) / 1461
        let e = c - 1461 * d / 4
        let m = (5 * e + 2) / 153
        a = 100 * b + d - 4800 + m / 10
        d = e - (153 * m + 2) / 5 + 1
        let month = Int(m + 3 - 12 * (m / 10))
        return SolarDate(year: Int(a), month: month, day: Int(d))
    }

    /// 1 = 周日 … 7 = 周六。跟 Foundation `Calendar` 的 weekday 取值保持一致，
    /// 免得两套编号在工期计算和 cron 之间来回换算时出错。
    static func weekday(of date: SolarDate) -> Int {
        // JDN 的 0 是周一，(JDN + 1) % 7 = 0 时是周日
        ((date.julianDay + 1) % 7) + 1
    }

    static func weekdayName(_ weekday: Int) -> String {
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        guard (1...7).contains(weekday) else { return "—" }
        return names[weekday - 1]
    }

    // MARK: - 干支 / 生肖

    static func ganZhi(year: Int) -> String {
        let stems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
        let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
        let index = ((year - 4) % 60 + 60) % 60
        return stems[index % 10] + branches[index % 12]
    }

    static func zodiac(year: Int) -> String {
        let animals = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"]
        let index = ((year - 4) % 12 + 12) % 12
        return animals[index]
    }

    static func lunarDayName(_ day: Int) -> String {
        let tens = ["初", "十", "廿", "三"]
        let units = ["十", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        switch day {
        case 1...10:
            return tens[0] + units[day % 10]
        case 11...19:
            return "十" + units[day % 10]
        case 20:
            return "二十"
        case 21...29:
            return "廿" + units[day % 10]
        case 30:
            return "三十"
        default:
            return "\(day)"
        }
    }

    // MARK: - 农历数据（1900-2100）

    /// 每年一个整数：低 4 位是闰月月份（0 表示无闰），0x10000 位表示闰月大小，
    /// 其余位从高到低表示正月到腊月的大小（1 = 30 天，0 = 29 天）。
    static let lunarInfo: [Int] = [
        0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0, 0x09ad0, 0x055d2, // 1900-1909
        0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540, 0x0d6a0, 0x0ada2, 0x095b0, 0x14977, // 1910-1919
        0x04970, 0x0a4b0, 0x0b4b5, 0x06a50, 0x06d40, 0x1ab54, 0x02b60, 0x09570, 0x052f2, 0x04970, // 1920-1929
        0x06566, 0x0d4a0, 0x0ea50, 0x06e95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0, 0x1c8d7, 0x0c950, // 1930-1939
        0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2, 0x0a950, 0x0b557, // 1940-1949
        0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5b0, 0x14573, 0x052b0, 0x0a9a8, 0x0e950, 0x06aa0, // 1950-1959
        0x0aea6, 0x0ab50, 0x04b60, 0x0aae4, 0x0a570, 0x05260, 0x0f263, 0x0d950, 0x05b57, 0x056a0, // 1960-1969
        0x096d0, 0x04dd5, 0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540, 0x0b6a0, 0x195a6, // 1970-1979
        0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46, 0x0ab60, 0x09570, // 1980-1989
        0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58, 0x055c0, 0x0ab60, 0x096d5, 0x092e0, // 1990-1999
        0x0c960, 0x0d954, 0x0d4a0, 0x0da50, 0x07552, 0x056a0, 0x0abb7, 0x025d0, 0x092d0, 0x0cab5, // 2000-2009
        0x0a950, 0x0b4a0, 0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176, 0x052b0, 0x0a930, // 2010-2019
        0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260, 0x0ea65, 0x0d530, // 2020-2029
        0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d250, 0x0d520, 0x0dd45, // 2030-2039
        0x0b5a0, 0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0, 0x0aa50, 0x1b255, 0x06d20, 0x0ada0, // 2040-2049
        0x14b63, 0x09370, 0x049f8, 0x04970, 0x064b0, 0x168a6, 0x0ea50, 0x06b20, 0x1a6c4, 0x0aae0, // 2050-2059
        0x0a2e0, 0x0d2e3, 0x0c960, 0x0d557, 0x0d4a0, 0x0da50, 0x05d55, 0x056a0, 0x0a6d0, 0x055d4, // 2060-2069
        0x052d0, 0x0a9b8, 0x0a950, 0x0b4a0, 0x0b6a6, 0x0ad50, 0x055a0, 0x0aba4, 0x0a5b0, 0x052b0, // 2070-2079
        0x0b273, 0x06930, 0x07337, 0x06aa0, 0x0ad50, 0x14b55, 0x04b60, 0x0a570, 0x054e4, 0x0d160, // 2080-2089
        0x0e968, 0x0d520, 0x0daa0, 0x16aa6, 0x056d0, 0x04ae0, 0x0a9d4, 0x0a2d0, 0x0d150, 0x0f252, // 2090-2099
        0x0d520,                                                                                   // 2100
    ]

    static let lunarYearRange = 1900...2100

    /// 1900 年正月初一对应的儒略日
    static let lunarEpochJDN = julianDay(year: 1900, month: 1, day: 31)

    static func leapMonth(year: Int) -> Int {
        guard lunarYearRange.contains(year) else { return 0 }
        return lunarInfo[year - 1900] & 0xf
    }

    static func leapMonthDays(year: Int) -> Int {
        guard leapMonth(year: year) != 0 else { return 0 }
        return (lunarInfo[year - 1900] & 0x10000) != 0 ? 30 : 29
    }

    static func lunarMonthDays(year: Int, month: Int) -> Int {
        guard lunarYearRange.contains(year), (1...12).contains(month) else { return 29 }
        return (lunarInfo[year - 1900] & (0x10000 >> month)) != 0 ? 30 : 29
    }

    static func lunarYearDays(_ year: Int) -> Int {
        guard lunarYearRange.contains(year) else { return 354 }
        var sum = 348
        var mask = 0x8000
        while mask > 0x8 {
            if (lunarInfo[year - 1900] & mask) != 0 { sum += 1 }
            mask >>= 1
        }
        return sum + leapMonthDays(year: year)
    }

    // MARK: 互转

    static func solarToLunar(_ date: SolarDate) -> LunarDate? {
        guard lunarYearRange.contains(date.year) else { return nil }
        var offset = date.julianDay - lunarEpochJDN

        var year = 1900
        var temp = 0
        while year <= 2100, offset > 0 {
            temp = lunarYearDays(year)
            offset -= temp
            year += 1
        }
        if offset < 0 {
            offset += temp
            year -= 1
        }
        guard lunarYearRange.contains(year) else { return nil }

        let leap = leapMonth(year: year)
        var isLeap = false
        var month = 1
        while month < 13, offset > 0 {
            if leap > 0, month == leap + 1, !isLeap {
                month -= 1
                isLeap = true
                temp = leapMonthDays(year: year)
            } else {
                temp = lunarMonthDays(year: year, month: month)
            }
            if isLeap, month == leap + 1 { isLeap = false }
            offset -= temp
            month += 1
        }

        if offset == 0, leap > 0, month == leap + 1 {
            if isLeap {
                isLeap = false
            } else {
                isLeap = true
                month -= 1
            }
        }
        if offset < 0 {
            offset += temp
            month -= 1
        }

        return LunarDate(year: year, month: month, day: offset + 1, isLeap: isLeap)
    }

    static func lunarToSolar(_ lunar: LunarDate) -> SolarDate? {
        guard lunarYearRange.contains(lunar.year), (1...12).contains(lunar.month), (1...30).contains(lunar.day) else {
            return nil
        }
        let leap = leapMonth(year: lunar.year)
        if lunar.isLeap, leap != lunar.month { return nil }

        var offset = 0
        for year in 1900..<lunar.year {
            offset += lunarYearDays(year)
        }

        // 累加到目标月之前（含闰月）
        for month in 1..<lunar.month {
            offset += lunarMonthDays(year: lunar.year, month: month)
            if leap == month { offset += leapMonthDays(year: lunar.year) }
        }
        if lunar.isLeap, leap == lunar.month {
            offset += lunarMonthDays(year: lunar.year, month: lunar.month)
        }

        let limit = lunar.isLeap ? leapMonthDays(year: lunar.year) : lunarMonthDays(year: lunar.year, month: lunar.month)
        guard lunar.day <= limit else { return nil }

        offset += lunar.day - 1
        return solarDate(fromJulianDay: lunarEpochJDN + offset)
    }

    /// 某个公历年份里所有农历月份（含闰月），用于界面上的月份选择
    static func lunarMonths(year: Int) -> [(month: Int, isLeap: Bool, name: String, days: Int)] {
        var result: [(Int, Bool, String, Int)] = []
        for month in 1...12 {
            let days = lunarMonthDays(year: year, month: month)
            let name = LunarDate(year: year, month: month, day: 1, isLeap: false).monthName
            result.append((month, false, name, days))
            if leapMonth(year: year) == month {
                let leapName = LunarDate(year: year, month: month, day: 1, isLeap: true).monthName
                result.append((month, true, leapName, leapMonthDays(year: year)))
            }
        }
        return result.map { (month: $0.0, isLeap: $0.1, name: $0.2, days: $0.3) }
    }

    // MARK: 节气

    static let solarTermNames = [
        "小寒", "大寒", "立春", "雨水", "惊蛰", "春分", "清明", "谷雨",
        "立夏", "小满", "芒种", "夏至", "小暑", "大暑", "立秋", "处暑",
        "白露", "秋分", "寒露", "霜降", "立冬", "小雪", "大雪", "冬至",
    ]

    /// 各节气相对"小寒"的分钟偏移（经验值，用于推算到天）
    private static let solarTermMinutes: [Double] = [
        0, 21208, 42467, 63836, 85337, 107014, 128867, 150921,
        173149, 195551, 218072, 240693, 263343, 285989, 308563, 331033,
        353350, 375494, 397447, 419210, 440795, 462224, 483532, 504758,
    ]

    private static let termBase: Date = {
        var components = DateComponents()
        components.year = 1900
        components.month = 1
        components.day = 6
        components.hour = 2
        components.minute = 5
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }()

    /// 回归年毫秒数
    private static let tropicalYearMilliseconds: Double = 31_556_925_974.7

    /// 第 index 个节气（0 = 小寒）在 year 年的公历日期
    static func solarTerm(year: Int, index: Int) -> SolarDate? {
        guard (0..<24).contains(index), (1900...2100).contains(year) else { return nil }
        let milliseconds = tropicalYearMilliseconds * Double(year - 1900)
            + solarTermMinutes[index] * 60_000
        let moment = termBase.addingTimeInterval(milliseconds / 1000)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let components = calendar.dateComponents([.year, .month, .day], from: moment)
        guard let month = components.month, let day = components.day else { return nil }
        return SolarDate(year: components.year ?? year, month: month, day: day)
    }

    /// 找出某天对应的节气（当天恰好交节时返回）
    static func solarTerm(on date: SolarDate) -> String? {
        let terms = solarTerms(inYear: date.year)
        return terms.first { $0.date == date }?.name
    }

    static func solarTerms(inYear year: Int) -> [SolarTerm] {
        (0..<24).compactMap { index in
            guard let date = solarTerm(year: year, index: index) else { return nil }
            return SolarTerm(name: solarTermNames[index], date: date, index: index)
        }
    }

    /// 下一个节气（含当天之后）
    static func nextSolarTerm(after date: SolarDate) -> SolarTerm? {
        var pool = solarTerms(inYear: date.year)
        if let upcoming = pool.first(where: { $0.date > date }) { return upcoming }
        pool = solarTerms(inYear: date.year + 1)
        return pool.first
    }

    /// 两个相邻节气之间的间隔天数，用来判断"当前处于哪个节气"
    static func currentSolarTerm(on date: SolarDate) -> SolarTerm? {
        var pool = solarTerms(inYear: date.year)
        if date < pool[0].date {
            pool = solarTerms(inYear: date.year - 1)
        }
        return pool.last { $0.date <= date }
    }

    // MARK: 节日

    static func festivals(on date: SolarDate, lunar: LunarDate?) -> [String] {
        var result: [String] = []

        let solarTable: [String: String] = [
            "01-01": "元旦", "02-14": "情人节", "03-08": "妇女节", "03-12": "植树节",
            "05-01": "劳动节", "05-04": "青年节", "06-01": "儿童节", "07-01": "建党节",
            "08-01": "建军节", "09-10": "教师节", "10-01": "国庆节", "12-24": "平安夜",
            "12-25": "圣诞节",
        ]
        let solarKey = String(format: "%02d-%02d", date.month, date.day)
        if let name = solarTable[solarKey] { result.append(name) }

        if let lunar {
            let lunarTable: [String: String] = [
                "1-1": "春节", "1-15": "元宵节", "2-2": "龙抬头", "5-5": "端午节",
                "7-7": "七夕", "7-15": "中元节", "8-15": "中秋节", "9-9": "重阳节",
                "12-8": "腊八节", "12-23": "小年",
            ]
            let key = "\(lunar.month)-\(lunar.day)"
            if !lunar.isLeap, let name = lunarTable[key] { result.append(name) }

            // 除夕 = 腊月的最后一天
            if !lunar.isLeap, lunar.month == 12 {
                let last = lunarMonthDays(year: lunar.year, month: 12)
                if lunar.day == last { result.append("除夕") }
            }
        }

        return result
    }

    // MARK: - 日期差

    static func difference(from start: SolarDate, to end: SolarDate, options: WorkdayOptions = WorkdayOptions()) -> DateDifference {
        let forward = start <= end
        let lower = forward ? start : end
        let upper = forward ? end : start
        let totalDays = abs(end.julianDay - start.julianDay)

        // 年月日精确分解
        let (years, months, days) = calendarBreakdown(from: lower, to: upper)

        let weeks = totalDays / 7
        let remainder = totalDays % 7

        var workdays = 0
        var restDays = 0
        forEachDay(from: lower, to: upper) { day in
            if options.isWorkday(day) { workdays += 1 } else { restDays += 1 }
        }

        return DateDifference(
            totalDays: totalDays,
            years: years,
            months: months,
            days: days,
            weeks: weeks,
            remainderDays: remainder,
            totalHours: totalDays * 24,
            totalMinutes: totalDays * 24 * 60,
            totalSeconds: totalDays * 24 * 3600,
            workdays: workdays,
            restDays: restDays,
            forward: forward
        )
    }

    /// 按"满年满月"的方式拆分两个日期。
    ///
    /// 直接拿年月日相减在月末会出错（1/31 → 3/1 会算出负数天数），
    /// 所以改成先按月对齐出一个锚点日期，再数剩下的天数。
    static func calendarBreakdown(from start: SolarDate, to end: SolarDate) -> (years: Int, months: Int, days: Int) {
        guard start <= end else { return calendarBreakdown(from: end, to: start) }

        var months = (end.year - start.year) * 12 + (end.month - start.month)
        var anchor = add(start, months: months)

        // 锚点越过终点说明这个月数偏大（比如 start 是 31 号，终点月份没有 31 号）
        if anchor > end {
            months -= 1
            anchor = add(start, months: months)
        }
        if months < 0 {
            months = 0
            anchor = start
        }

        let days = end.julianDay - anchor.julianDay
        return (months / 12, months % 12, days)
    }

    /// 遍历日期区间（闭区间），范围大时会有点慢，但日期差本来就很少跨上百年
    static func forEachDay(from start: SolarDate, to end: SolarDate, _ body: (SolarDate) -> Void) {
        guard start <= end else { return }
        var jdn = start.julianDay
        let last = end.julianDay
        while jdn <= last {
            body(solarDate(fromJulianDay: jdn))
            jdn += 1
        }
    }

    // MARK: 日期加减

    static func add(_ date: SolarDate, years: Int = 0, months: Int = 0, days: Int = 0) -> SolarDate {
        var jdn = date.julianDay + days
        var result = solarDate(fromJulianDay: jdn)

        if years != 0 || months != 0 {
            var totalMonths = result.year * 12 + (result.month - 1) + years * 12 + months
            var year = totalMonths / 12
            var month = totalMonths % 12 + 1
            if month < 1 {
                month += 12
                year -= 1
            }
            let day = min(result.day, daysInMonth(year: year, month: month))
            result = SolarDate(year: year, month: month, day: day)
            jdn = result.julianDay
        }
        return result
    }

    // MARK: 工作日

    /// 从 date 起往后（count > 0）或往前（count < 0）数 count 个工作日。
    /// 起点当天若是工作日，从它开始算第 1 个工作日。
    static func addWorkdays(from date: SolarDate, count: Int, options: WorkdayOptions = WorkdayOptions()) -> SolarDate {
        guard count != 0 else { return date }
        var remaining = abs(count)
        var cursor = date
        let step = count > 0 ? 1 : -1

        // 先确认起点是不是工作日：往后数时，起点本身要占掉一个名额
        if options.isWorkday(cursor) {
            remaining -= 1
            if remaining == 0 { return cursor }
        }

        var guardCounter = 0
        while remaining > 0, guardCounter < 40_000 {
            guardCounter += 1
            cursor = solarDate(fromJulianDay: cursor.julianDay + step)
            if options.isWorkday(cursor) {
                remaining -= 1
            }
        }
        return cursor
    }

    /// 两个日期之间有多少个工作日（闭区间）
    static func workdaysBetween(from start: SolarDate, to end: SolarDate, options: WorkdayOptions = WorkdayOptions()) -> Int {
        let lower = min(start, end)
        let upper = max(start, end)
        var count = 0
        forEachDay(from: lower, to: upper) { day in
            if options.isWorkday(day) { count += 1 }
        }
        return count
    }

    // MARK: 今日

    static func today() -> SolarDate {
        SolarDate(date: Date())
    }
}
