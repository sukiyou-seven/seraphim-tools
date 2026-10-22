// 用法: swift apply_icon.swift <源图> <appiconset目录>
// 读入一张方形图，套 macOS 图标圆角遮罩（四角透明），输出全套 appicon 尺寸。
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write("用法: apply_icon.swift <源图> <输出目录>\n".data(using: .utf8)!)
    exit(2)
}
let sourcePath = arguments[1]
let outputDir = arguments[2]

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: sourcePath) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write("读不了源图\n".data(using: .utf8)!)
    exit(1)
}

let size = min(image.width, image.height)
// Apple squircle 圆角约占边长 22.5%，稍微内收 1px 防白边
let radius = CGFloat(size) * 0.225
let inset: CGFloat = 1

let masked: CGImage = {
    let ctx = CGContext(
        data: nil,
        width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let rect = CGRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2)
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size)))
    return ctx.makeImage()!
}()

// macOS AppIcon 全套尺寸
let variants: [(name: String, pixels: Int)] = [
    ("icon_16.png", 16), ("icon_16@2x.png", 32),
    ("icon_32.png", 32), ("icon_32@2x.png", 64),
    ("icon_128.png", 128), ("icon_128@2x.png", 256),
    ("icon_256.png", 256), ("icon_256@2x.png", 512),
    ("icon_512.png", 512), ("icon_512@2x.png", 1024),
]

for variant in variants {
    let target = CGFloat(variant.pixels)
    let ctx = CGContext(
        data: nil,
        width: variant.pixels, height: variant.pixels,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high
    ctx.draw(masked, in: CGRect(x: 0, y: 0, width: target, height: target))
    guard let scaled = ctx.makeImage() else { continue }
    let url = URL(fileURLWithPath: outputDir).appendingPathComponent(variant.name) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, scaled, nil)
    CGImageDestinationFinalize(dest)
    print("写出 \(variant.name)  \(variant.pixels)px")
}
print("完成")
