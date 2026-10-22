import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImageToolView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case convert = "格式转换"
        case compress = "压缩"
        case resize = "尺寸缩放"
        case crop = "裁剪"
        case watermark = "水印"
        case base64 = "Base64"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .convert: return "arrow.triangle.2.circlepath"
            case .compress: return "arrow.down.circle"
            case .resize: return "arrow.up.left.and.arrow.down.right"
            case .crop: return "crop"
            case .watermark: return "signature"
            case .base64: return "chevron.left.forwardslash.chevron.right"
            }
        }
    }

    @StateObject private var source = WorkingImage.shared
    @ObservedObject private var appState = AppState.shared
    /// 记住上次用的子功能
    @AppStorage("imageMode") private var mode: Mode = .convert
    @State private var toast: String?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("模式", selection: $mode) {
                ForEach(Mode.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 14)

            ImageSourceBar(source: source) {
                loadFromPasteboard()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)

            Divider()

            Group {
                switch mode {
                case .convert:
                    ImageConvertView(source: source, toast: $toast)
                case .compress:
                    ImageCompressView(source: source, toast: $toast)
                case .resize:
                    ImageResizeView(source: source, toast: $toast)
                case .crop:
                    ImageCropView(source: source, toast: $toast)
                case .watermark:
                    ImageWatermarkView(source: source, toast: $toast)
                case .base64:
                    ImageBase64View(source: source, toast: $toast)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toast($toast)
        .onAppear { consumePendingFile() }
        .onChange(of: appState.pendingImageURL) { _, _ in
            consumePendingFile()
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [10, 6]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - 拖放 / 剪贴板

    /// 从 Finder 双击 / open 命令送进来的图片
    private func consumePendingFile() {
        guard let url = appState.takePendingImageURL() else { return }
        source.load(url: url)
        toast = "已载入 \(url.lastPathComponent)"
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { object, _ in
                guard let url = object else { return }
                DispatchQueue.main.async {
                    source.load(url: url)
                    toast = "已载入 \(url.lastPathComponent)"
                }
            }
            return true
        }

        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage else { return }
                DispatchQueue.main.async {
                    source.load(image: image, name: "拖入的图片")
                    toast = "已载入拖入的图片"
                }
            }
            return true
        }

        return false
    }

    private func loadFromPasteboard() {
        let pasteboard = NSPasteboard.general
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first {
            source.load(image: image, name: "剪贴板图片")
            toast = "已载入剪贴板图片"
            return
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), let image = NSImage(data: data) {
                source.load(image: image, name: "剪贴板图片", data: data)
                toast = "已载入剪贴板图片"
                return
            }
        }
        toast = "剪贴板里没有图片"
        NSSound.beep()
    }
}

// MARK: - 子页面共用的外壳

/// 左侧参数、右侧预览的两栏布局
struct ImagePaneLayout<Controls: View, Preview: View>: View {
    @ViewBuilder var controls: Controls
    @ViewBuilder var preview: Preview

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    controls
                }
                .frame(width: 336)

                VStack(spacing: 16) {
                    preview
                }
                .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
    }
}
