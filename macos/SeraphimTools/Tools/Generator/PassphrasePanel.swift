import SwiftUI

/// 记忆密码：给生活用的密码。
///
/// 生成的不是 `aK9#mQ2x` 这种随机串，而是「火锅-雨伞-柠檬-吉他」这样的短语——
/// 好记到不用抄在便签上，强度又按真实攻击成本算给你看。
struct PassphrasePanel: View {
    enum Mode: String, CaseIterable, Identifiable {
        case phrase
        case pin

        var id: String { rawValue }

        var title: String {
            switch self {
            case .phrase: return "短语密码"
            case .pin: return "纯数字"
            }
        }

        var systemImage: String {
            switch self {
            case .phrase: return "text.bubble"
            case .pin: return "number.square"
            }
        }
    }

    @AppStorage("passMode") private var mode: Mode = .phrase

    var body: some View {
        VStack(spacing: 0) {
            Picker("密码类型", selection: $mode) {
                ForEach(Mode.allCases) { item in
                    Label(item.title, systemImage: item.systemImage).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            switch mode {
            case .phrase:
                PhraseSection()
            case .pin:
                PINSection()
            }
        }
    }
}

// MARK: - 等级配色

extension PassphraseLevel {
    var tint: Color {
        switch self {
        case .weak: return .red
        case .thin: return .orange
        case .fair: return .yellow
        case .strong: return .green
        case .excellent: return .teal
        }
    }
}

// MARK: - 短语密码

private struct PhraseSection: View {
    @AppStorage("passWordlist") private var wordlist: PassphraseWordlist = .chinese
    @AppStorage("passWordCount") private var wordCount = 7
    @AppStorage("passSeparator") private var separator: PassphraseSeparator = .dash
    @AppStorage("passCapitalize") private var capitalize = false
    @AppStorage("passDigits") private var tailDigits = false
    @AppStorage("passSymbol") private var tailSymbol = false

    @State private var result: PassphraseResult?
    @State private var toast: String?
    @State private var didAutoRun = false

    private var options: PassphraseOptions {
        PassphraseOptions(
            wordlist: wordlist,
            wordCount: wordCount,
            separator: separator,
            capitalize: capitalize,
            tailDigits: tailDigits,
            tailSymbol: tailSymbol
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                wordlistCard
                resultCard
                if result != nil { strengthCard }
            }
            .padding(20)
        }
        .toast($toast)
        .onAppear {
            guard !didAutoRun else { return }
            didAutoRun = true
            regenerate()
        }
        .onChange(of: options) { _, _ in
            regenerate()
        }
    }

    // MARK: 词表与选项

    private var wordlistCard: some View {
        ToolCard(title: "怎么攒这个密码", systemImage: "book.closed") {
            VStack(alignment: .leading, spacing: 13) {
                FlowRow(spacing: 6) {
                    ForEach(PassphraseWordlist.allCases) { item in
                        ChipButton(title: "\(item.title) \(item.count)",
                                   isSelected: item.id == wordlist.id) {
                            wordlist = item
                        }
                    }
                }

                Text(wordlist.note)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Text("词数")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Stepper(value: $wordCount, in: PassphraseOptions.wordRange) {
                        Text("\(wordCount)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .frame(width: 22, alignment: .leading)
                    }
                    .controlSize(.small)

                    Text("每个词 \(String(format: "%.1f", wordlist.bitsPerWord)) bit，"
                         + "这个词数就是这个密码的底子")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 12) {
                    Text("分隔符")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    FlowRow(spacing: 6) {
                        ForEach(PassphraseSeparator.allCases) { item in
                            ChipButton(title: item.title, isSelected: item.id == separator.id) {
                                separator = item
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 18) {
                    Toggle("首字母大写", isOn: $capitalize)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11.5))
                    Toggle("末尾加两位数字", isOn: $tailDigits)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11.5))
                    Toggle("末尾加一个符号", isOn: $tailSymbol)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11.5))
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: 结果

    private var resultCard: some View {
        ToolCard(title: "这个密码", systemImage: "key.horizontal") {
            VStack(alignment: .leading, spacing: 12) {
                if let result {
                    HStack(alignment: .top, spacing: 10) {
                        Text(result.text)
                            .font(.system(size: 17, weight: .medium, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(4)
                        Spacer(minLength: 0)
                        CopyIconButton(text: result.text)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.18))
                    )

                    if let pinyin = result.pinyin {
                        HStack(spacing: 8) {
                            Text("拼音读法")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            Text(pinyin)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                            CopyIconButton(text: pinyin)
                        }
                        Text("中文密码不少网站不收，用这行拼音哪儿都能填，念出来还是那几个词。")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 16) {
                        metaTile("词数", "\(result.wordCount)")
                        metaTile("长度", "\(result.length) 字符")
                        metaTile("底子", String(format: "%.1f bit", result.bits))
                        if !result.isASCII {
                            NoticeTag(text: "含中文", systemImage: "character.book.closed",
                                      tint: .orange)
                        }
                        Spacer(minLength: 0)
                        Button {
                            regenerate()
                        } label: {
                            Label("换一个", systemImage: "arrow.clockwise")
                                .font(.system(size: 12))
                        }
                        .controlSize(.small)
                    }
                } else {
                    Text("正在准备…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: 强度

    private var strengthCard: some View {
        ToolCard(title: "能扛住多久", systemImage: "gauge.with.dots.needle.67percent") {
            VStack(alignment: .leading, spacing: 13) {
                if let result {
                    HStack(spacing: 12) {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.08))
                                Capsule()
                                    .fill(result.level.tint.gradient)
                                    .frame(width: max(6, geometry.size.width * barRatio(result.bits)))
                            }
                        }
                        .frame(height: 8)

                        Text("\(result.level.title) · \(String(format: "%.1f", result.bits)) bit")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(result.level.tint)
                            .fixedSize()
                    }

                    Text(result.level.advice)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 0) {
                        ForEach(result.crackTimes) { estimate in
                            crackRow(estimate)
                            if estimate.id != result.crackTimes.last?.id {
                                Divider().opacity(0.3)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.025))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07))
                    )

                    if tailDigits || tailSymbol {
                        NoticeTag(
                            text: "末尾那几位数字符号确实加了强度，但「末尾追加」是破解工具会优先照试的套路，真正撑场面的是词本身",
                            systemImage: "exclamationmark.triangle",
                            tint: .orange
                        )
                    }

                    Text("按「平均要试一半的可能」估算。词是从表里随机取的，别自己换词——你换的词往往比随机更可猜。")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func crackRow(_ estimate: PassphraseCrackEstimate) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(estimate.safe ? Color.green : Color.red)
                .frame(width: 7, height: 7)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(estimate.scenario)
                    .font(.system(size: 11.5, weight: .medium))
                Text(estimate.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(estimate.duration)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(estimate.safe ? Color.green : Color.red)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// 强度条按 120 bit 铺满——再往上都是「很久」和「更久」的区别了
    private func barRatio(_ bits: Double) -> Double {
        min(1, max(0, bits / 120))
    }

    private func metaTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
        }
    }

    private func regenerate() {
        result = PassphraseEngine.generate(options)
    }
}

// MARK: - 纯数字密码

private struct PINSection: View {
    @AppStorage("passPinLength") private var length = PINEngine.defaultLength
    @AppStorage("passPinCount") private var count = 5

    @State private var pins: [String] = []
    @State private var toast: String?
    @State private var didAutoRun = false

    private let counts = [1, 5, 10]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                generateCard
                guidanceCard
            }
            .padding(20)
        }
        .toast($toast)
        .onAppear {
            guard !didAutoRun else { return }
            didAutoRun = true
            regenerate()
        }
        .onChange(of: length) { _, _ in regenerate() }
        .onChange(of: count) { _, _ in regenerate() }
    }

    private var generateCard: some View {
        ToolCard(title: "生成", systemImage: "number.square") {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 12) {
                    Text("位数")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    FlowRow(spacing: 6) {
                        ForEach(PINEngine.lengthChoices, id: \.self) { item in
                            ChipButton(title: "\(item)", isSelected: item == length) {
                                length = item
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 12) {
                    Text("数量")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    FlowRow(spacing: 6) {
                        ForEach(counts, id: \.self) { item in
                            ChipButton(title: "\(item)", isSelected: item == count) {
                                count = item
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    Button {
                        regenerate()
                    } label: {
                        Label("再来一批", systemImage: "arrow.clockwise").font(.system(size: 12))
                    }
                    .controlSize(.small)

                    Button {
                        copyAll()
                    } label: {
                        Label("复制全部", systemImage: "doc.on.doc").font(.system(size: 12))
                    }
                    .controlSize(.small)
                    .disabled(pins.isEmpty)

                    Spacer(minLength: 0)

                    Text("已避开全同、连号、重复段这些一眼能猜到的组合")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                if pins.isEmpty {
                    Text("还没有生成内容")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 18)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(pins.enumerated()), id: \.offset) { index, pin in
                            HStack(spacing: 12) {
                                Text(PINEngine.grouped(pin))
                                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                                    .textSelection(.enabled)
                                Spacer(minLength: 8)
                                CopyIconButton(text: pin)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            if index < pins.count - 1 {
                                Divider().opacity(0.35)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.025))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07))
                    )
                }
            }
        }
    }

    private var guidanceCard: some View {
        ToolCard(title: "这种密码能用在哪儿", systemImage: "questionmark.circle") {
            VStack(alignment: .leading, spacing: 12) {
                pinCase(
                    icon: "lock.shield.fill",
                    tint: .green,
                    title: "有次数限制的地方：银行卡、手机锁屏、门禁",
                    body: "\(length) 位数字一共 \(groupedCount) 种可能，但只有 3 次机会，"
                        + "猜中的概率 \(chanceText)。真正拦住人的是那个次数限制，不是密码本身。"
                )

                pinCase(
                    icon: "exclamationmark.triangle.fill",
                    tint: .red,
                    title: "没有次数限制的地方：行李箱、Wi-Fi、网站密码",
                    body: "这里没人替你数次数，纯数字基本挡不住——12 位在 GPU 面前也就十几秒。"
                        + "这种地方请切回上面的短语密码。"
                )

                HStack(spacing: 16) {
                    meta("位数", "\(length)")
                    meta("空间", groupedCount)
                    meta("强度", String(format: "%.1f bit", PINEngine.bits(length: length)))
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func pinCase(icon: String, tint: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                Text(body)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func meta(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
        }
    }

    private var groupedCount: String {
        let total = pow(10.0, Double(length))
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return (formatter.string(from: NSNumber(value: total)) ?? "\(Int(total))") + " 种"
    }

    private var chanceText: String {
        let chance = PINEngine.lockoutHitChance(length: length)
        if chance >= 0.001 {
            return String(format: "%.2f%%", chance * 100)
        }
        return String(format: "%.4f%%", chance * 100)
    }

    private func regenerate() {
        pins = PINEngine.generate(length: length, count: count)
    }

    private func copyAll() {
        guard !pins.isEmpty else { return }
        NSPasteboard.copyString(pins.joined(separator: "\n"))
        toast = "已复制 \(pins.count) 条"
    }
}
