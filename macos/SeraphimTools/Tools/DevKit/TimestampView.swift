import AppKit
import SwiftUI

/// 时间戳 ⇄ 日期。输入框什么都吃：纯数字当时间戳，日期文本也能反着算。
struct TimestampView: View {
    @AppStorage("tsUnit") private var unit: TimestampUnit = .auto
    @AppStorage("tsZone") private var zoneID: String = TimeZone.current.identifier

    @State private var input = ""
    @State private var isLive = true
    @State private var frozen = Date()

    @State private var spanStart = ""
    @State private var spanEnd = ""

    @State private var toast: String?

    private var timeZone: TimeZone { TimeZone(identifier: zoneID) ?? .current }

    private var zoneOptions: [String] {
        var list = TimestampEngine.commonTimeZones
        if !list.contains(zoneID) { list.insert(zoneID, at: 0) }
        return list
    }

    private var parsed: TimestampEngine.ParsedInput? {
        TimestampEngine.parse(input, unit: unit, timeZone: timeZone)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                clockCard
                inputCard
                if let parsed {
                    resultCard(for: parsed, title: "结果")
                } else {
                    // 没输入的时候别留白：直接把"此刻"的全套表示摆出来，打开就能用
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        resultCard(
                            for: TimestampEngine.ParsedInput(
                                date: context.date,
                                kind: .timestamp(.seconds),
                                detail: "当前时刻"
                            ),
                            title: "当前时刻"
                        )
                    }
                }
                timeZoneCard
                spanCard
            }
            .padding(20)
        }
        .toast($toast)
    }

    // MARK: - 当前时间

    private var clockCard: some View {
        ToolCard(title: "当前时间", systemImage: "clock") {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let date = isLive ? context.date : frozen
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(TimestampEngine.format(date, pattern: "HH:mm:ss", timeZone: timeZone))
                            .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                        Text(TimestampEngine.formatLocalized(date, pattern: "yyyy年M月d日 EEEE", timeZone: timeZone))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if !isLive {
                            NoticeTag(text: "已暂停", systemImage: "pause.fill", tint: .orange)
                        }
                    }

                    HStack(spacing: 10) {
                        stampPill(title: "秒", value: String(Int(date.timeIntervalSince1970)))
                        stampPill(title: "毫秒", value: String(Int(date.timeIntervalSince1970 * 1000)))
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 8) {
                        Button {
                            isLive.toggle()
                            if !isLive { frozen = Date() }
                        } label: {
                            Label(isLive ? "暂停" : "继续", systemImage: isLive ? "pause" : "play")
                        }
                        .controlSize(.small)

                        Button {
                            frozen = Date()
                            isLive = false
                        } label: {
                            Label("定格", systemImage: "camera")
                        }
                        .controlSize(.small)
                        .help("锁住当前这一刻，方便慢慢看")

                        Button {
                            let now = isLive ? Date() : frozen
                            input = String(Int(now.timeIntervalSince1970))
                        } label: {
                            Label("填入输入框", systemImage: "arrow.down.doc")
                        }
                        .controlSize(.small)

                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func stampPill(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .textSelection(.enabled)
            CopyIconButton(text: value)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    // MARK: - 输入

    private var inputCard: some View {
        ToolCard(title: "转换", systemImage: "arrow.left.arrow.right") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("时间戳（10/13/16/19 位）或日期文本，比如 2026-10-14 13:08:42", text: $input)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                    if !input.isEmpty {
                        Button {
                            input = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.borderless)
                    }
                    Button {
                        if let string = NSPasteboard.general.string(forType: .string) {
                            input = string.trimmingCharacters(in: .whitespacesAndNewlines)
                        } else {
                            toast = "剪贴板里没有文本"
                            NSSound.beep()
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderless)
                    .help("粘贴")

                    Button {
                        input = String(Int(Date().timeIntervalSince1970))
                    } label: {
                        Text("现在")
                            .font(.system(size: 11.5))
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12))
                )

                HStack(spacing: 14) {
                    Text("时间戳单位")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("单位", selection: $unit) {
                        ForEach(TimestampUnit.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 320)

                    Text(unit.digitHint)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 14) {
                    Text("时区")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("时区", selection: $zoneID) {
                        ForEach(zoneOptions, id: \.self) { identifier in
                            Text("\(TimestampEngine.timeZoneTitle(identifier))　\(identifier)").tag(identifier)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320)

                    Text(TimestampEngine.offsetText(date: parsed?.date ?? Date(), timeZone: timeZone))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }

                if let parsed {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        Text(parsed.detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                } else if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ErrorBanner(message: "这段内容既不像时间戳，也不像认识的日期格式。试试 1760418522 或者 2026-10-14 13:08:42。")
                }
            }
        }
    }

    // MARK: - 结果

    private func resultCard(for parsed: TimestampEngine.ParsedInput, title: String) -> some View {
        ToolCard(title: title, systemImage: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(TimestampEngine.describe(parsed.date, timeZone: timeZone).enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().padding(.vertical, 2) }
                    displayRow(item)
                }
            }
        }
    }

    private func displayRow(_ item: TimestampDisplay) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(item.highlight ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    if let hint = item.hint {
                        Text(hint)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(item.value)
                    .font(.system(size: 12.5, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            CopyIconButton(text: item.value)
        }
        .padding(.vertical, 7)
    }

    // MARK: - 时区对照

    private var timeZoneCard: some View {
        ToolCard(title: "时区对照", systemImage: "globe") {
            let date = parsed?.date ?? (isLive ? Date() : frozen)
            let lines = TimestampEngine.timeZoneLines(for: date, base: timeZone)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: 10)], spacing: 10) {
                ForEach(lines) { line in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Text(line.city)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            if line.dayShift != 0 {
                                Text(line.dayShift > 0 ? "+1天" : "-1天")
                                    .font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.16), in: Capsule())
                                    .foregroundStyle(.orange)
                            }
                            Spacer(minLength: 0)
                            Text(line.offset)
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        Text(line.time)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.045))
                    )
                }
            }
        }
    }

    // MARK: - 时间差

    private var spanCard: some View {
        ToolCard(title: "时间差 / 倒计时", systemImage: "hourglass") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    spanField(title: "起点", text: $spanStart)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.tertiary)
                    spanField(title: "终点", text: $spanEnd)
                }

                HStack(spacing: 8) {
                    Button("现在作为起点") {
                        spanStart = String(Int(Date().timeIntervalSince1970))
                    }
                    .controlSize(.small)
                    Button("现在作为终点") {
                        spanEnd = String(Int(Date().timeIntervalSince1970))
                    }
                    .controlSize(.small)
                    Button("交换") {
                        swap(&spanStart, &spanEnd)
                    }
                    .controlSize(.small)
                    Spacer(minLength: 0)
                }

                if let start = TimestampEngine.parse(spanStart, unit: .auto, timeZone: timeZone),
                   let end = TimestampEngine.parse(spanEnd, unit: .auto, timeZone: timeZone) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(TimestampEngine.durationText(from: start.date, to: end.date))
                            .font(.system(size: 14, weight: .semibold))

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                            ForEach(TimestampEngine.durationBreakdown(from: start.date, to: end.date)) { item in
                                HStack {
                                    Text(item.title)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                    Spacer(minLength: 6)
                                    Text(item.value)
                                        .font(.system(size: 12, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.primary.opacity(0.045))
                                )
                            }
                        }
                    }
                } else if !spanStart.isEmpty || !spanEnd.isEmpty {
                    Text("两头都填上才能算差值。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("各填一个时间戳或日期，用来算耗时、算倒计时。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func spanField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            TextField("时间戳或日期", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
        }
    }
}
