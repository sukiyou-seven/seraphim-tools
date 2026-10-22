import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImageBase64View: View {
    @ObservedObject var source: WorkingImage
    @Binding var toast: String?

    enum Direction: String, CaseIterable, Identifiable {
        case encode = "图片 → Base64"
        case decode = "Base64 → 图片"
        var id: String { rawValue }
    }

    @State private var direction: Direction = .encode

    // 编码
    @State private var encodeFormat: ImageFormat = .png
    @State private var quality: Double = 0.85
    @State private var asDataURL = true
    @State private var lineWrapped = false
    @State private var encodedText: String?
    @State private var encodedTextLength = 0
    @State private var encodedSourceBytes = 0
    @State private var isEncoding = false

    // 解码
    @State private var input = ""
    @State private var decodedData: Data?
    @State private var decodedImage: CGImage?
    @State private var decodedFormat: ImageFormat?
    @State private var errorText: String?

    /// TextEditor 塞几 MB 文本会卡死，超长只显示头部
    private let previewCharacterLimit = 60_000

    var body: some View {
        VStack(spacing: 0) {
            Picker("方向", selection: $direction) {
                ForEach(Direction.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)
            .padding(.vertical, 12)

            Divider()

            if direction == .encode {
                encodePane
            } else {
                decodePane
            }
        }
    }

    // MARK: - 编码

    private var encodePane: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    ToolCard(title: "编码设置", systemImage: "gearshape") {
                        FlowRow(spacing: 6) {
                            ForEach([ImageFormat.png, .jpeg, .heic, .tiff, .gif]) { item in
                                ChipButton(
                                    title: item.title,
                                    isSelected: encodeFormat == item,
                                    isEnabled: ImageCodec.canEncode(item)
                                ) {
                                    encodeFormat = item
                                }
                            }
                        }

                        if encodeFormat.isLossy {
                            HStack {
                                Text("质量")
                                Spacer()
                                Text("\(Int((quality * 100).rounded()))%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $quality, in: 0.05...1)
                        }

                        Divider()

                        Toggle("加上 Data URL 前缀", isOn: $asDataURL)
                            .font(.caption)
                        Text("开启后生成 data:image/png;base64,… 形式，可以直接塞进 HTML / CSS / Markdown。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Toggle("每 76 字符换行", isOn: $lineWrapped)
                            .font(.caption)

                        Button {
                            Task { await encode() }
                        } label: {
                            Label(isEncoding ? "编码中…" : "生成 Base64", systemImage: "arrow.right.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!source.hasImage || isEncoding)
                    }

                    if let encodedText {
                        ToolCard(title: "结果", systemImage: "doc.text") {
                            MetricsRow(items: [
                                MetricItem(title: "原图", value: ByteFormatter.string(encodedSourceBytes)),
                                MetricItem(title: "Base64 字符数", value: "\(encodedTextLength)", tint: .accentColor),
                                MetricItem(title: "体积膨胀", value: expansionText),
                            ])

                            HStack(spacing: 8) {
                                Button {
                                    NSPasteboard.copyString(encodedText)
                                    toast = "Base64 已拷贝（\(encodedTextLength) 字符）"
                                } label: {
                                    Label("拷贝全部", systemImage: "doc.on.doc")
                                        .frame(maxWidth: .infinity)
                                }
                                Button {
                                    saveText(encodedText)
                                } label: {
                                    Label("保存 .txt", systemImage: "square.and.arrow.down")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                }
                .frame(width: 336)

                VStack(spacing: 16) {
                    ToolCard(title: "Base64 内容", systemImage: "chevron.left.forwardslash.chevron.right") {
                        if let encodedText {
                            TextEditor(text: .constant(displayedText(encodedText)))
                                .font(.system(size: 11, design: .monospaced))
                                .frame(minHeight: 420)
                                .overlay(alignment: .topLeading) {
                                    if encodedTextLength > previewCharacterLimit {
                                        Text("内容过长，此处只显示前 \(previewCharacterLimit) 字符。拷贝或保存会拿到完整内容。")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                            .padding(6)
                                            .background(.regularMaterial)
                                    }
                                }
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "chevron.left.forwardslash.chevron.right")
                                    .font(.system(size: 34))
                                    .foregroundStyle(.quaternary)
                                Text(source.hasImage ? "点左侧「生成 Base64」" : "先选一张图片")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 420)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
    }

    private var expansionText: String {
        guard encodedSourceBytes > 0 else { return "—" }
        let ratio = Double(encodedTextLength) / Double(encodedSourceBytes)
        return String(format: "×%.2f", ratio)
    }

    private func displayedText(_ text: String) -> String {
        text.count > previewCharacterLimit
            ? String(text.prefix(previewCharacterLimit))
            : text
    }

    // MARK: - 解码

    private var decodePane: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    ToolCard(title: "输入 Base64", systemImage: "square.and.pencil") {
                        Text("直接粘贴，带不带 data:image/...;base64, 前缀都行，换行和空格会自动忽略。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            Button {
                                if let string = NSPasteboard.general.string(forType: .string) {
                                    input = string
                                    toast = "已从剪贴板粘贴"
                                } else {
                                    toast = "剪贴板里没有文本"
                                }
                            } label: {
                                Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                            }
                            .controlSize(.small)

                            Button {
                                input = ""
                                decodedData = nil
                                decodedImage = nil
                                errorText = nil
                            } label: {
                                Label("清空", systemImage: "trash")
                            }
                            .controlSize(.small)
                            .disabled(input.isEmpty)
                        }

                        Button {
                            decode()
                        } label: {
                            Label("解码", systemImage: "arrow.down.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if decodedData != nil || errorText != nil {
                        ToolCard(title: "解码结果", systemImage: "checkmark.seal") {
                            if let errorText {
                                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if let decodedData {
                                MetricsRow(items: [
                                    MetricItem(title: "数据大小", value: ByteFormatter.string(decodedData.count), tint: .accentColor),
                                    MetricItem(title: "识别格式", value: decodedFormat?.title ?? "未知"),
                                    MetricItem(title: "尺寸", value: decodedImage.map { "\($0.width)×\($0.height)" } ?? "—"),
                                ])

                                ImageExportBar(
                                    saveTitle: decodedImage != nil ? "保存图片" : "保存原始数据",
                                    isEnabled: true
                                ) {
                                    saveDecoded()
                                } onCopy: {
                                    guard let decodedImage else { return }
                                    PasteboardWriter.copyImage(ImageCodec.nsImage(from: decodedImage))
                                    toast = "图片已拷贝"
                                }
                            }
                        }
                    }
                }
                .frame(width: 336)

                VStack(spacing: 16) {
                    ToolCard(title: "Base64 输入", systemImage: "text.alignleft") {
                        TextEditor(text: $input)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(minHeight: 180)
                    }

                    ToolCard(title: "图片预览", systemImage: "eye") {
                        ImagePreviewBox(cgImage: decodedImage, maxHeight: 320)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
    }

    // MARK: - 逻辑

    private func encode() async {
        guard let cg = source.cgImage else { return }
        isEncoding = true
        errorText = nil

        let format = encodeFormat
        let q = quality
        let dataURL = asDataURL
        let wrapped = lineWrapped
        let mime = Base64Tool.mimeType(for: format)

        let result: (text: String, sourceBytes: Int)? = await Task.detached(priority: .userInitiated) {
            guard let data = ImageCodec.encode(cg, format: format, quality: q) else { return nil }
            let text = Base64Tool.encode(data, mimeType: mime, asDataURL: dataURL, lineWrapped: wrapped)
            return (text, data.count)
        }.value

        isEncoding = false
        if let result {
            encodedText = result.text
            encodedTextLength = result.text.count
            encodedSourceBytes = result.sourceBytes
            toast = "已生成 Base64（\(result.text.count) 字符）"
        } else {
            encodedText = nil
            toast = "编码失败"
            NSSound.beep()
        }
    }

    private func decode() {
        errorText = nil
        decodedImage = nil
        decodedData = nil
        decodedFormat = nil

        guard let data = Base64Tool.decode(input) else {
            errorText = "这段内容不是合法的 Base64。"
            NSSound.beep()
            return
        }
        guard !data.isEmpty else {
            errorText = "解出来是空的。"
            NSSound.beep()
            return
        }

        decodedData = data
        decodedFormat = Base64Tool.detectFormat(of: data)
        decodedImage = ImageCodec.decode(data: data)

        if let image = decodedImage {
            toast = "解码成功：\(image.width)×\(image.height) \(decodedFormat?.title ?? "")"
        } else if decodedFormat != nil {
            errorText = "数据是 \(decodedFormat!.title) 文件，但没法作为图片打开。可以用「保存原始数据」把它存下来。"
        } else {
            errorText = "解出的数据不是已知的图片格式。可以用「保存原始数据」存下来看看是什么。"
        }
    }

    private func saveDecoded() {
        guard let data = decodedData else { return }
        if decodedImage != nil {
            let format = decodedFormat ?? .png
            let name = source.displayName.isEmpty
                ? "decoded.\(format.fileExtension)"
                : (source.displayName as NSString).deletingPathExtension + "-decoded.\(format.fileExtension)"
            if ImageCodec.save(data: data, suggestedName: name, contentType: format.utType) != nil {
                toast = "已保存 \(name)"
            }
        } else {
            if ImageCodec.save(data: data, suggestedName: "decoded.bin", contentType: .data) != nil {
                toast = "已保存原始数据"
            }
        }
    }

    private func saveText(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        if ImageCodec.save(data: data, suggestedName: "base64.txt", contentType: .plainText) != nil {
            toast = "已保存 base64.txt"
        }
    }
}
