import AppKit
import SwiftUI

// MARK: - 纠错等级

enum QRCorrectionLevel: String, CaseIterable, Identifiable {
    case low = "L"
    case medium = "M"
    case quartile = "Q"
    case high = "H"

    var id: String { rawValue }

    var title: String { rawValue }

    var detail: String {
        switch self {
        case .low: return "7%"
        case .medium: return "15%"
        case .quartile: return "25%"
        case .high: return "30%"
        }
    }

    var tip: String {
        switch self {
        case .low: return "容错 7%，数据密度最高，适合内容很长又不受损的场景"
        case .medium: return "容错 15%，日常默认"
        case .quartile: return "容错 25%，适合会沾灰、会磨损的印刷品"
        case .high: return "容错 30%，最抗造，但码点更密、需要更大尺寸"
        }
    }
}

// MARK: - 生成参数

struct QRImageOptions {
    var text: String = ""
    var level: QRCorrectionLevel = .medium
    var targetSize: CGFloat = 768
    var quietZone: Int = 4
    var foreground: NSColor = .black
    var background: NSColor = .white
    var transparentBackground: Bool = false
}

// MARK: - 错误

enum QRGenerationError: LocalizedError {
    case emptyInput
    case encodingFailed
    case contentTooLong(Int)
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "内容是空的，二维码变不出信息来。"
        case .encodingFailed:
            return "内容无法按 UTF-8 编码。"
        case .contentTooLong(let count):
            return "内容太长（\(count) 个字符），当前纠错等级装不下。降低纠错等级或缩短内容。"
        case .renderFailed:
            return "渲染二维码失败。"
        }
    }
}

// MARK: - 扫描结果

enum PayloadKind: String, CaseIterable {
    case url = "链接"
    case wifi = "Wi-Fi"
    case vcard = "名片"
    case email = "邮件"
    case phone = "电话"
    case sms = "短信"
    case geo = "位置"
    case text = "文本"

    var systemImage: String {
        switch self {
        case .url: return "link"
        case .wifi: return "wifi"
        case .vcard: return "person.crop.rectangle"
        case .email: return "envelope"
        case .phone: return "phone"
        case .sms: return "message"
        case .geo: return "mappin.and.ellipse"
        case .text: return "text.alignleft"
        }
    }

    var tint: Color {
        switch self {
        case .url: return .blue
        case .wifi: return .teal
        case .vcard: return .orange
        case .email: return .purple
        case .phone: return .green
        case .sms: return .pink
        case .geo: return .red
        case .text: return .secondary
        }
    }

    static func detect(_ payload: String) -> PayloadKind {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = trimmed.uppercased()
        if upper.hasPrefix("HTTP://") || upper.hasPrefix("HTTPS://") { return .url }
        if upper.hasPrefix("WIFI:") { return .wifi }
        if upper.hasPrefix("BEGIN:VCARD") { return .vcard }
        if upper.hasPrefix("MAILTO:") { return .email }
        if upper.hasPrefix("TEL:") { return .phone }
        if upper.hasPrefix("SMSTO:") || upper.hasPrefix("SMS:") { return .sms }
        if upper.hasPrefix("GEO:") { return .geo }
        return .text
    }
}

struct CodeScanResult: Identifiable, Hashable {
    var id = UUID()
    var payload: String
    var symbology: String
    var confidence: Float
    /// Vision 归一化坐标，原点在左下角
    var boundingBox: CGRect
    var source: String
    var timestamp: Date = Date()

    var kind: PayloadKind { PayloadKind.detect(payload) }

    var openableURL: URL? {
        guard kind == .url else { return nil }
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: trimmed)
    }

    /// 长内容截断显示
    var displayPayload: String {
        payload.count > 4000 ? String(payload.prefix(4000)) + "…" : payload
    }
}
