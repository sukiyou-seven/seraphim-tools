import AppKit
import SwiftUI

/// 单向摘要。没有解密——哈希本来就是不可逆的。
struct CryptoHashView: View {
    @AppStorage("hashAlgorithm") private var algorithm: HashAlgorithm = .sha256

    @State private var input = ""
    @State private var fileURL: URL?
    @State private var fileName = ""
    @State private var fileSize: Int = 0
    @State private var fileData: Data?

    @State private var useHMAC = false
    @State private var hmacKey = ""

    @State private var hexOutput = ""
    @State private var base64Output = ""
    @State private var isComputing = false
    @State private var errorMessage: String?
    @State private var toast: String?
    @State private var isDropTargeted = false

    private var taskKey: String {
        "\(algorithm.rawValue)|\(fileURL?.path ?? "")|\(input.hashValue)|\(useHMAC)|\(hmacKey.hashValue)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                algorithmCard
                keyCard
                inputCard

                VStack(spacing: 10) {
                    if let errorMessage {
                        ErrorBanner(message: errorMessage)
                    }
                    digestCard
                }
            }
            .padding(20)
        }
        .toast($toast)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [10, 6]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .task(id: taskKey) {
            await recompute()
        }
    }

    // MARK: 算法

    private var algorithmCard: some View {
        ToolCard(title: "摘要算法", systemImage: "number.square") {
            FlowRow(spacing: 7) {
                ForEach(HashAlgorithm.allCases) { item in
                    ChipButton(title: item.title, isSelected: item == algorithm) {
                        algorithm = item
                        if !item.supportsHMAC { useHMAC = false }
                    }
                }
            }

            HStack(alignment: .top, spacing: 8) {
                if algorithm.isWeak {
                    NoticeTag(text: "不推荐", systemImage: "exclamationmark.shield", tint: .orange)
                }
                Text(algorithm.summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("摘要长度 \(algorithm.digestLength) 字节 · \(algorithm.digestLength * 8) 位")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: HMAC

    @ViewBuilder
    private var keyCard: some View {
        ToolCard(title: "带密钥摘要（HMAC）", systemImage: "key") {
            HStack(spacing: 12) {
                Toggle("启用 HMAC", isOn: $useHMAC)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12.5))
                    .disabled(!algorithm.supportsHMAC)

                if useHMAC {
                    SecureField("密钥", text: $hmacKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                    Text("同一份内容配不同密钥会得到完全不同的摘要，用来验证消息没被人改过。")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                } else {
                    Text(algorithm.supportsHMAC
                         ? "打开后就是 HMAC-\(algorithm.title)，需要额外给一个密钥。"
                         : "CRC32 是校验和，不能用作 HMAC。要算 CRC-16 或者换参数，去「校验和」那一页。")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: 输入

    private var inputCard: some View {
        VStack(spacing: 10) {
            if let fileURL {
                fileChip(url: fileURL)
            }
            TextPane(
                title: fileURL == nil ? "文本" : "文本（已忽略，当前在对文件求摘要）",
                text: $input,
                placeholder: "输入要计算摘要的文本…",
                minHeight: 130,
                buttons: [
                    PaneButton(systemImage: "doc.on.clipboard", help: "从剪贴板粘贴") {
                        if let string = NSPasteboard.general.string(forType: .string) {
                            input = string
                            clearFile()
                        } else {
                            toast = "剪贴板里没有文本"
                            NSSound.beep()
                        }
                    },
                    PaneButton(systemImage: "doc.badge.plus", help: "选一个文件来算摘要") {
                        if let url = FilePicker.pick(title: "选择要计算摘要的文件") {
                            load(url: url)
                        }
                    },
                    PaneButton(systemImage: "trash", help: "清空") {
                        input = ""
                        clearFile()
                    },
                ]
            )
        }
    }

    private func fileChip(url: URL) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(fileName)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(ByteFormatter.string(fileSize))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("移除") { clearFile() }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.25))
        )
    }

    // MARK: 结果

    private var digestCard: some View {
        ToolCard(title: "摘要结果", systemImage: "checkmark.seal") {
            if isComputing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("计算中…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            } else if hexOutput.isEmpty {
                Text("输入内容后这里会实时显示摘要")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    resultRow(title: "十六进制", value: hexOutput)
                    resultRow(title: "Base64", value: base64Output)
                }
            }
        }
    }

    private func resultRow(title: String, value: String) -> some View {
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

    // MARK: 计算

    @MainActor
    private func recompute() async {
        let data: Data?
        if let fileURL {
            isComputing = true
            data = await Task.detached(priority: .userInitiated) {
                try? Data(contentsOf: fileURL)
            }.value
            isComputing = false
        } else {
            data = input.isEmpty ? nil : Data(input.utf8)
        }

        guard let data, !data.isEmpty else {
            hexOutput = ""
            base64Output = ""
            errorMessage = nil
            return
        }

        do {
            let digest = useHMAC
                ? try CryptoEngine.hmac(data, algorithm: algorithm, key: hmacKey)
                : CryptoEngine.digest(data, algorithm: algorithm)
            hexOutput = digest.map { String(format: "%02x", $0) }.joined()
            base64Output = digest.base64EncodedString()
            errorMessage = nil
        } catch {
            hexOutput = ""
            base64Output = ""
            errorMessage = error.localizedDescription
        }
    }

    private func load(url: URL) {
        fileURL = url
        fileName = url.lastPathComponent
        fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        input = ""
        toast = "已选择 \(url.lastPathComponent)"
    }

    private func clearFile() {
        fileURL = nil
        fileName = ""
        fileSize = 0
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first, provider.canLoadObject(ofClass: URL.self) else { return false }
        _ = provider.loadObject(ofClass: URL.self) { object, _ in
            guard let url = object else { return }
            DispatchQueue.main.async { load(url: url) }
        }
        return true
    }
}
