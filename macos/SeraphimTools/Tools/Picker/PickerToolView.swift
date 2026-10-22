import AppKit
import SwiftUI

/// 屏幕取色：系统吸管 + 截屏放大精确取色。
struct PickerToolView: View {
    @AppStorage("pickerStored") private var storedHex = "#C9A227"
    @AppStorage("pickerHistory") private var historyRaw = ""
    @AppStorage("pickerAutoCopy") private var autoCopy = true

    @State private var color = RGBAColor(r255: 201, g255: 162, b255: 39)
    @State private var sampler = NSColorSampler()

    @State private var screenImage: CGImage?
    @State private var screenBuffer: PixelBuffer?
    @State private var screenScale: CGFloat = 1
    @State private var grabbing = false
    @State private var grabNote: String?

    @State private var didLoad = false
    @State private var toast: String?

    private var history: [String] {
        historyRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                grabCard
                currentCard
                historyCard
                paletteCard
            }
            .padding(20)
        }
        .toast($toast)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let parsed = ColorEngine.parse(storedHex) { color = parsed }
        }
        .onChange(of: color) { _, newValue in
            storedHex = ColorEngine.string(for: newValue, format: .hex)
        }
    }

    // MARK: - 取色

    private var grabCard: some View {
        ToolCard(title: "屏幕取色", systemImage: "eyedropper.halffull") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Button {
                        pickWithSampler()
                    } label: {
                        Label("系统吸管取色", systemImage: "eyedropper")
                            .font(.system(size: 12))
                    }
                    .controlSize(.regular)
                    .help("系统自带的取色器，带放大镜和像素网格，不需要任何权限")

                    Button {
                        captureScreen()
                    } label: {
                        Label(grabbing ? "正在截屏…" : (screenImage == nil ? "截屏放大取色" : "重新截屏"), systemImage: "viewfinder")
                            .font(.system(size: 12))
                    }
                    .controlSize(.regular)
                    .disabled(grabbing)

                    if screenImage != nil {
                        Button {
                            clearScreen()
                        } label: {
                            Text("清掉截图").font(.system(size: 11.5))
                        }
                        .controlSize(.small)
                    }

                    Spacer(minLength: 0)

                    Toggle("取到就复制", isOn: $autoCopy)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11.5))
                }

                Text("系统吸管走 macOS 自带界面，随手就能用；截屏放大可以在工具里对着像素精确挑，取完可以反复点。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)

                if let grabNote {
                    ErrorBanner(message: grabNote)
                }

                if let screenImage, let screenBuffer {
                    ScreenPickCanvas(
                        image: screenImage,
                        buffer: screenBuffer,
                        scale: screenScale
                    ) { picked, _ in
                        apply(picked)
                    }
                }
            }
        }
    }

    // MARK: - 当前颜色

    private var currentCard: some View {
        ToolCard(title: "当前颜色", systemImage: "paintpalette") {
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 8) {
                    ZStack {
                        Checkerboard(square: 8)
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(swiftUIColor(color))
                    }
                    .frame(width: 118, height: 118)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12))
                    )

                    Text(ColorEngine.string(for: color, format: .hex))
                        .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                        .textSelection(.enabled)

                    if let nearest = ColorNameTable.nearestName(for: color) {
                        Text("接近 \(nearest.name)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(ColorEditorFormats) { format in
                        let value = ColorEngine.string(for: color, format: format)
                        HStack(spacing: 10) {
                            Text(format.title)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .frame(width: 118, alignment: .leading)
                            Text(value)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 6)
                            CopyIconButton(text: value)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                    }

                    HStack(spacing: 10) {
                        Button {
                            remember(color)
                            toast = "已记入调色板"
                        } label: {
                            Label("记住这个颜色", systemImage: "bookmark")
                                .font(.system(size: 11.5))
                        }
                        .controlSize(.small)

                        ColorPicker("", selection: colorBinding)
                            .labelsHidden()
                            .help("也可以手动微调")

                        Spacer(minLength: 0)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private let ColorEditorFormats: [ColorOutputFormat] = [
        .hex, .hexAlpha, .rgb, .hsl, .hsv, .cmyk, .swiftUI, .cssVariable,
    ]

    private var colorBinding: Binding<Color> {
        Binding(
            get: { swiftUIColor(color) },
            set: { newValue in
                let nsColor = NSColor(newValue).usingColorSpace(.sRGB) ?? .white
                color = RGBAColor(
                    red: Double(nsColor.redComponent),
                    green: Double(nsColor.greenComponent),
                    blue: Double(nsColor.blueComponent),
                    alpha: Double(nsColor.alphaComponent)
                )
            }
        )
    }

    // MARK: - 历史

    private var historyCard: some View {
        ToolCard(title: "取色历史", systemImage: "clock.arrow.circlepath") {
            if history.isEmpty {
                Text("还没取过色")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    FlowRow(spacing: 6) {
                        ForEach(history, id: \.self) { hex in
                            historySwatch(hex)
                        }
                    }

                    HStack(spacing: 10) {
                        Button("清空") { historyRaw = "" }
                            .controlSize(.small)
                            .font(.system(size: 11))
                        Button("复制全部") {
                            NSPasteboard.copyString(history.joined(separator: "\n"))
                            toast = "已复制 \(history.count) 个色值"
                        }
                        .controlSize(.small)
                        .font(.system(size: 11))
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func historySwatch(_ hex: String) -> some View {
        let parsed = ColorEngine.parse(hex) ?? RGBAColor(red: 0.5, green: 0.5, blue: 0.5)
        return Button {
            color = parsed
            toast = "回到 \(hex)"
        } label: {
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(swiftUIColor(parsed))
                    .frame(width: 44, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.14))
                    )
                Text(hex.replacingOccurrences(of: "#", with: ""))
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .help(hex)
    }

    // MARK: - 配色建议

    private var paletteCard: some View {
        ToolCard(title: "配色建议", systemImage: "square.grid.2x2") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                ForEach(Array(ColorEngine.palette(from: color).enumerated()), id: \.offset) { _, item in
                    Button {
                        color = item.1
                    } label: {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(swiftUIColor(item.1))
                                .frame(height: 38)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.10))
                                )
                            Text(item.0)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(ColorEngine.string(for: item.1, format: .hex))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 动作

    private func pickWithSampler() {
        sampler.show { picked in
            DispatchQueue.main.async {
                guard let picked else { return }
                let nsColor = picked.usingColorSpace(.sRGB) ?? picked
                let newColor = RGBAColor(
                    red: Double(nsColor.redComponent),
                    green: Double(nsColor.greenComponent),
                    blue: Double(nsColor.blueComponent),
                    alpha: Double(nsColor.alphaComponent)
                )
                apply(newColor)
            }
        }
    }

    private func captureScreen() {
        if !ScreenGrabber.hasPermission {
            grabNote = "「截屏放大取色」需要屏幕录制权限：已经帮你弹了授权请求，允许之后回到这里再点一次。如果没看到弹窗，可以去「系统设置 → 隐私与安全性 → 屏幕录制」里手动打开。"
            ScreenGrabber.requestPermission()
            return
        }

        grabbing = true
        grabNote = nil
        Task {
            do {
                let result = try await ScreenGrabber.grab()
                await MainActor.run {
                    screenImage = result.image
                    screenBuffer = PixelBuffer(cgImage: result.image)
                    screenScale = result.scale
                    grabbing = false
                    if screenBuffer == nil {
                        grabNote = "截图太大，内存里铺不开，换个小一点的显示器缩放试试"
                    }
                }
            } catch {
                await MainActor.run {
                    grabbing = false
                    grabNote = "截屏失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func clearScreen() {
        screenImage = nil
        screenBuffer = nil
        grabNote = nil
    }

    private func apply(_ newColor: RGBAColor) {
        color = newColor
        remember(newColor)
        let hex = ColorEngine.string(for: newColor, format: .hex)
        if autoCopy {
            NSPasteboard.copyString(hex)
            toast = "\(hex) 已复制"
        } else {
            toast = "取到 \(hex)"
        }
    }

    private func remember(_ newColor: RGBAColor) {
        let hex = ColorEngine.string(for: newColor, format: .hex)
        var list = history.filter { $0.uppercased() != hex.uppercased() }
        list.insert(hex, at: 0)
        historyRaw = list.prefix(24).joined(separator: ",")
    }
}

// MARK: - 截屏取色画布

private struct ScreenPickCanvas: View {
    let image: CGImage
    let buffer: PixelBuffer
    let scale: CGFloat
    var onPick: (RGBAColor, CGPoint) -> Void

    @State private var hoverPoint: CGPoint?
    @State private var hoverPixel: (x: Int, y: Int)?
    @State private var hoverColor: RGBAColor?

    private let grid = 15
    private let cell: CGFloat = 11

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Image(nsImage: ImageCodec.nsImage(from: image))
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geometry.size.width, height: geometry.size.height)

                if let hoverPixel, let hoverColor {
                    magnifier(pixel: hoverPixel, color: hoverColor)
                        .position(
                            x: min(max(CGFloat(hoverPoint?.x ?? 0), cell * CGFloat(grid) / 2 + 6),
                                   max(geometry.size.width - cell * CGFloat(grid) / 2 - 6, cell * CGFloat(grid) / 2 + 6)),
                            y: cell * CGFloat(grid) / 2 + 10
                        )
                }

                hitLayer(in: geometry.size)
            }
        }
        .frame(height: 340)
        .background(Checkerboard(square: 8))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10))
        )
    }

    /// 放大镜：把光标周围那一片像素铺成格子，中间那格就是取色点
    private func magnifier(pixel: (x: Int, y: Int), color: RGBAColor) -> some View {
        let half = grid / 2
        return VStack(spacing: 4) {
            Canvas { context, _ in
                for row in 0..<grid {
                    for col in 0..<grid {
                        let x = pixel.x - half + col
                        let y = pixel.y - half + row
                        let rect = CGRect(
                            x: CGFloat(col) * cell,
                            y: CGFloat(row) * cell,
                            width: cell,
                            height: cell
                        )
                        if let value = buffer.color(x: x, y: y) {
                            context.fill(Path(rect), with: .color(swiftUIColor(value)))
                        } else {
                            context.fill(Path(rect), with: .color(Color.black.opacity(0.25)))
                        }
                    }
                }

                let center = CGRect(
                    x: CGFloat(half) * cell,
                    y: CGFloat(half) * cell,
                    width: cell,
                    height: cell
                )
                context.stroke(Path(center), with: .color(.white), lineWidth: 2)
                context.stroke(
                    Path(center.insetBy(dx: -1.5, dy: -1.5)),
                    with: .color(.black.opacity(0.55)),
                    lineWidth: 1
                )
            }
            .frame(width: cell * CGFloat(grid), height: cell * CGFloat(grid))

            HStack(spacing: 6) {
                Text(ColorEngine.string(for: color, format: .hex))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                Text("屏幕 \(Int(CGFloat(pixel.x) / max(scale, 0.01))), \(Int(CGFloat(pixel.y) / max(scale, 0.01)))")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.16))
        )
        .shadow(radius: 6, y: 2)
        .allowsHitTesting(false)
    }

    private func hitLayer(in size: CGSize) -> some View {
        let fitted = PixelBuffer.fittedRect(imageSize: buffer.displaySize, in: size)
        return Color.clear
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverPoint = location
                    if let pixel = pixel(at: location, fitted: fitted) {
                        hoverPixel = pixel
                        hoverColor = buffer.color(x: pixel.x, y: pixel.y)
                    } else {
                        hoverPixel = nil
                        hoverColor = nil
                    }
                case .ended:
                    hoverPoint = nil
                    hoverPixel = nil
                    hoverColor = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard let pixel = pixel(at: value.location, fitted: fitted),
                              let picked = buffer.color(x: pixel.x, y: pixel.y) else { return }
                        onPick(picked, value.location)
                    }
            )
    }

    private func pixel(at point: CGPoint, fitted: CGRect) -> (x: Int, y: Int)? {
        guard fitted.width > 0, fitted.height > 0, fitted.contains(point) else { return nil }
        let unitX = (point.x - fitted.minX) / fitted.width
        let unitY = (point.y - fitted.minY) / fitted.height
        return (
            x: Int(unitX * CGFloat(buffer.width)),
            y: Int(unitY * CGFloat(buffer.height))
        )
    }
}
