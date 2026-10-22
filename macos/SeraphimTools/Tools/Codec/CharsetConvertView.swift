import CoreFoundation
import Foundation
import SwiftUI

// MARK: - 错误

enum CharsetError: LocalizedError {
    case cannotEncode(String)
    case cannotDecode(String)

    var errorDescription: String? {
        switch self {
        case .cannotEncode(let name):
            return "这段文本里有 \(name) 表示不了的字符，换个源编码或者删掉那些字符。"
        case .cannotDecode(let name):
            return "按 \(name) 解释这串字节失败了，字节序列不合法，换个目标编码试试。"
        }
    }
}

// MARK: - 界面

struct CharsetConvertView: View {
    @State private var input = ""
    @State private var source: TextCharset = .utf8
    @State private var target: TextCharset = .gb18030
    @State private var toast: String?

    private var outcome: Result<(data: Data, text: String), Error> {
        guard !input.isEmpty else { return .success((Data(), "")) }
        guard let data = input.data(using: source.encoding) else {
            return .failure(CharsetError.cannotEncode(source.title))
        }
        guard let text = String(data: data, encoding: target.encoding) else {
            return .failure(CharsetError.cannotDecode(target.title))
        }
        return .success((data, text))
    }

    private var outputText: String {
        if case .success(let value) = outcome { return value.text }
        return ""
    }

    private var payload: Data {
        if case .success(let value) = outcome { return value.data }
        return Data()
    }

    private var errorMessage: String? {
        if case .failure(let error) = outcome { return error.localizedDescription }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                encodingBar

                TextPane(
                    title: "原文",
                    text: $input,
                    placeholder: "输入或粘贴文本…",
                    minHeight: 140,
                    buttons: [
                        PaneButton(systemImage: "doc.on.clipboard", help: "从剪贴板粘贴") {
                            if let string = NSPasteboard.general.string(forType: .string) {
                                input = string
                            } else {
                                toast = "剪贴板里没有文本"
                                NSSound.beep()
                            }
                        },
                        PaneButton(systemImage: "trash", help: "清空") { input = "" },
                    ]
                )

                bytePreview

                VStack(spacing: 10) {
                    if let errorMessage {
                        ErrorBanner(message: errorMessage)
                    }
                    TextPane(
                        title: "按 \(target.title) 解释的结果",
                        text: .constant(outputText),
                        isEditable: false,
                        placeholder: errorMessage ?? "结果会实时出现在这里",
                        minHeight: 140,
                        buttons: [
                            PaneButton(systemImage: "doc.on.doc", help: "复制结果") {
                                guard !outputText.isEmpty else { return }
                                NSPasteboard.copyString(outputText)
                                toast = "结果已复制"
                            },
                        ]
                    )
                }
            }
            .padding(20)
        }
        .toast($toast)
    }

    private var encodingBar: some View {
        ToolCard(title: "字符集", systemImage: "textformat.size") {
            HStack(spacing: 10) {
                charsetPicker("源编码", selection: $source)

                Button {
                    let temp = source
                    source = target
                    target = temp
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .buttonStyle(.borderless)
                .help("互换源编码和目标编码")

                charsetPicker("目标编码", selection: $target)

                Spacer(minLength: 8)

                Text("常用套路：一段被当成 \(target.title) 显示的乱码，把源编码设成 \(source.title) 再转回来")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .frame(maxWidth: 300, alignment: .trailing)
            }
        }
    }

    private func charsetPicker(_ title: String, selection: Binding<TextCharset>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Picker("", selection: selection) {
                ForEach(TextCharset.allCases) { charset in
                    Text(charset.title).tag(charset)
                }
            }
            .labelsHidden()
            .frame(width: 176)
        }
    }

    private var bytePreview: some View {
        ToolCard(title: "字节视图", systemImage: "square.split.2x1") {
            if payload.isEmpty {
                Text("上面的文本按\(source.title)编码后会变成这些字节")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("共 \(payload.count) 字节" + (payload.count > 256 ? "，下面只显示前 256 字节" : ""))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(hexDump(payload))
                            .font(.system(size: 11.5, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                    }
                    .background(
                        Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10))
                    )
                }
            }
        }
    }

    /// 经典 hex dump：偏移 + 16 字节十六进制 + 右侧 ASCII
    private func hexDump(_ data: Data) -> String {
        let bytes = [UInt8](data.prefix(256))
        var lines: [String] = []
        var offset = 0
        while offset < bytes.count {
            let chunk = Array(bytes[offset..<min(offset + 16, bytes.count)])
            let hex = chunk.map { String(format: "%02X", $0) }.joined(separator: " ")
            let padded = hex.padding(toLength: 47, withPad: " ", startingAt: 0)
            let ascii = chunk.map { byte -> String in
                (0x20...0x7E).contains(byte) ? String(UnicodeScalar(byte)) : "."
            }.joined()
            lines.append(String(format: "%04X  %@  %@", offset, padded, ascii))
            offset += 16
        }
        return lines.joined(separator: "\n")
    }
}
