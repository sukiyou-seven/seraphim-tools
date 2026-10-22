import CryptoKit
import Foundation

// MARK: - 子进程

/// 一条命令跑完的结果。
struct SSHExecResult: Sendable {
    let code: Int32
    let out: String
    let err: String

    var ok: Bool { code == 0 }

    var combined: String {
        let a = out.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = err.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + "\n" + b
    }
}

/// 跑外部命令。SSH 相关的活都从这里出去。
enum SSHShell {
    @discardableResult
    static func run(
        _ path: String,
        _ arguments: [String],
        timeout: TimeInterval = 30,
        environment extra: [String: String]? = nil
    ) -> SSHExecResult {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return SSHExecResult(code: 127, out: "", err: "找不到 \(path)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        // 关键：ssh / ssh-add 遇到密码短语会停下来等输入，GUI 里这么一等就永远回不来
        process.standardInput = FileHandle.nullDevice

        var env = ProcessInfo.processInfo.environment
        env["LC_ALL"] = "en_US.UTF-8"   // 报错保持英文，关键词好匹配
        if let extra { env.merge(extra) { _, new in new } }
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return SSHExecResult(code: 126, out: "", err: error.localizedDescription)
        }

        var killer: DispatchWorkItem?
        if timeout > 0 {
            let item = DispatchWorkItem { if process.isRunning { process.terminate() } }
            killer = item
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
        }

        // 先读到 EOF 再等退出，免得输出撑满管道互相干等
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer?.cancel()

        return SSHExecResult(
            code: process.terminationStatus,
            out: String(data: outData, encoding: .utf8) ?? "",
            err: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}

// MARK: - 算法

enum SSHKeyAlgorithm: String, CaseIterable, Identifiable, Sendable {
    case ed25519
    case ecdsa256
    case ecdsa384
    case ecdsa521
    case rsa2048
    case rsa3072
    case rsa4096

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ed25519: return "Ed25519"
        case .ecdsa256: return "ECDSA 256"
        case .ecdsa384: return "ECDSA 384"
        case .ecdsa521: return "ECDSA 521"
        case .rsa2048: return "RSA 2048"
        case .rsa3072: return "RSA 3072"
        case .rsa4096: return "RSA 4096"
        }
    }

    /// 传给 `ssh-keygen -t`
    var keyType: String {
        switch self {
        case .ed25519: return "ed25519"
        case .ecdsa256, .ecdsa384, .ecdsa521: return "ecdsa"
        case .rsa2048, .rsa3072, .rsa4096: return "rsa"
        }
    }

    /// 传给 `ssh-keygen -b`，Ed25519 靠曲线固定长度不需要
    var bits: Int? {
        switch self {
        case .ed25519: return nil
        case .ecdsa256: return 256
        case .ecdsa384: return 384
        case .ecdsa521: return 521
        case .rsa2048: return 2048
        case .rsa3072: return 3072
        case .rsa4096: return 4096
        }
    }

    var defaultName: String {
        switch self {
        case .ed25519: return "id_ed25519"
        case .ecdsa256, .ecdsa384, .ecdsa521: return "id_ecdsa"
        case .rsa2048, .rsa3072, .rsa4096: return "id_rsa"
        }
    }

    var isRecommended: Bool { self == .ed25519 }

    var note: String {
        switch self {
        case .ed25519:
            return "最短的密钥长度换来最高的强度，快而且现代。现在新建就直接选它"
        case .ecdsa256, .ecdsa384, .ecdsa521:
            return "NIST 曲线，强度和 RSA 3072 相当但短得多。老系统偶尔不认"
        case .rsa2048:
            return "兼容性最好，但 2048 位已经算底线了，能换就换"
        case .rsa3072, .rsa4096:
            return "兼容老设备用的。位数越高握手越慢，4096 在低端设备上能感觉出来"
        }
    }
}

// MARK: - 密钥

/// 私钥能不能直接用。
enum SSHKeyLockState: String, Sendable {
    case unlocked
    case passphrase
    case unreadable

    var title: String {
        switch self {
        case .unlocked: return "无密码短语"
        case .passphrase: return "有密码短语"
        case .unreadable: return "读不出来"
        }
    }
}

struct SSHKeyInfo: Identifiable, Hashable, Sendable {
    let name: String
    let privatePath: String
    let publicPath: String
    /// .pub 文件在不在
    let hasPublicFile: Bool
    /// 公钥内容（.pub 丢了也能从私钥补出来，扫描时只读文件）
    let publicKey: String
    /// "ssh-ed25519" / "ssh-rsa" / "ecdsa-sha2-nistp256"
    let keyType: String
    let bits: Int
    let fingerprintSHA256: String
    let fingerprintMD5: String
    let comment: String
    let lockState: SSHKeyLockState
    /// 八进制权限位，读不到是 nil
    let privatePermissions: Int?
    let publicPermissions: Int?
    let privateSize: Int
    let createdAt: Date?
    let modifiedAt: Date?

    var id: String { privatePath }

    /// 展示用的算法名：ED25519 / RSA / ECDSA
    var algorithmTitle: String {
        if keyType.contains("ed25519") { return "ED25519" }
        if keyType.contains("rsa") { return "RSA" }
        if keyType.contains("ecdsa") { return "ECDSA" }
        if keyType.contains("dsa") { return "DSA" }
        return keyType.isEmpty ? "未知" : keyType
    }

    /// 算法 + 位长，列表里一眼能认出是哪把
    var strengthTitle: String {
        guard bits > 0 else { return algorithmTitle }
        return "\(algorithmTitle) \(bits)"
    }

    var publicKeyExists: Bool {
        !publicKey.isEmpty
    }

    /// 私钥权限是不是宽松到 ssh 会拒绝用（同组/其他 有任何权限位）
    var permissionsTooOpen: Bool {
        guard let permissions = privatePermissions else { return false }
        return permissions & 0o077 != 0
    }

    var permissionsText: String {
        guard let permissions = privatePermissions else { return "—" }
        return String(format: "%03o", permissions)
    }

    var shortFingerprint: String {
        guard fingerprintSHA256.count > 20 else { return fingerprintSHA256 }
        // SHA256:AbCdEf… 只留头尾，列表里够看就行
        let body = fingerprintSHA256.replacingOccurrences(of: "SHA256:", with: "")
        guard body.count > 14 else { return fingerprintSHA256 }
        return "SHA256:" + body.prefix(7) + "…" + body.suffix(6)
    }
}

// MARK: - 权限体检

enum SSHPermissionLevel: String, Sendable {
    case critical
    case warning
    case ok

    var title: String {
        switch self {
        case .critical: return "必须修"
        case .warning: return "建议修"
        case .ok: return "没问题"
        }
    }
}

struct SSHPermissionReport: Identifiable, Sendable, Hashable {
    let path: String
    let label: String
    let expected: Int
    let actual: Int?
    let level: SSHPermissionLevel
    let reason: String

    var id: String { path + "|" + label }

    var problem: Bool { level != .ok }

    var expectedText: String { String(format: "%03o", expected) }
    var actualText: String {
        guard let actual else { return "读不到" }
        return String(format: "%03o", actual)
    }

    var canFix: Bool { actual != nil && actual != expected }
}

// MARK: - known_hosts

/// known_hosts 里的一条主机公钥。
struct SSHKnownHostEntry: Identifiable, Sendable, Hashable {
    let id: Int
    let lineNumber: Int
    /// 主机名列表；主机名被哈希过时为空
    let hosts: [String]
    let keyType: String
    let isHashed: Bool
    /// "@cert-authority" / "@revoked"
    let marker: String?
    let fingerprint: String
    let rawLine: String

    var displayHosts: String {
        if isHashed { return "（主机名已哈希）" }
        return hosts.joined(separator: "、")
    }

    var algorithmTitle: String {
        if keyType.contains("ed25519") { return "ED25519" }
        if keyType.contains("rsa") { return "RSA" }
        if keyType.contains("ecdsa") { return "ECDSA" }
        return keyType
    }
}

// MARK: - config

/// ~/.ssh/config 里的一个 Host 块。
struct SSHConfigBlock: Identifiable, Sendable, Hashable {
    let id: Int
    let lineNumber: Int
    let patterns: [String]
    let hostName: String?
    let user: String?
    let port: Int?
    let identityFiles: [String]
    let proxyJump: String?
    let forwardAgent: Bool

    /// 是不是文件开头那段全局设置（Host 之前）
    let isGlobal: Bool

    var title: String {
        if isGlobal { return "全局默认" }
        return patterns.joined(separator: "、")
    }

    var resolvedIdentityPaths: [String] {
        identityFiles.map { ($0 as NSString).expandingTildeInPath }
    }

    /// 指向了不存在的密钥文件——改过密钥名之后最容易留下的坑
    var missingIdentityFiles: [String] {
        identityFiles.filter { !FileManager.default.fileExists(atPath: ($0 as NSString).expandingTildeInPath) }
    }

    /// 一行摘要，列表里显示
    var summary: String {
        var parts: [String] = []
        if let hostName { parts.append(hostName) }
        if let user { parts.append("用户 \(user)") }
        if let port, port != 22 { parts.append("端口 \(port)") }
        if !identityFiles.isEmpty { parts.append("钥匙 \(identityFiles.count) 把") }
        if let proxyJump { parts.append("跳板 \(proxyJump)") }
        return parts.isEmpty ? "（没有额外设置）" : parts.joined(separator: " · ")
    }
}

// MARK: - agent

struct SSHAgentKey: Identifiable, Sendable, Hashable {
    let bits: Int
    let fingerprint: String
    let comment: String
    let algorithm: String

    var id: String { fingerprint }
}

struct SSHAgentStatus: Sendable {
    let available: Bool
    let socket: String?
    let keys: [SSHAgentKey]
    let message: String
}

// MARK: - 连通

enum SSHProbeTarget: String, CaseIterable, Identifiable, Sendable {
    case github
    case gitee
    case gitlab
    case bitbucket
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .github: return "GitHub"
        case .gitee: return "Gitee"
        case .gitlab: return "GitLab"
        case .bitbucket: return "Bitbucket"
        case .custom: return "自定义"
        }
    }

    var host: String {
        switch self {
        case .github: return "github.com"
        case .gitee: return "gitee.com"
        case .gitlab: return "gitlab.com"
        case .bitbucket: return "bitbucket.org"
        case .custom: return ""
        }
    }

    /// 各家用来测连通的账号名
    var user: String {
        switch self {
        case .github, .gitlab, .bitbucket: return "git"
        case .gitee: return "git"
        case .custom: return "git"
        }
    }

    var sshKeyPage: URL? {
        switch self {
        case .github: return URL(string: "https://github.com/settings/ssh/new")
        case .gitee: return URL(string: "https://gitee.com/profile/sshkeys")
        case .gitlab: return URL(string: "https://gitlab.com/-/user_settings/ssh_keys")
        case .bitbucket: return URL(string: "https://bitbucket.org/account/settings/ssh-keys/")
        case .custom: return nil
        }
    }
}

struct SSHProbeResult: Sendable {
    let ok: Bool
    let message: String
    let account: String
    /// 平台最终认可的那把钥匙
    let acceptedKey: String?
    /// 客户端拿出去试过的钥匙
    let offeredKeys: [String]
    let rawOutput: String
}

// MARK: - 错误

enum SSHKeyError: LocalizedError {
    case nameMissing
    case nameInvalid(String)
    case alreadyExists(String)
    case generateFailed(String)
    case lockedPrivateKey
    case rebuildFailed(String)
    case trashFailed(String)

    var errorDescription: String? {
        switch self {
        case .nameMissing:
            return "给密钥起个文件名。"
        case .nameInvalid(let name):
            return "“\(name)” 这个文件名不合适，别带斜杠，也别用 ~ 开头。"
        case .alreadyExists(let name):
            return "\(name) 已经存在了。换个名字，或者先把旧的移走。"
        case .generateFailed(let message):
            return message
        case .lockedPrivateKey:
            return "这把私钥有密码短语，得先在终端里解锁才能导出公钥。"
        case .rebuildFailed(let message):
            return "公钥重建失败：\(message)"
        case .trashFailed(let message):
            return "移到废纸篓失败：\(message)"
        }
    }
}

// MARK: - 引擎

enum SSHKeyEngine {

    /// 别让 ssh-keygen / ssh-add 停下来问密码短语。
    ///
    /// 封住 stdin 是不够的——密码短语这些工具是从 `/dev/tty` 直接读的。
    /// 塞一个必定失败的 askpass 程序进去，它就立刻报错返回，不会挂在那里等。
    private static let noPrompt: [String: String] = [
        "SSH_ASKPASS": "/usr/bin/false",
        "SSH_ASKPASS_REQUIRE": "force",
        "DISPLAY": "seraphim-tools",
    ]

    /// 默认就是 ~/.ssh。
    ///
    /// 允许用环境变量指到别处，纯粹是为了让测试台本在临时目录里折腾——
    /// 生成密钥、改权限这些动作不能拿真实密钥开练。
    static var sshDirectory: String {
        if let override = ProcessInfo.processInfo.environment["SERAPHIM_SSH_DIR"], !override.isEmpty {
            return override
        }
        return (NSHomeDirectory() as NSString).appendingPathComponent(".ssh")
    }

    // MARK: 扫描

    /// 扫 ~/.ssh 下所有成对的密钥。只读，不动任何文件。
    static func scan() -> [SSHKeyInfo] {
        let manager = FileManager.default
        let directory = sshDirectory
        guard let entries = try? manager.contentsOfDirectory(atPath: directory) else { return [] }

        // 常见的排前面，其余按名字排
        let preferred = ["id_ed25519", "id_ecdsa", "id_rsa", "id_dsa"]
        var names: [String] = []
        for name in preferred where entries.contains(name) { names.append(name) }

        let ignorable: Set<String> = ["known_hosts", "known_hosts.old", "config", "authorized_keys"]
        for entry in entries.sorted() where !names.contains(entry) {
            guard !entry.hasPrefix("."), !ignorable.contains(entry) else { continue }
            // 有对应的 .pub、或者文件本身就是个私钥头，才算密钥
            let path = (directory as NSString).appendingPathComponent(entry)
            if manager.fileExists(atPath: path + ".pub") || looksLikePrivateKey(path) {
                names.append(entry)
            }
        }

        return names.compactMap { info(named: $0) }
    }

    static func info(named name: String) -> SSHKeyInfo? {
        let manager = FileManager.default
        let directory = sshDirectory
        let privatePath = (directory as NSString).appendingPathComponent(name)
        let publicPath = privatePath + ".pub"
        guard manager.fileExists(atPath: privatePath) else { return nil }

        let hasPublic = manager.fileExists(atPath: publicPath)
        let publicText = hasPublic
            ? ((try? String(contentsOfFile: publicPath, encoding: .utf8)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        let parsed = parsePublicKey(publicText)
        let attributes = try? manager.attributesOfItem(atPath: privatePath)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0

        return SSHKeyInfo(
            name: name,
            privatePath: privatePath,
            publicPath: publicPath,
            hasPublicFile: hasPublic,
            publicKey: publicText,
            keyType: parsed?.keyType ?? "",
            bits: parsed?.bits ?? 0,
            fingerprintSHA256: parsed?.sha256 ?? "",
            fingerprintMD5: parsed?.md5 ?? "",
            comment: parsed?.comment ?? "",
            lockState: lockState(of: privatePath, hasPublicKey: parsed != nil),
            privatePermissions: permissions(of: privatePath),
            publicPermissions: hasPublic ? permissions(of: publicPath) : nil,
            privateSize: size,
            createdAt: attributes?[.creationDate] as? Date,
            modifiedAt: attributes?[.modificationDate] as? Date
        )
    }

    private static func looksLikePrivateKey(_ path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let head = handle.readData(ofLength: 64)
        guard let text = String(data: head, encoding: .utf8) else { return false }
        return text.contains("PRIVATE KEY")
    }

    /// 演示 / 测试用：指定一个不同的 .ssh 目录时，绝大多数逻辑都能照着跑
    static func permissions(of path: String) -> Int? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue
    }

    // MARK: 公钥解析

    struct ParsedPublicKey: Sendable, Hashable {
        let keyType: String
        let bits: Int
        let sha256: String
        let md5: String
        let comment: String
    }

    /// 自己解公钥，不依赖 ssh-keygen。
    ///
    /// 好处是 known_hosts 里几百条也能一次算完，不必一行起一个子进程。
    static func parsePublicKey(_ text: String) -> ParsedPublicKey? {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }

        let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count >= 2 else { return nil }

        var index = 0
        if fields[0].hasPrefix("@") { index = 1 }        // known_hosts 的 @cert-authority
        guard fields.count > index + 1 else { return nil }

        // known_hosts 的行首是主机名，公钥格式的行首直接是类型
        var typeField = fields[index]
        var blobField = fields[index + 1]
        if !typeField.hasPrefix("ssh-") && !typeField.hasPrefix("ecdsa-") && !typeField.hasPrefix("sk-") {
            typeField = fields[index + 1]
            blobField = fields.count > index + 2 ? fields[index + 2] : ""
        }
        guard !blobField.isEmpty, let blob = Data(base64Encoded: blobField) else { return nil }

        let comment: String
        if let blobIndex = fields.firstIndex(of: blobField), blobIndex + 1 < fields.count {
            comment = fields[(blobIndex + 1)...].joined(separator: " ")
        } else {
            comment = ""
        }

        return ParsedPublicKey(
            keyType: typeField,
            bits: bitLength(keyType: typeField, blob: blob),
            sha256: fingerprint(blob: blob, style: .sha256) ?? "",
            md5: fingerprint(blob: blob, style: .md5) ?? "",
            comment: comment
        )
    }

    enum SSHFingerprintStyle: Sendable {
        case sha256
        case md5
    }

    static func fingerprint(blob: Data, style: SSHFingerprintStyle) -> String? {
        switch style {
        case .sha256:
            let digest = Data(SHA256.hash(data: blob))
            // OpenSSH 习惯把尾部的 = 去掉
            let base64 = digest.base64EncodedString().replacingOccurrences(of: "=", with: "")
            return "SHA256:" + base64
        case .md5:
            let digest = Data(Insecure.MD5.hash(data: blob))
            return "MD5:" + digest.map { String(format: "%02x", $0) }.joined(separator: ":")
        }
    }

    static func fingerprint(publicKeyText: String, style: SSHFingerprintStyle) -> String? {
        guard let parsed = parsePublicKey(publicKeyText) else { return nil }
        return style == .sha256 ? parsed.sha256 : parsed.md5
    }

    /// SSH 公钥的二进制结构是一串「长度 + 内容」，按这个把 RSA 的模数读出来算位长。
    private static func bitLength(keyType: String, blob: Data) -> Int {
        if keyType.contains("ed25519") { return 256 }
        if keyType.contains("nistp256") { return 256 }
        if keyType.contains("nistp384") { return 384 }
        if keyType.contains("nistp521") { return 521 }
        if keyType.contains("dsa") { return 1024 }
        guard keyType.contains("rsa") else { return 0 }

        var offset = 0
        guard skipString(blob, offset: &offset) != nil else { return 0 }   // "ssh-rsa"
        guard skipString(blob, offset: &offset) != nil else { return 0 }   // 指数 e
        guard let modulus = skipString(blob, offset: &offset) else { return 0 }
        // mpint 是补码大端，高位为 1 时会补一个 0x00，算位长要跳过
        var bytes = [UInt8](modulus)
        while let first = bytes.first, first == 0 { bytes.removeFirst() }
        guard let lead = bytes.first else { return 0 }
        let leadBits = 8 - lead.leadingZeroBitCount
        return (bytes.count - 1) * 8 + leadBits
    }

    private static func skipString(_ data: Data, offset: inout Int) -> Data? {
        guard offset + 4 <= data.count else { return nil }
        let base = data.startIndex + offset
        let length = Int(data[base]) << 24 | Int(data[base + 1]) << 16
            | Int(data[base + 2]) << 8 | Int(data[base + 3])
        offset += 4
        guard length >= 0, offset + length <= data.count else { return nil }
        let start = data.startIndex + offset
        let slice = data[start..<(start + length)]
        offset += length
        return Data(slice)
    }

    /// 私钥带不带密码短语。给它一个空短语试解，解得开就是没有。
    static func lockState(of privatePath: String, hasPublicKey: Bool = true) -> SSHKeyLockState {
        let result = SSHShell.run("/usr/bin/ssh-keygen", ["-y", "-P", "", "-f", privatePath],
                                  timeout: 15, environment: noPrompt)
        if result.ok { return .unlocked }
        let text = result.combined.lowercased()
        if text.contains("incorrect passphrase") || text.contains("passphrase") {
            return .passphrase
        }
        return hasPublicKey ? .unlocked : .unreadable
    }

    // MARK: 生成

    struct GenerateRequest: Sendable {
        var algorithm: SSHKeyAlgorithm = .ed25519
        var name: String = "id_ed25519"
        var comment: String = ""
        var passphrase: String = ""
    }

    static func generate(_ request: GenerateRequest) throws -> SSHKeyInfo {
        let manager = FileManager.default
        let name = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw SSHKeyError.nameMissing }
        guard !name.contains("/"), !name.hasPrefix("~"), !name.hasPrefix(".") else {
            throw SSHKeyError.nameInvalid(name)
        }

        let directory = sshDirectory
        try? manager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory)

        let privatePath = (directory as NSString).appendingPathComponent(name)
        guard !manager.fileExists(atPath: privatePath) else {
            throw SSHKeyError.alreadyExists(name)
        }

        var arguments = ["-t", request.algorithm.keyType]
        if let bits = request.algorithm.bits { arguments += ["-b", String(bits)] }
        arguments += [
            "-N", request.passphrase,
            "-C", request.comment.isEmpty ? defaultComment() : request.comment,
            "-f", privatePath,
        ]

        let result = SSHShell.run("/usr/bin/ssh-keygen", arguments, timeout: 60)
        guard result.ok else {
            // 生成失败时 ssh-keygen 可能已经落了半个文件，清掉免得留下垃圾
            try? manager.removeItem(atPath: privatePath)
            try? manager.removeItem(atPath: privatePath + ".pub")
            let message = result.combined
            throw SSHKeyError.generateFailed(
                message.isEmpty ? "ssh-keygen 没有正常结束（退出码 \(result.code)）" : friendly(message)
            )        }

        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privatePath)
        try? manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: privatePath + ".pub")

        guard let key = info(named: name) else {
            throw SSHKeyError.generateFailed("密钥生成完了但读不出来，检查一下 ~/.ssh 的权限。")
        }
        return key
    }

    static func defaultComment() -> String {
        let user = NSUserName()
        let host = Host.current().localizedName ?? "Mac"
        return "\(user)@\(host)"
    }

    /// ssh-keygen 的报错基本都是英文，挑常见的翻一下
    private static func friendly(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "命令没有返回内容" }
        let lower = text.lowercased()
        if lower.contains("permission denied") {
            return "没有权限写这个位置。检查一下 ~/.ssh 是不是你自己的、权限对不对。"
        }
        if lower.contains("no such file or directory") {
            return "目标目录不存在。"
        }
        if lower.contains("invalid filename") || (lower.contains("invalid") && lower.contains("name")) {
            return "文件名不合适，换个名字再试。"
        }
        if lower.contains("bad permissions") {
            return "文件权限有问题，去「体检」页一键修一下再试。"
        }
        return SSHText.firstLines(text, count: 3)
    }

    // MARK: 重建公钥 / 删除

    /// .pub 丢了（或者内容被改坏了）时，从私钥重新导出。
    static func rebuildPublicKey(for key: SSHKeyInfo) throws -> String {
        let result = SSHShell.run("/usr/bin/ssh-keygen", ["-y", "-f", key.privatePath],
                                  timeout: 30, environment: noPrompt)
        let content = result.out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.ok, !content.isEmpty else {
            let text = result.combined.lowercased()
            if text.contains("passphrase") || key.lockState == .passphrase {
                throw SSHKeyError.lockedPrivateKey
            }
            throw SSHKeyError.rebuildFailed(result.combined.isEmpty ? "退出码 \(result.code)" : friendly(result.combined))
        }
        try (content + "\n").write(toFile: key.publicPath, atomically: true, encoding: .utf8)
        return content
    }

    /// 删密钥走废纸篓，不做真正的删除——万一删错了还能捞回来。
    ///
    /// 用 FileManager 的废纸篓接口，不走 Finder：那条路需要「自动化」授权，
    /// 没授权时会静默挂住，比报错还难查。
    @discardableResult
    static func moveToTrash(_ paths: [String]) throws -> Int {
        let manager = FileManager.default
        let existing = paths.filter { manager.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return 0 }

        var moved = 0
        var lastError: String?
        for path in existing {
            do {
                try manager.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                moved += 1
            } catch {
                lastError = error.localizedDescription
            }
        }
        if moved == 0, let lastError {
            throw SSHKeyError.trashFailed(lastError)
        }
        return moved
    }

    // MARK: 权限体检

    /// ~/.ssh 下该紧的地方有没有松。ssh 对私钥权限很挑，
    /// 权限太开它会直接拒绝使用，报错还很不直观。
    static func auditPermissions() -> [SSHPermissionReport] {
        let manager = FileManager.default
        var reports: [SSHPermissionReport] = []

        let directory = sshDirectory
        if manager.fileExists(atPath: directory) {
            let actual = permissions(of: directory)
            let loose = (actual ?? 0) & 0o077 != 0
            reports.append(SSHPermissionReport(
                path: directory, label: ".ssh 目录", expected: 0o700, actual: actual,
                level: loose ? .critical : .ok,
                reason: loose
                    ? "别的用户能进这个目录，ssh 会因为目录权限太松而拒绝使用里面的私钥"
                    : "只有你能访问"
            ))
        }

        for key in scan() {
            let actual = key.privatePermissions
            let loose = (actual ?? 0) & 0o077 != 0
            reports.append(SSHPermissionReport(
                path: key.privatePath, label: "私钥 \(key.name)", expected: 0o600, actual: actual,
                level: loose ? .critical : .ok,
                reason: loose
                    ? "私钥权限是 \(key.permissionsText)，太开了。ssh 会报 “Permissions … are too open” 然后不用它"
                    : "只有你能读"
            ))
            // 公钥本来就是给人看的，只提示不报警
            if key.hasPublicFile, let publicPermissions = key.publicPermissions {
                let odd = publicPermissions & 0o022 != 0
                reports.append(SSHPermissionReport(
                    path: key.publicPath, label: "公钥 \(key.name).pub", expected: 0o644,
                    actual: publicPermissions,
                    level: odd ? .warning : .ok,
                    reason: odd ? "公钥谁都能读，但别让人能改它" : "正常"
                ))
            }
        }

        for (name, expected, level) in [
            ("config", 0o600, SSHPermissionLevel.warning),
            ("authorized_keys", 0o600, .warning),
        ] {
            let path = (directory as NSString).appendingPathComponent(name)
            guard manager.fileExists(atPath: path) else { continue }
            let actual = permissions(of: path)
            let loose = (actual ?? 0) & 0o077 != 0
            reports.append(SSHPermissionReport(
                path: path, label: name, expected: expected, actual: actual,
                level: loose ? level : .ok,
                reason: loose
                    ? (name == "authorized_keys"
                       ? "同组或其他人能改它，等于能把别人的钥匙塞进来"
                       : "配置里有主机名和用户名，别让其他人读到")
                    : "正常"
            ))
        }

        let knownHosts = (directory as NSString).appendingPathComponent("known_hosts")
        if manager.fileExists(atPath: knownHosts), let actual = permissions(of: knownHosts) {
            let odd = actual & 0o022 != 0
            reports.append(SSHPermissionReport(
                path: knownHosts, label: "known_hosts", expected: 0o644, actual: actual,
                level: odd ? .warning : .ok,
                reason: odd ? "别让其他人能改，不然主机指纹会被替换" : "正常"
            ))
        }

        return reports
    }

    /// 一键把权限改回该有的样子，返回改了哪些
    @discardableResult
    static func fixPermissions(_ reports: [SSHPermissionReport]) -> [String] {
        var fixed: [String] = []
        for report in reports where report.canFix {
            guard let actual = report.actual, actual != report.expected else { continue }
            if chmod(report.path, report.expected) {
                fixed.append(report.label)
            }
        }
        return fixed
    }

    @discardableResult
    static func chmod(_ path: String, _ mode: Int) -> Bool {
        let result = SSHShell.run("/bin/chmod", [String(mode, radix: 8), path], timeout: 10)
        return result.ok
    }

    // MARK: known_hosts

    static var knownHostsPath: String {
        (sshDirectory as NSString).appendingPathComponent("known_hosts")
    }

    static func knownHosts() -> [SSHKnownHostEntry] {
        guard let text = try? String(contentsOfFile: knownHostsPath, encoding: .utf8) else { return [] }
        var entries: [SSHKnownHostEntry] = []

        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            var fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard fields.count >= 3 else { continue }

            var marker: String?
            if fields[0].hasPrefix("@") {
                marker = fields.removeFirst()
                guard fields.count >= 3 else { continue }
            }

            let hostField = fields[0]
            let keyType = fields[1]
            let blobField = fields[2]
            let isHashed = hostField.hasPrefix("|1|")

            let hosts: [String] = isHashed
                ? []
                : hostField.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }

            var entryFingerprint = ""
            if let blob = Data(base64Encoded: blobField),
               let value = fingerprint(blob: blob, style: .sha256) {
                entryFingerprint = value
            }

            entries.append(SSHKnownHostEntry(
                id: index,
                lineNumber: index + 1,
                hosts: hosts,
                keyType: keyType,
                isHashed: isHashed,
                marker: marker,
                fingerprint: entryFingerprint,
                rawLine: line
            ))
        }
        return entries
    }

    /// 删掉某个主机在 known_hosts 里的记录。
    /// 服务器重建、换了 IP 之后会报 “REMOTE HOST IDENTIFICATION HAS CHANGED”，
    /// 处理方式就是把它删掉重新认识一次。ssh-keygen -R 自己会留 .old 备份。
    @discardableResult
    static func removeKnownHost(_ host: String) -> SSHExecResult {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SSHExecResult(code: 1, out: "", err: "先填个主机名")
        }
        return SSHShell.run("/usr/bin/ssh-keygen", ["-R", trimmed], timeout: 20)
    }

    // MARK: config

    static var configPath: String {
        (sshDirectory as NSString).appendingPathComponent("config")
    }

    static func hasConfig() -> Bool {
        FileManager.default.fileExists(atPath: configPath)
    }

    /// 解析 ~/.ssh/config。只认最常见的几个指令，够看清「自己配过什么」了。
    static func configBlocks() -> [SSHConfigBlock] {
        guard let text = try? String(contentsOfFile: configPath, encoding: .utf8) else { return [] }

        var blocks: [SSHConfigBlock] = []
        var pending: (line: Int, patterns: [String], values: [(String, String)])?
        var globalValues: [(String, String)] = []
        var globalLine = 0

        func flush() {
            guard let block = pending else {
                if !globalValues.isEmpty {
                    blocks.append(makeBlock(id: blocks.count, line: globalLine, patterns: [],
                                            values: globalValues, isGlobal: true))
                    globalValues = []
                }
                return
            }
            blocks.append(makeBlock(id: blocks.count, line: block.line, patterns: block.patterns,
                                    values: block.values, isGlobal: false))
            pending = nil
        }

        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            // "Host a  # 注释" 这种行尾注释要切掉
            let body = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty else { continue }

            let pieces = body.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let keyword = pieces.first else { continue }
            let args = Array(pieces.dropFirst())
            let key = keyword.lowercased()

            if key == "host" {
                flush()
                if !globalValues.isEmpty {
                    blocks.append(makeBlock(id: blocks.count, line: globalLine, patterns: [],
                                            values: globalValues, isGlobal: true))
                    globalValues = []
                }
                pending = (line: index + 1, patterns: args, values: [])
                continue
            }

            guard !args.isEmpty else { continue }
            let value = args.joined(separator: " ")
            if pending != nil {
                pending?.values.append((key, value))
            } else {
                if globalValues.isEmpty { globalLine = index + 1 }
                globalValues.append((key, value))
            }
        }
        flush()

        // 块里只剩 Include 这种无关指令的，没必要占位置
        return blocks
    }

    private static func makeBlock(
        id: Int, line: Int, patterns: [String], values: [(String, String)], isGlobal: Bool
    ) -> SSHConfigBlock {
        func first(_ key: String) -> String? {
            values.first { $0.0 == key }?.1
        }
        let identityFiles = values.filter { $0.0 == "identityfile" }.map(\.1)
        let proxyJump = first("proxyjump") ?? first("proxycommand")
        let forward = (first("forwardagent") ?? "no").lowercased()

        return SSHConfigBlock(
            id: id,
            lineNumber: line,
            patterns: patterns,
            hostName: first("hostname"),
            user: first("user"),
            port: first("port").flatMap { Int($0) },
            identityFiles: identityFiles,
            proxyJump: proxyJump,
            forwardAgent: forward == "yes" || forward == "true",
            isGlobal: isGlobal
        )
    }

    // MARK: authorized_keys

    static var authorizedKeysPath: String {
        (sshDirectory as NSString).appendingPathComponent("authorized_keys")
    }

    /// 本机上允许登录进来的公钥。每一行背后都是一个能连进这台机器的人。
    static func authorizedKeys() -> [ParsedPublicKey] {
        guard let text = try? String(contentsOfFile: authorizedKeysPath, encoding: .utf8) else { return [] }
        return text
            .components(separatedBy: .newlines)
            .compactMap { parsePublicKey($0) }
    }

    // MARK: agent

    static func agentStatus() -> SSHAgentStatus {
        let socket = ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"]
        let result = SSHShell.run("/usr/bin/ssh-add", ["-l"], timeout: 10)
        let text = result.combined.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()

        if lower.contains("could not open a connection") || lower.contains("no such file or directory") {
            return SSHAgentStatus(
                available: false, socket: socket, keys: [],
                message: "没有可用的 ssh-agent。密钥没加载的话，每次用都要输密码短语。"
            )
        }
        if lower.contains("the agent has no identities") {
            return SSHAgentStatus(
                available: true, socket: socket, keys: [],
                message: "agent 在跑，但一把钥匙都没加载。"
            )
        }
        guard result.ok || !text.isEmpty else {
            return SSHAgentStatus(
                available: false, socket: socket, keys: [],
                message: text.isEmpty ? "问不到 agent 的状态" : text
            )
        }

        var keys: [SSHAgentKey] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // "256 SHA256:xxx comment (ED25519)"
            let pieces = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard pieces.count >= 2, let bits = Int(pieces[0]) else { continue }
            var algorithm = ""
            if let last = pieces.last, last.hasPrefix("(") {
                algorithm = last.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            }
            let commentEnd = algorithm.isEmpty ? pieces.count : pieces.count - 1
            let comment = pieces.count > 3 ? pieces[2..<commentEnd].joined(separator: " ") : ""
            keys.append(SSHAgentKey(bits: bits, fingerprint: pieces[1], comment: comment, algorithm: algorithm))
        }

        return SSHAgentStatus(
            available: true, socket: socket, keys: keys,
            message: keys.isEmpty ? "agent 在跑，但一把钥匙都没加载。" : "已加载 \(keys.count) 把"
        )
    }

    /// 把密钥交给 agent。`useKeychain` 走 macOS 钥匙串，有密码短语的密钥也能记住。
    @discardableResult
    static func agentAdd(_ paths: [String], useKeychain: Bool = false) -> SSHExecResult {
        var arguments: [String] = []
        if useKeychain {
            arguments.append("--apple-use-keychain")
            // 走钥匙串时密码短语可以问系统，这时才允许它弹窗
            return SSHShell.run("/usr/bin/ssh-add", arguments + paths, timeout: 25)
        }
        arguments += paths
        return SSHShell.run("/usr/bin/ssh-add", arguments, timeout: 25, environment: noPrompt)
    }

    @discardableResult
    static func agentRemove(_ paths: [String]) -> SSHExecResult {
        if paths.isEmpty {
            return SSHShell.run("/usr/bin/ssh-add", ["-D"], timeout: 25)
        }
        return SSHShell.run("/usr/bin/ssh-add", ["-d"] + paths, timeout: 25)
    }

    // MARK: 连通

    /// 跟远端握个手，看它认不认这把钥匙。
    ///
    /// `ssh -T` 成功时退出码也是 1，所以只能看输出内容，不能看退出码。
    static func probe(
        host: String,
        user: String = "git",
        port: Int = 22,
        identityFile: String? = nil
    ) -> SSHProbeResult {
        let target = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            return SSHProbeResult(ok: false, message: "先填个主机名", account: "",
                                  acceptedKey: nil, offeredKeys: [], rawOutput: "")
        }

        var arguments = [
            "-T", "-v",
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=12",
        ]
        if let identityFile {
            arguments += ["-o", "IdentitiesOnly=yes", "-i", identityFile]
        }
        if port != 22 { arguments += ["-p", String(port)] }
        arguments.append("\(user)@\(target)")

        let result = SSHShell.run("/usr/bin/ssh", arguments, timeout: 30)
        let output = result.out + result.err
        let lower = output.lowercased()

        let accepted = firstMatch(in: output, marker: "Server accepts key:")
        var offered: [String] = []
        for line in output.components(separatedBy: .newlines) where line.contains("Offering public key:") {
            if let value = value(after: "Offering public key:", in: line) {
                offered.append(shorten(value))
            }
        }

        if lower.contains("successfully authenticated") || lower.contains("welcome to")
            || lower.contains("you've successfully authenticated") {
            let account = accountName(from: output)
            return SSHProbeResult(ok: true, message: "平台认这把钥匙", account: account,
                                  acceptedKey: accepted.map(shorten), offeredKeys: offered,
                                  rawOutput: output)
        }
        if lower.contains("permission denied") {
            return SSHProbeResult(
                ok: false,
                message: offered.isEmpty
                    ? "平台不认。它一把钥匙都没试过——检查一下是不是指定了不存在的密钥文件"
                    : "平台不认这把钥匙。把公钥加到平台账号的 SSH 设置里再试",
                account: "", acceptedKey: nil, offeredKeys: offered, rawOutput: output
            )
        }
        if lower.contains("could not resolve hostname") || lower.contains("nodename nor servname") {
            return SSHProbeResult(ok: false, message: "域名解析不了，检查网络或代理设置",
                                  account: "", acceptedKey: nil, offeredKeys: offered, rawOutput: output)
        }
        if lower.contains("operation timed out") || lower.contains("connection timed out")
            || lower.contains("connect to host") && lower.contains("timed out") {
            return SSHProbeResult(ok: false, message: "连接超时，网络到不了这个主机",
                                  account: "", acceptedKey: nil, offeredKeys: offered, rawOutput: output)
        }
        if lower.contains("connection refused") {
            return SSHProbeResult(ok: false, message: "对方拒绝连接，端口可能不对",
                                  account: "", acceptedKey: nil, offeredKeys: offered, rawOutput: output)
        }
        if lower.contains("host key verification failed") {
            return SSHProbeResult(ok: false, message: "主机指纹变了。去「主机」页把旧记录删掉再连",
                                  account: "", acceptedKey: nil, offeredKeys: offered, rawOutput: output)
        }

        let cleaned = result.combined.trimmingCharacters(in: .whitespacesAndNewlines)
        return SSHProbeResult(ok: false,
                              message: cleaned.isEmpty ? "没有收到回应" : SSHText.firstLines(cleaned, count: 3),
                              account: "", acceptedKey: accepted.map(shorten), offeredKeys: offered,
                              rawOutput: output)
    }

    /// 从 ssh -v 的输出里抠出账号名
    private static func accountName(from output: String) -> String {
        // GitHub: "Hi octocat! You've successfully authenticated, but GitHub does not provide shell access."
        // GitLab: "Welcome to GitLab, @octocat!"
        if let range = output.range(of: "Hi ") {
            let tail = output[range.upperBound...]
            if let end = tail.firstIndex(where: { $0 == "!" || $0 == "," || $0 == " " || $0 == "\n" }) {
                let name = String(tail[tail.startIndex..<end]).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { return name }
            }
        }
        if let range = output.range(of: "Welcome to ") {
            let tail = output[range.upperBound...]
            if let comma = tail.firstIndex(of: ",") {
                let after = tail[tail.index(after: comma)...]
                if let end = after.firstIndex(where: { $0 == "!" || $0 == "\n" || $0 == " " }) {
                    return String(after[after.startIndex..<end]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return ""
    }

    private static func firstMatch(in text: String, marker: String) -> String? {
        for line in text.components(separatedBy: .newlines) where line.contains(marker) {
            if let value = value(after: marker, in: line) { return value }
        }
        return nil
    }

    private static func value(after marker: String, in line: String) -> String? {
        guard let range = line.range(of: marker) else { return nil }
        let value = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// verbose 输出里的路径太长，只留文件名
    private static func shorten(_ text: String) -> String {
        var value = text
        // "Server accepts key: /Users/x/.ssh/id_ed25519 RSA SHA256:… agent" 这种
        if value.contains(" ") {
            let pieces = value.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            let mapped = pieces.map { piece -> String in
                piece.hasPrefix("/") ? (piece as NSString).lastPathComponent : piece
            }
            value = mapped.joined(separator: " ")
        } else if value.hasPrefix("/") {
            value = (value as NSString).lastPathComponent
        }
        return value
    }
}

/// 报错太长就掐断，界面里显示三行足够说明问题
enum SSHText {
    static func firstLines(_ text: String, count: Int) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.prefix(count).joined(separator: "\n")
    }
}
