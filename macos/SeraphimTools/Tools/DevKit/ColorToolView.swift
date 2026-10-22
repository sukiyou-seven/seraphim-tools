import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 颜色工具：任意格式互转 + 屏幕吸管 + 从图片取色 + 对比度体检。
struct ColorToolView: View {
    @AppStorage("colorStored") private var storedHex = "#C9A227"
    @AppStorage("colorHistory") private var historyRaw = ""

    @State private var color = RGBAColor(r255: 201, g255: 162, b255: 39)
    @State private var inputText = "#C9A227"
    @State private var inputInvalid = false
    @State private var didLoad = false

    @State private var sampler = NSColorSampler()
    @State private var toast: String?

    private var history: [String] {
        historyRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                pickerCard
                outputCard
                contrastCard
                paletteCard
                PixelSamplerCard { picked in
                    apply(picked, remember: true)
                    toast = "取到 \(ColorEngine.string(for: picked, format: .hex))"
                }
            }
            .padding(20)
        }
        .toast($toast)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let parsed = ColorEngine.parse(storedHex) {
                color = parsed
                inputText = ColorEngine.string(for: parsed, format: .hex)
            }
        }
        .onChange(of: color) { _, newValue in
            storedHex = ColorEngine.string(for: newValue, format: .hex)
            let text = ColorEngine.string(for: newValue, format: .hex)
            if inputText.uppercased() != text.uppercased() { inputText = text }
        }
    }

    // MARK: - 取色

    private var pickerCard: some View {
        ToolCard(title: "颜色", systemImage: "paintpalette") {
            HStack(alignment: .top, spacing: 16) {
                swatch

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        TextField("#RRGGBB / rgb() / hsl() / 颜色名", text: $inputText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12.5, design: .monospaced))
                            .frame(maxWidth: 260)
                            .onSubmit { applyInput() }
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(inputInvalid ? Color.orange : Color.clear)
                            )

                        Button {
                            applyInput()
                        } label: {
                            Text("应用").font(.system(size: 11.5))
                        }
                        .controlSize(.small)

                        Button {
                            pickFromScreen()
                        } label: {
                            Label("吸管", systemImage: "eyedropper")
                                .font(.system(size: 11.5))
                        }
                        .controlSize(.small)
                        .help("从屏幕任意位置吸取颜色")

                        HStack(spacing: 6) {
                            Text("色盘")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                            ColorPicker("", selection: colorBinding)
                                .labelsHidden()
                        }

                        Spacer(minLength: 0)
                    }

                    channelSlider(title: "R", value: $color.red, tint: .red)
                    channelSlider(title: "G", value: $color.green, tint: .green)
                    channelSlider(title: "B", value: $color.blue, tint: .blue)
                    channelSlider(title: "A", value: $color.alpha, tint: .gray)

                    HStack(spacing: 8) {
                        Button {
                            apply(color, remember: true)
                            toast = "已记入调色板"
                        } label: {
                            Label("记住这个颜色", systemImage: "bookmark")
                                .font(.system(size: 11.5))
                        }
                        .controlSize(.small)

                        if let nearest = ColorNameTable.nearestName(for: color) {
                            Text("最接近的命名色：\(nearest.name)")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                        }

                        if let traditional = ChineseColorTable.nearest(to: color, limit: 1).first {
                            Text("传统色：\(traditional.entry.name) \(traditional.entry.hex.uppercased())")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var swatch: some View {
        VStack(spacing: 8) {
            ZStack {
                Checkerboard(square: 8)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(swiftUIColor(color))
            }
            .frame(width: 132, height: 132)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12))
            )

            Text(ColorEngine.string(for: color, format: .hex))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .textSelection(.enabled)

            Text(color.alpha < 0.999 ? "半透明 \(Int((color.alpha * 100).rounded()))%" : "不透明")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private func channelSlider(title: String, value: Binding<Double>, tint: Color) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 12, alignment: .leading)

            Slider(value: value, in: 0...1)
                .controlSize(.small)

            Text(String(format: "%.3f", value.wrappedValue))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)

            Text("\(Int((value.wrappedValue * 255).rounded()))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 30, alignment: .trailing)
        }
    }

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

    // MARK: - 色值输出

    private var outputCard: some View {
        ToolCard(title: "色值", systemImage: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(["标准表示", "代码", "样式"], id: \.self) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)

                        ForEach(ColorOutputFormat.allCases.filter { $0.group == group }) { format in
                            let value = ColorEngine.string(for: color, format: format)
                            HStack(spacing: 10) {
                                Text(format.title)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 132, alignment: .leading)
                                Text(value)
                                    .font(.system(size: 12, design: .monospaced))
                                    .textSelection(.enabled)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 6)
                                CopyIconButton(text: value)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - 对比度

    private var contrastCard: some View {
        ToolCard(title: "可访问性对比度", systemImage: "eye") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    contrastSample(background: .white, label: "白底")
                    contrastSample(background: RGBAColor(red: 0, green: 0, blue: 0), label: "黑底")
                    Spacer(minLength: 0)
                }

                Text("WCAG 要求：正文 ≥ 4.5（AA）/ 7.0（AAA），大号字 ≥ 3.0（AA）/ 4.5（AAA）")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                HStack(spacing: 12) {
                    Text("当前颜色在黑底上的前景色建议")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(ColorEngine.string(for: color, format: .hex))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text("→")
                        .foregroundStyle(.tertiary)
                    Text(ColorEngine.string(for: ColorEngine.readableForeground(on: color), format: .hex))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func contrastSample(background: RGBAColor, label: String) -> some View {
        let ratio = ColorEngine.contrast(color, background)
        let passesAA = ratio >= 4.5
        let passesAAA = ratio >= 7
        let foreground = ColorEngine.readableForeground(on: background)

        return VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("示例正文 14px")
                    .font(.system(size: 14))
                    .foregroundStyle(swiftUIColor(color))
                Text("大字标题 22px")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(swiftUIColor(color))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(swiftUIColor(background), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10))
            )

            HStack(spacing: 8) {
                Text(String(format: "对比度 %.2f", ratio))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                NoticeTag(
                    text: passesAAA ? "AAA" : (passesAA ? "AA" : "不达标"),
                    systemImage: passesAAA ? "checkmark.seal.fill" : (passesAA ? "checkmark.circle" : "exclamationmark.triangle"),
                    tint: passesAAA ? .green : (passesAA ? .accentColor : .orange)
                )
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)

            Text("在此背景上更清楚的前景色：\(ColorEngine.string(for: foreground, format: .hex))")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
    }

    // MARK: - 配色

    private var paletteCard: some View {
        ToolCard(title: "配色建议与调色板", systemImage: "square.grid.2x2") {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                    ForEach(Array(ColorEngine.palette(from: color).enumerated()), id: \.offset) { _, item in
                        Button {
                            apply(item.1, remember: false)
                        } label: {
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(swiftUIColor(item.1))
                                    .frame(height: 40)
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

                if !history.isEmpty {
                    Divider()
                    HStack(spacing: 6) {
                        Text("最近用过")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                        Spacer()
                        Button("清空") { historyRaw = "" }
                            .controlSize(.small)
                            .font(.system(size: 10))
                    }
                    FlowRow(spacing: 6) {
                        ForEach(history, id: \.self) { hex in
                            Button {
                                if let parsed = ColorEngine.parse(hex) {
                                    color = parsed
                                    inputText = ColorEngine.string(for: parsed, format: .hex)
                                }
                            } label: {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(swiftUIColor(ColorEngine.parse(hex) ?? .init(red: 0.5, green: 0.5, blue: 0.5)))
                                    .frame(width: 34, height: 26)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .strokeBorder(Color.primary.opacity(0.14))
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(hex)
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("快捷取色")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                    FlowRow(spacing: 6) {
                        ForEach(ColorNameTable.quickPicks, id: \.name) { pick in
                            Button {
                                if let parsed = ColorEngine.parse(pick.hex) {
                                    apply(parsed, remember: false)
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(swiftUIColor(ColorEngine.parse(pick.hex) ?? .init(red: 0.5, green: 0.5, blue: 0.5)))
                                        .frame(width: 11, height: 11)
                                    Text(pick.name)
                                        .font(.system(size: 11))
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 动作

    private func applyInput() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let parsed = ColorEngine.parse(text) {
            color = parsed
            inputInvalid = false
        } else {
            inputInvalid = true
            NSSound.beep()
            toast = "认不出这个色值"
        }
    }

    private func apply(_ newColor: RGBAColor, remember: Bool) {
        color = newColor
        inputText = ColorEngine.string(for: newColor, format: .hex)
        inputInvalid = false
        if remember { rememberColor(newColor) }
    }

    private func rememberColor(_ newColor: RGBAColor) {
        let hex = ColorEngine.string(for: newColor, format: .hex)
        var list = history.filter { $0.uppercased() != hex.uppercased() }
        list.insert(hex, at: 0)
        historyRaw = list.prefix(18).joined(separator: ",")
    }

    private func pickFromScreen() {
        sampler.show { picked in
            guard let picked else { return }
            let nsColor = picked.usingColorSpace(.sRGB) ?? picked
            let newColor = RGBAColor(
                red: Double(nsColor.redComponent),
                green: Double(nsColor.greenComponent),
                blue: Double(nsColor.blueComponent),
                alpha: Double(nsColor.alphaComponent)
            )
            apply(newColor, remember: true)
            toast = "吸到 \(ColorEngine.string(for: newColor, format: .hex))"
        }
    }
}

// MARK: - 公共小工具

func swiftUIColor(_ color: RGBAColor) -> Color {
    Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
}

// MARK: - 图片取色

/// 拖一张图进来，鼠标扫过就能看到那个像素的颜色，点一下取走。
struct PixelSamplerCard: View {
    var onPick: (RGBAColor) -> Void

    @State private var image: NSImage?
    @State private var buffer: PixelBuffer?
    @State private var name = ""
    @State private var isDropTargeted = false

    var body: some View {
        ToolCard(title: "从图片取色", systemImage: "photo") {
            if let image, let buffer {
                loadedContent(image: image, buffer: buffer)
            } else {
                emptyState
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func loadedContent(image: NSImage, buffer: PixelBuffer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SamplerCanvas(image: image, buffer: buffer, onPick: onPick)
                .frame(height: 320)

            HStack(spacing: 10) {
                Text("\(name) · \(buffer.width)×\(buffer.height)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("换一张") { pickImage() }
                    .controlSize(.small)
                Button("移除") { clear() }
                    .controlSize(.small)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text("把图片拖到这里，或者点下面选一张")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("选择图片…") { pickImage() }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 170)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.primary.opacity(0.12),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [7, 5])
                )
        )
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.title = "选择要取色的图片"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url: url)
    }

    private func clear() {
        image = nil
        buffer = nil
        name = ""
    }

    private func load(url: URL) {
        guard let data = try? Data(contentsOf: url), let cg = ImageCodec.decode(data: data) else {
            NSSound.beep()
            return
        }
        image = ImageCodec.nsImage(from: cg)
        buffer = PixelBuffer(cgImage: cg)
        name = url.lastPathComponent
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

/// 取色画布：图片 + 跟随鼠标的十字标记 + 坐标换算
private struct SamplerCanvas: View {
    let image: NSImage
    let buffer: PixelBuffer
    var onPick: (RGBAColor) -> Void

    @State private var hoverPoint: CGPoint?
    @State private var hoverColor: RGBAColor?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geometry.size.width, height: geometry.size.height)

                if let hoverPoint {
                    crosshair(at: hoverPoint, in: geometry.size)
                }

                hitLayer(in: geometry.size)
            }
        }
        .background(Checkerboard(square: 8))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10))
        )
    }

    private func crosshair(at point: CGPoint, in size: CGSize) -> some View {
        let badgeX = min(max(point.x, 48), max(size.width - 48, 48))
        let badgeY = max(point.y - 22, 14)
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.white)
                .frame(width: 13, height: 13)
                .overlay(Rectangle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1.5))
                .position(point)
            hoverBadge
                .position(x: badgeX, y: badgeY)
        }
    }

    @ViewBuilder
    private var hoverBadge: some View {
        if let hoverColor {
            Text(ColorEngine.string(for: hoverColor, format: .hex))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(ColorEngine.isDark(hoverColor) ? Color.white : Color.black)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(swiftUIColor(hoverColor), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.25))
                )
        }
    }

    private func hitLayer(in size: CGSize) -> some View {
        let fitted = PixelBuffer.fittedRect(imageSize: buffer.displaySize, in: size)
        return Color.clear
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverPoint = location
                    hoverColor = buffer.color(atViewPoint: location, fitted: fitted)
                case .ended:
                    hoverPoint = nil
                    hoverColor = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        if let picked = buffer.color(atViewPoint: value.location, fitted: fitted) {
                            onPick(picked)
                        }
                    }
            )
    }
}

/// 把 CGImage 摊平成 RGBA8 缓冲，取像素就变成查数组。
/// 直接在原始 dataProvider 上读会踩各种 stride / 色彩空间的坑，不值得。
struct PixelBuffer {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init?(cgImage: CGImage) {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0, width * height < 60_000_000 else { return nil }

        var storage = [UInt8](repeating: 0, count: width * height * 4)
        let success = storage.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard success else { return nil }

        self.width = width
        self.height = height
        self.bytes = storage
    }

    var displaySize: CGSize { CGSize(width: width, height: height) }

    /// CGContext 的原点在左下，界面点击是从上往下的，这里要把 y 翻过来
    func color(x: Int, y: Int) -> RGBAColor? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let flippedY = height - 1 - y
        let index = (flippedY * width + x) * 4
        guard index + 3 < bytes.count else { return nil }

        let alpha = Double(bytes[index + 3]) / 255
        guard alpha > 0 else {
            return RGBAColor(red: 0, green: 0, blue: 0, alpha: 0)
        }
        // 缓冲是预乘过的，除回去还原真实颜色
        return RGBAColor(
            red: Double(bytes[index]) / 255 / alpha,
            green: Double(bytes[index + 1]) / 255 / alpha,
            blue: Double(bytes[index + 2]) / 255 / alpha,
            alpha: alpha
        )
    }

    func color(atViewPoint point: CGPoint, fitted: CGRect) -> RGBAColor? {
        guard fitted.width > 0, fitted.height > 0, fitted.contains(point) else { return nil }
        let unitX = (point.x - fitted.minX) / fitted.width
        let unitY = (point.y - fitted.minY) / fitted.height
        let x = Int(unitX * CGFloat(width))
        let y = Int(unitY * CGFloat(height))
        return color(x: x, y: y)
    }

    /// 图片按 aspect fit 摆进容器后实际占据的矩形
    static func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
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
}
