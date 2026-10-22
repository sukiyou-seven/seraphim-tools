import SwiftUI

/// 日历与时间：农历互转、日期计算、工作日、定时任务表达式。
struct CalendarToolView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case lunar
        case calc
        case cron

        var id: String { rawValue }

        var title: String {
            switch self {
            case .lunar: return "农历"
            case .calc: return "日期计算"
            case .cron: return "定时任务"
            }
        }

        var systemImage: String {
            switch self {
            case .lunar: return "moon.stars"
            case .calc: return "calendar"
            case .cron: return "clock.arrow.circlepath"
            }
        }
    }

    @AppStorage("calendarMode") private var mode: Mode = .lunar

    var body: some View {
        VStack(spacing: 0) {
            Picker("模式", selection: $mode) {
                ForEach(Mode.allCases) { item in
                    Label(item.title, systemImage: item.systemImage).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            switch mode {
            case .lunar:
                LunarPanel()
            case .calc:
                DateCalcPanel()
            case .cron:
                CronPanel()
            }
        }
    }
}

// MARK: - 小工具

/// 结果里的一格：标题 + 值
struct CalendarStat: View {
    let title: String
    let value: String
    var hint: String?
    var highlight: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 13, weight: highlight ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(highlight ? Color.accentColor : Color.primary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            if let hint {
                Text(hint)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(minWidth: 96, alignment: .leading)
    }
}

// MARK: - 农历

private struct LunarPanel: View {
    @AppStorage("lunarDate") private var dateText = ""
    @AppStorage("lunarYear") private var lunarYear = 2026
    @AppStorage("lunarMonthIndex") private var lunarMonthIndex = 0
    @AppStorage("lunarDay") private var lunarDay = 1

    @State private var didLoad = false
    @State private var toast: String?

    private var solar: SolarDate {
        SolarDate(text: dateText) ?? CalendarEngine.today()
    }

    private var lunar: LunarDate? {
        CalendarEngine.solarToLunar(solar)
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { solar.date },
            set: { dateText = SolarDate(date: $0).description }
        )
    }

    private var monthOptions: [(month: Int, isLeap: Bool, name: String, days: Int)] {
        CalendarEngine.lunarMonths(year: lunarYear)
    }

    private var reverseSolar: SolarDate? {
        let options = monthOptions
        guard options.indices.contains(lunarMonthIndex) else { return nil }
        let option = options[lunarMonthIndex]
        return CalendarEngine.lunarToSolar(
            LunarDate(year: lunarYear, month: option.month, day: lunarDay, isLeap: option.isLeap)
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                solarCard
                reverseCard
                termCard
            }
            .padding(20)
        }
        .toast($toast)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if dateText.isEmpty { dateText = CalendarEngine.today().description }
            if lunarYear < 1901 { lunarYear = CalendarEngine.today().year }
        }
    }

    // MARK: 公历 → 农历

    private var solarCard: some View {
        ToolCard(title: "公历 → 农历", systemImage: "calendar.badge.clock") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    DatePicker("", selection: dateBinding, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)

                    Button("今天") {
                        dateText = CalendarEngine.today().description
                    }
                    .controlSize(.small)

                    Text(solar.cjk + " " + solar.weekdayName)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    if let lunar {
                        NoticeTag(text: lunar.zodiac + "年", systemImage: "pawprint", tint: .secondary)
                    }
                }

                if let lunar {
                    resultGrid(lunar)
                } else {
                    ErrorBanner(message: "农历数据只覆盖 1900 到 2100 年")
                }
            }
        }
    }

    private func resultGrid(_ lunar: LunarDate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 22) {
                CalendarStat(title: "农历", value: lunar.displayText, highlight: true)
                CalendarStat(title: "干支", value: lunar.yearGanZhi + "年")
                CalendarStat(title: "月", value: lunar.monthName, hint: lunar.isLeap ? "闰月" : nil)
                CalendarStat(title: "日", value: lunar.dayName)
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                if let term = CalendarEngine.solarTerm(on: solar) {
                    NoticeTag(text: "今日节气 · \(term)", systemImage: "sun.max", tint: .orange)
                } else if let term = CalendarEngine.currentSolarTerm(on: solar) {
                    NoticeTag(text: "当前节气 · \(term.name)", systemImage: "sun.max", tint: .secondary)
                }

                let festivals = CalendarEngine.festivals(on: solar, lunar: lunar)
                if !festivals.isEmpty {
                    NoticeTag(text: festivals.joined(separator: " / "), systemImage: "party.popper", tint: .pink)
                }

                Spacer(minLength: 0)

                CopyIconButton(text: "\(solar.cjk)（\(solar.weekdayName)）· 农历 \(lunar.displayText)", help: "复制这一天")
            }

            if let next = CalendarEngine.nextSolarTerm(after: solar) {
                Text("下一个节气：\(next.name) · \(next.date.cjk)（还有 \(next.date.julianDay - solar.julianDay) 天）")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: 农历 → 公历

    private var reverseCard: some View {
        ToolCard(title: "农历 → 公历", systemImage: "arrow.uturn.left") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Text("年")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Stepper(value: $lunarYear, in: 1900...2100) {
                            Text("\(lunarYear)")
                                .font(.system(size: 12.5, design: .monospaced))
                                .frame(width: 46, alignment: .leading)
                        }
                        .controlSize(.small)
                    }

                    HStack(spacing: 6) {
                        Text("月")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Menu(monthOptions.indices.contains(lunarMonthIndex) ? monthOptions[lunarMonthIndex].name : "正月") {
                            ForEach(Array(monthOptions.enumerated()), id: \.offset) { index, option in
                                Button {
                                    lunarMonthIndex = index
                                    lunarDay = min(lunarDay, option.days)
                                } label: {
                                    Text("\(option.name)（\(option.days) 天）")
                                }
                            }
                        }
                        .frame(width: 96)
                        .controlSize(.small)
                    }

                    HStack(spacing: 6) {
                        Text("日")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Menu(CalendarEngine.lunarDayName(lunarDay)) {
                            ForEach(1...currentMonthDays, id: \.self) { day in
                                Button("\(day) · \(CalendarEngine.lunarDayName(day))") {
                                    lunarDay = day
                                }
                            }
                        }
                        .frame(width: 92)
                        .controlSize(.small)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 22) {
                    if let reverseSolar {
                        CalendarStat(title: "对应公历", value: reverseSolar.description, hint: reverseSolar.weekdayName, highlight: true)
                        CalendarStat(title: "中文", value: reverseSolar.cjk)
                        if let backLunar = CalendarEngine.solarToLunar(reverseSolar) {
                            CalendarStat(title: "回验", value: backLunar.shortText, hint: "往返一致")
                        }
                    } else {
                        Text("这个组合不存在（比如选了闰月但当年没有该闰月，或日期超出当月天数）")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var currentMonthDays: Int {
        let options = monthOptions
        guard options.indices.contains(lunarMonthIndex) else { return 30 }
        return options[lunarMonthIndex].days
    }

    // MARK: 节气表

    private var termCard: some View {
        ToolCard(title: "\(solar.year) 年二十四节气", systemImage: "sun.horizon") {
            FlowRow(spacing: 6) {
                ForEach(CalendarEngine.solarTerms(inYear: solar.year)) { term in
                    Button {
                        dateText = term.date.description
                    } label: {
                        VStack(spacing: 1) {
                            Text(term.name)
                                .font(.system(size: 11, weight: .medium))
                            Text(String(format: "%02d-%02d", term.date.month, term.date.day))
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - 日期计算

private struct DateCalcPanel: View {
    @AppStorage("calcStart") private var startText = ""
    @AppStorage("calcEnd") private var endText = ""
    @AppStorage("calcBase") private var baseText = ""
    @AppStorage("calcYears") private var calcYears = 0
    @AppStorage("calcMonths") private var calcMonths = 0
    @AppStorage("calcDays") private var calcDays = 0
    @AppStorage("calcWorkdays") private var calcWorkdays = 10
    @AppStorage("workdayWeekend") private var weekendRaw = "1,7"
    @AppStorage("workdayHolidays") private var holidaysRaw = ""
    @AppStorage("workdayMakeup") private var makeupRaw = ""
    @AppStorage("workdayExpanded") private var showWorkdayEditor = false

    @State private var didLoad = false

    private var options: WorkdayOptions {
        WorkdayOptions(
            weekendDays: Set(weekendRaw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }),
            holidays: lineSet(holidaysRaw),
            makeupWorkdays: lineSet(makeupRaw)
        )
    }

    private func lineSet(_ text: String) -> Set<String> {
        Set(
            text.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
    }

    private var start: SolarDate { SolarDate(text: startText) ?? CalendarEngine.today() }
    private var end: SolarDate { SolarDate(text: endText) ?? CalendarEngine.today() }
    private var base: SolarDate { SolarDate(text: baseText) ?? CalendarEngine.today() }

    private var diff: DateDifference {
        CalendarEngine.difference(from: start, to: end, options: options)
    }

    private var shifted: SolarDate {
        CalendarEngine.add(base, years: calcYears, months: calcMonths, days: calcDays)
    }

    private var workdayShifted: SolarDate {
        CalendarEngine.addWorkdays(from: shifted, count: calcWorkdays, options: options)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                diffCard
                shiftCard
                workdayCard
            }
            .padding(20)
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            let today = CalendarEngine.today()
            if startText.isEmpty { startText = SolarDate(year: today.year, month: 1, day: 1).description }
            if endText.isEmpty { endText = today.description }
            if baseText.isEmpty { baseText = today.description }
        }
    }

    // MARK: 日期差

    private var diffCard: some View {
        ToolCard(title: "日期差", systemImage: "arrow.left.and.right") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    DatePicker("", selection: binding(for: $startText), displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.tertiary)
                    DatePicker("", selection: binding(for: $endText), displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)

                    Button("交换") {
                        let temp = startText
                        startText = endText
                        endText = temp
                    }
                    .controlSize(.small)

                    Spacer(minLength: 0)

                    NoticeTag(
                        text: diff.forward ? "往后" : "往前",
                        systemImage: diff.forward ? "arrow.right" : "arrow.left",
                        tint: .secondary
                    )
                }

                HStack(alignment: .top, spacing: 22) {
                    CalendarStat(title: "总天数", value: "\(diff.totalDays)", hint: "天", highlight: true)
                    CalendarStat(title: "按年月日", value: "\(diff.years) 年 \(diff.months) 月 \(diff.days) 天")
                    CalendarStat(title: "周", value: "\(diff.weeks) 周 \(diff.remainderDays) 天")
                    CalendarStat(title: "小时", value: "\(diff.totalHours)")
                    CalendarStat(title: "分钟", value: "\(diff.totalMinutes)")
                    Spacer(minLength: 0)
                }

                HStack(alignment: .top, spacing: 22) {
                    CalendarStat(title: "工作日", value: "\(diff.workdays)", hint: "区间含两端", highlight: true)
                    CalendarStat(title: "休息日", value: "\(diff.restDays)", hint: "按下方周末设置")
                    Spacer(minLength: 0)
                    CopyIconButton(
                        text: "\(start.description) → \(end.description)：相差 \(diff.totalDays) 天（\(diff.years) 年 \(diff.months) 月 \(diff.days) 天），区间内工作日 \(diff.workdays) 天",
                        help: "复制结果"
                    )
                }
            }
        }
    }

    // MARK: 日期加减

    private var shiftCard: some View {
        ToolCard(title: "日期加减", systemImage: "plusminus") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    DatePicker("", selection: binding(for: $baseText), displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)

                    numberStepper(title: "年", value: $calcYears, range: -200...200)
                    numberStepper(title: "月", value: $calcMonths, range: -1200...1200)
                    numberStepper(title: "天", value: $calcDays, range: -36500...36500)

                    Spacer(minLength: 0)
                }

                HStack(spacing: 22) {
                    CalendarStat(title: "结果", value: shifted.description, hint: shifted.weekdayName, highlight: true)
                    CalendarStat(title: "中文", value: shifted.cjk)
                    CalendarStat(
                        title: "相对今天",
                        value: shifted < CalendarEngine.today() ? "已过去" : (shifted > CalendarEngine.today() ? "还没到" : "就是今天")
                    )
                    Spacer(minLength: 0)
                }

                if calcYears == 0 && calcMonths == 0 && calcDays == 0 {
                    Text("调一下年 / 月 / 天，右边会立刻跟着变。月末加月会自动落到该月最后一天（1 月 31 日 + 1 月 = 2 月 28/29 日）。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: 工作日

    private var workdayCard: some View {
        ToolCard(title: "工作日计算", systemImage: "briefcase") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    DatePicker("", selection: binding(for: $baseText), displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)

                    numberStepper(title: "工作日", value: $calcWorkdays, range: -999...999)

                    Spacer(minLength: 0)

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { showWorkdayEditor.toggle() }
                    } label: {
                        Label(showWorkdayEditor ? "收起设置" : "周末与节假日", systemImage: "slider.horizontal.3")
                            .font(.system(size: 11.5))
                    }
                    .controlSize(.small)
                }

                HStack(spacing: 22) {
                    CalendarStat(
                        title: "第 \(calcWorkdays) 个工作日",
                        value: workdayShifted.description,
                        hint: workdayShifted.weekdayName,
                        highlight: true
                    )
                    CalendarStat(title: "中文", value: workdayShifted.cjk)
                    CalendarStat(
                        title: "含起点共",
                        value: "\(CalendarEngine.workdaysBetween(from: min(base, workdayShifted), to: max(base, workdayShifted), options: options)) 个工作日"
                    )
                    Spacer(minLength: 0)
                }

                if showWorkdayEditor {
                    Divider()
                    workdayEditor
                }
            }
        }
    }

    private var workdayEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("哪几天休息")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                ForEach(1...7, id: \.self) { day in
                    let name = CalendarEngine.weekdayName(day)
                    ChipButton(title: name, isSelected: weekendSet.contains(day)) {
                        toggleWeekend(day)
                    }
                }
                Spacer(minLength: 0)
                Button("双休") { weekendRaw = "1,7" }
                    .controlSize(.small)
                    .font(.system(size: 11))
                Button("单休（周日）") { weekendRaw = "1" }
                    .controlSize(.small)
                    .font(.system(size: 11))
            }

            HStack(alignment: .top, spacing: 12) {
                holidayEditor(
                    title: "放假日（每行一个，2026-10-01）",
                    text: $holidaysRaw,
                    hint: "这些天不算工作日"
                )
                holidayEditor(
                    title: "调休上班日",
                    text: $makeupRaw,
                    hint: "这些周末要上班"
                )
            }

            Text("法定节假日每年都会调整，就不内置了——按需要自己贴进来，格式 2026-10-01，一行一个。")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
    }

    private func holidayEditor(title: String, text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.system(size: 11, design: .monospaced))
                .frame(height: 70)
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10))
                )
            Text(hint)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weekendSet: Set<Int> {
        Set(weekendRaw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
    }

    private func toggleWeekend(_ day: Int) {
        var set = weekendSet
        if set.contains(day) { set.remove(day) } else { set.insert(day) }
        weekendRaw = set.sorted().map(String.init).joined(separator: ",")
    }

    // MARK: 小控件

    private func binding(for text: Binding<String>) -> Binding<Date> {
        Binding(
            get: { SolarDate(text: text.wrappedValue)?.date ?? Date() },
            set: { text.wrappedValue = SolarDate(date: $0).description }
        )
    }

    private func numberStepper(title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            HStack(spacing: 3) {
                TextField("", value: value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 62)
                Stepper("", value: value, in: range)
                    .labelsHidden()
                    .controlSize(.mini)
            }
        }
    }
}

// MARK: - 定时任务

private struct CronPanel: View {
    @AppStorage("cronExpression") private var expression = "0 9 * * 1-5"
    @AppStorage("cronShowLocal") private var showLocal = false
    @AppStorage("cronPeriod") private var period: CronEngine.Period = .daily
    @AppStorage("cronMinute") private var minute = 0
    @AppStorage("cronHour") private var hour = 9
    @AppStorage("cronInterval") private var interval = 15
    @AppStorage("cronWeekday") private var weekday = 1
    @AppStorage("cronDay") private var dayOfMonth = 1
    @AppStorage("cronZoneID") private var zoneID = "Asia/Shanghai"

    @State private var schedule: CronSchedule?
    @State private var parseError: String?
    @State private var runs: [Date] = []
    @State private var local: CronEngine.LocalCrontab?
    @State private var toast: String?
    @State private var didLoad = false
    @State private var fieldTexts: [String] = []

    /// 逐字段编辑器里每个字段的说明和快捷值
    private let fieldSpecs: [(name: String, range: String, shortcuts: [String])] = [
        ("分", "0-59", ["*", "*/5", "*/15"]),
        ("时", "0-23", ["*", "9", "*/2"]),
        ("日", "1-31", ["*", "L", "LW", "15W"]),
        ("月", "1-12", ["*", "*/3", "1,4,7,10"]),
        ("周", "0-7", ["*", "1-5", "5L", "3#2"]),
    ]

    private var activeZone: TimeZone {
        TimeZone(identifier: zoneID) ?? CronEngine.zone
    }

    private var zoneOptions: [(label: String, id: String)] {
        var options: [(label: String, id: String)] = [
            ("上海", "Asia/Shanghai"),
            ("UTC", "UTC"),
            ("东京", "Asia/Tokyo"),
            ("纽约", "America/New_York"),
            ("伦敦", "Europe/London"),
        ]
        // 本机时区跟列表里的重了就不重复给一颗 chip
        let local = TimeZone.current.identifier
        if !options.contains(where: { $0.id == local }) {
            options.insert(("本机", local), at: 0)
        }
        return options
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                expressionCard
                fieldsCard
                presetCard
                builderCard
                localCard
            }
            .padding(20)
        }
        .toast($toast)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            reparse()
        }
    }

    // MARK: 表达式

    private var expressionCard: some View {
        ToolCard(title: "表达式", systemImage: "text.append") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    TextField("分 时 日 月 周", text: $expression)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14, design: .monospaced))
                        .frame(maxWidth: 260)
                        .onSubmit { reparse() }

                    Button("解析") { reparse() }
                        .controlSize(.small)

                    if let schedule {
                        NoticeTag(
                            text: schedule.hasSeconds ? "6 段（带秒）" : "5 段",
                            systemImage: "number",
                            tint: .secondary
                        )
                        if let macro = schedule.macro {
                            NoticeTag(text: macro, systemImage: "at", tint: .accentColor)
                        }
                    }

                    Spacer(minLength: 0)
                }

                if let parseError {
                    ErrorBanner(message: parseError)
                } else if let schedule {
                    described(schedule)
                }

                HStack(spacing: 8) {
                    Text("时区")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .leading)
                    FlowRow(spacing: 6) {
                        ForEach(zoneOptions, id: \.id) { option in
                            ChipButton(title: option.label, isSelected: option.id == zoneID) {
                                zoneID = option.id
                                reparse()
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func described(_ schedule: CronSchedule) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(CronEngine.describe(schedule))
                    .font(.system(size: 15, weight: .medium))
                CopyIconButton(text: schedule.expression, help: "复制表达式")
                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                ForEach(Array(CronEngine.breakdown(schedule).enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 12) {
                        Text(row.field)
                            .font(.system(size: 11.5, weight: .medium))
                            .frame(width: 22, alignment: .leading)
                        Text(row.raw)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 90, alignment: .leading)
                        Text(row.expanded)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 6)
                        Text(row.range)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    if index < 5 {
                        Divider().opacity(0.3)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07))
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("接下来 6 次 · \(zoneID)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                if runs.isEmpty {
                    Text("往后 4 年都排不出下一次执行时间，检查一下日和月的组合（比如 2 月 30 日）")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.orange)
                } else {
                    FlowRow(spacing: 6) {
                        ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(format(run))
                                    .font(.system(size: 11, design: .monospaced))
                                Text(CronEngine.relativeText(run))
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                Color.primary.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: 逐字段编辑

    private var fieldsCard: some View {
        ToolCard(title: "逐字段编辑", systemImage: "tablecells") {
            if schedule?.hasSeconds == true {
                Text("带秒的表达式（6 段）用上面整行编辑，这里只支持标准 5 段。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
            } else if schedule?.macro != nil {
                Text("@宏 会展开成固定写法，想逐字段编辑就把它换成一个具体表达式。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
            } else if fieldTexts.count == 5 {
                VStack(spacing: 0) {
                    ForEach(Array(fieldSpecs.enumerated()), id: \.offset) { index, spec in
                        fieldRow(index: index, spec: spec)
                        if index < fieldSpecs.count - 1 {
                            Divider().opacity(0.3)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07))
                )

                Text("日字段的 L、LW、15W 和周字段的 5L、3#2 是 Quartz 扩展，macOS 的 launchd 不认，crontab 也别用——看目标调度器支不支持。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fieldRow(index: Int, spec: (name: String, range: String, shortcuts: [String])) -> some View {
        let diagnostics = CronEngine.fieldErrors(of: expression)
        let error = index < diagnostics.count ? diagnostics[index] : nil

        return HStack(spacing: 10) {
            Text(spec.name)
                .font(.system(size: 11.5, weight: .medium))
                .frame(width: 22, alignment: .leading)

            TextField(spec.range, text: fieldBinding(index))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 84)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(error == nil ? Color.clear : Color.red.opacity(0.55), lineWidth: 1)
                )

            Text(error ?? spec.range)
                .font(.system(size: 10.5))
                .foregroundStyle(error == nil ? Color.secondary : Color.red)
                .lineLimit(1)

            FlowRow(spacing: 5) {
                ForEach(spec.shortcuts, id: \.self) { shortcut in
                    Button {
                        updateField(index, shortcut)
                    } label: {
                        Text(shortcut)
                            .font(.system(size: 10.5, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("填入 \(shortcut)")
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func fieldBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { index < fieldTexts.count ? fieldTexts[index] : "" },
            set: { updateField(index, $0) }
        )
    }

    private func updateField(_ index: Int, _ value: String) {
        guard fieldTexts.count == 5 else { return }
        var fields = fieldTexts
        fields[index] = value
        fieldTexts = fields
        expression = fields.joined(separator: " ")
        reparse()
    }

    // MARK: 模板

    private var presetCard: some View {
        ToolCard(title: "常用模板", systemImage: "square.grid.3x3") {
            VStack(alignment: .leading, spacing: 10) {
                FlowRow(spacing: 6) {
                    ForEach(CronPreset.all) { preset in
                        Button {
                            expression = preset.expression
                            reparse()
                        } label: {
                            Text(preset.title)
                                .font(.system(size: 11.5))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    preset.expression == expression
                                        ? Color.accentColor
                                        : Color.primary.opacity(0.06),
                                    in: Capsule()
                                )
                                .foregroundStyle(preset.expression == expression ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .help("\(preset.expression) · \(preset.note)")
                    }
                }
            }
        }
    }

    // MARK: 反向生成

    private var builderCard: some View {
        ToolCard(title: "按周期生成", systemImage: "hammer") {
            VStack(alignment: .leading, spacing: 12) {
                FlowRow(spacing: 6) {
                    ForEach(CronEngine.Period.allCases) { item in
                        ChipButton(title: item.title, isSelected: item.id == period.id) {
                            period = item
                        }
                    }
                }

                HStack(spacing: 14) {
                    if period == .everyNMinutes {
                        numberField(title: "每几分钟", value: $interval, range: 1...59)
                    } else {
                        numberField(title: "分", value: $minute, range: 0...59)
                        if period != .hourly {
                            numberField(title: "时", value: $hour, range: 0...23)
                        }
                    }
                    if period == .weekly {
                        weekdayMenu
                    }
                    if period == .monthly {
                        numberField(title: "日", value: $dayOfMonth, range: 1...31)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    Text(builtExpression)
                        .font(.system(size: 14, design: .monospaced))
                        .textSelection(.enabled)
                    Button("用这个") {
                        expression = builtExpression
                        reparse()
                    }
                    .controlSize(.small)
                    CopyIconButton(text: builtExpression)
                    Spacer(minLength: 0)
                    if let built = try? CronEngine.parse(builtExpression) {
                        Text(CronEngine.describe(built))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var builtExpression: String {
        CronEngine.build(
            period: period,
            minute: minute,
            hour: hour,
            interval: interval,
            weekday: weekday,
            dayOfMonth: dayOfMonth
        )
    }

    private var weekdayMenu: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("周几")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Menu(CronEngine.weekdayName(weekday)) {
                ForEach(0...6, id: \.self) { value in
                    Button(CronEngine.weekdayName(value)) { weekday = value }
                }
            }
            .frame(width: 80)
            .controlSize(.small)
        }
    }

    private func numberField(title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            HStack(spacing: 3) {
                TextField("", value: value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 52)
                Stepper("", value: value, in: range)
                    .labelsHidden()
                    .controlSize(.mini)
            }
        }
    }

    // MARK: 本机 crontab

    private var localCard: some View {
        ToolCard(title: "本机 crontab", systemImage: "terminal") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { showLocal.toggle() }
                    } label: {
                        Label(showLocal ? "收起" : "查看", systemImage: showLocal ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11.5))
                    }
                    .controlSize(.small)

                    Button {
                        local = CronEngine.localCrontab()
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise").font(.system(size: 11.5))
                    }
                    .controlSize(.small)

                    Spacer(minLength: 0)

                    Text("只读，不会改你的 crontab")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                if showLocal {
                    if let local {
                        if let error = local.error {
                            Text(error)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        } else if local.entries.isEmpty {
                            Text("没有任何定时任务")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.tertiary)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(local.entries.enumerated()), id: \.offset) { index, entry in
                                    localRow(entry)
                                    if index < local.entries.count - 1 {
                                        Divider().opacity(0.3)
                                    }
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color.primary.opacity(0.03))
                            )
                        }
                    } else {
                        Text("点「查看」读一下当前用户的 crontab")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .onChange(of: showLocal) { _, isOpen in
            if isOpen, local == nil { local = CronEngine.localCrontab() }
        }
    }

    private func localRow(_ entry: CronEngine.LocalCronEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Text(entry.expression)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                if let parsed = try? CronEngine.parse(entry.expression) {
                    Text(CronEngine.describe(parsed))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    NoticeTag(text: "解析不了", systemImage: "questionmark", tint: .orange)
                }
                Spacer(minLength: 0)
                CopyIconButton(text: entry.raw, help: "复制整行")
            }
            Text(entry.command)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: 动作

    private func reparse() {
        do {
            let parsed = try CronEngine.parse(expression)
            schedule = parsed
            parseError = nil
            runs = CronEngine.nextRuns(parsed, after: Date(), count: 6, timeZone: activeZone)
            // 5 段且没有宏的表达式拆给逐字段编辑器
            if !parsed.hasSeconds, parsed.macro == nil {
                let parts = expression.split(separator: " ").map(String.init)
                if parts.count == 5, parts != fieldTexts {
                    fieldTexts = parts
                }
            }
        } catch {
            schedule = nil
            parseError = error.localizedDescription
            runs = []
        }
    }

    private func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = activeZone
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
