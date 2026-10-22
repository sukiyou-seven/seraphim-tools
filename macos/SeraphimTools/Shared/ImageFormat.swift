import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 可跨线程传递的纯色（NSColor 不是 Sendable，后台编码时用它）
struct RGBColor: Sendable, Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat

    init(red: CGFloat, green: CGFloat, blue: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? .white
        self.red = srgb.redComponent
        self.green = srgb.greenComponent
        self.blue = srgb.blueComponent
    }

    init(_ color: Color) {
        self.init(NSColor(color))
    }

    var hexString: String {
        String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    var cgColor: CGColor { nsColor.cgColor }

    static let white = RGBColor(red: 1, green: 1, blue: 1)
    static let black = RGBColor(red: 0, green: 0, blue: 0)
}

/// 工具箱支持的图片输出格式。
/// 系统没有对应编码器的格式会在 UI 上标出来并禁用。
enum ImageFormat: String, CaseIterable, Identifiable, Sendable {
    case png
    case jpeg
    case heic
    case tiff
    case gif
    case bmp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        case .tiff: return "TIFF"
        case .gif: return "GIF"
        case .bmp: return "BMP"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .tiff: return "tiff"
        case .gif: return "gif"
        case .bmp: return "bmp"
        }
    }

    var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .tiff: return .tiff
        case .gif: return .gif
        case .bmp: return .bmp
        }
    }

    /// 有损格式，可以调质量
    var isLossy: Bool {
        self == .jpeg || self == .heic
    }

    /// 是否支持透明通道
    var supportsAlpha: Bool {
        switch self {
        case .png, .tiff, .gif: return true
        case .jpeg, .heic, .bmp: return false
        }
    }

    var note: String {
        switch self {
        case .png: return "无损，支持透明，文件偏大"
        case .jpeg: return "有损，兼容性最好，不支持透明"
        case .heic: return "有损，同画质下体积最小，Apple 生态首选"
        case .tiff: return "无损，印刷场景，支持透明"
        case .gif: return "256 色，仅导出当前静态帧"
        case .bmp: return "无压缩位图，体积巨大，不建议"
        }
    }

    /// 从文件扩展名猜测格式
    static func from(fileExtension ext: String) -> ImageFormat? {
        let lowered = ext.lowercased()
        return allCases.first { $0.fileExtension == lowered }
            ?? (lowered == "jpeg" ? .jpeg : nil)
            ?? (lowered == "tif" ? .tiff : nil)
    }
}
