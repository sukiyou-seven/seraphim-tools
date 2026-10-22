import AppKit
import SwiftUI

struct ImageWatermarkView: View {
    @ObservedObject var source: WorkingImage
    @Binding var toast: String?

    @State private var options = WatermarkOptions()
    @State private var fontTouched = false
    @State private var previewImage: CGImage?
    @State private var isWorking = false
    @State private var watermarkName: String?

    private struct Key: Equatable {
        var token: UUID
        var style: String
        var text: String
        var fontSize: Int
        var color: String
        var shadow: Bool
        var imageScale: Int
        var imageToken: String
        var opacity: Int
        var rotation: Int
        var anchor: String
        var tiled: Bool
        var spacing: Int
    }

    private var key: Key {
        Key(
            token: source.token,
            style: options.style.rawValue,
            text: options.text,
            fontSize: Int(options.fontSize.rounded()),
            color: RGBColor(options.color).hexString,
            shadow: options.shadow,
            imageScale: Int((options.imageScale * 1000).rounded()),
            imageToken: watermarkName ?? "",
            opacity: Int((options.opacity * 100).rounded()),
            rotation: Int(options.rotation.rounded()),
            anchor: options.anchor.rawValue,
            tiled: options.tiled,
            spacing: Int(options.spacing.rounded())
        )
    }

    var body: some View {
        if source.hasImage {
            ImagePaneLayout {
                styleCard
                if options.style == .text {
                    textCard
                } else {
                    imageCard
                }
                placementCard
            } preview: {
                resultCard
            }
            .task(id: key) {
                await render()
            }
            .task(id: source.token) {
                // 默认字号随图片宽度走，固定 48px 在大图上小得看不见
                guard !fontTouched, source.pixelSize.width > 0 else { return }
                options.fontSize = Double(max(28, (source.pixelSize.width / 18).rounded()))
            }
        } else {
            ImageEmptyHint()
        }
    }

    // MARK: - 控件

    private var styleCard: some View {
        ToolCard(title: "水印类型", systemImage: "signature") {
            HStack(spacing: 6) {
                ForEach(WatermarkStyle.allCases) { item in
                    ChipButton(title: item.title, isSelected: options.style == item, minWidth: 76) {
                        options.style = item
                    }
                }
            }
        }
    }

    private var textCard: some View {
        ToolCard(title: "文字内容", systemImage: "textformat") {
            TextField("水印文字", text: $options.text)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("字号")
                Spacer()
                Text("\(Int(options.fontSize)) px")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { options.fontSize },
                set: { options.fontSize = $0; fontTouched = true }
            ), in: 8...400)

            ColorPicker("颜色", selection: $options.color, supportsOpacity: false)
            Toggle("描边阴影（深色底上更清楚）", isOn: $options.shadow)
                .font(.caption)
        }
    }

    private var imageCard: some View {
        ToolCard(title: "水印图片", systemImage: "photo") {
            HStack(spacing: 10) {
                ZStack {
                    if let cg = options.watermarkImage?.pixelCGImage {
                        Checkerboard(square: 5)
                        Image(decorative: cg, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)))

                VStack(alignment: .leading, spacing: 4) {
                    Text(watermarkName ?? "还没有选择水印图")
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("选择图片…") {
                        if let image = ImageCodec.pickImage(title: "选择水印图片") {
                            options.watermarkImage = image
                            watermarkName = "已选择水印图"
                        }
                    }
                    .controlSize(.small)
                }
            }

            HStack {
                Text("相对宽度")
                Spacer()
                Text("\(Int((options.imageScale * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $options.imageScale, in: 0.03...1)

            Text("水印图建议用带透明通道的 PNG。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var placementCard: some View {
        ToolCard(title: "位置与样式", systemImage: "square.grid.3x3") {
            Toggle("平铺（全图重复）", isOn: $options.tiled)

            if !options.tiled {
                anchorGrid
            } else {
                HStack {
                    Text("间距")
                    Spacer()
                    Text("\(Int(options.spacing)) px")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $options.spacing, in: 0...400)
            }

            HStack {
                Text("不透明度")
                Spacer()
                Text("\(Int((options.opacity * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $options.opacity, in: 0.05...1)

            HStack {
                Text("旋转")
                Spacer()
                Text("\(Int(options.rotation))°")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $options.rotation, in: -90...90)
        }
    }

    private var anchorGrid: some View {
        VStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { column in
                        let anchor = anchorAt(row: row, column: column)
                        Button {
                            options.anchor = anchor
                        } label: {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(options.anchor == anchor ? Color.accentColor : Color.primary.opacity(0.08))
                                .frame(width: 34, height: 26)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.10))
                                )
                        }
                        .buttonStyle(.plain)
                        .help(anchorName(anchor))
                    }
                }
            }
        }
    }

    private func anchorAt(row: Int, column: Int) -> WatermarkAnchor {
        switch (row, column) {
        case (0, 0): return .topLeft
        case (0, 1): return .topCenter
        case (0, 2): return .topRight
        case (1, 0): return .middleLeft
        case (1, 1): return .center
        case (1, 2): return .middleRight
        case (2, 0): return .bottomLeft
        case (2, 1): return .bottomCenter
        default: return .bottomRight
        }
    }

    private func anchorName(_ anchor: WatermarkAnchor) -> String {
        switch anchor {
        case .topLeft: return "左上"
        case .topCenter: return "上中"
        case .topRight: return "右上"
        case .middleLeft: return "左中"
        case .center: return "正中"
        case .middleRight: return "右中"
        case .bottomLeft: return "左下"
        case .bottomCenter: return "下中"
        case .bottomRight: return "右下"
        }
    }

    // MARK: - 结果

    private var resultCard: some View {
        ToolCard(title: "预览", systemImage: "eye") {
            ZStack {
                ImagePreviewBox(
                    cgImage: previewImage,
                    maxHeight: 340,
                    showCheckerboard: false,
                    placeholder: isWorking ? "渲染中…" : "无法预览"
                )
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                        .background(.regularMaterial, in: Circle())
                }
            }

            Text("预览使用降采样版本，导出时按原图分辨率重新渲染，位置和比例完全一致。")
                .font(.caption)
                .foregroundStyle(.tertiary)

            ImageExportBar(isEnabled: previewImage != nil) {
                save()
            } onCopy: {
                copyImage()
            }
        }
    }

    // MARK: - 逻辑

    /// 预览用参数：绝对像素的参数按预览比例缩放
    private func previewOptions(scale: CGFloat) -> WatermarkOptions {
        var adjusted = options
        adjusted.fontSize = options.fontSize * Double(scale)
        adjusted.spacing = options.spacing * Double(scale)
        return adjusted
    }

    private func render() async {
        guard let preview = source.previewCGImage() else {
            previewImage = nil
            return
        }
        isWorking = true
        try? await Task.sleep(nanoseconds: 180_000_000)
        if Task.isCancelled { return }

        let adjusted = previewOptions(scale: source.previewScale())
        previewImage = ImageProcessor.watermarked(preview, options: adjusted)
        isWorking = false
    }

    private func save() {
        guard let full = source.cgImage else {
            toast = "没有原图"
            NSSound.beep()
            return
        }
        guard let result = ImageProcessor.watermarked(full, options: options) else {
            toast = "水印渲染失败"
            NSSound.beep()
            return
        }
        let format = source.detectedFormat ?? .png
        let name = source.suggestedName(suffix: "watermark", format: format)
        guard let data = ImageCodec.encode(result, format: format) else {
            toast = "编码失败"
            NSSound.beep()
            return
        }
        if ImageCodec.save(data: data, suggestedName: name, contentType: format.utType) != nil {
            toast = "已保存 \(name)"
        }
    }

    private func copyImage() {
        guard let full = source.cgImage,
              let result = ImageProcessor.watermarked(full, options: options) else { return }
        PasteboardWriter.copyImage(ImageCodec.nsImage(from: result))
        toast = "水印结果已拷贝"
    }
}
