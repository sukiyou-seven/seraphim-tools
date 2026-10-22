import AppKit
import SwiftUI

struct ImageConvertView: View {
    @ObservedObject var source: WorkingImage
    @Binding var toast: String?

    @State private var format: ImageFormat = .jpeg
    @State private var quality: Double = 0.85
    @State private var backgroundColor: Color = .white

    @State private var outputData: Data?
    @State private var previewImage: CGImage?
    @State private var isWorking = false
    @State private var errorText: String?

    private struct Key: Equatable {
        var token: UUID
        var format: String
        var quality: Int
        var background: String
    }

    private var key: Key {
        Key(
            token: source.token,
            format: format.rawValue,
            quality: Int((quality * 100).rounded()),
            background: RGBColor(backgroundColor).hexString
        )
    }

    var body: some View {
        if source.hasImage {
            ImagePaneLayout {
                formatCard
                qualityCard
                if !format.supportsAlpha {
                    backgroundCard
                }
            } preview: {
                resultCard
            }
            .task(id: key) {
                await encode()
            }
        } else {
            ImageEmptyHint()
        }
    }

    // MARK: - 控件

    private var formatCard: some View {
        ToolCard(title: "目标格式", systemImage: "arrow.triangle.2.circlepath") {
            FlowRow(spacing: 6) {
                ForEach(ImageFormat.allCases) { item in
                    ChipButton(
                        title: item.title,
                        isSelected: format == item,
                        isEnabled: ImageCodec.canEncode(item)
                    ) {
                        format = item
                    }
                }
            }
            Text(format.note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let detected = source.detectedFormat {
                Text("当前是 \(detected.title)，转成 \(format.title)\(detected == format ? "（同格式重编码）" : "")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var qualityCard: some View {
        if format.isLossy {
            ToolCard(title: "质量", systemImage: "dial.medium") {
                HStack {
                    Text("压缩质量")
                    Spacer()
                    Text("\(Int((quality * 100).rounded()))%")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $quality, in: 0.05...1)
                FlowRow(spacing: 6) {
                    ForEach([("原图级", 0.95), ("高", 0.85), ("中", 0.65), ("小体积", 0.4)], id: \.0) { item in
                        ChipButton(title: item.0, isSelected: abs(quality - item.1) < 0.01) {
                            quality = item.1
                        }
                    }
                }
            }
        } else {
            ToolCard(title: "质量", systemImage: "dial.medium") {
                Text("\(format.title) 是无损格式，没有质量参数。想压体积就换 JPEG / HEIC，或者去「压缩」页调目标大小。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var backgroundCard: some View {
        ToolCard(title: "透明区域", systemImage: "paintpalette") {
            ColorPicker("填充颜色", selection: $backgroundColor, supportsOpacity: false)
            Text("\(format.title) 不支持透明通道，原图的透明区域会填成这个颜色。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 结果

    private var resultCard: some View {
        ToolCard(title: "预览", systemImage: "eye") {
            ZStack {
                ImagePreviewBox(cgImage: previewImage, maxHeight: 300, placeholder: isWorking ? "编码中…" : "无法预览")
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                        .background(.regularMaterial, in: Circle())
                }
            }

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                MetricsRow(items: metrics)
            }

            ImageExportBar(isEnabled: outputData != nil) {
                save()
            } onCopy: {
                copyImage()
            }
        }
    }

    private var metrics: [MetricItem] {
        var items: [MetricItem] = []
        if let bytes = source.byteSize {
            items.append(MetricItem(title: "原图", value: ByteFormatter.string(bytes)))
        }
        if let outputData {
            items.append(MetricItem(title: "转出", value: ByteFormatter.string(outputData.count), tint: .accentColor))
            if let bytes = source.byteSize, bytes > 0 {
                let delta = (Double(outputData.count) - Double(bytes)) / Double(bytes) * 100
                let sign = delta >= 0 ? "+" : ""
                items.append(MetricItem(
                    title: "体积变化",
                    value: "\(sign)\(String(format: "%.0f", delta))%",
                    tint: delta > 0 ? .orange : .green
                ))
            }
        }
        let size = source.pixelSize
        items.append(MetricItem(title: "尺寸", value: "\(Int(size.width))×\(Int(size.height))"))
        if format.isLossy {
            items.append(MetricItem(title: "质量", value: "\(Int((quality * 100).rounded()))%"))
        }
        return items
    }

    // MARK: - 逻辑

    private func encode() async {
        guard let cg = source.cgImage else {
            outputData = nil
            previewImage = nil
            return
        }
        isWorking = true
        errorText = nil
        try? await Task.sleep(nanoseconds: 220_000_000)
        if Task.isCancelled { return }

        let fmt = format
        let q = quality
        let bg = RGBColor(backgroundColor)

        let data = await Task.detached(priority: .userInitiated) {
            ImageCodec.encode(cg, format: fmt, quality: q, background: bg)
        }.value

        if Task.isCancelled { return }
        isWorking = false

        if let data {
            outputData = data
            previewImage = ImageCodec.decode(data: data)
        } else {
            outputData = nil
            previewImage = nil
            errorText = ImageOperationError.encodeFailed(fmt).localizedDescription
        }
    }

    private func save() {
        guard let cg = source.cgImage, let data = ImageCodec.encode(cg, format: format, quality: quality, background: RGBColor(backgroundColor)) else {
            toast = "编码失败"
            NSSound.beep()
            return
        }
        let name = source.suggestedName(suffix: format.fileExtension, format: format)
        if ImageCodec.save(data: data, suggestedName: name, contentType: format.utType) != nil {
            toast = "已保存 \(name)"
        }
    }

    private func copyImage() {
        guard let previewImage else { return }
        PasteboardWriter.copyImage(ImageCodec.nsImage(from: previewImage))
        toast = "结果已拷贝到剪贴板"
    }
}
