import AppKit
import SwiftUI

// MARK: - 预览框

/// 统一的图片预览：自动适配宽高、透明区域棋盘格背景
struct ImagePreviewBox: View {
    let cgImage: CGImage?
    var maxHeight: CGFloat = 320
    var showCheckerboard: Bool = true
    var placeholder: String = "暂无预览"

    var body: some View {
        ZStack {
            if let cgImage {
                ZStack {
                    if showCheckerboard {
                        Checkerboard()
                    }
                    Image(decorative: cgImage, scale: 1)
                        .resizable()
                        .interpolation(.high)
                }
                .aspectRatio(
                    CGFloat(cgImage.width) / CGFloat(max(1, cgImage.height)),
                    contentMode: .fit
                )
                .frame(maxWidth: .infinity, maxHeight: maxHeight)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 30))
                        .foregroundStyle(.quaternary)
                    Text(placeholder)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180, maxHeight: maxHeight)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10))
        )
    }
}

// MARK: - 指标展示

struct MetricItem: Identifiable {
    let id = UUID()
    var title: String
    var value: String
    var tint: Color = .primary
}

struct MetricsRow: View {
    let items: [MetricItem]

    var body: some View {
        FlowRow(spacing: 10) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(item.value)
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(item.tint)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

// MARK: - 来源信息栏

struct ImageSourceBar: View {
    @ObservedObject var source: WorkingImage
    var onPaste: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 2) {
                Text(source.hasImage ? source.displayName : "还没有选择图片")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(metaText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button {
                if let url = ImageCodec.pickImageURL() { source.load(url: url) }
            } label: {
                Label("选择图片", systemImage: "folder")
            }
            .controlSize(.small)

            Button {
                onPaste()
            } label: {
                Label("剪贴板", systemImage: "doc.on.clipboard")
            }
            .controlSize(.small)

            Button {
                source.clear()
            } label: {
                Image(systemName: "xmark.circle")
            }
            .controlSize(.small)
            .help("清空当前图片")
            .disabled(!source.hasImage)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }

    private var thumbnail: some View {
        ZStack {
            if let cg = source.previewCGImage(maxDimension: 120) {
                Checkerboard(square: 5)
                Image(decorative: cg, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10))
        )
    }

    private var metaText: String {
        guard source.hasImage else { return "支持拖放图片到窗口任意位置" }
        let size = source.pixelSize
        var parts = ["\(Int(size.width)) × \(Int(size.height))"]
        if let format = source.detectedFormat { parts.append(format.title) }
        if let bytes = source.byteSize { parts.append(ByteFormatter.string(bytes)) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 导出按钮组

struct ImageExportBar: View {
    var saveTitle: String = "保存"
    var isEnabled: Bool
    var onSave: () -> Void
    var onCopy: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                onSave()
            } label: {
                Label(saveTitle, systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!isEnabled)

            Button {
                onCopy()
            } label: {
                Label("拷贝图像", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!isEnabled)
        }
    }
}

// MARK: - 空状态

struct ImageEmptyHint: View {
    var text: String = "先在上面选一张图片，或直接把图片拖进来"

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 38))
                .foregroundStyle(.quaternary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
