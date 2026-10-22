import Foundation

// MARK: - 颜色模型

/// 归一化到 0…1 的 sRGB 颜色。所有对外接口都用它，避免 NSColor 到处传染。
struct RGBAColor: Equatable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red.clamped01
        self.green = green.clamped01
        self.blue = blue.clamped01
        self.alpha = alpha.clamped01
    }

    init(r255: Int, g255: Int, b255: Int, alpha: Double = 1) {
        self.init(
            red: Double(r255) / 255,
            green: Double(g255) / 255,
            blue: Double(b255) / 255,
            alpha: alpha
        )
    }

    var r255: Int { Int((red * 255).rounded()) }
    var g255: Int { Int((green * 255).rounded()) }
    var b255: Int { Int((blue * 255).rounded()) }
    var a255: Int { Int((alpha * 255).rounded()) }

    /// 叠在白底上的实色（用于对比度计算时忽略透明度）
    var opaqueOnWhite: RGBAColor {
        RGBAColor(
            red: red * alpha + (1 - alpha),
            green: green * alpha + (1 - alpha),
            blue: blue * alpha + (1 - alpha),
            alpha: 1
        )
    }

    static let white = RGBAColor(red: 1, green: 1, blue: 1)
    static let black = RGBAColor(red: 0, green: 0, blue: 0)
}

struct HSLColor: Equatable, Sendable {
    var hue: Double        // 0…360
    var saturation: Double // 0…1
    var lightness: Double  // 0…1
    var alpha: Double
}

struct HSVColor: Equatable, Sendable {
    var hue: Double
    var saturation: Double
    var value: Double
    var alpha: Double
}

struct CMYKColor: Equatable, Sendable {
    var cyan: Double
    var magenta: Double
    var yellow: Double
    var key: Double
}

// MARK: - 输出格式

enum ColorOutputFormat: String, CaseIterable, Identifiable, Sendable {
    case hex
    case hexAlpha
    case rgb
    case rgba
    case hsl
    case hsv
    case cmyk
    case swiftUI
    case nsColor
    case uiColor
    case android
    case flutter
    case cssVariable
    case java

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hex: return "HEX"
        case .hexAlpha: return "HEX（含透明度）"
        case .rgb: return "RGB"
        case .rgba: return "RGBA"
        case .hsl: return "HSL"
        case .hsv: return "HSV / HSB"
        case .cmyk: return "CMYK"
        case .swiftUI: return "SwiftUI"
        case .nsColor: return "AppKit NSColor"
        case .uiColor: return "UIKit UIColor"
        case .android: return "Android"
        case .flutter: return "Flutter"
        case .cssVariable: return "CSS 变量"
        case .java: return "Java / AWT"
        }
    }

    var group: String {
        switch self {
        case .hex, .hexAlpha, .rgb, .rgba, .hsl, .hsv, .cmyk: return "标准表示"
        case .swiftUI, .nsColor, .uiColor, .android, .flutter, .java: return "代码"
        case .cssVariable: return "样式"
        }
    }
}

// MARK: - 引擎

enum ColorEngine {

    // MARK: 基础工具

    static func clamp(_ value: Double, _ lower: Double = 0, _ upper: Double = 1) -> Double {
        Swift.min(Swift.max(value, lower), upper)
    }

    // MARK: 解析

    /// 吃掉各种写法：`#RGB` `#RRGGBB` `#RRGGBBAA` `#AARRGGBB`、`rgb()`、`rgba()`、
    /// `hsl()`、`hsla()`、`hsv()`、`0xFF0000`、`255,0,0`、以及 CSS 命名色。
    static func parse(_ raw: String) -> RGBAColor? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }

        // 命名色（含 transparent）
        if let named = ColorNameTable.color(named: text) { return named }

        // 0x / # 前缀统一成 #
        if text.hasPrefix("0x") { text = "#" + text.dropFirst(2) }
        if text.hasPrefix("#") {
            return parseHex(String(text.dropFirst()))
        }

        // 函数式写法
        if let open = text.firstIndex(of: "("), text.hasSuffix(")") {
            let name = String(text[text.startIndex..<open]).trimmingCharacters(in: .whitespaces)
            let body = String(text[text.index(after: open)..<text.index(before: text.endIndex)])
            let parts = body
                .replacingOccurrences(of: "/", with: ",")
                .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" })
                .map(String.init)
                .filter { !$0.isEmpty }

            switch name {
            case "rgb", "rgba":
                guard parts.count >= 3 else { return nil }
                let channels = parts.prefix(3).map { parseChannel($0) }
                guard !channels.contains(where: { $0 == nil }) else { return nil }
                let alpha = parts.count >= 4 ? parseAlpha(parts[3]) : 1
                return RGBAColor(
                    red: channels[0]!,
                    green: channels[1]!,
                    blue: channels[2]!,
                    alpha: alpha ?? 1
                )

            case "hsl", "hsla":
                guard parts.count >= 3,
                      let hue = Double(parts[0].replacingOccurrences(of: "deg", with: "")),
                      let sat = Double(parts[1].replacingOccurrences(of: "%", with: "")),
                      let light = Double(parts[2].replacingOccurrences(of: "%", with: ""))
                else { return nil }
                let alpha = parts.count >= 4 ? parseAlpha(parts[3]) : 1
                return rgb(from: HSLColor(hue: hue, saturation: sat / 100, lightness: light / 100, alpha: alpha ?? 1))

            case "hsv", "hsb":
                guard parts.count >= 3,
                      let hue = Double(parts[0].replacingOccurrences(of: "deg", with: "")),
                      let sat = Double(parts[1].replacingOccurrences(of: "%", with: "")),
                      let value = Double(parts[2].replacingOccurrences(of: "%", with: ""))
                else { return nil }
                let alpha = parts.count >= 4 ? parseAlpha(parts[3]) : 1
                return rgb(from: HSVColor(hue: hue, saturation: sat / 100, value: value / 100, alpha: alpha ?? 1))

            default:
                return nil
            }
        }

        // 裸三元组：255,0,0 或 25%,0%,0%
        let parts = text
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" || $0 == "/" })
            .map(String.init)
            .filter { !$0.isEmpty }
        if parts.count == 3 || parts.count == 4 {
            let channels = parts.prefix(3).map { parseChannel($0) }
            if !channels.contains(where: { $0 == nil }) {
                let alpha = parts.count == 4 ? parseAlpha(parts[3]) : 1
                return RGBAColor(
                    red: channels[0]!,
                    green: channels[1]!,
                    blue: channels[2]!,
                    alpha: alpha ?? 1
                )
            }
        }

        return nil
    }

    private static func parseHex(_ hex: String) -> RGBAColor? {
        let digits = hex.filter { $0.isHexDigit }
        guard digits.count == hex.count else { return nil }

        func byte(_ pair: Substring) -> Double? {
            guard let value = UInt8(pair, radix: 16) else { return nil }
            return Double(value) / 255
        }

        let chars = Array(digits)
        switch chars.count {
        case 3:
            guard let r = byte("\(chars[0])\(chars[0])"),
                  let g = byte("\(chars[1])\(chars[1])"),
                  let b = byte("\(chars[2])\(chars[2])") else { return nil }
            return RGBAColor(red: r, green: g, blue: b)
        case 4:
            guard let r = byte("\(chars[0])\(chars[0])"),
                  let g = byte("\(chars[1])\(chars[1])"),
                  let b = byte("\(chars[2])\(chars[2])"),
                  let a = byte("\(chars[3])\(chars[3])") else { return nil }
            return RGBAColor(red: r, green: g, blue: b, alpha: a)
        case 6:
            let s = String(digits)
            guard let r = byte(s.prefix(2)),
                  let g = byte(s.dropFirst(2).prefix(2)),
                  let b = byte(s.dropFirst(4).prefix(2)) else { return nil }
            return RGBAColor(red: r, green: g, blue: b)
        case 8:
            let s = String(digits)
            guard let r = byte(s.prefix(2)),
                  let g = byte(s.dropFirst(2).prefix(2)),
                  let b = byte(s.dropFirst(4).prefix(2)),
                  let a = byte(s.dropFirst(6).prefix(2)) else { return nil }
            // 八位一律按 Web 惯例的 #RRGGBBAA 读。
            // （#AARRGGBB 和它无法区分，硬猜只会坑人；Android 色值在输出那一侧单独给。）
            return RGBAColor(red: r, green: g, blue: b, alpha: a)
        default:
            return nil
        }
    }

    private static func parseChannel(_ text: String) -> Double? {
        if text.hasSuffix("%") {
            guard let value = Double(text.dropLast()) else { return nil }
            return clamp(value / 100)
        }
        guard let value = Double(text) else { return nil }
        return clamp(value / 255)
    }

    private static func parseAlpha(_ text: String) -> Double? {
        if text.hasSuffix("%") {
            guard let value = Double(text.dropLast()) else { return nil }
            return clamp(value / 100)
        }
        guard let value = Double(text) else { return nil }
        // 1 以内当 0…1，超过则当 0…255
        return clamp(value > 1 ? value / 255 : value)
    }

    // MARK: 色彩空间互转

    static func rgb(from hsl: HSLColor) -> RGBAColor {
        let h = hsl.hue.truncatingRemainder(dividingBy: 360) / 360
        let s = clamp(hsl.saturation)
        let l = clamp(hsl.lightness)

        if s == 0 {
            return RGBAColor(red: l, green: l, blue: l, alpha: hsl.alpha)
        }

        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q

        func hueToRGB(_ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }

        return RGBAColor(
            red: hueToRGB(h + 1.0 / 3),
            green: hueToRGB(h),
            blue: hueToRGB(h - 1.0 / 3),
            alpha: hsl.alpha
        )
    }

    static func hsl(from color: RGBAColor) -> HSLColor {
        let r = color.red, g = color.green, b = color.blue
        let maxValue = max(r, g, b)
        let minValue = min(r, g, b)
        let delta = maxValue - minValue

        var hue: Double = 0
        if delta > 0 {
            if maxValue == r {
                hue = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
            } else if maxValue == g {
                hue = 60 * ((b - r) / delta + 2)
            } else {
                hue = 60 * ((r - g) / delta + 4)
            }
        }
        if hue < 0 { hue += 360 }

        let lightness = (maxValue + minValue) / 2
        let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))

        return HSLColor(hue: hue, saturation: clamp(saturation), lightness: lightness, alpha: color.alpha)
    }

    static func hsv(from color: RGBAColor) -> HSVColor {
        let r = color.red, g = color.green, b = color.blue
        let maxValue = max(r, g, b)
        let minValue = min(r, g, b)
        let delta = maxValue - minValue

        var hue: Double = 0
        if delta > 0 {
            if maxValue == r {
                hue = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
            } else if maxValue == g {
                hue = 60 * ((b - r) / delta + 2)
            } else {
                hue = 60 * ((r - g) / delta + 4)
            }
        }
        if hue < 0 { hue += 360 }

        return HSVColor(
            hue: hue,
            saturation: maxValue == 0 ? 0 : clamp(delta / maxValue),
            value: maxValue,
            alpha: color.alpha
        )
    }

    static func rgb(from hsv: HSVColor) -> RGBAColor {
        let h = (hsv.hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let s = clamp(hsv.saturation)
        let v = clamp(hsv.value)

        let c = v * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c

        let (r, g, b): (Double, Double, Double)
        switch h {
        case 0..<60: (r, g, b) = (c, x, 0)
        case 60..<120: (r, g, b) = (x, c, 0)
        case 120..<180: (r, g, b) = (0, c, x)
        case 180..<240: (r, g, b) = (0, x, c)
        case 240..<300: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }

        return RGBAColor(red: r + m, green: g + m, blue: b + m, alpha: hsv.alpha)
    }

    static func cmyk(from color: RGBAColor) -> CMYKColor {
        let r = color.red, g = color.green, b = color.blue
        let key = 1 - max(r, g, b)
        guard key < 1 else { return CMYKColor(cyan: 0, magenta: 0, yellow: 0, key: 1) }
        return CMYKColor(
            cyan: (1 - r - key) / (1 - key),
            magenta: (1 - g - key) / (1 - key),
            yellow: (1 - b - key) / (1 - key),
            key: key
        )
    }

    static func rgb(from cmyk: CMYKColor) -> RGBAColor {
        RGBAColor(
            red: (1 - cmyk.cyan) * (1 - cmyk.key),
            green: (1 - cmyk.magenta) * (1 - cmyk.key),
            blue: (1 - cmyk.yellow) * (1 - cmyk.key)
        )
    }

    // MARK: 感知

    /// WCAG 相对亮度（sRGB 线性化后加权）
    static func relativeLuminance(_ color: RGBAColor) -> Double {
        let solid = color.opaqueOnWhite
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(solid.red) + 0.7152 * linear(solid.green) + 0.0722 * linear(solid.blue)
    }

    /// WCAG 对比度，1…21
    static func contrast(_ a: RGBAColor, _ b: RGBAColor) -> Double {
        let l1 = relativeLuminance(a)
        let l2 = relativeLuminance(b)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    static func isDark(_ color: RGBAColor) -> Bool {
        relativeLuminance(color) < 0.5
    }

    /// 在黑白之间挑一个更清楚的前景色
    static func readableForeground(on color: RGBAColor) -> RGBAColor {
        contrast(RGBAColor(red: 1, green: 1, blue: 1), color) >= contrast(RGBAColor(red: 0, green: 0, blue: 0), color)
            ? RGBAColor(red: 1, green: 1, blue: 1)
            : RGBAColor(red: 0, green: 0, blue: 0)
    }

    /// 感知亮度（YIQ），用来粗判深浅
    static func perceptualBrightness(_ color: RGBAColor) -> Double {
        let red = Double(color.r255) * 299
        let green = Double(color.g255) * 587
        let blue = Double(color.b255) * 114
        return (red + green + blue) / 1000
    }

    // MARK: 微调

    static func adjust(_ color: RGBAColor, hueShift: Double = 0, saturationScale: Double = 1, brightnessScale: Double = 1) -> RGBAColor {
        var hsv = hsv(from: color)
        hsv.hue = (hsv.hue + hueShift).truncatingRemainder(dividingBy: 360)
        if hsv.hue < 0 { hsv.hue += 360 }
        hsv.saturation = clamp(hsv.saturation * saturationScale)
        hsv.value = clamp(hsv.value * brightnessScale)
        return rgb(from: hsv)
    }

    // MARK: 输出

    static func string(for color: RGBAColor, format: ColorOutputFormat) -> String {
        // 不含透明度的格式直接给原始 RGB —— 用户要的是"这个颜色的色值"，
        // 而不是它叠在白底上看起来像什么。（对比度那类感知计算才需要压到实色。）
        let solid = color
        switch format {
        case .hex:
            return String(format: "#%02X%02X%02X", solid.r255, solid.g255, solid.b255)

        case .hexAlpha:
            return String(format: "#%02X%02X%02X%02X", solid.r255, solid.g255, solid.b255, color.a255)

        case .rgb:
            return "rgb(\(solid.r255), \(solid.g255), \(solid.b255))"

        case .rgba:
            return "rgba(\(solid.r255), \(solid.g255), \(solid.b255), \(trimmed(color.alpha)))"

        case .hsl:
            let hsl = self.hsl(from: solid)
            return "hsl(\(Int(hsl.hue.rounded())), \(Int((hsl.saturation * 100).rounded()))%, \(Int((hsl.lightness * 100).rounded()))%)"

        case .hsv:
            let hsv = self.hsv(from: solid)
            return "hsv(\(Int(hsv.hue.rounded())), \(Int((hsv.saturation * 100).rounded()))%, \(Int((hsv.value * 100).rounded()))%)"

        case .cmyk:
            let cmyk = self.cmyk(from: solid)
            return String(
                format: "cmyk(%d%%, %d%%, %d%%, %d%%)",
                Int((cmyk.cyan * 100).rounded()),
                Int((cmyk.magenta * 100).rounded()),
                Int((cmyk.yellow * 100).rounded()),
                Int((cmyk.key * 100).rounded())
            )

        case .swiftUI:
            if color.alpha >= 0.999 {
                return String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)", solid.red, solid.green, solid.blue)
            }
            return String(
                format: "Color(.sRGB, red: %.3f, green: %.3f, blue: %.3f, opacity: %.2f)",
                solid.red, solid.green, solid.blue, color.alpha
            )

        case .nsColor:
            return String(
                format: "NSColor(srgbRed: %.3f, green: %.3f, blue: %.3f, alpha: %.2f)",
                solid.red, solid.green, solid.blue, color.alpha
            )

        case .uiColor:
            return String(
                format: "UIColor(red: %.3f, green: %.3f, blue: %.3f, alpha: %.2f)",
                solid.red, solid.green, solid.blue, color.alpha
            )

        case .android:
            return String(format: "#%02X%02X%02X%02X", color.a255, solid.r255, solid.g255, solid.b255)

        case .flutter:
            return String(format: "Color(0x%02X%02X%02X%02X)", color.a255, solid.r255, solid.g255, solid.b255)

        case .java:
            return String(format: "new Color(%d, %d, %d, %d)", solid.r255, solid.g255, solid.b255, color.a255)

        case .cssVariable:
            return String(format: "--color: #%02X%02X%02X;", solid.r255, solid.g255, solid.b255)
        }
    }

    private static func trimmed(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.2f", rounded)
    }

    // MARK: 配色生成

    /// 给一个基色生成一组配得上的颜色（互补、三分、近似、明暗阶梯）
    static func palette(from color: RGBAColor) -> [(String, RGBAColor)] {
        let hsl = self.hsl(from: color)
        func make(_ name: String, _ hue: Double, _ sat: Double, _ light: Double) -> (String, RGBAColor) {
            (name, rgb(from: HSLColor(hue: (hsl.hue + hue).truncatingRemainder(dividingBy: 360),
                                     saturation: clamp(sat),
                                     lightness: clamp(light),
                                     alpha: color.alpha)))
        }
        return [
            make("原色", 0, hsl.saturation, hsl.lightness),
            make("同类·浅", 0, hsl.saturation, self.clamp(hsl.lightness + 0.18)),
            make("同类·深", 0, hsl.saturation, self.clamp(hsl.lightness - 0.18)),
            make("互补", 180, hsl.saturation, hsl.lightness),
            make("邻近 +30°", 30, hsl.saturation, hsl.lightness),
            make("邻近 -30°", -30, hsl.saturation, hsl.lightness),
            make("三分 +120°", 120, hsl.saturation, hsl.lightness),
            make("三分 -120°", 240, hsl.saturation, hsl.lightness),
            make("去饱和", 0, hsl.saturation * 0.35, hsl.lightness),
            make("高饱和", 0, self.clamp(hsl.saturation * 1.4), self.clamp(hsl.lightness * 0.95)),
        ]
    }
}

extension Double {
    var clamped01: Double { Swift.min(Swift.max(self, 0), 1) }
}
