import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct QRCodeScanView: View {

    enum Source: String, CaseIterable, Identifiable {
        case camera = "摄像头"
        case image = "图片"
        case clipboard = "剪贴板"
        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .camera: return "camera"
            case .image: return "photo"
            case .clipboard: return "doc.on.clipboard"
            }
        }
    }

    @StateObject private var scanner = CameraScanner()

    @State private var source: Source = .camera
    @State private var detectAllSymbologies = false
    @State private var results: [CodeScanResult] = []
    @State private var loadedImage: NSImage?
    @State private var loadedImageName: String?
    @State private var errorMessage: String?
    @State private var toast: String?
    @State private var isDropTargeted = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 16) {
                sourceCard
                resultListCard
            }
            .frame(minWidth: 340)
            .padding(20)

            Divider()

            VStack(spacing: 16) {
                switch source {
                case .camera: cameraPane
                case .image: imagePane
                case .clipboard: clipboardPane
                }
            }
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .toast($toast)
        .onChange(of: source) { _, newValue in
            if newValue == .camera {
                scanner.start()
            } else {
                scanner.stop()
            }
        }
        .onAppear {
            scanner.onDetect = { result in
                append(result)
            }
            if source == .camera { scanner.start() }
        }
        .onDisappear {
            scanner.stop()
        }
    }

    // MARK: - 左侧：来源选择

    private var sourceCard: some View {
        ToolCard(title: "来源", systemImage: "antenna.radiowaves.left.and.right") {
            Picker("来源", selection: $source) {
                ForEach(Source.allCases) { item in
                    Label(item.rawValue, systemImage: item.systemImage).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Toggle("同时识别一维码（EAN / Code128 等）", isOn: $detectAllSymbologies)
                .font(.caption)

            if let errorMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            }
        }
    }

    // MARK: - 左侧：结果列表

    private var resultListCard: some View {
        ToolCard(title: "结果 \(results.isEmpty ? "" : "· \(results.count)")", systemImage: "list.bullet.rectangle") {
            if results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 30))
                        .foregroundStyle(.quaternary)
                    Text("还没有识别到内容")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(results) { result in
                            ScanResultRow(result: result) { toastMessage in
                                toast = toastMessage
                            }
                        }
                    }
                }
                .frame(maxHeight: 420)

                if results.count > 1 {
                    Button {
                        withAnimation { results.removeAll() }
                    } label: {
                        Label("清空结果", systemImage: "trash")
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - 右侧：摄像头

    private var cameraPane: some View {
        ToolCard(title: "实时扫描", systemImage: "camera.viewfinder") {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black)
                if scanner.isRunning {
                    CameraPreview(session: scanner.session)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(scanGuide)
                } else {
                    cameraPlaceholder
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .frame(maxWidth: 720)

            HStack {
                statusBadge
                Spacer()
                Button {
                    if scanner.isRunning {
                        scanner.stop()
                    } else {
                        scanner.refreshAuthorization()
                        scanner.start()
                    }
                } label: {
                    Label(scanner.isRunning ? "停止" : "开始扫描",
                          systemImage: scanner.isRunning ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)

                if scanner.status == .denied {
                    Button("打开系统设置") { openCameraSettings() }
                        .controlSize(.small)
                }
            }
        }
    }

    private var cameraPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: scanner.status == .denied ? "video.slash" : "camera")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.5))
            Text(placeholderText)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private var placeholderText: String {
        switch scanner.status {
        case .idle: return "点「开始扫描」把二维码对准摄像头"
        case .requesting: return "正在请求摄像头权限…"
        case .denied: return "摄像头权限被拒绝了。去「系统设置 → 隐私与安全性 → 摄像头」里给 SeraphimTools 打开。"
        case .unavailable(let reason): return reason
        case .running: return "正在启动…"
        }
    }

    private var scanGuide: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.62
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                .frame(width: side, height: side)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .allowsHitTesting(false)
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(scanner.isRunning ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 8, height: 8)
            Text(scanner.isRunning ? "扫描中" : "已停止")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 右侧：图片

    private var imagePane: some View {
        ToolCard(title: "从图片识别", systemImage: "photo") {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isDropTargeted ? Color.accentColor : Color.primary.opacity(0.15),
                                style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [8, 6])
                            )
                    )

                if let loadedImage {
                    ScannedImagePreview(image: loadedImage, results: results)
                        .padding(8)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 34))
                            .foregroundStyle(.tertiary)
                        Text("把图片拖进来，或者")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("选择图片…") { loadFromFile() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        Text("支持 PNG / JPEG / HEIC / TIFF 等常见格式")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .frame(maxWidth: 720)
            .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
            }

            HStack {
                if let loadedImageName {
                    Label(loadedImageName, systemImage: "photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("重新识别") { rescanCurrentImage() }
                    .controlSize(.small)
                    .disabled(loadedImage == nil)
                Button("选择图片…") { loadFromFile() }
                    .controlSize(.small)
                Button("清空") {
                    loadedImage = nil
                    loadedImageName = nil
                    errorMessage = nil
                    results.removeAll()
                }
                .controlSize(.small)
                .disabled(loadedImage == nil)
            }
        }
    }

    // MARK: - 右侧：剪贴板

    private var clipboardPane: some View {
        ToolCard(title: "从剪贴板识别", systemImage: "doc.on.clipboard") {
            VStack(spacing: 12) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 34))
                    .foregroundStyle(.tertiary)
                Text("截图里带二维码？截完直接回来点一下就行。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    readFromClipboard()
                } label: {
                    Label("读取剪贴板", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                Text("剪贴板里的文本如果本身就是链接 / Wi-Fi 配置，也会被识别出来。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        }
    }

    // MARK: - 动作

    private func append(_ result: CodeScanResult) {
        guard !results.contains(where: { $0.payload == result.payload }) else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            results.insert(result, at: 0)
        }
        NSSound.beep()
        toast = "识别到 \(result.kind.rawValue)"
    }

    private func loadFromFile() {
        guard let image = ImageCodec.pickImage() else { return }
        apply(image: image, name: "本地图片")
    }

    private func rescanCurrentImage() {
        guard let loadedImage else { return }
        apply(image: loadedImage, name: loadedImageName ?? "本地图片")
    }

    private func apply(image: NSImage, name: String) {
        loadedImage = image
        loadedImageName = name
        errorMessage = nil
        do {
            let found = try CodeReader.scan(
                nsImage: image,
                detectAllSymbologies: detectAllSymbologies,
                source: name
            )
            if found.isEmpty {
                results = []
                errorMessage = "这张图里没找到二维码。试试勾上「同时识别一维码」，或者换张更清晰的图。"
            } else {
                results = found
                toast = "识别到 \(found.count) 个码"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func readFromClipboard() {
        errorMessage = nil
        do {
            let found = try CodeReader.scanPasteboard(detectAllSymbologies: detectAllSymbologies)
            if found.isEmpty {
                results = []
                errorMessage = "剪贴板里没有可识别的内容。"
            } else {
                results = found
                toast = "从剪贴板识别到 \(found.count) 条内容"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage else { return }
                DispatchQueue.main.async {
                    apply(image: image, name: "拖入的图片")
                }
            }
            return true
        }

        _ = provider.loadObject(ofClass: URL.self) { object, _ in
            guard let url = object, let image = NSImage(contentsOf: url) else { return }
            DispatchQueue.main.async {
                apply(image: image, name: url.lastPathComponent)
            }
        }
        return true
    }

    private func openCameraSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - 结果行

private struct ScanResultRow: View {
    let result: CodeScanResult
    var onToast: (String) -> Void

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label(result.kind.rawValue, systemImage: result.kind.systemImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(result.kind.tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(result.kind.tint.opacity(0.12), in: Capsule())

                Text(result.symbology)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int((result.confidence * 100).rounded()))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Text(expanded ? result.displayPayload : String(result.payload.prefix(160)))
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(expanded ? nil : 4)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Text(result.source)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(result.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                if result.payload.count > 160 {
                    Button(expanded ? "收起" : "展开") { expanded.toggle() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
                if let url = result.openableURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("打开", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
                Button {
                    NSPasteboard.copyString(result.payload)
                    onToast("已拷贝")
                } label: {
                    Label("拷贝", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

// MARK: - 图片 + 标注框

private struct ScannedImagePreview: View {
    let image: NSImage
    let results: [CodeScanResult]

    var body: some View {
        GeometryReader { geo in
            let container = geo.size
            let fitted = fittedRect(imageSize: image.size, in: container)

            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: container.width, height: container.height)

                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    let rect = mappedRect(result.boundingBox, fitted: fitted)
                    if rect.width > 1, rect.height > 1 {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.08))
                            )
                            .frame(width: rect.width, height: rect.height)
                            .overlay(alignment: .topLeading) {
                                Text("\(index + 1)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.accentColor, in: Capsule())
                                    .offset(x: 2, y: -14)
                            }
                            .offset(x: rect.minX, y: rect.minY)
                    }
                }
            }
        }
    }

    private func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
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

    /// Vision 的归一化坐标原点在左下角，SwiftUI 在左上角，这里翻一下
    private func mappedRect(_ boundingBox: CGRect, fitted: CGRect) -> CGRect {
        guard boundingBox != .zero, fitted != .zero else { return .zero }
        return CGRect(
            x: fitted.minX + boundingBox.minX * fitted.width,
            y: fitted.minY + (1 - boundingBox.maxY) * fitted.height,
            width: boundingBox.width * fitted.width,
            height: boundingBox.height * fitted.height
        )
    }
}
