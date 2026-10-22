import AppKit
import SwiftUI

/// 古典密码。全都是可逆的，没有单向的那种。
struct CryptoClassicView: View {
    enum CipherDirection: String, CaseIterable, Identifiable {
        case encode
        case decode

        var id: String { rawValue }

        var title: String {
            switch self {
            case .encode: return "加密"
            case .decode: return "解密"
            }
        }
    }

    @AppStorage("classicCipher") private var cipher: ClassicCipher = .caesar

    @State private var direction: CipherDirection = .encode
    @State private var input = ""
    @State private var shift = 3
    @State private var key = "SERAPHIM"
    @State private var xorFormat: XORFormat = .hex
    @State private var toast: String?

    private var output: String {
        guard !input.isEmpty else { return "" }
        switch cipher {
        case .caesar:
            return CryptoEngine.caesar(input, shift: direction == .encode ? shift : -shift)
        case .rot13:
            return CryptoEngine.caesar(input, shift: 13)
        case .vigenere:
            return CryptoEngine.vigenere(input, key: key, decode: direction == .decode)
        case .xor:
            if direction == .encode {
                return CryptoEngine.xorEncode(input, key: key, format: xorFormat)
            }
            return (try? CryptoEngine.xorDecode(input, key: key)) ?? ""
        case .morse:
            return direction == .encode
                ? CryptoEngine.morseEncode(input)
                : CryptoEngine.morseDecode(input)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                cipherCard
                parameterCard

                TextPane(
                    title: direction == .encode ? "原文" : "密文",
                    text: $input,
                    placeholder: direction == .encode ? "输入要加密的文本…" : "粘贴要解密的内容…",
                    minHeight: 120,
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

                directionBar

                TextPane(
                    title: direction == .encode ? "密文" : "明文",
                    text: .constant(output),
                    isEditable: false,
                    placeholder: "结果会实时出现在这里",
                    minHeight: 120,
                    buttons: [
                        PaneButton(systemImage: "doc.on.doc", help: "复制结果") {
                            guard !output.isEmpty else { return }
                            NSPasteboard.copyString(output)
                            toast = "结果已复制"
                        },
                    ]
                )

                if cipher == .caesar, !input.isEmpty {
                    bruteForceCard
                }
            }
            .padding(20)
        }
        .toast($toast)
    }

    // MARK: 密码选择

    private var cipherCard: some View {
        ToolCard(title: "古典密码", systemImage: "scroll") {
            FlowRow(spacing: 7) {
                ForEach(ClassicCipher.allCases) { item in
                    ChipButton(title: item.title, isSelected: item == cipher) {
                        cipher = item
                    }
                }
            }
            HStack(alignment: .top, spacing: 8) {
                if cipher == .rot13 {
                    NoticeTag(text: "自逆", systemImage: "arrow.triangle.2.circlepath", tint: .green)
                }
                if cipher == .xor {
                    NoticeTag(text: "密钥重复使用不安全", systemImage: "exclamationmark.shield", tint: .orange)
                }
                Text(cipher.summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 参数

    @ViewBuilder
    private var parameterCard: some View {
        if cipher.needsShift || cipher.needsKey || cipher == .xor {
            ToolCard(title: "参数", systemImage: "dial.medium") {
                FlowRow(spacing: 16) {
                    if cipher.needsShift {
                        HStack(spacing: 8) {
                            Text("位移")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Slider(value: Binding(
                                get: { Double(shift) },
                                set: { shift = Int($0.rounded()) }
                            ), in: 1...25)
                            .frame(width: 160)
                            Text("\(shift)")
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .frame(width: 22)
                        }
                    }

                    if cipher.needsKey {
                        HStack(spacing: 6) {
                            Text("密钥")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            TextField(cipher == .xor ? "异或密钥" : "字母密钥", text: $key)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 180)
                        }
                    }

                    if cipher == .xor, direction == .encode {
                        HStack(spacing: 6) {
                            Text("输出格式")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $xorFormat) {
                                ForEach(XORFormat.allCases) { item in
                                    Text(item.title).tag(item)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 110)
                        }
                    }

                    if cipher == .morse {
                        Text("只支持字母、数字和常用标点，其他字符会被跳过。")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: 方向

    private var directionBar: some View {
        HStack(spacing: 8) {
            if cipher == .rot13 {
                Text("ROT13 正反是同一个操作，不用选方向。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            } else {
                ChipButton(title: "加密 ↓", isSelected: direction == .encode, minWidth: 84) {
                    direction = .encode
                }
                ChipButton(title: "解密 ↑", isSelected: direction == .decode, minWidth: 84) {
                    direction = .decode
                }
                Button {
                    swap()
                } label: {
                    Label("交换", systemImage: "arrow.up.arrow.down")
                }
                .controlSize(.small)
                .disabled(output.isEmpty)
            }

            Spacer(minLength: 8)

            Text("输入改变即实时转换")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: 凯撒暴力破解

    private var bruteForceCard: some View {
        ToolCard(title: "25 种位移全试一遍", systemImage: "wand.and.stars") {
            Text("凯撒密码只有 25 种可能，挨个看一遍总有一个是人话。点一行直接用那个位移。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(CryptoEngine.caesarAllShifts(input), id: \.shift) { item in
                        Button {
                            shift = item.shift
                            direction = .decode
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(item.shift)")
                                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                                    .foregroundStyle(shift == item.shift ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                                    .frame(width: 20, alignment: .trailing)
                                Text(item.text.isEmpty ? " " : item.text)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(shift == item.shift ? Color.accentColor : .primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                shift == item.shift ? Color.accentColor.opacity(0.10) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
    }

    private func swap() {
        guard !output.isEmpty else { return }
        input = output
        direction = direction == .encode ? .decode : .encode
    }
}
