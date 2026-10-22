import AppKit
import SwiftUI

/// 对称加密。加密解密都能做，因为密钥就在你手里。
struct CryptoSymmetricView: View {
    enum Direction: String, CaseIterable, Identifiable {
        case encrypt
        case decrypt

        var id: String { rawValue }

        var title: String {
            switch self {
            case .encrypt: return "加密"
            case .decrypt: return "解密"
            }
        }
    }

    @AppStorage("symAlgorithm") private var algorithm: SymmetricAlgorithm = .aesGCM

    @State private var direction: Direction = .encrypt
    @State private var keySource: KeySource = .passphrase
    @State private var passphrase = ""
    @State private var rawKey = ""
    @State private var input = ""
    @State private var output = ""
    @State private var errorMessage: String?
    @State private var toast: String?
    @State private var isWorking = false

    private var secret: String {
        keySource == .passphrase ? passphrase : rawKey
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                algorithmCard
                keyCard

                TextPane(
                    title: direction == .encrypt ? "明文" : "密文",
                    text: $input,
                    placeholder: direction == .encrypt ? "输入要加密的内容…" : "粘贴以 STM1. 开头的密文…",
                    minHeight: 130,
                    buttons: [
                        PaneButton(systemImage: "doc.on.clipboard", help: "从剪贴板粘贴") {
                            if let string = NSPasteboard.general.string(forType: .string) {
                                input = string
                            } else {
                                toast = "剪贴板里没有文本"
                                NSSound.beep()
                            }
                        },
                        PaneButton(systemImage: "trash", help: "清空") {
                            input = ""
                            output = ""
                            errorMessage = nil
                        },
                    ]
                )

                actionBar

                VStack(spacing: 10) {
                    if let errorMessage {
                        ErrorBanner(message: errorMessage)
                    }
                    TextPane(
                        title: direction == .encrypt ? "密文" : "明文",
                        text: .constant(output),
                        isEditable: false,
                        placeholder: errorMessage ?? "点上面的「\(direction.title)」按钮开始",
                        minHeight: 130,
                        buttons: [
                            PaneButton(systemImage: "doc.on.doc", help: "复制结果") {
                                guard !output.isEmpty else { return }
                                NSPasteboard.copyString(output)
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

    // MARK: 算法

    private var algorithmCard: some View {
        ToolCard(title: "加密算法", systemImage: "lock.shield") {
            FlowRow(spacing: 7) {
                ForEach(SymmetricAlgorithm.allCases) { item in
                    ChipButton(title: item.title, isSelected: item == algorithm) {
                        algorithm = item
                    }
                }
            }
            HStack(alignment: .top, spacing: 8) {
                if algorithm.isAuthenticated {
                    NoticeTag(text: "防篡改", systemImage: "checkmark.shield", tint: .green)
                } else {
                    NoticeTag(text: "不防篡改", systemImage: "exclamationmark.shield", tint: .orange)
                }
                Text(algorithm.summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 密钥

    private var keyCard: some View {
        ToolCard(title: "密钥", systemImage: "key") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: $keySource) {
                    ForEach(KeySource.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)

                if keySource == .passphrase {
                    SecureField("口令", text: $passphrase)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 340)
                    Text("口令会经 PBKDF2-SHA256（10 万轮）派生密钥，随机盐会一并写进密文，所以每次加密结果都不一样。")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 8) {
                        TextField("64 位十六进制，或 Base64 的 32 字节", text: $rawKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        Button {
                            rawKey = CryptoEngine.randomBytes(32).map { String(format: "%02x", $0) }.joined()
                            toast = "已生成随机密钥"
                        } label: {
                            Label("生成", systemImage: "dice")
                        }
                        .controlSize(.small)
                    }
                    Text(rawKeyHint)
                        .font(.system(size: 11))
                        .foregroundStyle(rawKeyIsValid ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.orange))
                }
            }
        }
    }

    private var rawKeyIsValid: Bool {
        guard let data = CryptoEngine.parseRawKey(rawKey) else { return rawKey.isEmpty }
        return data.count == 32
    }

    private var rawKeyHint: String {
        guard !rawKey.isEmpty else { return "直接给密钥时跳过口令派生，加解密双方必须用完全相同的密钥。" }
        guard let data = CryptoEngine.parseRawKey(rawKey) else {
            return "这个格式读不出来，检查一下。"
        }
        return data.count == 32
            ? "密钥有效 · 32 字节"
            : "当前解析出 \(data.count) 字节，AES-256 需要 32 字节。"
    }

    // MARK: 操作条

    private var actionBar: some View {
        HStack(spacing: 8) {
            ChipButton(title: "加密 ↓", isSelected: direction == .encrypt, minWidth: 84) {
                direction = .encrypt
            }
            ChipButton(title: "解密 ↑", isSelected: direction == .decrypt, minWidth: 84) {
                direction = .decrypt
            }

            Button {
                run()
            } label: {
                Label(direction.title, systemImage: direction == .encrypt ? "lock.fill" : "lock.open.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(input.isEmpty || secret.isEmpty || isWorking)

            Button {
                swap()
            } label: {
                Label("交换", systemImage: "arrow.up.arrow.down")
            }
            .controlSize(.small)
            .disabled(output.isEmpty)
            .help("把结果当作输入，并切换方向")

            if isWorking {
                ProgressView().controlSize(.small)
            }

            Spacer(minLength: 8)

            Text(direction == .decrypt
                 ? "解密会自动读取密文里的算法标记，不用手动对齐参数"
                 : "密文里带着算法和盐，直接整段复制给对方就行")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    // MARK: 执行

    private func run() {
        let text = input
        let currentSecret = secret
        let source = keySource
        let alg = algorithm
        let isEncrypt = direction == .encrypt

        errorMessage = nil
        output = ""
        isWorking = true

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (String?, String?) in
                do {
                    if isEncrypt {
                        return (try CryptoEngine.encrypt(
                            plaintext: text,
                            secret: currentSecret,
                            source: source,
                            algorithm: alg
                        ), nil)
                    }
                    return (try CryptoEngine.decrypt(text, secret: currentSecret), nil)
                } catch {
                    return (nil, error.localizedDescription)
                }
            }.value

            isWorking = false
            if let value = outcome.0 {
                output = value
                toast = isEncrypt ? "加密完成" : "解密完成"
            } else {
                errorMessage = outcome.1
                NSSound.beep()
            }
        }
    }

    private func swap() {
        guard !output.isEmpty else { return }
        input = output
        output = ""
        errorMessage = nil
        direction = direction == .encrypt ? .decrypt : .encrypt
    }
}
