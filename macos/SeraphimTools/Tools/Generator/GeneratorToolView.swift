import SwiftUI

/// 生成器：测试数据 + 短 ID + 雪花 ID + UUID + 记忆密码。
struct GeneratorToolView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case faker
        case identifier
        case uuid
        case passphrase

        var id: String { rawValue }

        var title: String {
            switch self {
            case .faker: return "测试数据"
            case .identifier: return "ID 生成"
            case .uuid: return "UUID"
            case .passphrase: return "记忆密码"
            }
        }

        var systemImage: String {
            switch self {
            case .faker: return "person.text.rectangle"
            case .identifier: return "number"
            case .uuid: return "circle.hexagongrid"
            case .passphrase: return "brain.head.profile"
            }
        }
    }

    @AppStorage("genMode") private var mode: Mode = .faker

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
            case .faker:
                FakerPanel()
            case .identifier:
                IdentifierPanel()
            case .uuid:
                UUIDPanel()
            case .passphrase:
                PassphrasePanel()
            }
        }
    }
}

// MARK: - 测试数据

private struct FakerPanel: View {
    @AppStorage("fakerKind") private var kind: FakerKind = .idCard
    @AppStorage("fakerCount") private var count = 10
    @AppStorage("fakerGender") private var gender: FakerGender = .any
    @AppStorage("fakerCarrier") private var carrier: PhoneCarrier = .any

    @State private var items: [FakerItem] = []
    @State private var toast: String?
    @State private var checkText = ""
    @State private var checkResult: Bool?
    @State private var didAutoRun = false

    private let counts = [1, 5, 10, 20, 50]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                controlCard
                if kind == .idCard { validatorCard }
                resultCard
            }
            .padding(20)
        }
        .toast($toast)
        .onAppear {
            guard !didAutoRun else { return }
            didAutoRun = true
            generate()
        }
    }

    // MARK: 控制

    private var controlCard: some View {
        ToolCard(title: "生成", systemImage: "wand.and.stars") {
            VStack(alignment: .leading, spacing: 14) {
                FlowRow(spacing: 6) {
                    ForEach(FakerKind.allCases) { item in
                        ChipButton(title: item.title, isSelected: item.id == kind.id) {
                            kind = item
                            generate()
                        }
                    }
                }

                HStack(spacing: 12) {
                    Text("数量")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    FlowRow(spacing: 6) {
                        ForEach(counts, id: \.self) { value in
                            ChipButton(title: "\(value)", isSelected: value == count) {
                                count = value
                                generate()
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }

                if kind == .idCard || kind == .englishName || kind == .email {
                    optionRow(title: "性别") {
                        FlowRow(spacing: 6) {
                            ForEach(FakerGender.allCases) { item in
                                ChipButton(title: item.title, isSelected: item.id == gender.id) {
                                    gender = item
                                    generate()
                                }
                            }
                        }
                    }
                }

                if kind == .phone {
                    optionRow(title: "运营商") {
                        FlowRow(spacing: 6) {
                            ForEach(PhoneCarrier.allCases) { item in
                                ChipButton(title: item.title, isSelected: item.id == carrier.id) {
                                    carrier = item
                                    generate()
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        generate()
                    } label: {
                        Label("换一批", systemImage: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .controlSize(.small)

                    Button {
                        copyAll()
                    } label: {
                        Label("复制全部", systemImage: "doc.on.doc")
                            .font(.system(size: 12))
                    }
                    .controlSize(.small)
                    .disabled(items.isEmpty)

                    Spacer(minLength: 0)

                    Text(kind.note)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func optionRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    // MARK: 身份证校验

    private var validatorCard: some View {
        ToolCard(title: "校验身份证号", systemImage: "checkmark.shield") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    TextField("粘贴一个 18 位身份证号", text: $checkText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5, design: .monospaced))
                        .frame(maxWidth: 300)
                        .onSubmit { runCheck() }

                    Button("校验") { runCheck() }
                        .controlSize(.small)

                    if let checkResult {
                        NoticeTag(
                            text: checkResult ? "校验位正确" : "校验失败",
                            systemImage: checkResult ? "checkmark.seal.fill" : "xmark.seal.fill",
                            tint: checkResult ? .green : .red
                        )
                    }
                    Spacer(minLength: 0)
                }

                Text("按 GB 11643-1999 的模 11-2 算法校验最后一位，同时检查出生日期是否真实存在。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func runCheck() {
        let text = checkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            checkResult = nil
            return
        }
        checkResult = FakerEngine.validateIDCard(text)
    }

    // MARK: 结果

    private var resultCard: some View {
        ToolCard(title: "结果", systemImage: "list.bullet") {
            if items.isEmpty {
                Text("还没有生成内容")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        itemRow(item)
                        if index < items.count - 1 {
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

    private func itemRow(_ item: FakerItem) -> some View {
        HStack(spacing: 12) {
            Text(item.value)
                .font(.system(size: 12.5, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            if !item.detail.isEmpty {
                Text(item.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            CopyIconButton(text: item.value)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    // MARK: 动作

    private func generate() {
        items = FakerEngine.generate(kind: kind, count: count, gender: gender, carrier: carrier)
    }

    private func copyAll() {
        guard !items.isEmpty else { return }
        NSPasteboard.copyString(items.map(\.value).joined(separator: "\n"))
        toast = "已复制 \(items.count) 条"
    }
}

// MARK: - 短 ID 与雪花 ID

private struct IdentifierPanel: View {
    @AppStorage("shortIDStyle") private var style: ShortIDStyle = .uuidBase62
    @AppStorage("shortIDLength") private var length = 12
    @AppStorage("shortIDCount") private var count = 8

    @State private var shortIDs: [String] = []

    @AppStorage("snowMachineBits") private var machineBits = 10
    @AppStorage("snowSequenceBits") private var sequenceBits = 12
    @AppStorage("snowMachineID") private var machineID = 1
    @AppStorage("snowEpoch") private var epochText = "1288834974657"
    @AppStorage("snowPreset") private var preset = "twitter"

    @State private var snowIDs: [Int64] = []
    @State private var generator = SnowflakeGenerator(config: .twitter)
    @State private var decodeText = ""
    @State private var decoded: SnowflakeDecoded?
    @State private var decodeError: String?
    @State private var didAutoRun = false

    private let counts = [1, 5, 10, 20, 50]

    private var config: SnowflakeConfig {
        SnowflakeConfig(
            epochMilliseconds: Int64(epochText.trimmingCharacters(in: .whitespaces)) ?? SnowflakeConfig.twitter.epochMilliseconds,
            machineBits: max(1, min(22, machineBits)),
            sequenceBits: max(1, min(22, sequenceBits)),
            machineID: Int64(max(0, machineID))
        )
    }

    private var configValid: Bool { machineBits + sequenceBits <= 63 }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                shortIDCard
                snowflakeCard
                decodeCard
            }
            .padding(20)
        }
        .onAppear {
            guard !didAutoRun else { return }
            didAutoRun = true
            makeShortIDs()
            makeSnowflakeIDs()
        }
    }

    // MARK: 短 ID

    private var shortIDCard: some View {
        ToolCard(title: "短 ID", systemImage: "number.square") {
            VStack(alignment: .leading, spacing: 12) {
                FlowRow(spacing: 6) {
                    ForEach(ShortIDStyle.allCases) { item in
                        ChipButton(title: item.title, isSelected: item.id == style.id) {
                            style = item
                            length = item.defaultLength
                            makeShortIDs()
                        }
                    }
                }

                HStack(spacing: 14) {
                    if style.fixedLength == nil {
                        HStack(spacing: 8) {
                            Text("长度")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                            Stepper(value: $length, in: style.lengthRange) {
                                Text("\(length)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 30, alignment: .leading)
                            }
                            .controlSize(.small)
                            .onChange(of: length) { _, _ in makeShortIDs() }
                        }
                    } else {
                        Text("长度固定 \(style.defaultLength)")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Text("数量")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        FlowRow(spacing: 6) {
                            ForEach(counts, id: \.self) { value in
                                ChipButton(title: "\(value)", isSelected: value == count) {
                                    count = value
                                    makeShortIDs()
                                }
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    Button {
                        makeShortIDs()
                    } label: {
                        Label("生成", systemImage: "arrow.clockwise").font(.system(size: 12))
                    }
                    .controlSize(.small)

                    Button {
                        copyShortIDs()
                    } label: {
                        Label("复制全部", systemImage: "doc.on.doc").font(.system(size: 12))
                    }
                    .controlSize(.small)
                    .disabled(shortIDs.isEmpty)

                    Spacer(minLength: 0)

                    Text(style.note)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                valueList(shortIDs.map { ($0, "") }) { text in
                    NSPasteboard.copyString(text)
                }
            }
        }
    }

    private func makeShortIDs() {
        shortIDs = IdEngine.shortIDs(style: style, length: length, count: count)
    }

    private func copyShortIDs() {
        guard !shortIDs.isEmpty else { return }
        NSPasteboard.copyString(shortIDs.joined(separator: "\n"))
    }

    // MARK: 雪花生成

    private var snowflakeCard: some View {
        ToolCard(title: "Snowflake ID 生成", systemImage: "snowflake") {
            VStack(alignment: .leading, spacing: 12) {
                FlowRow(spacing: 6) {
                    ForEach(presets, id: \.key) { item in
                        ChipButton(title: item.title, isSelected: preset == item.key) {
                            applyPreset(item)
                        }
                    }
                }

                HStack(spacing: 18) {
                    numberField(title: "机器位", value: $machineBits, range: 1...22)
                    numberField(title: "序列位", value: $sequenceBits, range: 1...22)
                    numberField(title: "机器号", value: $machineID, range: 0...Int(max(0, config.maxMachine)))
                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    Text("纪元（毫秒）")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    TextField("", text: $epochText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 170)
                        .onSubmit { applyConfig() }
                    Text(IdEngine.formatDateTime(config.epochDate))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }

                configSummary

                HStack(spacing: 10) {
                    Button {
                        makeSnowflakeIDs()
                    } label: {
                        Label("生成", systemImage: "arrow.clockwise").font(.system(size: 12))
                    }
                    .controlSize(.small)
                    .disabled(!configValid)

                    Button {
                        copySnowflakeIDs()
                    } label: {
                        Label("复制全部", systemImage: "doc.on.doc").font(.system(size: 12))
                    }
                    .controlSize(.small)
                    .disabled(snowIDs.isEmpty)

                    Spacer(minLength: 0)
                }

                valueList(snowIDs.map { ("\($0)", "") }) { text in NSPasteboard.copyString(text) }
            }
        }
    }

    private var presets: [(key: String, title: String, config: SnowflakeConfig)] {
        [
            ("twitter", "Twitter", .twitter),
            ("discord", "Discord", .discord),
            ("baidu", "百度 uid", .baidu),
            ("unix", "Unix 纪元", .unixEpoch),
        ]
    }

    private func applyPreset(_ item: (key: String, title: String, config: SnowflakeConfig)) {
        preset = item.key
        machineBits = Int(item.config.machineBits)
        sequenceBits = Int(item.config.sequenceBits)
        machineID = Int(item.config.machineID)
        epochText = "\(item.config.epochMilliseconds)"
        applyConfig()
    }

    private func applyConfig() {
        generator.update(config: config)
    }

    private var configSummary: some View {
        HStack(spacing: 14) {
            summaryItem("时间位", "\(config.timeBits)")
            summaryItem("每毫秒", "\(config.idsPerMillisecond) 个")
            summaryItem("可用", String(format: "%.0f 年", config.lifespanYears))
            if !configValid {
                NoticeTag(text: "机器位 + 序列位不能超过 63", systemImage: "exclamationmark.triangle", tint: .orange)
            }
            Spacer(minLength: 0)
        }
    }

    private func summaryItem(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
    }

    private func numberField(title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                TextField("", value: value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 54)
                Stepper("", value: value, in: range)
                    .labelsHidden()
                    .controlSize(.mini)
            }
        }
    }

    private func makeSnowflakeIDs() {
        guard configValid else { return }
        generator.update(config: config)
        var result: [Int64] = []
        result.reserveCapacity(count)
        for _ in 0..<count {
            result.append(generator.next())
        }
        snowIDs = result
    }

    private func copySnowflakeIDs() {
        guard !snowIDs.isEmpty else { return }
        NSPasteboard.copyString(snowIDs.map { "\($0)" }.joined(separator: "\n"))
    }

    // MARK: 雪花解析

    private var decodeCard: some View {
        ToolCard(title: "Snowflake ID 解析", systemImage: "magnifyingglass") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TextField("粘贴一个雪花 ID（纯数字）", text: $decodeText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5, design: .monospaced))
                        .frame(maxWidth: 320)
                        .onSubmit { runDecode() }

                    Button("解析") { runDecode() }
                        .controlSize(.small)

                    Button {
                        if let first = snowIDs.first {
                            decodeText = "\(first)"
                            runDecode()
                        }
                    } label: {
                        Text("用上面第一个").font(.system(size: 11.5))
                    }
                    .controlSize(.small)
                    .disabled(snowIDs.isEmpty)

                    Spacer(minLength: 0)
                }

                if let decodeError {
                    ErrorBanner(message: decodeError)
                }

                if let decoded {
                    decodeResult(decoded)
                } else if decodeError == nil {
                    Text("解析用上面那套位宽配置，换成别的平台产生的 ID 时记得先调配置。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func decodeResult(_ decoded: SnowflakeDecoded) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 2) {
                ForEach(decoded.segments) { segment in
                    segmentBar(segment, total: 63)
                }
            }
            .frame(height: 6)

            Text(decoded.binary)
                .font(.system(size: 8.5, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                ForEach(decoded.segments) { segment in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(segmentColor(segment.id))
                            .frame(width: 8, height: 8)
                        Text(segment.title)
                            .font(.system(size: 11.5))
                            .frame(width: 96, alignment: .leading)
                        Text(segment.bits.isEmpty ? "—" : segment.bits)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 6)
                        Text(segment.meaning)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.035))
                    )
                }
            }

            HStack(spacing: 14) {
                summaryItem("生成时间", IdEngine.formatDateTime(decoded.date))
                summaryItem("原始时间戳", "\(decoded.timestampMilliseconds) ms")
                Spacer(minLength: 0)
                CopyIconButton(text: "\(decoded.raw)")
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(IdEngine.sanityCheck(decoded), id: \.self) { note in
                    Text("· \(note)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func segmentBar(_ segment: SnowflakeSegment, total: Int) -> some View {
        let weight = max(1, segment.bits.count)
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(segmentColor(segment.id))
            .frame(maxWidth: .infinity)
            .layoutPriority(Double(weight))
    }

    private func segmentColor(_ id: String) -> Color {
        switch id {
        case "time": return .accentColor
        case "machine": return .green
        default: return .orange
        }
    }

    private func runDecode() {
        let text = decodeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            decoded = nil
            decodeError = nil
            return
        }
        do {
            decoded = try IdEngine.decode(text: text, config: config)
            decodeError = nil
        } catch {
            decoded = nil
            decodeError = error.localizedDescription
        }
    }

    // MARK: 公用列表

    private func valueList(_ values: [(String, String)], onCopy: @escaping (String) -> Void) -> some View {
        Group {
            if values.isEmpty {
                Text("还没有生成内容")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 12) {
                            Text(item.0)
                                .font(.system(size: 12.5, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            CopyIconButton(text: item.0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        if index < values.count - 1 {
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
