import AppKit
import CoreGraphics

/// 图像处理引擎：缩放 / 裁剪 / 水印 / 压缩。
/// 全部基于 CoreGraphics，不依赖任何第三方库。
enum ImageProcessor {

    // MARK: - 缩放

    static func resized(_ image: CGImage, to size: CGSize, quality: ResizeQuality) -> CGImage? {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = quality.cgQuality
        ctx.setShouldAntialias(quality != .none)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    /// 长边限制在 maxDimension 以内（不放大）
    static func fitted(_ image: CGImage, maxDimension: CGFloat) -> CGImage {
        let longest = CGFloat(max(image.width, image.height))
        guard maxDimension > 0, longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let target = CGSize(
            width: max(1, (CGFloat(image.width) * scale).rounded()),
            height: max(1, (CGFloat(image.height) * scale).rounded())
        )
        return resized(image, to: target, quality: .high) ?? image
    }

    // MARK: - 裁剪

    /// normalizedRect 归一化坐标（0–1），原点在左上角，和 CGImage.cropping 的坐标系一致。
    static func cropped(_ image: CGImage, normalizedRect rect: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        let clamped = rect.standardized.intersection(bounds)
        guard !clamped.isNull, clamped.width > 0.0005, clamped.height > 0.0005 else { return nil }

        let pixelRect = CGRect(
            x: (clamped.minX * CGFloat(image.width)).rounded(),
            y: (clamped.minY * CGFloat(image.height)).rounded(),
            width: max(1, (clamped.width * CGFloat(image.width)).rounded()),
            height: max(1, (clamped.height * CGFloat(image.height)).rounded())
        ).intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))

        guard pixelRect.width >= 1, pixelRect.height >= 1 else { return nil }
        return image.cropping(to: pixelRect)
    }

    // MARK: - 水印

    static func watermarked(_ base: CGImage, options: WatermarkOptions) -> CGImage? {
        let width = base.width
        let height = base.height
        guard width > 0, height > 0 else { return nil }

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))

        let canvas = CGSize(width: width, height: height)

        switch options.style {
        case .text:
            let content = options.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return base }
            let attributed = makeAttributedText(options)
            drawWatermarkLayer(ctx: ctx, canvas: canvas, options: options, stampSize: attributed.size()) { center, radians in
                stampText(attributed, ctx: ctx, center: center, size: attributed.size(), radians: radians)
            }

        case .image:
            guard let watermark = options.watermarkImage?.pixelCGImage,
                  watermark.width > 0, watermark.height > 0 else { return base }
            let scale = max(0.02, min(2.0, options.imageScale))
            let targetWidth = canvas.width * CGFloat(scale)
            let targetSize = CGSize(
                width: targetWidth,
                height: targetWidth * CGFloat(watermark.height) / CGFloat(watermark.width)
            )
            drawWatermarkLayer(ctx: ctx, canvas: canvas, options: options, stampSize: targetSize) { center, radians in
                stampImage(watermark, ctx: ctx, center: center, size: targetSize, radians: radians)
            }
        }

        return ctx.makeImage()
    }

    // MARK: 水印绘制细节

    /// 统一的摆放逻辑：平铺或者按九宫格锚点摆放
    private static func drawWatermarkLayer(
        ctx: CGContext,
        canvas: CGSize,
        options: WatermarkOptions,
        stampSize: CGSize,
        stamp: (CGPoint, CGFloat) -> Void
    ) {
        let radians = CGFloat(options.rotation) * .pi / 180
        let margin = min(canvas.width, canvas.height) * 0.03

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        ctx.setAlpha(CGFloat(max(0.01, min(1, options.opacity))))

        if options.tiled {
            // 用旋转后的包围盒做步长，保证平铺不重叠
            let cosA = abs(cos(radians))
            let sinA = abs(sin(radians))
            let boxW = stampSize.width * cosA + stampSize.height * sinA
            let boxH = stampSize.width * sinA + stampSize.height * cosA
            let stepX = max(boxW + CGFloat(options.spacing), 16)
            let stepY = max(boxH + CGFloat(options.spacing), 16)
            let diagonal = (canvas.width * canvas.width + canvas.height * canvas.height).squareRoot()

            var y = -diagonal / 2
            while y < canvas.height + diagonal / 2 {
                var x = -diagonal / 2
                while x < canvas.width + diagonal / 2 {
                    stamp(CGPoint(x: x + boxW / 2, y: y + boxH / 2), radians)
                    x += stepX
                }
                y += stepY
            }
        } else {
            let unit = options.anchor.unit
            let center = CGPoint(
                x: margin + (canvas.width - margin * 2 - stampSize.width) * unit.x + stampSize.width / 2,
                y: margin + (canvas.height - margin * 2 - stampSize.height) * unit.y + stampSize.height / 2
            )
            stamp(center, radians)
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private static func makeAttributedText(_ options: WatermarkOptions) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: CGFloat(options.fontSize), weight: .semibold)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(options.color),
        ]
        if options.shadow {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
            shadow.shadowBlurRadius = CGFloat(options.fontSize) * 0.14
            shadow.shadowOffset = NSSize(width: 0, height: -CGFloat(options.fontSize) * 0.05)
            attributes[.shadow] = shadow
        }
        return NSAttributedString(string: options.text, attributes: attributes)
    }

    private static func stampText(_ attributed: NSAttributedString,
                                  ctx: CGContext,
                                  center: CGPoint,
                                  size: CGSize,
                                  radians: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: radians)
        attributed.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
        ctx.restoreGState()
    }

    private static func stampImage(_ image: CGImage,
                                   ctx: CGContext,
                                   center: CGPoint,
                                   size: CGSize,
                                   radians: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: radians)
        ctx.draw(image, in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        ctx.restoreGState()
    }

    // MARK: - 压缩

    static func compressed(_ image: CGImage, request: CompressionRequest) -> CompressionOutcome? {
        var source = image
        if request.maxDimension > 0 {
            source = fitted(image, maxDimension: CGFloat(request.maxDimension))
        }

        let format = request.format
        guard ImageCodec.canEncode(format) else { return nil }

        if format.isLossy, request.mode == .targetSize {
            return compressToTarget(source, format: format, target: request.targetBytes)
        }

        let quality = format.isLossy ? request.quality : 1.0
        guard let data = ImageCodec.encode(source, format: format, quality: quality) else { return nil }
        return CompressionOutcome(
            data: data,
            quality: quality,
            reachedTarget: data.count <= request.targetBytes || request.mode == .quality,
            format: format
        )
    }

    /// 二分搜索质量参数逼近目标体积
    private static func compressToTarget(_ image: CGImage,
                                         format: ImageFormat,
                                         target: Int) -> CompressionOutcome? {
        guard target > 0 else { return nil }

        var low = 0.02
        var high = 1.0
        var best: (data: Data, quality: Double)?
        var smallest: (data: Data, quality: Double)?

        for _ in 0..<13 {
            let mid = (low + high) / 2
            guard let data = ImageCodec.encode(image, format: format, quality: mid) else { break }

            if smallest == nil || data.count < smallest!.data.count {
                smallest = (data, mid)
            }
            if data.count <= target {
                best = (data, mid)
                low = mid
            } else {
                high = mid
            }
            if abs(high - low) < 0.005 { break }
        }

        if let best {
            return CompressionOutcome(data: best.data, quality: best.quality, reachedTarget: true, format: format)
        }
        if let smallest {
            return CompressionOutcome(data: smallest.data, quality: smallest.quality, reachedTarget: false, format: format)
        }
        return nil
    }
}

// MARK: - Base64

enum Base64Tool {

    /// 把 Data 编成 Base64，可选 Data URL 前缀和 76 字符换行
    static func encode(_ data: Data,
                       mimeType: String?,
                       asDataURL: Bool,
                       lineWrapped: Bool) -> String {
        var base64 = data.base64EncodedString(options: lineWrapped ? [.lineLength76Characters, .endLineWithLineFeed] : [])
        if asDataURL, let mimeType {
            // Data URL 里换行是合法的，但为了好复制还是去掉
            base64 = base64.replacingOccurrences(of: "\n", with: "")
            return "data:\(mimeType);base64,\(base64)"
        }
        return base64
    }

    /// 宽容解码：自动去掉 Data URL 前缀、空白、引号，兼容 URL-safe 变体，自动补 padding
    static func decode(_ raw: String) -> Data? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let range = text.range(of: "base64,") {
            text = String(text[range.upperBound...])
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'` "))
        text = text.replacingOccurrences(of: "[\\s\\n\\r\\t]", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")

        if text.count % 4 == 1 {
            // 余 1 说明尾部是截断的残缺字符，直接丢掉再补 padding
            text = String(text.dropLast())
        }
        if text.count % 4 != 0 {
            text += String(repeating: "=", count: 4 - text.count % 4)
        }

        return Data(base64Encoded: text, options: [.ignoreUnknownCharacters])
    }

    /// 从 Base64 里猜出图片的 MIME 类型（用于编码时给 Data URL 加前缀）
    static func mimeType(for format: ImageFormat) -> String {
        switch format {
        case .png: return "image/png"
        case .jpeg: return "image/jpeg"
        case .heic: return "image/heic"
        case .tiff: return "image/tiff"
        case .gif: return "image/gif"
        case .bmp: return "image/bmp"
        }
    }

    /// 解码后按魔数判断真实格式
    static func detectFormat(of data: Data) -> ImageFormat? {
        ImageCodec.sniff(data: data)
    }
}
