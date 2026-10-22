import AppKit
import SwiftUI

// MARK: - 当前处理的图片

/// 所有子工具共享的"当前图片"。换页不丢图，一次加载到处用。
///
/// 用单例是为了让图片在切换工具（视图重建）之后还在。
@MainActor
final class WorkingImage: ObservableObject {
    static let shared = WorkingImage()

    @Published private(set) var image: NSImage?
    @Published private(set) var displayName: String = ""
    @Published private(set) var originalData: Data?
    @Published var errorMessage: String?
    /// 换图时递增，用作异步计算任务的 id（自动取消过期任务）
    @Published private(set) var token = UUID()

    private init() {}

    private var previewCache: [Int: CGImage] = [:]

    var cgImage: CGImage? { image?.pixelCGImage }

    var pixelSize: CGSize {
        guard let cgImage else { return .zero }
        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    /// 大图预览用的降采样版本，避免每次调节参数都重算几千万像素。
    /// 导出时仍然用全分辨率原图。缓存按尺寸分键，缩略图和大预览互不干扰。
    func previewCGImage(maxDimension: CGFloat = 1400) -> CGImage? {
        guard let full = cgImage else { return nil }
        let key = Int(maxDimension)
        if let hit = previewCache[key] { return hit }

        let base: CGImage
        if let cached = previewCache[1400] {
            base = cached
        } else {
            let computed = ImageProcessor.fitted(full, maxDimension: 1400)
            previewCache[1400] = computed
            base = computed
        }

        let result = CGFloat(max(base.width, base.height)) <= maxDimension
            ? base
            : ImageProcessor.fitted(base, maxDimension: maxDimension)
        previewCache[key] = result
        return result
    }

    /// 预览缩放比例（预览图 / 原图），水印这类绝对像素参数需要按它换算
    func previewScale(maxDimension: CGFloat = 1400) -> CGFloat {
        guard let preview = previewCGImage(maxDimension: maxDimension),
              preview.width > 0, let full = cgImage, full.width > 0 else { return 1 }
        return CGFloat(preview.width) / CGFloat(full.width)
    }

    var byteSize: Int? { originalData?.count }

    /// 真实格式（按文件头嗅探，不信扩展名）
    var detectedFormat: ImageFormat? {
        guard let originalData else { return nil }
        return ImageCodec.sniff(data: originalData)
    }

    var hasImage: Bool { image != nil }

    func load(url: URL) {
        errorMessage = nil
        let data = try? Data(contentsOf: url)
        guard let data, let cg = ImageCodec.decode(data: data) else {
            errorMessage = "读不出这张图片：\(url.lastPathComponent)"
            NSSound.beep()
            return
        }
        image = ImageCodec.nsImage(from: cg)
        originalData = data
        displayName = url.lastPathComponent
        previewCache = [:]
        token = UUID()
    }

    func load(image newImage: NSImage, name: String, data: Data? = nil) {
        errorMessage = nil
        image = newImage
        displayName = name
        originalData = data
        previewCache = [:]
        token = UUID()
    }

    func clear() {
        image = nil
        originalData = nil
        displayName = ""
        errorMessage = nil
        previewCache = [:]
        token = UUID()
    }

    /// 结果图的统一文件名：原名 + 后缀
    func suggestedName(suffix: String, format: ImageFormat) -> String {
        let base = (displayName as NSString).deletingPathExtension
        let stem = base.isEmpty ? "image" : base
        return "\(stem)-\(suffix).\(format.fileExtension)"
    }
}

// MARK: - 裁剪比例

enum CropAspect: String, CaseIterable, Identifiable {
    case free
    case original
    case square
    case r4x3
    case r3x2
    case r16x9
    case r9x16
    case r3x4
    case r2x3

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: return "自由"
        case .original: return "原图"
        case .square: return "1:1"
        case .r4x3: return "4:3"
        case .r3x2: return "3:2"
        case .r16x9: return "16:9"
        case .r9x16: return "9:16"
        case .r3x4: return "3:4"
        case .r2x3: return "2:3"
        }
    }

    /// 宽 / 高
    func ratio(originalSize: CGSize) -> CGFloat? {
        switch self {
        case .free: return nil
        case .original: return originalSize.height > 0 ? originalSize.width / originalSize.height : nil
        case .square: return 1
        case .r4x3: return 4.0 / 3.0
        case .r3x2: return 3.0 / 2.0
        case .r16x9: return 16.0 / 9.0
        case .r9x16: return 9.0 / 16.0
        case .r3x4: return 3.0 / 4.0
        case .r2x3: return 2.0 / 3.0
        }
    }
}

// MARK: - 缩放质量

enum ResizeQuality: String, CaseIterable, Identifiable {
    case smooth
    case high
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smooth: return "平滑"
        case .high: return "高质量"
        case .none: return "锐利像素"
        }
    }

    var cgQuality: CGInterpolationQuality {
        switch self {
        case .smooth: return .medium
        case .high: return .high
        case .none: return .none
        }
    }
}

// MARK: - 水印

enum WatermarkStyle: String, CaseIterable, Identifiable {
    case text
    case image
    var id: String { rawValue }
    var title: String { self == .text ? "文字" : "图片" }
}

enum WatermarkAnchor: String, CaseIterable, Identifiable {
    case topLeft, topCenter, topRight
    case middleLeft, center, middleRight
    case bottomLeft, bottomCenter, bottomRight

    var id: String { rawValue }

    /// 归一化锚点：x 0=左 1=右，y 0=下 1=上（CoreGraphics 坐标系）
    var unit: CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: 0, y: 1)
        case .topCenter: return CGPoint(x: 0.5, y: 1)
        case .topRight: return CGPoint(x: 1, y: 1)
        case .middleLeft: return CGPoint(x: 0, y: 0.5)
        case .center: return CGPoint(x: 0.5, y: 0.5)
        case .middleRight: return CGPoint(x: 1, y: 0.5)
        case .bottomLeft: return CGPoint(x: 0, y: 0)
        case .bottomCenter: return CGPoint(x: 0.5, y: 0)
        case .bottomRight: return CGPoint(x: 1, y: 0)
        }
    }
}

struct WatermarkOptions {
    var style: WatermarkStyle = .text

    // 文字
    var text: String = "SeraphimTools"
    var fontSize: Double = 48
    var color: Color = .white
    var shadow: Bool = true

    // 图片
    var watermarkImage: NSImage?
    /// 相对底图宽度
    var imageScale: Double = 0.22

    // 通用
    var opacity: Double = 0.65
    var rotation: Double = -30
    var anchor: WatermarkAnchor = .bottomRight
    var tiled: Bool = false
    var spacing: Double = 60
}

// MARK: - 压缩

struct CompressionOutcome: Sendable {
    var data: Data
    var quality: Double
    var reachedTarget: Bool
    var format: ImageFormat
}

struct CompressionRequest: Sendable {
    var format: ImageFormat = .jpeg
    var mode: Mode = .quality
    var quality: Double = 0.7
    var targetBytes: Int = 300 * 1024
    /// 0 表示不限制
    var maxDimension: Double = 0

    enum Mode: String, CaseIterable, Identifiable {
        case quality
        case targetSize
        var id: String { rawValue }
        var title: String { self == .quality ? "按质量" : "按目标大小" }
    }
}

// MARK: - 错误

enum ImageOperationError: LocalizedError {
    case noSourceImage
    case encodeFailed(ImageFormat)
    case unsupportedFormat(String)
    case decodeFailed
    case invalidCrop
    case cropTooSmall

    var errorDescription: String? {
        switch self {
        case .noSourceImage: return "先选一张图片。"
        case .encodeFailed(let format): return "\(format.title) 编码失败，可能是格式不被支持或参数不合理。"
        case .unsupportedFormat(let name): return "系统没有 \(name) 的编码器，换个格式试试。"
        case .decodeFailed: return "这段 Base64 解不出图片，检查一下是不是完整的图片数据。"
        case .invalidCrop: return "裁剪区域的尺寸不合法。"
        case .cropTooSmall: return "裁剪区域太小了。"
        }
    }
}
