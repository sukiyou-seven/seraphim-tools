import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// 二维码生成：CoreImage 出码点矩阵，再按整数倍像素放大，保证边缘绝对锐利。
enum QRCodeGenerator {

    /// 生成位图。返回的 CGImage 边长 = 每个码点的整数倍 × 总码点数，所以不会出现半像素毛边。
    static func cgImage(for options: QRImageOptions) throws -> CGImage {
        let matrix = try moduleMatrix(for: options)
        let moduleCount = matrix.count
        let quiet = max(0, options.quietZone)
        let total = moduleCount + quiet * 2
        let pixelsPerModule = max(1, Int((options.targetSize / CGFloat(total)).rounded(.down)))
        let side = pixelsPerModule * total

        guard let ctx = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw QRGenerationError.renderFailed }

        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)

        let bg = options.transparentBackground ? NSColor.clear : options.background
        if let bgColor = srgb(bg) {
            ctx.setFillColor(bgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }

        guard let fgColor = srgb(options.foreground) else { throw QRGenerationError.renderFailed }
        ctx.setFillColor(fgColor)

        for row in 0..<moduleCount {
            for col in 0..<moduleCount where matrix[row][col] {
                // CGContext 原点在左下，矩阵第 0 行在最上面，所以要翻一下
                let x = (col + quiet) * pixelsPerModule
                let y = (moduleCount - 1 - row + quiet) * pixelsPerModule
                ctx.fill(CGRect(x: x, y: y, width: pixelsPerModule, height: pixelsPerModule))
            }
        }

        guard let image = ctx.makeImage() else { throw QRGenerationError.renderFailed }
        return image
    }

    /// 读出最底层的黑白码点矩阵（true = 深色模块）
    static func moduleMatrix(for options: QRImageOptions) throws -> [[Bool]] {
        let text = options.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw QRGenerationError.emptyInput }
        guard let data = text.data(using: .utf8) else { throw QRGenerationError.encodingFailed }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = options.level.rawValue

        guard let output = filter.outputImage else {
            throw QRGenerationError.contentTooLong(text.count)
        }

        let moduleCount = Int(output.extent.width.rounded())
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let moduleImage = context.createCGImage(output, from: output.extent) else {
            throw QRGenerationError.renderFailed
        }

        var pixels = [UInt8](repeating: 0, count: moduleCount * moduleCount)
        guard let ctx = CGContext(
            data: &pixels,
            width: moduleCount,
            height: moduleCount,
            bitsPerComponent: 8,
            bytesPerRow: moduleCount,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { throw QRGenerationError.renderFailed }

        ctx.draw(moduleImage, in: CGRect(x: 0, y: 0, width: moduleCount, height: moduleCount))

        // CGContext 的行序是从下往上，翻转成人类阅读顺序
        var matrix = [[Bool]]()
        matrix.reserveCapacity(moduleCount)
        for row in 0..<moduleCount {
            let sourceRow = moduleCount - 1 - row
            let offset = sourceRow * moduleCount
            var line = [Bool]()
            line.reserveCapacity(moduleCount)
            for col in 0..<moduleCount {
                line.append(pixels[offset + col] < 128)
            }
            matrix.append(line)
        }
        return matrix
    }

    /// 矢量导出，适合印刷和放进设计稿
    static func svg(for options: QRImageOptions) throws -> String {
        let matrix = try moduleMatrix(for: options)
        let moduleCount = matrix.count
        let quiet = max(0, options.quietZone)
        let total = moduleCount + quiet * 2
        let scale = max(1, Int(options.targetSize / CGFloat(total)))
        let side = total * scale
        let moduleSize = scale

        let fg = hexString(from: options.foreground)
        let bg = options.transparentBackground ? nil : hexString(from: options.background)

        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(side)\" height=\"\(side)\" viewBox=\"0 0 \(side) \(side)\" shape-rendering=\"crispEdges\">")

        if let bg {
            lines.append("  <rect width=\"\(side)\" height=\"\(side)\" fill=\"\(bg)\"/>")
        }

        var path = ""
        for row in 0..<moduleCount {
            var col = 0
            while col < moduleCount {
                guard matrix[row][col] else { col += 1; continue }
                var run = 1
                while col + run < moduleCount && matrix[row][col + run] { run += 1 }
                let x = (col + quiet) * moduleSize
                let y = (row + quiet) * moduleSize
                path += "M\(x) \(y)h\(run * moduleSize)v\(moduleSize)h\(-run * moduleSize)z"
                col += run
            }
        }
        lines.append("  <path d=\"\(path)\" fill=\"\(fg)\"/>")
        lines.append("</svg>")
        return lines.joined(separator: "\n")
    }

    // MARK: - 小工具

    private static func srgb(_ color: NSColor) -> CGColor? {
        color.usingColorSpace(.sRGB)?.cgColor
    }

    private static func hexString(from color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
