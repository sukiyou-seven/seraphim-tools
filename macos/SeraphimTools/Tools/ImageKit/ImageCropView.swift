import AppKit
import SwiftUI

struct ImageCropView: View {
    @ObservedObject var source: WorkingImage
    @Binding var toast: String?

    /// 归一化裁剪框（0–1），原点在左上角
    @State private var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var aspect: CropAspect = .free
    @State private var resultImage: CGImage?
    @State private var isWorking = false

    private var imageSize: CGSize { source.pixelSize }

    private var imageAspect: CGFloat {
        imageSize.height > 0 ? imageSize.width / imageSize.height : 1
    }

    private struct Key: Equatable {
        var token: UUID
        var crop: String
    }

    private var key: Key {
        Key(
            token: source.token,
            crop: String(format: "%.4f-%.4f-%.4f-%.4f", crop.minX, crop.minY, crop.width, crop.height)
        )
    }

    var body: some View {
        if source.hasImage {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    aspectCard
                    numberCard
                    tipCard
                }
                .frame(width: 300)

                VStack(spacing: 16) {
                    canvasCard
                    resultCard
                }
                .frame(maxWidth: .infinity)
            }
            .padding(20)
            .task(id: source.token) {
                crop = CGRect(x: 0, y: 0, width: 1, height: 1)
                applyAspectPreset()
            }
            .task(id: key) {
                await renderResult()
            }
        } else {
            ImageEmptyHint()
        }
    }

    // MARK: - 左侧控件

    private var aspectCard: some View {
        ToolCard(title: "裁剪比例", systemImage: "aspectratio") {
            FlowRow(spacing: 6) {
                ForEach(CropAspect.allCases) { item in
                    ChipButton(title: item.title, isSelected: aspect == item, minWidth: 42) {
                        aspect = item
                        applyAspectPreset()
                    }
                }
            }
            Text(aspect == .free ? "自由拖拽，任意比例。" : "比例已锁定，拖拽手柄时会保持该比例。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var numberCard: some View {
        ToolCard(title: "精确数值（像素）", systemImage: "number") {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("X").font(.caption).foregroundStyle(.secondary)
                    TextField("X", value: binding(.x), format: .number)
                        .textFieldStyle(.roundedBorder)
                    Text("Y").font(.caption).foregroundStyle(.secondary)
                    TextField("Y", value: binding(.y), format: .number)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("宽").font(.caption).foregroundStyle(.secondary)
                    TextField("宽", value: binding(.width), format: .number)
                        .textFieldStyle(.roundedBorder)
                    Text("高").font(.caption).foregroundStyle(.secondary)
                    TextField("高", value: binding(.height), format: .number)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: 8) {
                Button("重新框选") {
                    crop = CGRect(x: 0, y: 0, width: 1, height: 1)
                    applyAspectPreset()
                }
                .controlSize(.small)
                Button("居中 \(Int(imageSize.width))×\(Int(imageSize.height))") {
                    crop = CGRect(x: 0, y: 0, width: 1, height: 1)
                }
                .controlSize(.small)
            }

            Text("原图 \(Int(imageSize.width)) × \(Int(imageSize.height)) px")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var tipCard: some View {
        ToolCard(title: "操作方式", systemImage: "hand.draw") {
            VStack(alignment: .leading, spacing: 4) {
                Label("框内拖动 = 平移选区", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                Label("拖四角 = 等比/自由缩放", systemImage: "arrow.up.left.and.arrow.down.right")
                Label("拖四边 = 单边调整", systemImage: "arrow.left.and.right")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - 画布

    private var canvasCard: some View {
        ToolCard(title: "选取范围", systemImage: "crop") {
            CropCanvas(
                cgImage: source.previewCGImage(maxDimension: 1600),
                imageSize: imageSize,
                crop: $crop,
                lockedRatio: aspect.ratio(originalSize: imageSize)
            )
            .frame(height: 400)
        }
    }

    private var resultCard: some View {
        ToolCard(title: "裁剪结果", systemImage: "eye") {
            HStack(alignment: .top, spacing: 14) {
                ImagePreviewBox(cgImage: resultImage, maxHeight: 200, placeholder: "—")
                    .frame(maxWidth: 260)

                VStack(alignment: .leading, spacing: 10) {
                    MetricsRow(items: [
                        MetricItem(title: "输出尺寸", value: outputSizeText, tint: .accentColor),
                        MetricItem(title: "占原图", value: areaPercentText),
                    ])
                    ImageExportBar(isEnabled: resultImage != nil) {
                        save()
                    } onCopy: {
                        copyImage()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var outputPixelSize: CGSize {
        CGSize(
            width: max(1, (crop.width * imageSize.width).rounded()),
            height: max(1, (crop.height * imageSize.height).rounded())
        )
    }

    private var outputSizeText: String {
        "\(Int(outputPixelSize.width))×\(Int(outputPixelSize.height))"
    }

    private var areaPercentText: String {
        String(format: "%.0f%%", crop.width * crop.height * 100)
    }

    // MARK: - 数值绑定

    private enum CropField { case x, y, width, height }

    private func binding(_ field: CropField) -> Binding<Double> {
        Binding(
            get: {
                let pixels: CGFloat
                switch field {
                case .x: pixels = crop.minX * imageSize.width
                case .y: pixels = crop.minY * imageSize.height
                case .width: pixels = crop.width * imageSize.width
                case .height: pixels = crop.height * imageSize.height
                }
                return Double(pixels.rounded())
            },
            set: { newValue in
                guard imageSize.width > 0, imageSize.height > 0 else { return }
                var rect = crop
                let ratio = aspect.ratio(originalSize: imageSize)

                switch field {
                case .x:
                    let normalized = CGFloat(newValue) / imageSize.width
                    rect.origin.x = min(max(normalized, 0), max(0, 1 - rect.width))

                case .y:
                    let normalized = CGFloat(newValue) / imageSize.height
                    rect.origin.y = min(max(normalized, 0), max(0, 1 - rect.height))

                case .width:
                    let normalized = CGFloat(newValue) / imageSize.width
                    rect.size.width = min(max(normalized, 0.005), 1 - rect.minX)
                    if let ratio, imageAspect > 0 {
                        rect.size.height = min(rect.width * imageAspect / ratio, 1 - rect.minY)
                    }

                case .height:
                    let normalized = CGFloat(newValue) / imageSize.height
                    rect.size.height = min(max(normalized, 0.005), 1 - rect.minY)
                    if let ratio, imageAspect > 0 {
                        rect.size.width = min(rect.height * ratio / imageAspect, 1 - rect.minX)
                    }
                }

                crop = rect
            }
        )
    }

    private func applyAspectPreset() {
        guard let ratio = aspect.ratio(originalSize: imageSize) else { return }
        let k = imageAspect / ratio

        // 在整图内找最大居中矩形
        var width: CGFloat = 1
        var height = width * k
        if height > 1 {
            height = 1
            width = k > 0 ? height / k : 1
        }
        crop = CGRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
    }

    // MARK: - 逻辑

    private func renderResult() async {
        guard let preview = source.previewCGImage() else {
            resultImage = nil
            return
        }
        isWorking = true
        try? await Task.sleep(nanoseconds: 180_000_000)
        if Task.isCancelled { return }
        resultImage = ImageProcessor.cropped(preview, normalizedRect: crop)
        isWorking = false
    }

    private func save() {
        guard let full = source.cgImage,
              let cropped = ImageProcessor.cropped(full, normalizedRect: crop) else {
            toast = "裁剪失败"
            NSSound.beep()
            return
        }
        let format = source.detectedFormat ?? .png
        let name = source.suggestedName(
            suffix: "cropped-\(Int(cropped.width))x\(Int(cropped.height))",
            format: format
        )
        guard let data = ImageCodec.encode(cropped, format: format) else {
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
              let cropped = ImageProcessor.cropped(full, normalizedRect: crop) else { return }
        PasteboardWriter.copyImage(ImageCodec.nsImage(from: cropped))
        toast = "裁剪结果已拷贝"
    }
}

// MARK: - 交互式裁剪画布

private enum CropHandle {
    case move, topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return true
        default: return false
        }
    }
}

private struct HandleDot: Identifiable {
    let id: Int
    let position: CGPoint
}

private struct CropCanvas: View {
    let cgImage: CGImage?
    let imageSize: CGSize
    @Binding var crop: CGRect
    let lockedRatio: CGFloat?

    @State private var dragStart: CGRect?
    @State private var activeHandle: CropHandle = .move
    @State private var fittedRect: CGRect = .zero

    private let handleSize: CGFloat = 11
    private let hitSlop: CGFloat = 16
    private let minSize: CGFloat = 0.02

    var body: some View {
        GeometryReader { geo in
            let fitted = Self.fittedRect(imageSize: imageSize, in: geo.size)

            ZStack(alignment: .topLeading) {
                Color.black
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                if let cgImage {
                    Image(decorative: cgImage, scale: 1)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                }

                // 选区外压暗
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geo.size))
                    path.addRect(pixelRect(in: fitted))
                }
                .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))

                // 三分线
                thirds(in: pixelRect(in: fitted))
                    .stroke(Color.white.opacity(0.28), lineWidth: 0.5)

                // 边框
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.95), lineWidth: 1.5)
                    .frame(width: pixelRect(in: fitted).width, height: pixelRect(in: fitted).height)
                    .offset(x: pixelRect(in: fitted).minX, y: pixelRect(in: fitted).minY)

                // 手柄
                ForEach(handlePositions(in: pixelRect(in: fitted))) { dot in
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: handleSize, height: handleSize)
                        .overlay(Rectangle().strokeBorder(Color.black.opacity(0.35)))
                        .position(dot.position)
                }

                // 尺寸角标
                Text("\(Int(outputSize.width)) × \(Int(outputSize.height))")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .position(
                        x: min(max(pixelRect(in: fitted).midX, 46), geo.size.width - 46),
                        y: max(pixelRect(in: fitted).minY - 14, 12)
                    )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStart == nil {
                            fittedRect = fitted
                            dragStart = crop
                            activeHandle = handle(at: value.startLocation, in: fitted)
                        }
                        guard let start = dragStart else { return }
                        crop = apply(
                            handle: activeHandle,
                            start: start,
                            translation: value.translation,
                            fitted: fitted
                        )
                    }
                    .onEnded { _ in
                        dragStart = nil
                    }
            )
            .onAppear { fittedRect = fitted }
        }
    }

    private var outputSize: CGSize {
        CGSize(
            width: max(1, (crop.width * imageSize.width).rounded()),
            height: max(1, (crop.height * imageSize.height).rounded())
        )
    }

    // MARK: 坐标换算

    private static func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              container.width > 0, container.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: (container.width - width) / 2,
            y: (container.height - height) / 2,
            width: width,
            height: height
        )
    }

    private func pixelRect(in fitted: CGRect) -> CGRect {
        CGRect(
            x: fitted.minX + crop.minX * fitted.width,
            y: fitted.minY + crop.minY * fitted.height,
            width: crop.width * fitted.width,
            height: crop.height * fitted.height
        )
    }

    private func handlePositions(in rect: CGRect) -> [HandleDot] {
        let points: [CGPoint] = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.midY),
        ]
        return points.enumerated().map { HandleDot(id: $0.offset, position: $0.element) }
    }

    private func thirds(in rect: CGRect) -> Path {
        Path { path in
            for i in 1...2 {
                let x = rect.minX + rect.width * CGFloat(i) / 3
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))

                let y = rect.minY + rect.height * CGFloat(i) / 3
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }
    }

    private func handle(at point: CGPoint, in fitted: CGRect) -> CropHandle {
        let rect = pixelRect(in: fitted)
        let nearLeft = abs(point.x - rect.minX) <= hitSlop
        let nearRight = abs(point.x - rect.maxX) <= hitSlop
        let nearTop = abs(point.y - rect.minY) <= hitSlop
        let nearBottom = abs(point.y - rect.maxY) <= hitSlop
        let withinX = point.x >= rect.minX - hitSlop && point.x <= rect.maxX + hitSlop
        let withinY = point.y >= rect.minY - hitSlop && point.y <= rect.maxY + hitSlop

        if nearLeft && nearTop { return .topLeft }
        if nearRight && nearTop { return .topRight }
        if nearRight && nearBottom { return .bottomRight }
        if nearLeft && nearBottom { return .bottomLeft }
        if nearTop && withinX { return .top }
        if nearBottom && withinX { return .bottom }
        if nearLeft && withinY { return .left }
        if nearRight && withinY { return .right }
        return .move
    }

    // MARK: 拖拽计算

    private func apply(handle: CropHandle,
                       start: CGRect,
                       translation: CGSize,
                       fitted: CGRect) -> CGRect {
        guard fitted.width > 0, fitted.height > 0 else { return start }
        let dx = translation.width / fitted.width
        let dy = translation.height / fitted.height

        if handle == .move {
            return CGRect(
                x: min(max(start.minX + dx, 0), 1 - start.width),
                y: min(max(start.minY + dy, 0), 1 - start.height),
                width: start.width,
                height: start.height
            )
        }

        guard let ratio = lockedRatio, imageSize.width > 0, imageSize.height > 0 else {
            return freeform(handle: handle, start: start, dx: dx, dy: dy)
        }

        let k = (imageSize.width / imageSize.height) / ratio
        return locked(handle: handle, start: start, dx: dx, dy: dy, k: k)
    }

    /// 自由比例：各自独立改变四条边
    private func freeform(handle: CropHandle, start: CGRect, dx: CGFloat, dy: CGFloat) -> CGRect {
        var minX = start.minX
        var minY = start.minY
        var maxX = start.maxX
        var maxY = start.maxY

        switch handle {
        case .top, .topLeft, .topRight: minY += dy
        case .bottom, .bottomLeft, .bottomRight: maxY += dy
        default: break
        }
        switch handle {
        case .left, .topLeft, .bottomLeft: minX += dx
        case .right, .topRight, .bottomRight: maxX += dx
        default: break
        }

        minX = min(max(minX, 0), 1)
        maxX = min(max(maxX, 0), 1)
        minY = min(max(minY, 0), 1)
        maxY = min(max(maxY, 0), 1)

        if maxX - minX < minSize {
            if handle == .left || handle == .topLeft || handle == .bottomLeft {
                minX = maxX - minSize
            } else {
                maxX = minX + minSize
            }
        }
        if maxY - minY < minSize {
            if handle == .top || handle == .topLeft || handle == .topRight {
                minY = maxY - minSize
            } else {
                maxY = minY + minSize
            }
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// 锁定比例：一个方向驱动，另一个方向按 k 推导，锚点跟着手柄走
    private func locked(handle: CropHandle, start: CGRect, dx: CGFloat, dy: CGFloat, k: CGFloat) -> CGRect {
        var width = start.width
        var height = start.height

        switch handle {
        case .left, .topLeft, .bottomLeft:
            width = start.maxX - (start.minX + dx)
        case .right, .topRight, .bottomRight:
            width = (start.maxX + dx) - start.minX
        case .top:
            height = start.maxY - (start.minY + dy)
        case .bottom:
            height = (start.maxY + dy) - start.minY
        default:
            break
        }

        // 竖直方向手柄驱动宽度，其余由宽度驱动高度
        if handle == .top || handle == .bottom {
            width = k > 0 ? height / k : width
        } else {
            height = width * k
        }

        // 限制在画布内
        if width > 1 { width = 1; height = width * k }
        if height > 1 { height = 1; width = k > 0 ? height / k : width }
        if width < minSize { width = minSize; height = width * k }
        if height < minSize { height = minSize; width = k > 0 ? height / k : width }

        var minX: CGFloat
        var minY: CGFloat

        switch handle {
        case .left, .topLeft, .bottomLeft:
            minX = start.maxX - width
        default:
            minX = start.minX
        }
        if handle == .top || handle == .bottom {
            minX = start.midX - width / 2
        }

        switch handle {
        case .top, .topLeft, .topRight:
            minY = start.maxY - height
        case .left, .right:
            minY = start.midY - height / 2
        default:
            minY = start.minY
        }

        minX = min(max(minX, 0), max(0, 1 - width))
        minY = min(max(minY, 0), max(0, 1 - height))

        return CGRect(x: minX, y: minY, width: width, height: height)
    }
}
