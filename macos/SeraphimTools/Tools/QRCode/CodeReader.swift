import AppKit
import Vision
import CoreGraphics

enum CodeReaderError: LocalizedError {
    case noImage
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .noImage: return "没拿到可识别的图像。"
        case .requestFailed(let reason): return "识别失败：\(reason)"
        }
    }
}

/// 基于 Vision 的条码识别。
enum CodeReader {

    static func scan(cgImage: CGImage,
                     detectAllSymbologies: Bool = false,
                     source: String = "图片") throws -> [CodeScanResult] {
        let request = VNDetectBarcodesRequest()
        if !detectAllSymbologies {
            request.symbologies = [.qr]
        }

        let handler = VNImageRequestHandler(cgImage: flattenOnWhite(cgImage), orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw CodeReaderError.requestFailed(error.localizedDescription)
        }

        let observations = request.results ?? []
        return observations.compactMap { observation in
            guard let payload = observation.payloadStringValue, !payload.isEmpty else { return nil }
            return CodeScanResult(
                payload: payload,
                symbology: displayName(for: observation.symbology),
                confidence: observation.confidence,
                boundingBox: observation.boundingBox,
                source: source
            )
        }
    }

    static func scan(nsImage: NSImage,
                     detectAllSymbologies: Bool = false,
                     source: String = "图片") throws -> [CodeScanResult] {
        guard let cgImage = nsImage.pixelCGImage else { throw CodeReaderError.noImage }
        return try scan(cgImage: cgImage, detectAllSymbologies: detectAllSymbologies, source: source)
    }

    static func scan(url: URL, detectAllSymbologies: Bool = false) throws -> [CodeScanResult] {
        guard let image = NSImage(contentsOf: url) else { throw CodeReaderError.noImage }
        return try scan(nsImage: image, detectAllSymbologies: detectAllSymbologies, source: url.lastPathComponent)
    }

    /// 从剪贴板读取图片
    static func scanPasteboard(detectAllSymbologies: Bool = false) throws -> [CodeScanResult] {
        let pasteboard = NSPasteboard.general

        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first {
            return try scan(nsImage: image, detectAllSymbologies: detectAllSymbologies, source: "剪贴板")
        }

        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), let image = NSImage(data: data) {
                return try scan(nsImage: image, detectAllSymbologies: detectAllSymbologies, source: "剪贴板")
            }
        }

        // 剪贴板里只有纯文本时，看看它本身是不是个二维码 payload
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            return [CodeScanResult(
                payload: string,
                symbology: "文本",
                confidence: 1,
                boundingBox: .zero,
                source: "剪贴板"
            )]
        }

        throw CodeReaderError.noImage
    }

    /// Vision 会把透明像素当作黑色处理，透明底的码会变成"黑码黑底"。
    /// 识别前统一垫一层白底，顺便解决各种带 alpha 的截图。
    private static func flattenOnWhite(_ image: CGImage) -> CGImage {
        guard let ctx = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return image }

        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage() ?? image
    }

    private static func displayName(for symbology: VNBarcodeSymbology) -> String {
        switch symbology {
        case .qr: return "QR Code"
        case .aztec: return "Aztec"
        case .pdf417: return "PDF417"
        case .code128: return "Code 128"
        case .code39: return "Code 39"
        case .code93: return "Code 93"
        case .ean8: return "EAN-8"
        case .ean13: return "EAN-13"
        case .upce: return "UPC-E"
        case .itf14: return "ITF-14"
        case .dataMatrix: return "Data Matrix"
        case .codabar: return "Codabar"
        default: return symbology.rawValue
        }
    }
}
