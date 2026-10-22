import AppKit
import SwiftUI

// MARK: - 面板

/// JWT 解析、验签与签发。
struct JWTPanel: View {
    enum Mode: String, CaseIterable, Identifiable {
        case decode
        case sign

        var id: String { rawValue }

        var title: String {
            switch self {
            case .decode: return "解析验签"
            case .sign: return "签发"
            }
        }
    }

    @AppStorage("jwtMode") private var mode: Mode = .decode

    var body: some View {
        VStack(spacing: 0) {
            Picker("模式", selection: $mode) {
                ForEach(Mode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 60)
            .padding(.top, 12)

            switch mode {
            case .decode: JWTDecodeSection()
            case .sign: JWTSignSection()
            }
        }
    }
}

// MARK: - 解析验签

private struct JWTDecodeSection: View {
    @AppStorage("jwtToken") private var tokenText = ""
    @AppStorage("jwtKeyFormat") private var keyFormat: JWTKeyFormat = .text
    @AppStorage("jwtVerifyKey") private var keyText = ""
    @State private var decoded: JWTToken?
    @State private var decodeError: String?
    @State private var verifyResult: JWTVerifyResult = .notAttempted
    @State private var claims: [JWTClaim] = []
    @State private var timeText = ""
    @State private var timeStatus: JWTClaimStatus = .info
    @State private var toast: String?

    private var taskKey: String {
        "\(tokenText)|\(keyText)|\(keyFormat.rawValue)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                tokenCard
                keyCard

                if let decodeError {
                    ErrorBanner(message: decodeError)
                }

                if decoded != nil {
                    verdictCard
                    structureCard
                    if !claims.isEmpty { claimsCard }
                    signatureCard
                }
            }
            .padding(20)
        }
        .toast($toast)
        .task(id: taskKey) { recompute() }
    }

    // MARK: 输入

    private var tokenCard: some View {
        TextPane(
            title: "Token",
            text: $tokenText,
            placeholder: "把 JWT 贴进来，三段用 . 分隔…",
            minHeight: 120,
            buttons: [
                PaneButton(systemImage: "sparkles", help: "放一个示例 token（密钥会自动填好）") {
                    let sample = (try? JWTEngine.sign(
                        payloadJSON: #"{"sub":"1234567890","name":"Seraphim","admin":true,"iat":1516239022}"#,
                        algorithm: .hs256,
                        keyText: "seraphim-tools-demo-key"
                    )) ?? ""
                    tokenText = sample
                    keyText = "seraphim-tools-demo-key"
                    keyFormat = .text
                    toast = "示例填好了，密钥也一起填了"
                },
                PaneButton(systemImage: "doc.on.clipboard", help: "从剪贴板粘贴") {
                    if let string = NSPasteboard.general.string(forType: .string) {
                        tokenText = string.trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        toast = "剪贴板里没有文本"
                        NSSound.beep()
                    }
                },
                PaneButton(systemImage: "trash", help: "清空") {
                    tokenText = ""
                },
            ]
        )
    }

    private var keyCard: some View {
        ToolCard(title: "验签密钥", systemImage: "key") {
            HStack(spacing: 10) {
                Text("密钥写法")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                FlowRow(spacing: 6) {
                    ForEach(JWTKeyFormat.allCases) { item in
                        ChipButton(title: item.title, isSelected: item == keyFormat) {
                            keyFormat = item
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            TextPane(
                title: "密钥 / 公钥 / 证书",
                text: $keyText,
                placeholder: isSymmetricToken
                    ? "HS 算法：填签发时用的那段密钥"
                    : "RS / PS / ES 算法：贴 PEM 公钥（BEGIN PUBLIC KEY）或证书（BEGIN CERTIFICATE）",
                minHeight: 90,
                buttons: [
                    PaneButton(systemImage: "doc.on.clipboard", help: "从剪贴板粘贴") {
                        if let string = NSPasteboard.general.string(forType: .string) {
                            keyText = string
                        } else {
                            toast = "剪贴板里没有文本"
                            NSSound.beep()
                        }
                    },
                    PaneButton(systemImage: "doc.badge.plus", help: "从文件读入 PEM 或证书") {
                        if let url = FilePicker.pick(title: "选择 PEM 公钥或证书") {
                            if let text = try? String(contentsOf: url, encoding: .utf8) {
                                keyText = text
                                keyFormat = .text
                                toast = "已读入 \(url.lastPathComponent)"
                            } else {
                                toast = "这个文件不是文本，读不了"
                                NSSound.beep()
                            }
                        }
                    },
                    PaneButton(systemImage: "trash", help: "清空") {
                        keyText = ""
                    },
                ]
            )

            Text(keyHint)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 结论

    private var verdictCard: some View {
        ToolCard(title: "结论", systemImage: "checkmark.seal") {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: verifyIcon)
                    .font(.system(size: 17))
                    .foregroundStyle(verifyTint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verifyHeadline)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(verifyTint)
                    Text(verifyResult.text)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if !timeText.isEmpty {
                Divider()
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: timeStatus == .bad
                          ? "clock.badge.exclamationmark"
                          : (timeStatus == .warn ? "clock.badge.questionmark" : "clock"))
                        .font(.system(size: 15))
                        .foregroundStyle(timeStatus.tint)
                    Text(timeText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: 结构

    private var structureCard: some View {
        ToolCard(title: "结构", systemImage: "curlybraces") {
            if let decoded {
                JWTValueRow(title: "Header", value: decoded.header.pretty)
                JWTValueRow(title: "Payload", value: decoded.payload.pretty)
            }
        }
    }

    // MARK: 声明

    private var claimsCard: some View {
        ToolCard(title: "声明解读", systemImage: "list.bullet.rectangle") {
            VStack(spacing: 0) {
                ForEach(Array(claims.enumerated()), id: \.element.id) { index, claim in
                    if index > 0 { Divider() }
                    claimRow(claim)
                }
            }
        }
    }

    private func claimRow(_ claim: JWTClaim) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(claim.status.tint)
                .frame(width: 7, height: 7)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(claim.key)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Text(claim.value)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                if !claim.meaning.isEmpty {
                    Text(claim.meaning)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    // MARK: 签名

    private var signatureCard: some View {
        ToolCard(title: "签名段", systemImage: "signature") {
            if let decoded {
                if decoded.signature.isEmpty {
                    Text("第三段是空的：alg 写着 \(decoded.algorithmRaw)，但并没有签名。这种 token 谁都能伪造，别当真。")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    JWTValueRow(title: "Base64URL", value: decoded.signatureBase64URL)
                    JWTValueRow(
                        title: "长度",
                        value: "\(decoded.signatureLength) 字节（\(decoded.signatureLength * 8) 位）"
                    )
                    JWTValueRow(title: "Hex（前 64 字节）", value: hexPrefix(decoded.signature, limit: 64))
                }
            }
        }
    }

    // MARK: 计算

    @MainActor
    private func recompute() {
        let trimmed = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            decoded = nil
            decodeError = nil
            verifyResult = .notAttempted
            claims = []
            timeText = ""
            return
        }

        do {
            let token = try JWTEngine.decode(trimmed)
            decoded = token
            decodeError = nil
            claims = JWTEngine.claims(of: token)
            let verdict = JWTEngine.timeVerdict(of: token)
            timeText = verdict.text
            timeStatus = verdict.status

            let key = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
            verifyResult = key.isEmpty
                ? .notAttempted
                : JWTEngine.verify(token, keyText: key, keyFormat: keyFormat)
        } catch {
            decoded = nil
            decodeError = error.localizedDescription
            verifyResult = .notAttempted
            claims = []
            timeText = ""
        }
    }

    // MARK: 派生文案

    private var isSymmetricToken: Bool {
        decoded?.algorithm?.isSymmetric ?? false
    }

    private var verifyHeadline: String {
        switch verifyResult {
        case .valid: return "签名有效"
        case .invalid: return "签名对不上"
        case .badKey: return "密钥读不出来"
        case .unsupported: return "验不了"
        case .noSignature: return "没有签名"
        case .notAttempted: return decoded == nil ? "还没验签" : "等密钥"
        }
    }

    private var verifyIcon: String {
        switch verifyResult {
        case .valid: return "checkmark.seal.fill"
        case .invalid, .badKey: return "xmark.seal.fill"
        case .unsupported, .noSignature: return "exclamationmark.triangle.fill"
        case .notAttempted: return "questionmark.circle"
        }
    }

    private var verifyTint: Color {
        switch verifyResult {
        case .valid: return .green
        case .invalid, .badKey: return .red
        case .unsupported, .noSignature: return .orange
        case .notAttempted: return .secondary
        }
    }

    private var keyHint: String {
        switch verifyResult {
        case .notAttempted where decoded != nil:
            return isSymmetricToken
                ? "这个 token 是 HS 算法：填上签发时用的那段密钥就能验。"
                : "这个 token 是 \(decoded?.algorithmRaw ?? "")：填上对应的公钥或证书就能验。"
        case .badKey:
            return "RSA 支持 PEM 公钥、PEM 证书，也支持去掉头尾的裸 base64；EC 支持 PEM 公钥。私钥不能用来验签。"
        default:
            return "HS 算法填密钥；RS / PS / ES 填公钥或证书。留空就只解析、不验签。"
        }
    }

    private func hexPrefix(_ data: Data, limit: Int) -> String {
        let slice = data.prefix(limit)
        var text = slice.map { String(format: "%02x", $0) }.joined()
        if data.count > limit { text += "…" }
        return text
    }
}

// MARK: - 签发

private struct JWTSignSection: View {
    @AppStorage("jwtAlgorithm") private var algorithm: JWTAlgorithm = .hs256
    @AppStorage("jwtKeyFormat") private var keyFormat: JWTKeyFormat = .text
    @AppStorage("jwtPayload") private var payloadText = JWTDefaults.payload
    @AppStorage("jwtSignKey") private var symmetricKey = ""

    @State private var keyText = ""
    @State private var kidText = ""
    @State private var outputToken = ""
    @State private var errorMessage: String?
    @State private var toast: String?
    @State private var keyPrivate = ""
    @State private var keyPublic = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                algorithmCard
                keyCard
                payloadCard

                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }

                actionRow

                if !outputToken.isEmpty {
                    outputCard
                }
                if !keyPrivate.isEmpty {
                    generatedCard
                }
            }
            .padding(20)
        }
        .toast($toast)
    }

    // MARK: 算法

    private var algorithmCard: some View {
        ToolCard(title: "签名算法", systemImage: "signature") {
            ForEach(algorithmGroups, id: \.name) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.name)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                    FlowRow(spacing: 7) {
                        ForEach(group.items) { item in
                            ChipButton(title: item.rawValue, isSelected: item == algorithm) {
                                algorithm = item
                                // 换算法后旧的签名结果留着会误导
                                outputToken = ""
                                errorMessage = nil
                            }
                        }
                    }
                }
            }

            if let risk = algorithmRisk {
                NoticeTag(text: risk, systemImage: "exclamationmark.shield", tint: .orange)
            }

            Text(algorithm.note)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var algorithmGroups: [(name: String, items: [JWTAlgorithm])] {
        [
            ("HMAC（对称，双方共用密钥）", [.hs256, .hs384, .hs512]),
            ("RSA · PKCS#1 v1.5（JWKS 里最常见）", [.rs256, .rs384, .rs512]),
            ("RSA · PSS", [.ps256, .ps384, .ps512]),
            ("ECDSA（签名更短）", [.es256, .es384, .es512]),
        ]
    }

    private var algorithmRisk: String? {
        algorithm == .none ? "不签名" : nil
    }

    // MARK: 密钥

    @ViewBuilder
    private var keyCard: some View {
        if algorithm.isSymmetric {
            ToolCard(title: "签名密钥", systemImage: "key") {
                HStack(spacing: 10) {
                    Text("密钥写法")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    FlowRow(spacing: 6) {
                        ForEach(JWTKeyFormat.allCases) { item in
                            ChipButton(title: item.title, isSelected: item == keyFormat) {
                                keyFormat = item
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }

                SecureField("对称密钥（越长越好）", text: $symmetricKey)
                    .textFieldStyle(.roundedBorder)

                Text("同一个密钥既签又验，所以不能公开。JWKS 里的 k 是 base64url 字节，别按文本填——选 Base64 那一档。")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                TextPane(
                    title: "私钥",
                    text: $keyText,
                    placeholder: "粘贴 PEM 私钥：PKCS#8 的 BEGIN PRIVATE KEY，或 PKCS#1 的 BEGIN RSA PRIVATE KEY",
                    minHeight: 120,
                    buttons: [
                        PaneButton(systemImage: "wand.and.stars", help: "现场生成一对 \(algorithm.rawValue) 密钥") {
                            generateKey()
                        },
                        PaneButton(systemImage: "doc.badge.plus", help: "从文件读入 PEM 私钥") {
                            if let url = FilePicker.pick(title: "选择 PEM 私钥") {
                                if let text = try? String(contentsOf: url, encoding: .utf8) {
                                    keyText = text
                                    toast = "已读入 \(url.lastPathComponent)"
                                } else {
                                    toast = "这个文件不是文本，读不了"
                                    NSSound.beep()
                                }
                            }
                        },
                        PaneButton(systemImage: "trash", help: "清空") {
                            keyText = ""
                        },
                    ]
                )

                Text("没有密钥可以点右上角那个小魔棒，现场生成一对，私钥会填进来、公钥留在下面的卡片里。")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Payload

    private var payloadCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextPane(
                title: "Payload（JSON 对象）",
                text: $payloadText,
                placeholder: "{\n  \"sub\": \"1234567890\"\n}",
                minHeight: 150,
                buttons: [
                    PaneButton(systemImage: "clock.arrow.circlepath", help: "把 iat 刷成现在、exp 设为一小时后") {
                        refreshTimes()
                    },
                    PaneButton(systemImage: "doc.on.clipboard", help: "从剪贴板粘贴") {
                        if let string = NSPasteboard.general.string(forType: .string) {
                            payloadText = string
                        } else {
                            toast = "剪贴板里没有文本"
                            NSSound.beep()
                        }
                    },
                    PaneButton(systemImage: "trash", help: "清空") {
                        payloadText = ""
                    },
                ]
            )

            ToolCard(title: "头部附加字段", systemImage: "puzzlepiece") {
                HStack(spacing: 10) {
                    Text("kid")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .leading)
                    TextField("留空就不写进 header", text: $kidText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                    Spacer(minLength: 0)
                }
                Text("kid 用来告诉对方「用哪把钥匙验」——JWKS 里有好几把公钥时全靠它。")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: 动作

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                performSign()
            } label: {
                Label("签发 token", systemImage: "signature")
                    .frame(minWidth: 96)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if !outputToken.isEmpty {
                CopyIconButton(text: outputToken, help: "复制完整 token")
                Button("清空结果") {
                    outputToken = ""
                }
                .controlSize(.small)
            }

            Spacer(minLength: 0)
        }
    }

    private var outputCard: some View {
        ToolCard(title: "生成的 token", systemImage: "checkmark.seal") {
            JWTValueRow(title: "完整 token", value: outputToken)

            if let decoded = try? JWTEngine.decode(outputToken) {
                JWTValueRow(title: "Header", value: decoded.header.pretty)
                JWTValueRow(title: "Payload", value: decoded.payload.pretty)
                JWTValueRow(title: "签名长度", value: "\(decoded.signatureLength) 字节")
            }

            Text("想验证它？复制 token、切到上面「解析验签」，再填上对应的密钥或公钥。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private var generatedCard: some View {
        ToolCard(title: "刚生成的密钥对", systemImage: "key.horizontal") {
            Text("私钥已经填进上面的输入框了。公钥留着——这就是「私钥签名、公钥验签」里那把公钥。")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            JWTValueRow(title: "私钥", value: keyPrivate, limit: 8)

            if !keyPublic.isEmpty {
                JWTValueRow(title: "公钥", value: keyPublic, limit: 8)
            }
        }
    }

    // MARK: 逻辑

    private func performSign() {
        let key = (algorithm.isSymmetric ? symmetricKey : keyText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            outputToken = try JWTEngine.sign(
                payloadJSON: payloadText,
                algorithm: algorithm,
                keyText: key,
                keyFormat: keyFormat,
                kid: kidText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            errorMessage = nil
            toast = "已签发"
        } catch {
            outputToken = ""
            errorMessage = error.localizedDescription
        }
    }

    private func generateKey() {
        guard !algorithm.isSymmetric, algorithm != .none else {
            toast = "\(algorithm.rawValue) 不需要密钥对"
            return
        }
        do {
            let pair = try JWTEngine.generateKeyPair(algorithm: algorithm)
            keyPrivate = pair.privateKey
            keyPublic = pair.publicKey
            keyText = pair.privateKey
            errorMessage = nil
            toast = "已生成一对 \(algorithm.rawValue) 密钥"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshTimes() {
        guard let data = payloadText.data(using: .utf8),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            toast = "先填一段合法的 JSON 对象"
            NSSound.beep()
            return
        }
        let now = Int(Date().timeIntervalSince1970)
        object["iat"] = now
        object["exp"] = now + 3600
        guard let output = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ), let text = String(data: output, encoding: .utf8) else {
            toast = "改写失败"
            NSSound.beep()
            return
        }
        payloadText = text
        toast = "iat 刷成现在，exp 设为一小时后"
    }
}

// MARK: - 小组件

/// 带复制按钮的等宽展示块
private struct JWTValueRow: View {
    var title: String
    var value: String
    var limit: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
                CopyIconButton(text: value)
            }
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(limit > 0 ? limit : nil)
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

private enum JWTDefaults {
    static let payload = """
    {
      "sub": "1234567890",
      "name": "Seraphim",
      "admin": true,
      "iat": 1516239022
    }
    """
}

private extension JWTClaimStatus {
    var tint: Color {
        switch self {
        case .ok: return .green
        case .warn: return .orange
        case .bad: return .red
        case .info: return .secondary
        }
    }
}
