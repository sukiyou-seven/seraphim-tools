import AppKit
import SwiftUI

/// 随机生成器。附带的，但少了它每次要密钥都得去别处找。
struct CryptoRandomView: View {
    // UUID
    @State private var uuidCount = 5
    @State private var uuids: [String] = []

    // 密码
    @State private var passwordLength = 20.0
    @State private var useUpper = true
    @State private var useLower = true
    @State private var useDigits = true
    @State private var useSymbols = true
    @State private var excludeConfusable = false
    @State private var password = ""

    // 密钥 / 字节
    @State private var keyLength = 32
    @State private var randomHex = ""
    @State private var randomBase64 = ""

    @State private var toast: String?

    // MARK: 字符表

    private var alphabet: String {
        var characters = ""
        if useUpper { characters += "ABCDEFGHIJKLMNOPQRSTUVWXYZ" }
        if useLower { characters += "abcdefghijklmnopqrstuvwxyz" }
        if useDigits { characters += "0123456789" }
        if useSymbols { characters += "!@#$%^&*()-_=+[]{}<>?,./|~" }
        if excludeConfusable {
            let confusable = Set("0O1lI|`'\",;:.<>{}[]()/\\")
            characters = String(characters.filter { !confusable.contains($0) })
        }
        return characters
    }

    private var passwordKey: String {
        "\(Int(passwordLength))|\(useUpper)|\(useLower)|\(useDigits)|\(useSymbols)|\(excludeConfusable)"
    }

    private var entropyBits: Double {
        guard !alphabet.isEmpty else { return 0 }
        return passwordLength * log2(Double(alphabet.count))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                uuidCard
                passwordCard
                keyCard
            }
            .padding(20)
        }
        .toast($toast)
        .task(id: uuidCount) {
            uuids = (0..<uuidCount).map { _ in UUID().uuidString.lowercased() }
        }
        .task(id: passwordKey) {
            password = CryptoEngine.randomPassword(length: Int(passwordLength), alphabet: alphabet)
        }
        .task(id: keyLength) {
            let data = CryptoEngine.randomBytes(keyLength)
            randomHex = data.map { String(format: "%02x", $0) }.joined()
            randomBase64 = data.base64EncodedString()
        }
    }

    // MARK: UUID

    private var uuidCard: some View {
        ToolCard(title: "UUID v4", systemImage: "number") {
            HStack(spacing: 10) {
                Picker("", selection: $uuidCount) {
                    Text("1 个").tag(1)
                    Text("5 个").tag(5)
                    Text("10 个").tag(10)
                    Text("20 个").tag(20)
                }
                .labelsHidden()
                .frame(width: 100)

                Button {
                    uuids = (0..<uuidCount).map { _ in UUID().uuidString.lowercased() }
                } label: {
                    Label("重新生成", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)

                Button {
                    let text = uuids.joined(separator: "\n")
                    NSPasteboard.copyString(text)
                    toast = "已复制 \(uuids.count) 个 UUID"
                } label: {
                    Label("全部复制", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                .disabled(uuids.isEmpty)

                Spacer(minLength: 0)

                Text("基于系统加密随机源，v4 版本")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 3) {
                ForEach(uuids, id: \.self) { value in
                    HStack(spacing: 8) {
                        Text(value)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                        CopyIconButton(text: value)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: 密码

    private var passwordCard: some View {
        ToolCard(title: "随机密码", systemImage: "key.horizontal") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("长度")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Slider(value: $passwordLength, in: 6...64, step: 1)
                    Text("\(Int(passwordLength))")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .frame(width: 26)
                }

                FlowRow(spacing: 14) {
                    checkbox("大写 A-Z", $useUpper)
                    checkbox("小写 a-z", $useLower)
                    checkbox("数字 0-9", $useDigits)
                    checkbox("符号 !@#", $useSymbols)
                    checkbox("排除易混淆字符（0O1lI）", $excludeConfusable)
                }

                HStack(spacing: 10) {
                    Text(password.isEmpty ? "至少选一类字符" : password)
                        .font(.system(size: 14, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.10))
                        )

                    VStack(spacing: 4) {
                        CopyIconButton(text: password)
                        Button {
                            password = CryptoEngine.randomPassword(length: Int(passwordLength), alphabet: alphabet)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("换一个")
                    }
                }

                HStack(spacing: 8) {
                    strengthTag
                    Text(String(format: "字符表 %d 个 · 约 %.0f 位熵", alphabet.count, entropyBits))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var strengthTag: some View {
        let (title, tint): (String, Color) = {
            if alphabet.isEmpty { return ("无字符", .gray) }
            switch entropyBits {
            case ..<50: return ("偏弱", .red)
            case ..<80: return ("够用", .orange)
            case ..<120: return ("强", .green)
            default: return ("很强", .green)
            }
        }()
        return NoticeTag(text: title, systemImage: "shield.lefthalf.filled", tint: tint)
    }

    private func checkbox(_ title: String, _ binding: Binding<Bool>) -> some View {
        Toggle(title, isOn: binding)
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
    }

    // MARK: 密钥 / 字节

    private var keyCard: some View {
        ToolCard(title: "随机密钥 / 随机字节", systemImage: "dice") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Picker("", selection: $keyLength) {
                        Text("16 字节").tag(16)
                        Text("24 字节").tag(24)
                        Text("32 字节").tag(32)
                        Text("48 字节").tag(48)
                        Text("64 字节").tag(64)
                    }
                    .labelsHidden()
                    .frame(width: 120)

                    Button {
                        let data = CryptoEngine.randomBytes(keyLength)
                        randomHex = data.map { String(format: "%02x", $0) }.joined()
                        randomBase64 = data.base64EncodedString()
                    } label: {
                        Label("重新生成", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)

                    Spacer(minLength: 0)

                    Text("32 字节正好是 AES-256 的密钥长度")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                outputRow(title: "十六进制", value: randomHex)
                outputRow(title: "Base64", value: randomBase64)
            }
        }
    }

    private func outputRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                CopyIconButton(text: value)
            }
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
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
