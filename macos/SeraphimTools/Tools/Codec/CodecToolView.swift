import AppKit
import SwiftUI

struct CodecToolView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case codec
        case charset

        var id: String { rawValue }

        var title: String {
            switch self {
            case .codec: return "编解码"
            case .charset: return "字符集转换"
            }
        }

        var systemImage: String {
            switch self {
            case .codec: return "arrow.left.arrow.right"
            case .charset: return "textformat.size"
            }
        }
    }

    @AppStorage("codecMode") private var mode: Mode = .codec

    var body: some View {
        VStack(spacing: 0) {
            Picker("模式", selection: $mode) {
                ForEach(Mode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            switch mode {
            case .codec:
                CodecPanelView()
            case .charset:
                CharsetConvertView()
            }
        }
    }
}

// MARK: - 编解码面板

struct CodecPanelView: View {
    enum Direction: String, CaseIterable, Identifiable {
        case encode
        case decode

        var id: String { rawValue }

        var title: String {
            switch self {
            case .encode: return "编码"
            case .decode: return "解码"
            }
        }
    }

    @AppStorage("codecAlgorithm") private var algorithm: CodecAlgorithm = .base64
    @AppStorage("codecDirection") private var direction: Direction = .encode

    @State private var input = ""
    @State private var options = CodecOptions()
    @State private var toast: String?

    // MARK: 实时转换结果

    private var outcome: Result<String, Error> {
        guard !input.isEmpty else { return .success("") }
        do {
            let value = direction == .encode
                ? try CodecEngine.encode(input, algorithm: algorithm, options: options)
                : try CodecEngine.decode(input, algorithm: algorithm, options: options)
            return .success(value)
        } catch {
            return .failure(error)
        }
    }

    private var outputText: String {
        if case .success(let text) = outcome { return text }
        return ""
    }

    private var errorMessage: String? {
        if case .failure(let error) = outcome { return error.localizedDescription }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                algorithmCard
                settingsCard

                TextPane(
                    title: direction == .encode ? "原文" : "待解码内容",
                    text: $input,
                    placeholder: direction == .encode ? "输入要编码的文本…" : "粘贴要解码的内容…",
                    minHeight: 150,
                    buttons: inputButtons
                )

                directionBar

                VStack(spacing: 10) {
                    if let errorMessage {
                        ErrorBanner(message: errorMessage)
                    }
                    TextPane(
                        title: "结果",
                        text: .constant(outputText),
                        isEditable: false,
                        placeholder: errorMessage ?? "结果会实时出现在这里",
                        minHeight: 150,
                        buttons: outputButtons
                    )
                }
            }
            .padding(20)
        }
        .toast($toast)
    }

    // MARK: 算法选择

    private var algorithmCard: some View {
        ToolCard(title: "编码算法", systemImage: "square.stack.3d.up") {
            FlowRow(spacing: 7) {
                ForEach(CodecAlgorithm.allCases) { item in
                    ChipButton(title: item.title, isSelected: item == algorithm) {
                        algorithm = item
                        if !input.isEmpty { toast = "已切到 \(item.title)" }
                    }
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: algorithm.systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(algorithm.summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 选项

    @ViewBuilder
    private var settingsCard: some View {
        ToolCard(title: "选项", systemImage: "slider.horizontal.3") {
            FlowRow(spacing: 14) {
                switch algorithm {
                case .base64:
                    checkbox("URL-safe（-_ 代替 +/）", $options.base64URLSafe)
                    checkbox("保留 = 填充", $options.base64KeepPadding)
                    checkbox("每 76 字符换行", $options.base64Wrap76)

                case .url:
                    checkbox("仅保留必要字符", $options.urlStrict)
                    checkbox("解码时把 + 当空格", $options.urlPlusAsSpace)

                case .hex:
                    checkbox("大写", $options.hexUppercase)
                    checkbox("0x 前缀", $options.hexPrefix)
                    separatorPicker
                    wrapPicker

                case .binary, .octal, .decimal:
                    separatorPicker
                    wrapPicker
                    Text("这几个进制不加分隔符就没法读，所以选「无」时会自动按空格隔开。")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)

                case .html:
                    checkbox("只用数字实体", $options.htmlNumericOnly)

                case .unicode:
                    checkbox("用 \\u{XXXX} 形式", $options.unicodeBraced)
                    checkbox("ASCII 也转义", $options.unicodeEscapeASCII)

                case .jsonString:
                    checkbox("非 ASCII 转成 \\uXXXX", $options.jsonEscapeUnicode)

                case .base32:
                    Text("标准 RFC 4648 字母表（A–Z、2–7），补齐填充位。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func checkbox(_ title: String, _ binding: Binding<Bool>) -> some View {
        Toggle(title, isOn: binding)
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
    }

    private var separatorPicker: some View {
        HStack(spacing: 6) {
            Text("分隔符")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Picker("", selection: $options.separator) {
                ForEach(ByteSeparator.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .labelsHidden()
            .frame(width: 88)
        }
    }

    private var wrapPicker: some View {
        HStack(spacing: 6) {
            Text("每行")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Picker("", selection: $options.wrapEvery) {
                Text("不换行").tag(0)
                Text("8 字节").tag(8)
                Text("16 字节").tag(16)
                Text("32 字节").tag(32)
            }
            .labelsHidden()
            .frame(width: 100)
        }
    }

    // MARK: 方向控制

    private var directionBar: some View {
        HStack(spacing: 8) {
            ChipButton(title: "编码 ↓", isSelected: direction == .encode, minWidth: 84) {
                direction = .encode
            }
            ChipButton(title: "解码 ↑", isSelected: direction == .decode, minWidth: 84) {
                direction = .decode
            }

            Button {
                swap()
            } label: {
                Label("交换", systemImage: "arrow.up.arrow.down")
            }
            .controlSize(.small)
            .disabled(input.isEmpty && outputText.isEmpty)
            .help("把结果当作输入，并切换编解码方向")

            Button {
                fillSample()
            } label: {
                Label("示例", systemImage: "sparkles")
            }
            .controlSize(.small)

            Spacer(minLength: 8)

            Text("输入改变即实时转换")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: 按钮

    private var inputButtons: [PaneButton] {
        [
            PaneButton(systemImage: "doc.on.clipboard", help: "从剪贴板粘贴") {
                if let string = NSPasteboard.general.string(forType: .string) {
                    input = string
                } else {
                    toast = "剪贴板里没有文本"
                    NSSound.beep()
                }
            },
            PaneButton(systemImage: "trash", help: "清空输入") {
                input = ""
            },
        ]
    }

    private var outputButtons: [PaneButton] {
        [
            PaneButton(systemImage: "doc.on.doc", help: "复制结果") {
                guard !outputText.isEmpty else { return }
                NSPasteboard.copyString(outputText)
                toast = "结果已复制"
            },
            PaneButton(systemImage: "square.and.arrow.down", help: "保存为文件") {
                guard !outputText.isEmpty else { return }
                let name = "\(algorithm.rawValue)-\(direction.rawValue).txt"
                if FilePicker.saveText(outputText, suggestedName: name) != nil {
                    toast = "已保存"
                }
            },
        ]
    }

    // MARK: 操作

    private func swap() {
        let result = outputText
        guard !result.isEmpty else { return }
        input = result
        direction = direction == .encode ? .decode : .encode
    }

    private func fillSample() {
        input = direction == .encode ? algorithm.sample.plain : algorithm.sample.encoded
    }
}
