import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct QRCodeGenerateView: View {

    // 内容
    @State private var text = "https://www.apple.com.cn"
    @State private var level: QRCorrectionLevel = .medium

    // 外观
    @State private var targetSize: Double = 768
    @State private var quietZone: Int = 4
    @State private var useCustomColors = false
    @State private var foregroundColor: Color = .black
    @State private var backgroundColor: Color = .white
    @State private var transparentBackground = false

    @State private var toast: String?

    private var options: QRImageOptions {
        QRImageOptions(
            text: text,
            level: level,
            targetSize: targetSize,
            quietZone: quietZone,
            foreground: useCustomColors ? NSColor(foregroundColor) : .black,
            background: transparentBackground ? .clear : (useCustomColors ? NSColor(backgroundColor) : .white),
            transparentBackground: transparentBackground
        )
    }

    private var rendered: Result<CGImage, Error> {
        Result { try QRCodeGenerator.cgImage(for: options) }
    }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    contentCard
                    appearanceCard
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 16) {
                    previewCard
                    exportCard
                }
                .frame(width: 330)
            }
            .padding(20)
        }
        .toast($toast)
    }

    // MARK: - 内容

    private var contentCard: some View {
        ToolCard(title: "内容", systemImage: "text.cursor") {
            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 110)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10))
                )

            HStack {
                Text("\(text.count) 字符 · \(byteCount) 字节")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    if let string = NSPasteboard.general.string(forType: .string) {
                        text = string
                    } else {
                        toast = "剪贴板里没有文本"
                    }
                } label: {
                    Label("粘贴", systemImage: "doc.on.clipboard")
                }
                .controlSize(.small)
                Button {
                    text = ""
                } label: {
                    Label("清空", systemImage: "trash")
                }
                .controlSize(.small)
                .disabled(text.isEmpty)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("快捷模板")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FlowRow(spacing: 8) {
                    ForEach(QRContentTemplate.allCases) { template in
                        Button(template.title) {
                            text = template.sample
                            toast = "已填入 \(template.title) 模板"
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var byteCount: Int {
        text.data(using: .utf8)?.count ?? 0
    }

    // MARK: - 外观

    private var appearanceCard: some View {
        ToolCard(title: "外观", systemImage: "paintpalette") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("纠错等级")
                    Spacer()
                    Text("容错 \(level.detail)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("纠错等级", selection: $level) {
                    ForEach(QRCorrectionLevel.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(level.tip)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("输出尺寸")
                    Spacer()
                    Text("\(Int(targetSize)) px")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $targetSize, in: 128...2048, step: 64)
                HStack(spacing: 8) {
                    ForEach([256.0, 512.0, 768.0, 1024.0, 2048.0], id: \.self) { preset in
                        Button("\(Int(preset))") { targetSize = preset }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("静默区（码点）")
                    Spacer()
                    Text("\(quietZone)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Stepper(value: $quietZone, in: 0...12) {
                    Text(quietZone == 0 ? "没有留白，贴在深色背景上会扫不出来" : "四周留白 \(quietZone) 个码点")
                        .font(.caption)
                        .foregroundStyle(quietZone == 0 ? .orange : .secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Toggle("自定义颜色", isOn: $useCustomColors)
                if useCustomColors {
                    HStack(spacing: 16) {
                        ColorPicker("前景", selection: $foregroundColor, supportsOpacity: false)
                        ColorPicker("背景", selection: $backgroundColor, supportsOpacity: false)
                            .disabled(transparentBackground)
                    }
                }
                Toggle("透明背景", isOn: $transparentBackground)
                Text("深色前景 + 浅色背景对比度越高越好认；反色（浅码深底）很多手机扫不出来。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 预览

    private var previewCard: some View {
        ToolCard(title: "预览", systemImage: "eye") {
            VStack(spacing: 10) {
                Group {
                    switch rendered {
                    case .success(let cgImage):
                        Image(decorative: cgImage, scale: 1)
                            .resizable()
                            .interpolation(.none)
                            .aspectRatio(1, contentMode: .fit)
                    case .failure:
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                            Image(systemName: "qrcode")
                                .font(.system(size: 40))
                                .foregroundStyle(.quaternary)
                        }
                        .aspectRatio(1, contentMode: .fit)
                    }
                }
                .frame(maxWidth: 260, maxHeight: 260)
                .background {
                    if transparentBackground {
                        Checkerboard()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12))
                )

                statusLine
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch rendered {
        case .success(let cgImage):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("\(cgImage.width) × \(cgImage.height) px")
                    .font(.caption.monospacedDigit())
                if let matrix = try? QRCodeGenerator.moduleMatrix(for: options) {
                    Text("· \(matrix.count) × \(matrix.count) 码点")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        case .failure(let error):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error.localizedDescription)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 导出

    private var exportCard: some View {
        ToolCard(title: "导出", systemImage: "square.and.arrow.down") {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        copyImage()
                    } label: {
                        Label("拷贝图像", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!isValid)

                    Button {
                        savePNG()
                    } label: {
                        Label("PNG", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!isValid)
                }

                HStack(spacing: 8) {
                    Button {
                        saveSVG()
                    } label: {
                        Label("SVG 矢量", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!isValid)

                    Button {
                        NSPasteboard.copyString(text)
                        toast = "内容已拷贝"
                    } label: {
                        Label("拷贝内容", systemImage: "textformat")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(text.isEmpty)
                }
            }
        }
    }

    private var isValid: Bool {
        if case .success = rendered { return true }
        return false
    }

    // MARK: - 动作

    private func copyImage() {
        guard case .success(let cgImage) = rendered else { return }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        PasteboardWriter.copyImage(image)
        toast = "图像已拷贝到剪贴板"
    }

    private func savePNG() {
        guard case .success(let cgImage) = rendered,
              let data = ImageCodec.pngData(from: cgImage) else { return }
        if ImageCodec.save(data: data, suggestedName: "qrcode.png", contentType: .png) != nil {
            toast = "已保存 PNG"
        }
    }

    private func saveSVG() {
        guard let svg = try? QRCodeGenerator.svg(for: options),
              let data = svg.data(using: .utf8) else { return }
        if ImageCodec.save(data: data, suggestedName: "qrcode.svg", contentType: .svg) != nil {
            toast = "已保存 SVG"
        }
    }
}

// MARK: - 模板

enum QRContentTemplate: String, CaseIterable, Identifiable {
    case url, text, wifi, vcard, email, phone, sms, geo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .url: return "网址"
        case .text: return "纯文本"
        case .wifi: return "Wi-Fi"
        case .vcard: return "名片"
        case .email: return "邮件"
        case .phone: return "电话"
        case .sms: return "短信"
        case .geo: return "位置"
        }
    }

    var sample: String {
        switch self {
        case .url: return "https://www.example.com"
        case .text: return "在这里写点什么"
        case .wifi: return "WIFI:T:WPA;S:MyWiFi;P:password123;H:false;;"
        case .vcard: return """
        BEGIN:VCARD
        VERSION:3.0
        N:张;三
        FN:张三
        ORG:示例公司
        TEL:+8613800000000
        EMAIL:zhangsan@example.com
        URL:https://www.example.com
        END:VCARD
        """
        case .email: return "mailto:hello@example.com?subject=你好"
        case .phone: return "tel:+8613800000000"
        case .sms: return "SMSTO:+8613800000000:你好"
        case .geo: return "geo:39.9042,116.4074"
        }
    }
}
