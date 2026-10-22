import Foundation

/// CSS 命名颜色表。顺带提供"这个色最接近哪个名字"的查询——
/// 拿到一个 #FA8072 的时候，人脑认不出，但"salmon"能认出来。
enum ColorNameTable {

    /// 名字 → 24 位 RGB
    static let raw: [String: UInt32] = [
        "aliceblue": 0xF0F8FF, "antiquewhite": 0xFAEBD7, "aqua": 0x00FFFF,
        "aquamarine": 0x7FFFD4, "azure": 0xF0FFFF, "beige": 0xF5F5DC,
        "bisque": 0xFFE4C4, "black": 0x000000, "blanchedalmond": 0xFFEBCD,
        "blue": 0x0000FF, "blueviolet": 0x8A2BE2, "brown": 0xA52A2A,
        "burlywood": 0xDEB887, "cadetblue": 0x5F9EA0, "chartreuse": 0x7FFF00,
        "chocolate": 0xD2691E, "coral": 0xFF7F50, "cornflowerblue": 0x6495ED,
        "cornsilk": 0xFFF8DC, "crimson": 0xDC143C, "cyan": 0x00FFFF,
        "darkblue": 0x00008B, "darkcyan": 0x008B8B, "darkgoldenrod": 0xB8860B,
        "darkgray": 0xA9A9A9, "darkgreen": 0x006400, "darkgrey": 0xA9A9A9,
        "darkkhaki": 0xBDB76B, "darkmagenta": 0x8B008B, "darkolivegreen": 0x556B2F,
        "darkorange": 0xFF8C00, "darkorchid": 0x9932CC, "darkred": 0x8B0000,
        "darksalmon": 0xE9967A, "darkseagreen": 0x8FBC8F, "darkslateblue": 0x483D8B,
        "darkslategray": 0x2F4F4F, "darkslategrey": 0x2F4F4F, "darkturquoise": 0x00CED1,
        "darkviolet": 0x9400D3, "deeppink": 0xFF1493, "deepskyblue": 0x00BFFF,
        "dimgray": 0x696969, "dimgrey": 0x696969, "dodgerblue": 0x1E90FF,
        "firebrick": 0xB22222, "floralwhite": 0xFFFAF0, "forestgreen": 0x228B22,
        "fuchsia": 0xFF00FF, "gainsboro": 0xDCDCDC, "ghostwhite": 0xF8F8FF,
        "gold": 0xFFD700, "goldenrod": 0xDAA520, "gray": 0x808080,
        "green": 0x008000, "greenyellow": 0xADFF2F, "grey": 0x808080,
        "honeydew": 0xF0FFF0, "hotpink": 0xFF69B4, "indianred": 0xCD5C5C,
        "indigo": 0x4B0082, "ivory": 0xFFFFF0, "khaki": 0xF0E68C,
        "lavender": 0xE6E6FA, "lavenderblush": 0xFFF0F5, "lawngreen": 0x7CFC00,
        "lemonchiffon": 0xFFFACD, "lightblue": 0xADD8E6, "lightcoral": 0xF08080,
        "lightcyan": 0xE0FFFF, "lightgoldenrodyellow": 0xFAFAD2, "lightgray": 0xD3D3D3,
        "lightgreen": 0x90EE90, "lightgrey": 0xD3D3D3, "lightpink": 0xFFB6C1,
        "lightsalmon": 0xFFA07A, "lightseagreen": 0x20B2AA, "lightskyblue": 0x87CEFA,
        "lightslategray": 0x778899, "lightslategrey": 0x778899, "lightsteelblue": 0xB0C4DE,
        "lightyellow": 0xFFFFE0, "lime": 0x00FF00, "limegreen": 0x32CD32,
        "linen": 0xFAF0E6, "magenta": 0xFF00FF, "maroon": 0x800000,
        "mediumaquamarine": 0x66CDAA, "mediumblue": 0x0000CD, "mediumorchid": 0xBA55D3,
        "mediumpurple": 0x9370DB, "mediumseagreen": 0x3CB371, "mediumslateblue": 0x7B68EE,
        "mediumspringgreen": 0x00FA9A, "mediumturquoise": 0x48D1CC, "mediumvioletred": 0xC71585,
        "midnightblue": 0x191970, "mintcream": 0xF5FFFA, "mistyrose": 0xFFE4E1,
        "moccasin": 0xFFE4B5, "navajowhite": 0xFFDEAD, "navy": 0x000080,
        "oldlace": 0xFDF5E6, "olive": 0x808000, "olivedrab": 0x6B8E23,
        "orange": 0xFFA500, "orangered": 0xFF4500, "orchid": 0xDA70D6,
        "palegoldenrod": 0xEEE8AA, "palegreen": 0x98FB98, "paleturquoise": 0xAFEEEE,
        "palevioletred": 0xDB7093, "papayawhip": 0xFFEFD5, "peachpuff": 0xFFDAB9,
        "peru": 0xCD853F, "pink": 0xFFC0CB, "plum": 0xDDA0DD,
        "powderblue": 0xB0E0E6, "purple": 0x800080, "rebeccapurple": 0x663399,
        "red": 0xFF0000, "rosybrown": 0xBC8F8F, "royalblue": 0x4169E1,
        "saddlebrown": 0x8B4513, "salmon": 0xFA8072, "sandybrown": 0xF4A460,
        "seagreen": 0x2E8B57, "seashell": 0xFFF5EE, "sienna": 0xA0522D,
        "silver": 0xC0C0C0, "skyblue": 0x87CEEB, "slateblue": 0x6A5ACD,
        "slategray": 0x708090, "slategrey": 0x708090, "snow": 0xFFFAFA,
        "springgreen": 0x00FF7F, "steelblue": 0x4682B4, "tan": 0xD2B48C,
        "teal": 0x008080, "thistle": 0xD8BFD8, "tomato": 0xFF6347,
        "turquoise": 0x40E0D0, "violet": 0xEE82EE, "wheat": 0xF5DEB3,
        "white": 0xFFFFFF, "whitesmoke": 0xF5F5F5, "yellow": 0xFFFF00,
        "yellowgreen": 0x9ACD32,
    ]

    /// 中文常用叫法到命名色的映射，纯为输入方便
    private static let aliases: [String: String] = [
        "红": "red", "红色": "red", "绿": "green", "绿色": "green",
        "蓝": "blue", "蓝色": "blue", "黑": "black", "黑色": "black",
        "白": "white", "白色": "white", "灰": "gray", "灰色": "gray",
        "黄": "yellow", "黄色": "yellow", "橙": "orange", "橙色": "orange",
        "紫": "purple", "紫色": "purple", "粉": "pink", "粉色": "pink",
        "青": "cyan", "青色": "cyan", "棕": "brown", "棕色": "brown",
        "金": "gold", "金色": "gold", "银": "silver", "银色": "silver",
        "海军蓝": "navy", "天蓝": "skyblue", "草绿": "limegreen",
        "番茄红": "tomato", "珊瑚": "coral", "鲑鱼色": "salmon",
        "米色": "beige", "象牙白": "ivory", "雪白": "snow",
    ]

    static func color(named name: String) -> RGBAColor? {
        var key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key == "transparent" { return RGBAColor(red: 0, green: 0, blue: 0, alpha: 0) }
        if key == "none" { return RGBAColor(red: 0, green: 0, blue: 0, alpha: 0) }
        if let alias = aliases[key] { key = alias }
        guard let value = raw[key] else { return nil }
        return RGBAColor(
            r255: Int((value >> 16) & 0xFF),
            g255: Int((value >> 8) & 0xFF),
            b255: Int(value & 0xFF)
        )
    }

    /// 最接近的命名色。先按 RGB 距离筛一遍，再按色相差异打散同距离的候选。
    static func nearestName(for color: RGBAColor) -> (name: String, color: RGBAColor, distance: Double)? {
        var best: (name: String, color: RGBAColor, distance: Double)?
        let target = ColorEngine.hsv(from: color)

        for (name, value) in raw where !(name.hasSuffix("grey") && name != "grey") {
            let candidate = RGBAColor(
                r255: Int((value >> 16) & 0xFF),
                g255: Int((value >> 8) & 0xFF),
                b255: Int(value & 0xFF)
            )
            let dr = candidate.red - color.red
            let dg = candidate.green - color.green
            let db = candidate.blue - color.blue
            let rgbDistance = (dr * dr + dg * dg + db * db).squareRoot()

            let candidateHSV = ColorEngine.hsv(from: candidate)
            var hueDelta = abs(candidateHSV.hue - target.hue)
            if hueDelta > 180 { hueDelta = 360 - hueDelta }
            // 灰色系色相没意义，不加惩罚
            let huePenalty = (candidateHSV.saturation < 0.05 || target.saturation < 0.05) ? 0 : hueDelta / 360 * 0.35

            let score = rgbDistance + huePenalty
            if best == nil || score < best!.distance {
                best = (name, candidate, score)
            }
        }
        return best
    }

    /// 按色相挑一组"好看的邻居"，给快捷取色用
    static let quickPicks: [(name: String, hex: String)] = [
        ("红", "#E5484D"), ("橙", "#F76B15"), ("琥珀", "#FFB224"),
        ("黄", "#F5D90A"), ("青柠", "#99D52A"), ("绿", "#30A46C"),
        ("翡翠", "#12A594"), ("青", "#00A2C7"), ("天蓝", "#0091FF"),
        ("蓝", "#3E63DD"), ("靛", "#5B5BD6"), ("紫", "#8E4EC6"),
        ("品红", "#D6409F"), ("玫瑰", "#E93D82"), ("棕", "#AD7F58"),
        ("石墨", "#60646C"), ("浅灰", "#D7DBDF"), ("黑", "#1C2024"),
        ("白", "#FFFFFF"), ("品牌金", "#C9A227"),
    ]
}
