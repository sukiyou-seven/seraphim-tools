import AppKit
import SwiftUI

/// CRC 校验计算。
///
/// 和上面那页摘要不是一回事：CRC 是参数化的一族算法，同一个多项式
/// 换个初值或反射位就是另一个结果。所以这页的重点是「把参数摆清楚」——
/// 抄来的多项式算不对，多半是参数没对齐。
struct CryptoChecksumView: View {
    @AppStorage("crcFamily") private var family: CRCFamily = .crc32
    @AppStorage("crcModel") private var modelName = "CRC-32/ISO-HDLC"
    @AppStorage("crcExpected") private var expectedText = ""

    @AppStorage("crcCustomName") private var customName = ""
    @AppStorage("crcCustomWidth") private var customWidth = 16
    @AppStorage("crcCustomPoly") private var customPoly = "8005"
    @AppStorage("crcCustomInit") private var customInit = "0000"
    @AppStorage("crcCustomXorOut") private var customXorOut = "0000"
    @AppStorage("crcCustomRefin") private var customRefin = true
    @AppStorage("crcCustomRefout") private var customRefout = true

    /// 输入也存起来：算 CRC 常常要反复换参数对比同一份数据，输入不该丢
    @AppStorage("crcText") private var input = "123456789"
    @State private var fileURL: URL?
    @State private var fileName = ""
    @State private var fileSize = 0

    @State private var result: UInt64?
    @State private var isComputing = false
    @State private var errorMessage: String?
    @State private var toast: String?
    @State private var isDropTargeted = false
    /// 展开状态也记住：调参数的时候没人想每次都点开
    @AppStorage("crcShowParameters") private var showParameters = false

    private let widths = [8, 16, 32, 64]

    // MARK: 当前参数集

    private var spec: CRCSpec {
        family == .custom ? customSpec : CRCSpec.preset(orDefault: modelName)
    }

    private var customSpec: CRCSpec {
        let width = customWidth
        let probe = CRCSpec(
            name: "自定义", width: width,
            poly: HexFieldParse.hex(customPoly, width: width),
            initial: HexFieldParse.hex(customInit, width: width),
            refin: customRefin, refout: customRefout,
            xorOut: HexFieldParse.hex(customXorOut, width: width),
            check: 0, isCustom: true
        )
        let check = ChecksumEngine.compute(CRCSpec.checkText, spec: probe)
        return CRCSpec(
            name: customName.isEmpty ? "自定义" : customName,
            width: width,
            poly: probe.poly,
            initial: probe.initial,
            refin: customRefin,
            refout: customRefout,
            xorOut: probe.xorOut,
            check: check,
            alias: "",
            note: "自己填的参数",
            isCustom: true
        )
    }

    private var taskKey: String {
        "\(spec.name)|\(spec.width)|\(spec.poly)|\(spec.initial)|\(spec.refin)|\(spec.refout)|\(spec.xorOut)"
            + "|\(fileURL?.path ?? "")|\(input.hashValue)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                modelCard
                if family == .custom { customCard }
                inputCard
                resultCard
            }
            .padding(20)
        }
        .toast($toast)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [10, 6]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .task(id: taskKey) {
            await recompute()
        }
    }

    // MARK: 模型

    private var modelCard: some View {
        ToolCard(title: "CRC 参数模型", systemImage: "checkmark.shield") {
            VStack(alignment: .leading, spacing: 12) {
                FlowRow(spacing: 6) {
                    ForEach(CRCFamily.allCases) { item in
                        ChipButton(title: item.title, isSelected: item == family) {
                            family = item
                            if let width = item.width {
                                // 切家族顺手挑一个该宽度的常用模型，省得下拉找
                                if spec.width != width {
                                    modelName = CRCSpec.presets(of: item).first?.name ?? modelName
                                }
                            }
                        }
                    }
                }

                if family == .custom {
                    Text("自定义宽度和六个参数。想从现成模型改，去上面的「参数详情」里点「改一份」。")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                } else {
                    variantChips
                }

                Divider().opacity(0.5)

                parameterDetails

                Text(spec.note.isEmpty ? family.hint : spec.note)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var variantChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowRow(spacing: 6) {
                ForEach(CRCSpec.presets(of: family)) { item in
                    ChipButton(title: item.name, isSelected: item.name == spec.name) {
                        modelName = item.name
                    }
                }
            }

            if !spec.alias.isEmpty {
                Text("也叫 \(spec.alias)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var parameterDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showParameters.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: showParameters ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text("参数详情").font(.system(size: 11.5))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)

                Text(spec.parameterLine)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }

            if showParameters {
                VStack(spacing: 6) {
                    parameterRow("宽度", "\(spec.width) 位", "结果占 \(spec.byteCount) 字节")
                    parameterRow("多项式", "0x" + ChecksumEngine.hex(spec.poly, width: spec.width),
                                 "决定计算方式的生成多项式")
                    parameterRow("初值", "0x" + ChecksumEngine.hex(spec.initial, width: spec.width),
                                 "开始计算前 crc 寄存器的值")
                    parameterRow("输入反射", spec.refin ? "是" : "否",
                                 spec.refin ? "每个字节按位倒过来再算" : "字节按原样参与运算")
                    parameterRow("输出反射", spec.refout ? "是" : "否",
                                 spec.refout ? "结果按位倒过来" : "结果保持原样")
                    parameterRow("结果异或", "0x" + ChecksumEngine.hex(spec.xorOut, width: spec.width),
                                 "最后和这个值异或，全 0 就是不改")
                    parameterRow("标准校验值", "0x" + ChecksumEngine.hex(spec.check, width: spec.width),
                                 "对 \"123456789\" 算出来的值，拿来核对参数有没有抄错")
                }
                .padding(.top, 2)

                if family != .custom {
                    Button {
                        cloneToCustom()
                    } label: {
                        Label("改一份", systemImage: "square.on.square.dashed")
                            .font(.system(size: 11.5))
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func parameterRow(_ name: String, _ value: String, _ meaning: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(width: 150, alignment: .leading)
            Text(meaning)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
    }

    // MARK: 自定义参数

    private var customCard: some View {
        ToolCard(title: "自定义参数", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("名称")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .leading)
                    TextField("给这套参数起个名字（可留空）", text: $customName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(maxWidth: 260)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Text("宽度")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .leading)
                    FlowRow(spacing: 6) {
                        ForEach(widths, id: \.self) { value in
                            ChipButton(title: "\(value)", isSelected: value == customWidth) {
                                customWidth = value
                                normalizeCustomFields()
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }

                hexField("多项式", text: $customPoly, hint: "生成多项式，十六进制")
                hexField("初值", text: $customInit, hint: "crc 寄存器初值")
                hexField("结果异或", text: $customXorOut, hint: "最后一步异或，全 0 表示不改")

                HStack(spacing: 18) {
                    Toggle("输入反射", isOn: $customRefin)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11.5))
                    Toggle("输出反射", isOn: $customRefout)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11.5))
                    Spacer(minLength: 0)
                }

                if customRefin != customRefout {
                    NoticeTag(text: "两处反射不一致的模型很少见，这种参数会走慢速实现",
                              systemImage: "exclamationmark.triangle", tint: .orange)
                }

                HStack(spacing: 8) {
                    Text("校验值")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .leading)
                    Text("0x" + ChecksumEngine.hex(spec.check, width: spec.width))
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                    Text("对 \"123456789\" 的结果，和 CRC 目录里对一下就知道参数填对没有")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func hexField(_ title: String, text: Binding<String>, hint: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
            HStack(spacing: 4) {
                Text("0x")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                TextField("", text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14))
            )
            .frame(width: 170)

            Text(hint)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
    }

    // MARK: 输入

    private var inputCard: some View {
        VStack(spacing: 10) {
            if let fileURL {
                fileChip(url: fileURL)
            }
            TextPane(
                title: fileURL == nil ? "文本" : "文本（已忽略，当前在算文件）",
                text: $input,
                placeholder: "输入要计算 CRC 的内容…",
                minHeight: 130,
                buttons: [
                    PaneButton(systemImage: "doc.on.clipboard", help: "从剪贴板粘贴") {
                        if let string = NSPasteboard.general.string(forType: .string) {
                            input = string
                            clearFile()
                        } else {
                            toast = "剪贴板里没有文本"
                            NSSound.beep()
                        }
                    },
                    PaneButton(systemImage: "text.badge.checkmark", help: "填入标准测试串 123456789，用它核对参数") {
                        input = "123456789"
                        clearFile()
                        toast = "已填入标准测试串"
                    },
                    PaneButton(systemImage: "doc.badge.plus", help: "选一个文件来算校验") {
                        if let url = FilePicker.pick(title: "选择要计算 CRC 的文件") {
                            load(url: url)
                        }
                    },
                    PaneButton(systemImage: "trash", help: "清空") {
                        input = ""
                        clearFile()
                    },
                ]
            )
        }
    }

    private func fileChip(url: URL) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(fileName)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(ByteFormatter.string(fileSize))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("移除") { clearFile() }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.25))
        )
    }

    // MARK: 结果

    private var resultCard: some View {
        ToolCard(title: "校验结果", systemImage: "number") {
            VStack(alignment: .leading, spacing: 14) {
                if isComputing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("计算中…").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                } else if let errorMessage {
                    ErrorBanner(message: errorMessage)
                } else if let result {
                    mainValue(result)
                    secondaryValues(result)
                    Divider().opacity(0.5)
                    expectationRow(result)
                    footerNote
                } else {
                    Text("输入内容或选个文件，这里会实时算出 CRC")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    footerNote
                }
            }
        }
    }

    private func mainValue(_ value: UInt64) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(spec.isCustom ? "结果" : spec.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                CopyIconButton(text: "0x" + ChecksumEngine.hex(value, width: spec.width))
            }
            Text("0x" + ChecksumEngine.hex(value, width: spec.width))
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10))
                )
        }
    }

    private func secondaryValues(_ value: UInt64) -> some View {
        VStack(spacing: 6) {
            valueRow("十进制", ChecksumEngine.decimalText(value))
            valueRow("字节 · 大端", ChecksumEngine.byteText(value, width: spec.width, bigEndian: true),
                     note: "网络序、文件尾")
            valueRow("字节 · 小端", ChecksumEngine.byteText(value, width: spec.width, bigEndian: false),
                     note: "Modbus 这类协议就这么发")
        }
    }

    private func valueRow(_ title: String, _ value: String, note: String = "") -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
            if !note.isEmpty {
                Text(note)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 6)
            CopyIconButton(text: value)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
    }

    private func expectationRow(_ value: UInt64) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("核对已知值")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                TextField("拿到别人的 CRC 就贴这儿", text: $expectedText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5, design: .monospaced))
                    .frame(maxWidth: 220)
                if !expectedText.isEmpty {
                    Button {
                        expectedText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                }
                Spacer(minLength: 0)
            }

            verdict(for: ChecksumEngine.compare(expectedText, actual: value, spec: spec), actual: value)
        }
    }

    @ViewBuilder
    private func verdict(for outcome: CRCCompareResult, actual: UInt64) -> some View {
        switch outcome {
        case .empty:
            Text("贴一个已知的 CRC 上来，这里会告诉你算出来的对不对。")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        case .invalid:
            NoticeTag(text: "这个值不像 \(spec.width) 位的十六进制，检查一下位数", systemImage: "questionmark.circle", tint: .orange)
        case .match:
            NoticeTag(text: "一致，数据没问题", systemImage: "checkmark.seal.fill", tint: .green)
        case .matchSwapped:
            NoticeTag(text: "一致 —— 你贴的是小端字节序的写法，也对得上",
                      systemImage: "checkmark.seal.fill", tint: .green)
        case .mismatch(let expected):
            VStack(alignment: .leading, spacing: 5) {
                NoticeTag(text: "对不上", systemImage: "xmark.seal.fill", tint: .red)
                Text("你给的 0x\(ChecksumEngine.hex(expected, width: spec.width))，"
                     + "实算 0x\(ChecksumEngine.hex(actual, width: spec.width))，"
                     + "差了 0x\(ChecksumEngine.hex(expected ^ actual, width: spec.width))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footerNote: some View {
        Text("CRC 是用来发现传输和存储错误的，挡不住故意改数据的人——改了内容顺手把 CRC 一起改掉就完了。防篡改要用 SHA-256 或者 HMAC。")
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: 计算

    @MainActor
    private func recompute() async {
        let current = spec

        if let fileURL {
            isComputing = true
            let value = await Task.detached(priority: .userInitiated) { () -> UInt64? in
                guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
                defer { try? handle.close() }
                var calculator = ChecksumEngine.CRCCalculator(spec: current)
                // 分块喂，几 GB 的文件也不至于把内存吃掉
                while true {
                    let bunch: Data
                    do {
                        guard let next = try handle.read(upToCount: 1 << 20), !next.isEmpty else { break }
                        bunch = next
                    } catch {
                        // 读到一半失败就作罢，别拿半截数据算出一个看着挺正常的假结果
                        return nil
                    }
                    calculator.update(bunch)
                }
                return calculator.value
            }.value
            isComputing = false
            result = value
            errorMessage = value == nil ? "文件读不动，检查一下权限或者换一个试试。" : nil
            return
        }

        guard !input.isEmpty else {
            result = nil
            errorMessage = nil
            return
        }
        let data = Data(input.utf8)
        result = await Task.detached(priority: .userInitiated) {
            ChecksumEngine.computeFast(data, spec: current)
        }.value
        errorMessage = nil
    }

    // MARK: 操作

    private func cloneToCustom() {
        customName = spec.name + "（改）"
        customWidth = spec.width
        customPoly = ChecksumEngine.hex(spec.poly, width: spec.width)
        customInit = ChecksumEngine.hex(spec.initial, width: spec.width)
        customXorOut = ChecksumEngine.hex(spec.xorOut, width: spec.width)
        customRefin = spec.refin
        customRefout = spec.refout
        family = .custom
        showParameters = true
        toast = "参数已拷到自定义"
    }

    /// 换宽度时把三个十六进制字段补齐或截断到新长度
    private func normalizeCustomFields() {
        customPoly = ChecksumEngine.hex(HexFieldParse.hex(customPoly, width: customWidth), width: customWidth)
        customInit = ChecksumEngine.hex(HexFieldParse.hex(customInit, width: customWidth), width: customWidth)
        customXorOut = ChecksumEngine.hex(HexFieldParse.hex(customXorOut, width: customWidth), width: customWidth)
    }

    private func load(url: URL) {
        fileURL = url
        fileName = url.lastPathComponent
        fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        input = ""
        toast = "已选择 \(url.lastPathComponent)"
    }

    private func clearFile() {
        fileURL = nil
        fileName = ""
        fileSize = 0
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first, provider.canLoadObject(ofClass: URL.self) else { return false }
        _ = provider.loadObject(ofClass: URL.self) { object, _ in
            guard let url = object else { return }
            DispatchQueue.main.async { load(url: url) }
        }
        return true
    }
}

// MARK: - 小工具

/// 十六进制字段的宽松解析。宽度不对就按低位置截断，不弹错误——
/// 用户一边打字一边校验会一直闪红，体验反而差。
private enum HexFieldParse {
    static func hex(_ text: String, width: Int) -> UInt64 {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: "[\\s:_]", with: "", options: .regularExpression)
        guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.isHexDigit }),
              let value = UInt64(cleaned, radix: 16) else { return 0 }
        return value & ChecksumEngine.mask(width)
    }
}
