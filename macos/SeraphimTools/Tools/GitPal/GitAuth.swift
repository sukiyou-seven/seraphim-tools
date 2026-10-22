import Foundation

// MARK: - askpass 桥

/// git 需要密码时会去调用 `GIT_ASKPASS` 指向的程序。
///
/// 我们放一个几行的脚本来承接这件事，用户名和令牌通过**环境变量**传进去——
/// 这样令牌不会出现在 remote 配置里，也不会留在 shell 历史或进程参数里。
enum GitAskPass {
    static let tokenKey = "SERAPHIM_GIT_TOKEN"
    static let usernameKey = "SERAPHIM_GIT_USER"

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("SeraphimTools", isDirectory: true)
    }

    static var scriptPath: String {
        directory.appendingPathComponent("git-askpass.sh").path
    }

    /// 确保脚本存在，返回路径
    static func ensureScript() -> String? {
        let manager = FileManager.default
        let path = scriptPath

        if manager.fileExists(atPath: path) { return path }

        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let script = """
        #!/bin/sh
        # SeraphimTools 用来把令牌交给 git，不写进任何配置文件
        case "$1" in
          *sername*|*Username*|*username*)
            printf '%s\\n' "$\(usernameKey)"
            ;;
          *)
            printf '%s\\n' "$\(tokenKey)"
            ;;
        esac
        """

        do {
            try script.write(toFile: path, atomically: true, encoding: .utf8)
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
            return path
        } catch {
            return nil
        }
    }
}

// MARK: - 令牌存储

/// 平台令牌存放处：macOS 钥匙串。
///
/// 读出来之后在内存里缓存，一个会话只问系统要一次。
final class GitCredentialStore: @unchecked Sendable {
    static let shared = GitCredentialStore()

    private let service = "SeraphimTools.git"
    private let lock = NSLock()
    private var cache: [String: String] = [:]

    private init() {}

    /// 某个平台存过令牌没有
    func has(for host: GitHost) -> Bool {
        load(for: host) != nil
    }

    func load(for host: GitHost) -> String? {
        lock.lock()
        if let cached = cache[host.rawValue] { lock.unlock(); return cached }
        lock.unlock()

        guard let token = Keychain.value(service: service, account: host.rawValue), !token.isEmpty else {
            return nil
        }
        lock.lock()
        cache[host.rawValue] = token
        lock.unlock()
        return token
    }

    @discardableResult
    func save(_ token: String, for host: GitHost) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard Keychain.set(trimmed, service: service, account: host.rawValue) else { return false }
        lock.lock()
        cache[host.rawValue] = trimmed
        lock.unlock()
        return true
    }

    @discardableResult
    func delete(for host: GitHost) -> Bool {
        lock.lock()
        cache[host.rawValue] = nil
        lock.unlock()
        return Keychain.remove(service: service, account: host.rawValue)
    }

    /// 拼出这次请求要用的凭据
    func credential(for host: GitHost) -> GitCredential? {
        guard let token = load(for: host), !token.isEmpty else { return nil }
        return GitCredential(token: token, username: host.tokenUsername, mode: .token)
    }

    /// 只用来做展示：把令牌打码
    func maskedToken(for host: GitHost) -> String? {
        guard let token = load(for: host), !token.isEmpty else { return nil }
        if token.count <= 8 { return String(repeating: "•", count: token.count) }
        return token.prefix(4) + String(repeating: "•", count: 8) + token.suffix(4)
    }
}

// MARK: - 钥匙串

/// 用系统自带的 `security` 命令读写钥匙串，不额外引入依赖。
enum Keychain {
    @discardableResult
    static func set(_ value: String, service: String, account: String) -> Bool {
        // -U：已存在就更新，不重复添加
        let result = Security.run([
            "add-generic-password",
            "-a", account,
            "-s", service,
            "-w", value,
            "-U",
        ])
        return result.code == 0
    }

    static func value(service: String, account: String) -> String? {
        let result = Security.run([
            "find-generic-password",
            "-a", account,
            "-s", service,
            "-w",
        ])
        guard result.code == 0 else { return nil }
        let text = result.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    @discardableResult
    static func remove(service: String, account: String) -> Bool {
        let result = Security.run([
            "delete-generic-password",
            "-a", account,
            "-s", service,
        ])
        return result.code == 0
    }
}

/// 跑 `security` 命令的小工具
enum Security {
    static func run(_ arguments: [String]) -> GitExecResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return GitExecResult(code: 126, out: "", err: error.localizedDescription)
        }

        process.waitUntilExit()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

        return GitExecResult(
            code: process.terminationStatus,
            out: String(data: outData, encoding: .utf8) ?? "",
            err: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}

// MARK: - SSH 密钥

/// SSH 密钥管理。真正的实现在 SSHKey 工具（Tools/SSHKey/SSHKeyEngine），
/// 这里只是一层适配：把通用的密钥信息翻译成 Git 助手要的 GitSSHKey。
///
/// 两边共用同一份实现——同一个动作有两份代码，迟早会有一边忘了改。
enum SSHKeyManager {
    static var sshDirectory: String { SSHKeyEngine.sshDirectory }

    /// 扫描本机现有的密钥，按常用程度排序
    static func keys() -> [GitSSHKey] {
        SSHKeyEngine.scan().map(convert)
    }

    /// 生成一把新的 ed25519 密钥。
    /// 这里刻意不带密码短语——一键推送要是每次都弹密码框就不好用了。
    static func generate(name: String = "id_ed25519", comment: String) throws -> GitSSHKey {
        let info = try SSHKeyEngine.generate(
            SSHKeyEngine.GenerateRequest(algorithm: .ed25519, name: name, comment: comment)
        )
        return convert(info)
    }

    /// 跟平台握个手，看这把密钥认不认。
    /// 注意 `ssh -T` 成功时退出码也是 1，所以只能看输出内容。
    static func testConnection(to host: GitHost) -> (ok: Bool, message: String) {
        guard let domain = host.domain else {
            return (false, "这个平台没有固定域名，先手动确认一下")
        }
        let result = SSHKeyEngine.probe(host: domain, user: "git")
        if result.ok {
            let who = result.account.isEmpty ? "" : "（\(result.account)）"
            return (true, "\(host.title) 认这把钥匙\(who)")
        }
        return (false, result.message)
    }

    /// 是不是本机已经有可用的密钥了
    static func hasUsableKey() -> Bool {
        !SSHKeyEngine.scan().isEmpty
    }

    /// 用来填 ssh-keygen 注释的默认值
    static func defaultComment() -> String {
        SSHKeyEngine.defaultComment()
    }

    private static func convert(_ info: SSHKeyInfo) -> GitSSHKey {
        GitSSHKey(
            privatePath: info.privatePath,
            publicPath: info.publicPath,
            publicKey: info.publicKey,
            fingerprint: info.fingerprintSHA256,
            algorithm: info.algorithmTitle
        )
    }
}
