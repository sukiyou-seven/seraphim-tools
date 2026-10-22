import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - NSImage 便利

extension NSImage {
    /// 拿到真实像素的 CGImage，用于 CoreImage / Vision / CoreGraphics 处理。
    var pixelCGImage: CGImage? {
        var proposed = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &proposed, context: nil, hints: nil)
    }

    /// 像素尺寸（不是 point 尺寸）
    var pixelSize: CGSize {
        guard let cg = pixelCGImage else { return size }
        return CGSize(width: cg.width, height: cg.height)
    }

    convenience init(cgImage image: CGImage) {
        self.init(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

// MARK: - 图像编解码 / 文件读写

enum ImageCodec {

    // MARK: CGImage 转换

    static func cgImage(from nsImage: NSImage) -> CGImage? {
        nsImage.pixelCGImage
    }

    static func nsImage(from cgImage: CGImage) -> NSImage {
        NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// 把带 alpha 的图像合成到纯色背景上（JPEG / BMP 之类没有透明通道的格式需要）
    static func flatten(_ image: CGImage, on background: RGBColor = .white) -> CGImage {
        guard let ctx = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return image }

        ctx.setFillColor(background.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage() ?? image
    }

    // MARK: 编码

    /// 按指定格式编码。quality 只对 JPEG / HEIC 生效。
    static func encode(
        _ image: CGImage,
        format: ImageFormat,
        quality: Double = 0.85,
        background: RGBColor = .white
    ) -> Data? {
        let source = format.supportsAlpha ? image : flatten(image, on: background)

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            format.utType.identifier as CFString,
            1,
            nil
        ) else { return nil }

        var options: [CFString: Any] = [:]
        if format.isLossy {
            options[kCGImageDestinationLossyCompressionQuality] = max(0.0, min(1.0, quality))
        }
        CGImageDestinationAddImage(destination, source, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func pngData(from cgImage: CGImage) -> Data? {
        encode(cgImage, format: .png)
    }

    static func jpegData(from cgImage: CGImage, quality: Double = 0.85) -> Data? {
        encode(cgImage, format: .jpeg, quality: quality)
    }

    // MARK: 解码

    static func decode(data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return image
    }

    static func decode(url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data: data)
    }

    /// 从文件头嗅探真实格式，比看扩展名靠谱
    static func sniff(data: Data) -> ImageFormat? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String? else { return nil }
        return ImageFormat.allCases.first { $0.utType.identifier == type }
    }

    /// 该格式在当前系统上是否有可用的编码器
    static func canEncode(_ format: ImageFormat) -> Bool {
        guard let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] else { return false }
        return identifiers.contains(format.utType.identifier)
    }

    // MARK: 文件对话框

    static func save(data: Data, suggestedName: String, contentType: UTType) -> URL? {
        guard let url = saveURL(suggestedName: suggestedName, contentType: contentType) else { return nil }
        do {
            try data.write(to: url)
            return url
        } catch {
            NSSound.beep()
            return nil
        }
    }

    static func saveURL(suggestedName: String, contentType: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.title = "保存"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func pickImage(title: String = "选择图片") -> NSImage? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = title
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return NSImage(contentsOf: url)
    }

    static func pickImageURL(title: String = "选择图片") -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = title
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}

// MARK: - 字节数格式化

enum ByteFormatter {
    static func string(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
