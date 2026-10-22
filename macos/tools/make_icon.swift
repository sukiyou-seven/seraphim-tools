#!/usr/bin/env swift
// 用 Swift 直接画出 App 图标，输出到 Assets.xcassets/AppIcon.appiconset
// 用法: swift tools/make_icon.swift [输出目录]

import AppKit
import CoreGraphics
import Foundation

let outputDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: "SeraphimTools/Assets.xcassets/AppIcon.appiconset")

func makeIcon(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { fatalError("无法创建位图") }

    rep.size = NSSize(width: size, height: size)

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("无法创建绘图上下文") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    let bounds = NSRect(x: 0, y: 0, width: size, height: size)

    // MARK: 底板（macOS 风格的圆角方形 + 留白）
    let inset = size * 0.055
    let plate = bounds.insetBy(dx: inset, dy: inset)
    let radius = plate.width * 0.225
    let platePath = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)

    platePath.addClip()
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.42, green: 0.33, blue: 0.98, alpha: 1),
        NSColor(srgbRed: 0.62, green: 0.28, blue: 0.94, alpha: 1),
    ])!
    gradient.draw(in: plate, angle: -60)

    // 顶部高光
    let highlight = NSGradient(colors: [
        NSColor(white: 1, alpha: 0.22),
        NSColor(white: 1, alpha: 0.0),
    ])!
    highlight.draw(in: NSRect(x: plate.minX, y: plate.midY, width: plate.width, height: plate.height / 2), angle: -90)

    // MARK: 二维码图案（自绘，避免 SF Symbol 在小尺寸下糊成一团）
    let grid = 11
    let margin = plate.width * 0.215
    let drawArea = plate.insetBy(dx: margin, dy: margin)
    let cell = drawArea.width / CGFloat(grid)
    let dotRadius = cell * 0.16

    // 三个定位角 + 若干数据点
    var modules: [(Int, Int)] = []
    let finders = [(0, 0), (0, grid - 3), (grid - 3, 0)]
    for (r0, c0) in finders {
        for r in 0..<3 {
            for c in 0..<3 {
                let isBorder = r == 0 || r == 2 || c == 0 || c == 2
                if isBorder { modules.append((r0 + r, c0 + c)) }
            }
        }
    }
    // 定位角中心的小实心块
    for (r0, c0) in finders {
        modules.append((r0 + 1, c0 + 1))
    }
    // 右下区域的数据点（固定图案，保证每次生成一致）
    let dataPoints = [
        (5, 5), (5, 7), (5, 9),
        (7, 5), (7, 6), (7, 9), (7, 10),
        (9, 5), (9, 8),
        (3, 5), (3, 8), (3, 10),
        (5, 3), (6, 3), (8, 3),
        (10, 3), (4, 7), (4, 9),
    ]
    modules.append(contentsOf: dataPoints)

    NSColor.white.setFill()
    for (row, col) in modules {
        // 注意：NSBezierPath 的 y 轴向上，网格行要翻转
        let x = drawArea.minX + CGFloat(col) * cell
        let y = drawArea.maxY - CGFloat(row + 1) * cell
        let rect = NSRect(x: x, y: y, width: cell, height: cell).insetBy(dx: cell * 0.04, dy: cell * 0.04)
        NSBezierPath(roundedRect: rect, xRadius: dotRadius, yRadius: dotRadius).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let sizes: [(CGFloat, String)] = [
    (16, "icon_16.png"),
    (32, "icon_16@2x.png"),
    (32, "icon_32.png"),
    (64, "icon_32@2x.png"),
    (128, "icon_128.png"),
    (256, "icon_128@2x.png"),
    (256, "icon_256.png"),
    (512, "icon_256@2x.png"),
    (512, "icon_512.png"),
    (1024, "icon_512@2x.png"),
]

try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

for (size, name) in sizes {
    let rep = makeIcon(size: size)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("导出 PNG 失败: \(name)")
    }
    try data.write(to: outputDir.appendingPathComponent(name))
    print("已生成 \(name) (\(Int(size))px)")
}
