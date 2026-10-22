import AppKit
import SwiftUI

struct ImageCompressView: View {
    @ObservedObject var source: WorkingImage
    @Binding var toast: String?

    @State private var outputFormat: ImageFormat = .jpeg
    @State private var followSourceFormat = true
    @State private var mode: CompressionRequest.Mode = .targetSize
    @State private var quality: Double = 0.7
    @State private var targetBytes: Double = 300 * 1024
    @State private var maxDimension: Double = 0

    @State private var outcome: CompressionOutcome?
    @State private var previewImage: CGImage?
    @State private var isWorking = false

    private struct Key: Equatable {
        var token: UUID
        var format: String
        var mode: String
        var quality: Int
        var target: Int
        var maxDimension: Int
    }

    private var effectiveFormat: ImageFormat {
        if followSourceFormat, let detected = source.detectedFormat, ImageCodec.canEncode(detected) {
            return detected
        }
        return outputFormat
    }

    private var request: CompressionRequest {
        CompressionRequest(
            format: effectiveFormat,
            mode: mode,
            quality: quality,
            targetBytes: Int(targetBytes),
            maxDimension: maxDimension
        )
    }

    private var key: Key {
        Key(
            token: source.token,
            format: effectiveFormat.rawValue,
            mode: mode.rawValue,
            quality: Int((quality * 100).rounded()),
            target: Int(targetBytes),
            maxDimension: Int(maxDimension)
        )
    }

    var body: some View {
        if source.hasImage {
            ImagePaneLayout {
                formatCard
                modeCard
                limitCard
            } preview: {
                resultCard
            }
            .task(id: key) {
                await compress()
            }
        } else {
            ImageEmptyHint()
        }
    }

    // MARK: - 控件

    private var formatCard: some View {
        ToolCard(title: "输出格式", systemImage: "doc.badge.gearshape") {
            Toggle("跟随原图格式", isOn: $followSourceFormat)

            if followSourceFormat {
                Text("当前会输出 \(effectiveFormat.title)\(source.detectedFormat == nil ? "（没读到原格式，回退到默认）" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                FlowRow(spacing: 6) {
                    ForEach([ImageFormat.jpeg, .heic, .png, .tiff]) { item in
                        ChipButton(
                            title: item.title,
                            isSelected: outputFormat == item,
                            isEnabled: ImageCodec.canEncode(item)
                        ) {
                            outputFormat = item
                        }
                    }
                }
            }

            if !effectiveFormat.isLossy {
                Label("\(effectiveFormat.title) 是无损格式，压不动多少。要体积小请用 JPEG 或 HEIC。", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var modeCard: some View {
        ToolCard(title: "压缩方式", systemImage: "arrow.down.circle") {
            HStack(spacing: 6) {
                ForEach(CompressionRequest.Mode.allCases) { item in
                    ChipButton(title: item.title, isSelected: mode == item, minWidth: 84) {
                        mode = item
                    }
                }
            }

            if mode == .quality {
                HStack {
                    Text("质量")
                    Spacer()
                    Text("\(Int((quality * 100).rounded()))%")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $quality, in: 0.05...1)
                .disabled(!effectiveFormat.isLossy)
                FlowRow(spacing: 6) {
                    ForEach([("高", 0.85), ("中", 0.65), ("低", 0.45), ("极限", 0.25)], id: \.0) { item in
                        ChipButton(title: item.0, isSelected: abs(quality - item.1) < 0.01) {
                            quality = item.1
                        }
                    }
                }
                .disabled(!effectiveFormat.isLossy)
            } else {
                HStack {
                    Text("目标大小")
                    Spacer()
                    Text(ByteFormatter.string(Int(targetBytes)))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $targetBytes, in: 20 * 1024...(5 * 1024 * 1024))
                    .disabled(!effectiveFormat.isLossy)
                FlowRow(spacing: 6) {
                    ForEach([("50 KB", 50), ("100 KB", 100), ("300 KB", 300), ("500 KB", 500), ("1 MB", 1024), ("2 MB", 2048)], id: \.0) { item in
                        ChipButton(
                            title: item.0,
                            isSelected: abs(targetBytes - Double(item.1 * 1024)) < 1024
                        ) {
                            targetBytes = Double(item.1 * 1024)
                        }
                    }
                }
                .disabled(!effectiveFormat.isLossy)

                Text("会自动二分搜索最接近目标体积的质量参数，画质尽量保住。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var limitCard: some View {
        ToolCard(title: "限制长边", systemImage: "arrow.up.left.and.arrow.down.right") {
            FlowRow(spacing: 6) {
                ChipButton(title: "不限制", isSelected: maxDimension == 0) { maxDimension = 0 }
                ForEach([800.0, 1280.0, 1920.0, 2560.0, 3840.0], id: \.self) { value in
                    ChipButton(
                        title: "\(Int(value)) px",
                        isSelected: abs(maxDimension - value) < 1
                    ) {
                        maxDimension = value
                    }
                }
            }
            Text("长边超过限制时会先等比缩小再压缩，进一步省体积。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 结果

    private var resultCard: some View {
        ToolCard(title: "结果", systemImage: "chart.bar") {
            ZStack {
                ImagePreviewBox(cgImage: previewImage, maxHeight: 300, placeholder: isWorking ? "计算中…" : "无法预览")
                if isWorking {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("计算中…").font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                }
            }

            MetricsRow(items: metrics)

            if let outcome, !outcome.reachedTarget, mode == .targetSize, outcome.format.isLossy {
                Label("已经压到最低质量仍超过目标，建议同时限制长边，或换 HEIC。", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let bytes = source.byteSize, let outcome {
                savingsBar(original: bytes, compressed: outcome.data.count)
            }

            ImageExportBar(isEnabled: outcome != nil) {
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
        if let outcome {
            items.append(MetricItem(title: "压缩后", value: ByteFormatter.string(outcome.data.count), tint: .green))
            if outcome.format.isLossy {
                items.append(MetricItem(title: "实际质量", value: "\(Int((outcome.quality * 100).rounded()))%"))
            }
        }
        let size = source.pixelSize
        items.append(MetricItem(title: "尺寸", value: "\(Int(size.width))×\(Int(size.height))"))
        return items
    }

    private func savingsBar(original: Int, compressed: Int) -> some View {
        let ratio = original > 0 ? min(1, max(0, Double(compressed) / Double(original))) : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("省下 \(String(format: "%.0f", (1 - ratio) * 100))%")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ratio < 0.9 ? .green : .orange)
                Spacer()
                Text("\(ByteFormatter.string(original)) → \(ByteFormatter.string(compressed))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(Color.green.opacity(0.75))
                        .frame(width: max(4, geo.size.width * ratio))
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: - 逻辑

    private func compress() async {
        guard let cg = source.cgImage else {
            outcome = nil
            previewImage = nil
            return
        }
        isWorking = true
        try? await Task.sleep(nanoseconds: 420_000_000)
        if Task.isCancelled { return }

        let req = request
        let result = await Task.detached(priority: .userInitiated) {
            ImageProcessor.compressed(cg, request: req)
        }.value

        if Task.isCancelled { return }
        isWorking = false
        outcome = result
        previewImage = result.flatMap { ImageCodec.decode(data: $0.data) }
    }

    private func save() {
        guard let cg = source.cgImage,
              let outcome = ImageProcessor.compressed(cg, request: request) else {
            toast = "压缩失败"
            NSSound.beep()
            return
        }
        let fmt = outcome.format
        let name = source.suggestedName(suffix: "compressed", format: fmt)
        if ImageCodec.save(data: outcome.data, suggestedName: name, contentType: fmt.utType) != nil {
            toast = "已保存 \(name)（\(ByteFormatter.string(outcome.data.count))）"
        }
    }

    private func copyImage() {
        guard let previewImage else { return }
        PasteboardWriter.copyImage(ImageCodec.nsImage(from: previewImage))
        toast = "压缩结果已拷贝"
    }
}
