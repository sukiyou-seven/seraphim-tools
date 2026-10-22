import AppKit
import SwiftUI

struct ImageResizeView: View {
    @ObservedObject var source: WorkingImage
    @Binding var toast: String?

    @State private var width: Double = 1000
    @State private var height: Double = 1000
    @State private var lockAspect = true
    @State private var quality: ResizeQuality = .high
    @State private var preventUpscale = false
    @State private var isSyncing = false

    @State private var previewImage: CGImage?
    @State private var isWorking = false

    private struct Key: Equatable {
        var token: UUID
        var width: Int
        var height: Int
        var quality: String
    }

    private var key: Key {
        Key(token: source.token, width: Int(width.rounded()), height: Int(height.rounded()), quality: quality.rawValue)
    }

    private var originalSize: CGSize { source.pixelSize }

    private var aspectRatio: CGFloat {
        originalSize.height > 0 ? originalSize.width / originalSize.height : 1
    }

    /// 实际会输出的尺寸（考虑"不放大"限制）
    private var effectiveSize: CGSize {
        var target = CGSize(width: max(1, width.rounded()), height: max(1, height.rounded()))
        if preventUpscale {
            target.width = min(target.width, max(1, originalSize.width))
            target.height = min(target.height, max(1, originalSize.height))
        }
        return target
    }

    var body: some View {
        if source.hasImage {
            ImagePaneLayout {
                sizeCard
                presetCard
                qualityCard
            } preview: {
                resultCard
            }
            .task(id: source.token) {
                width = max(1, originalSize.width.rounded())
                height = max(1, originalSize.height.rounded())
            }
            .task(id: key) {
                await renderPreview()
            }
            .onChange(of: width) { _, newValue in
                guard lockAspect, !isSyncing, aspectRatio > 0 else { return }
                isSyncing = true
                height = max(1, (newValue / aspectRatio).rounded())
                isSyncing = false
            }
            .onChange(of: height) { _, newValue in
                guard lockAspect, !isSyncing, aspectRatio > 0 else { return }
                isSyncing = true
                width = max(1, (newValue * aspectRatio).rounded())
                isSyncing = false
            }
        } else {
            ImageEmptyHint()
        }
    }

    // MARK: - 控件

    private var sizeCard: some View {
        ToolCard(title: "目标尺寸", systemImage: "ruler") {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("宽度").font(.caption).foregroundStyle(.secondary)
                    TextField("宽", value: $width, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 92)
                }
                Button {
                    lockAspect.toggle()
                    if lockAspect {
                        height = max(1, (width / aspectRatio).rounded())
                    }
                } label: {
                    Image(systemName: lockAspect ? "lock.fill" : "lock.open")
                        .foregroundStyle(lockAspect ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help(lockAspect ? "已锁定宽高比" : "宽高比自由")
                .padding(.top, 14)

                VStack(alignment: .leading, spacing: 3) {
                    Text("高度").font(.caption).foregroundStyle(.secondary)
                    TextField("高", value: $height, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 92)
                }
            }

            Toggle("不放大（超出原图尺寸时按原图）", isOn: $preventUpscale)
                .font(.caption)

            Text("原图 \(Int(originalSize.width)) × \(Int(originalSize.height)) px")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var presetCard: some View {
        ToolCard(title: "快捷比例", systemImage: "square.resize") {
            Text("按百分比")
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowRow(spacing: 6) {
                ForEach([25.0, 50.0, 75.0, 100.0, 150.0, 200.0], id: \.self) { percent in
                    ChipButton(
                        title: "\(Int(percent))%",
                        isSelected: isPercentSelected(percent)
                    ) {
                        width = max(1, (originalSize.width * percent / 100).rounded())
                        height = max(1, (originalSize.height * percent / 100).rounded())
                    }
                }
            }

            Text("按长边")
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowRow(spacing: 6) {
                ForEach([640.0, 800.0, 1280.0, 1920.0, 2560.0, 3840.0], id: \.self) { longEdge in
                    ChipButton(
                        title: "\(Int(longEdge))",
                        isSelected: abs(max(width, height) - longEdge) < 1
                    ) {
                        let longest = max(originalSize.width, originalSize.height)
                        guard longest > 0 else { return }
                        let scale = longEdge / longest
                        width = max(1, (originalSize.width * scale).rounded())
                        height = max(1, (originalSize.height * scale).rounded())
                    }
                }
            }
        }
    }

    private var qualityCard: some View {
        ToolCard(title: "缩放算法", systemImage: "wand.and.stars") {
            HStack(spacing: 6) {
                ForEach(ResizeQuality.allCases) { item in
                    ChipButton(title: item.title, isSelected: quality == item, minWidth: 72) {
                        quality = item
                    }
                }
            }
            Text(quality == .none
                 ? "锐利像素：不做插值，放大时保留硬边（像素画、截图放大用）。"
                 : "缩小图片建议用「高质量」，边缘更干净。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 结果

    private var resultCard: some View {
        ToolCard(title: "预览（按比例显示）", systemImage: "eye") {
            ZStack {
                ImagePreviewBox(cgImage: previewImage, maxHeight: 300, placeholder: isWorking ? "处理中…" : "无法预览")
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                        .background(.regularMaterial, in: Circle())
                }
            }

            MetricsRow(items: [
                MetricItem(title: "原尺寸", value: "\(Int(originalSize.width))×\(Int(originalSize.height))"),
                MetricItem(title: "新尺寸", value: "\(Int(effectiveSize.width))×\(Int(effectiveSize.height))", tint: .accentColor),
                MetricItem(title: "倍数", value: percentText),
            ])

            ImageExportBar(isEnabled: previewImage != nil) {
                save()
            } onCopy: {
                copyImage()
            }
        }
    }

    private var percentText: String {
        guard originalSize.width > 0 else { return "—" }
        let ratio = effectiveSize.width / originalSize.width * 100
        return String(format: "%.0f%%", ratio)
    }

    private func isPercentSelected(_ percent: Double) -> Bool {
        guard originalSize.width > 0 else { return false }
        return abs(width - (originalSize.width * percent / 100).rounded()) < 1
    }

    // MARK: - 逻辑

    private func renderPreview() async {
        guard let preview = source.previewCGImage() else {
            previewImage = nil
            return
        }
        isWorking = true
        try? await Task.sleep(nanoseconds: 120_000_000)
        if Task.isCancelled { return }

        let scale = source.previewScale()
        let target = CGSize(
            width: max(1, effectiveSize.width * scale),
            height: max(1, effectiveSize.height * scale)
        )
        let q = quality
        previewImage = ImageProcessor.resized(preview, to: target, quality: q)
        isWorking = false
    }

    private func save() {
        guard let full = source.cgImage,
              let result = ImageProcessor.resized(full, to: effectiveSize, quality: quality) else {
            toast = "缩放失败"
            NSSound.beep()
            return
        }
        let format = source.detectedFormat ?? .png
        let name = source.suggestedName(suffix: "\(Int(effectiveSize.width))x\(Int(effectiveSize.height))", format: format)
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
              let result = ImageProcessor.resized(full, to: effectiveSize, quality: quality) else { return }
        PasteboardWriter.copyImage(ImageCodec.nsImage(from: result))
        toast = "缩放结果已拷贝"
    }
}
