import Foundation
import Darwin

// MARK: - 执行结果

struct GitExecResult: Sendable {
    var code: Int32
    var out: String
    var err: String

    var ok: Bool { code == 0 }
    var combined: String {
        [out, err].filter { !$0.isEmpty }.joined(separator: "\n")
    }
    /// 失败时的用户可读说明
    var friendlyError: String { GitText.friendly(err.isEmpty ? out : err) }
}

/// 跨线程收数据的盒子
private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func set(_ data: Data) {
        lock.lock(); storage = data; lock.unlock()
    }

    var value: Data {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}

// MARK: - 引擎

/// 对 git 命令行的一层薄封装。
///
/// 只用系统和用户已经装好的 git，不引入任何第三方依赖，也不需要 GitHub CLI。
enum GitEngine {

    // MARK: 可执行文件

    private static let pathLock = NSLock()
    private static var cachedPath: String?
    private static var didProbe = false

    /// 找到 git 可执行文件
    static func executable() -> String? {
        pathLock.lock()
        defer { pathLock.unlock() }
        if didProbe { return cachedPath }
        didProbe = true

        for path in ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"]
        where FileManager.default.isExecutableFile(atPath: path) {
            cachedPath = path
            return path
        }

        // Xcode 自带的 git 走 xcrun 找
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["-f", "git"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0,
               let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                cachedPath = text
                return text
            }
        } catch {
            return nil
        }
        return nil
    }

    static var isAvailable: Bool { executable() != nil }

    /// git 版本号
    static func version() -> String? {
        let result = run(["--version"])
        guard result.ok else { return nil }
        // "git version 2.54.0 (Apple Git-157)" → "2.54.0"
        return result.out
            .replacingOccurrences(of: "git version ", with: "")
            .split(separator: " ")
            .first
            .map(String.init)
    }

    // MARK: 一次性执行

    @discardableResult
    static func run(
        _ arguments: [String],
        in directory: String? = nil,
        environment: [String: String] = [:],
        timeout: TimeInterval = 120
    ) -> GitExecResult {
        guard let binary = executable() else {
            return GitExecResult(code: 127, out: "", err: "找不到 git。先装一下 Xcode 命令行工具：xcode-select --install")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        if let directory {
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
        }
        process.environment = mergedEnvironment(environment)

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return GitExecResult(code: 126, out: "", err: "启动 git 失败：\(error.localizedDescription)")
        }

        // 两个管道各派一个线程读，防止写满缓冲区互相卡住
        let outBox = DataBox()
        let errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outBox.set(outPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errBox.set(errPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }

        let exited = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            exited.signal()
        }

        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if exited.wait(timeout: .now() + 1.5) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 1.5)
            }
        }
        _ = group.wait(timeout: .now() + 3)

        let out = decode(outBox.value)
        let err = decode(errBox.value)
        if timedOut {
            return GitExecResult(code: -1, out: out, err: err.isEmpty ? "命令跑了太久（超过 \(Int(timeout)) 秒），已中断" : err)
        }
        return GitExecResult(code: process.terminationStatus, out: out, err: err)
    }

    private static func mergedEnvironment(_ extra: [String: String]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for (key, value) in extra { env[key] = value }
        // 非终端环境下这几个不关掉会卡在交互提示上
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_PAGER"] = "cat"
        env["SSH_ASKPASS"] = "/usr/bin/true"
        env["SSH_ASKPASS_REQUIRE"] = "never"
        if env["LC_ALL"] == nil { env["LC_ALL"] = "zh_CN.UTF-8" }
        return env
    }

    private static func decode(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    // MARK: 流式执行

    /// 边跑边吐输出。克隆这种耗时的命令用这个，能实时看见进度。
    static func stream(
        _ arguments: [String],
        in directory: String? = nil,
        environment: [String: String] = [:],
        credential: GitCredential? = nil
    ) -> AsyncStream<GitEvent> {
        AsyncStream { continuation in
            guard let binary = executable() else {
                continuation.yield(.failure("找不到 git。先装一下 Xcode 命令行工具：xcode-select --install"))
                continuation.yield(.finished(code: 127))
                continuation.finish()
                return
            }

            var extra = environment
            // 令牌通过环境变量喂给 askpass 脚本：不写进 remote，也不留在配置里
            if let credential, !credential.isEmpty, let script = GitAskPass.ensureScript() {
                extra["GIT_ASKPASS"] = script
                extra["SSH_ASKPASS"] = script
                extra[GitAskPass.usernameKey] = credential.username
                extra[GitAskPass.tokenKey] = credential.token
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = arguments
            if let directory {
                process.currentDirectoryURL = URL(fileURLWithPath: directory)
            }
            process.environment = mergedEnvironment(extra)

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let emitter = LineEmitter(continuation: continuation)
            let flush: @Sendable (Data) -> Void = { data in emitter.emit(data) }

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                flush(data)
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                flush(data)
            }

            process.terminationHandler = { finished in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                // handler 摘掉之后还有尾巴没读出来
                if let tail = try? outPipe.fileHandleForReading.readToEnd(), !tail.isEmpty {
                    flush(tail)
                }
                if let tail = try? errPipe.fileHandleForReading.readToEnd(), !tail.isEmpty {
                    flush(tail)
                }
                continuation.yield(.finished(code: finished.terminationStatus))
                continuation.finish()
            }

            continuation.onTermination = { _ in
                if process.isRunning { process.terminate() }
            }

            do {
                try process.run()
            } catch {
                continuation.yield(.failure("启动 git 失败：\(error.localizedDescription)"))
                continuation.yield(.finished(code: 126))
                continuation.finish()
            }
        }
    }

    /// 按行切分并翻译成事件
    private final class LineEmitter: @unchecked Sendable {
        private let continuation: AsyncStream<GitEvent>.Continuation
        private let lock = NSLock()
        private var buffer = ""

        init(continuation: AsyncStream<GitEvent>.Continuation) {
            self.continuation = continuation
        }

        func emit(_ data: Data) {
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return }
            lock.lock()
            buffer += text
            var lines: [String] = []
            while let index = buffer.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
                lines.append(String(buffer[buffer.startIndex..<index]))
                buffer.removeSubrange(buffer.startIndex...index)
            }
            // 没有换行的进度行也别压着，直接吐出去
            if let last = lines.last, GitText.progressPercent(from: last) != nil, !buffer.isEmpty {
                lines.append(buffer)
                buffer = ""
            }
            lock.unlock()

            for raw in lines {
                let line = cleanLine(raw)
                guard !line.isEmpty else { continue }
                // 平台回显的 "remote: ..." 对用户没意义
                if line.lowercased().hasPrefix("remote:") { continue }
                if let percent = GitText.progressPercent(from: line) {
                    continuation.yield(.progress(percent))
                }
                continuation.yield(isFailureLine(line) ? .failure(line) : .line(line))
            }
        }

        private func cleanLine(_ text: String) -> String {
            var line = text
            if let last = line.split(separator: "\r").last { line = String(last) }
            if line.contains("\u{1B}") { line = Self.stripANSI(line) }
            return line.trimmingCharacters(in: .whitespaces)
        }

        static func stripANSI(_ text: String) -> String {
            var output = ""
            var escaping = false
            for character in text {
                if character == "\u{1B}" { escaping = true; continue }
                if escaping {
                    if character.isLetter { escaping = false }
                    continue
                }
                output.append(character)
            }
            return output
        }

        private func isFailureLine(_ line: String) -> Bool {
            let lower = line.lowercased()
            return ["fatal:", "error:", "failed", "permission denied", "could not",
                    "unable to", "rejected", "refusing", "conflict"].contains { lower.contains($0) }
        }
    }

    // MARK: 仓库探测

    static func isRepository(at path: String) -> Bool {
        run(["rev-parse", "--is-inside-work-tree"], in: path)
            .out.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    static func repositoryRoot(at path: String) -> String? {
        let result = run(["rev-parse", "--show-toplevel"], in: path)
        guard result.ok else { return nil }
        let text = result.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    static func initRepository(at path: String, branch: String = "main") -> GitExecResult {
        run(["init", "-b", branch, "--quiet"], in: path)
    }

    // MARK: 远程

    static func remoteURL(in path: String, name: String = "origin") -> String? {
        let result = run(["remote", "get-url", name], in: path)
        guard result.ok else { return nil }
        let text = result.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    static func setRemote(_ url: String, in path: String, name: String = "origin") -> GitExecResult {
        if remoteURL(in: path, name: name) != nil {
            return run(["remote", "set-url", name, url], in: path)
        }
        return run(["remote", "add", name, url], in: path)
    }

    /// 远程有哪些分支（顺便当连通性测试用）
    static func remoteHeads(
        _ url: String,
        credential: GitCredential? = nil,
        timeout: TimeInterval = 30
    ) -> GitExecResult {
        var environment: [String: String] = [:]
        if let credential, !credential.isEmpty, let script = GitAskPass.ensureScript() {
            environment["GIT_ASKPASS"] = script
            environment["SSH_ASKPASS"] = script
            environment[GitAskPass.usernameKey] = credential.username
            environment[GitAskPass.tokenKey] = credential.token
        }
        return run(["ls-remote", "--heads", url], environment: environment, timeout: timeout)
    }

    // MARK: 状态

    static func currentBranch(in path: String) -> String? {
        let result = run(["rev-parse", "--abbrev-ref", "HEAD"], in: path)
        let text = result.out.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.ok, !text.isEmpty, text != "HEAD" { return text }

        // 一次提交都还没有的仓库，rev-parse 读不出分支名，得问 symbolic-ref
        let symbolic = run(["symbolic-ref", "--short", "HEAD"], in: path)
        let name = symbolic.out.trimmingCharacters(in: .whitespacesAndNewlines)
        if symbolic.ok, !name.isEmpty { return name }
        return text == "HEAD" ? "游离 HEAD" : nil
    }

    static func status(in path: String) -> GitStatus? {
        let result = run(["status", "--porcelain=v2", "--branch", "--untracked-files=all"], in: path)
        guard result.ok else { return nil }
        return parseStatus(result.out)
    }

    static func parseStatus(_ text: String) -> GitStatus {
        var branch = "main"
        var upstream: String?
        var ahead = 0
        var behind = 0
        var unborn = false
        var changes: [GitFileChange] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)

            if line.hasPrefix("# branch.head ") {
                branch = String(line.dropFirst("# branch.head ".count))
                if branch == "(detached)" { branch = "游离 HEAD" }
            } else if line.hasPrefix("# branch.upstream ") {
                upstream = String(line.dropFirst("# branch.upstream ".count))
            } else if line.hasPrefix("# branch.ab ") {
                for part in line.dropFirst("# branch.ab ".count).split(separator: " ") {
                    if part.hasPrefix("+") { ahead = Int(part.dropFirst()) ?? 0 }
                    if part.hasPrefix("-") { behind = Int(part.dropFirst()) ?? 0 }
                }
            } else if line.hasPrefix("# branch.oid ") {
                if line.contains("(initial)") { unborn = true }
            } else if line.hasPrefix("1 ") {
                let parts = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
                guard parts.count >= 9 else { continue }
                if let change = makeChange(xy: String(parts[1]), path: String(parts[8])) {
                    changes.append(change)
                }
            } else if line.hasPrefix("2 ") {
                let parts = line.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
                guard parts.count >= 10 else { continue }
                let tail = String(parts[9])
                let pieces = tail.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
                let fileName = String(pieces.first ?? "")
                var change = makeChange(xy: String(parts[1]), path: fileName)
                    ?? GitFileChange(path: fileName, kind: .renamed, staged: true)
                change.kind = .renamed
                change.originalPath = pieces.count > 1 ? String(pieces[1]) : nil
                changes.append(change)
            } else if line.hasPrefix("u ") {
                // u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>
                // 有些 git 版本字段数略有出入，直接取最后一段当路径最稳
                guard let path = line.split(separator: " ", omittingEmptySubsequences: false).last else { continue }
                changes.append(GitFileChange(path: String(path), kind: .conflicted, staged: false))
            } else if line.hasPrefix("? ") {
                changes.append(GitFileChange(path: String(line.dropFirst(2)), kind: .untracked, staged: false))
            }
        }

        changes.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        return GitStatus(
            branch: branch,
            upstream: upstream,
            ahead: ahead,
            behind: behind,
            changes: changes,
            hasCommits: !unborn,
            isUnborn: unborn
        )
    }

    /// XY 里 X 是暂存区状态、Y 是工作区状态。优先展示「还没进暂存区」的那一边。
    private static func makeChange(xy: String, path: String) -> GitFileChange? {
        let characters = Array(xy)
        guard characters.count >= 2 else { return nil }
        let indexStatus = characters[0]
        let workStatus = characters[1]
        if indexStatus == ".", workStatus == "." { return nil }

        let primary = workStatus == "." ? indexStatus : workStatus
        let staged = workStatus == "."
        return GitFileChange(path: path, kind: kind(from: primary), staged: staged)
    }

    private static func kind(from character: Character) -> GitFileChange.Kind {
        switch character {
        case "A": return .added
        case "M": return .modified
        case "D": return .deleted
        case "R": return .renamed
        case "C": return .copied
        case "T": return .typeChanged
        case "U": return .conflicted
        case "?": return .untracked
        default: return .unknown
        }
    }

    // MARK: 提交与推送

    static func stageAll(in path: String) -> GitExecResult {
        run(["add", "-A"], in: path)
    }

    /// 先看看有没有东西可提交，省得走一遍必然失败的命令
    static func hasStagedChanges(in path: String) -> Bool {
        !run(["diff", "--cached", "--quiet"], in: path).ok
    }

    static func commit(message: String, in path: String) -> GitExecResult {
        run(["commit", "-m", message], in: path)
    }

    /// 第一次提交前必须有名字和邮箱，缺哪个补哪个
    static func missingIdentity(in path: String) -> [String] {
        var missing: [String] = []
        if run(["config", "user.name"], in: path).out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("名字")
        }
        if run(["config", "user.email"], in: path).out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("邮箱")
        }
        return missing
    }

    static func setIdentity(name: String, email: String, in path: String, global: Bool = false) -> GitExecResult {
        var arguments = ["config"]
        if global { arguments.append("--global") }
        let nameResult = run(arguments + ["user.name", name], in: path)
        guard nameResult.ok else { return nameResult }
        return run(arguments + ["user.email", email], in: path)
    }

    static func existingIdentity() -> (name: String, email: String) {
        let name = run(["config", "--global", "user.name"]).out.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = run(["config", "--global", "user.email"]).out.trimmingCharacters(in: .whitespacesAndNewlines)
        return (name, email)
    }

    static func hasUpstream(in path: String) -> Bool {
        run(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], in: path).ok
    }

    static func push(in path: String, setUpstream: Bool, credential: GitCredential? = nil) -> AsyncStream<GitEvent> {
        guard let branch = currentBranch(in: path) else {
            return failureStream("读不出当前分支名，仓库可能还没提交过内容")
        }
        var arguments = ["push", "--progress"]
        if setUpstream { arguments += ["-u", "origin", branch] }
        return stream(arguments, in: path, credential: credential)
    }

    static func pull(in path: String, credential: GitCredential? = nil) -> AsyncStream<GitEvent> {
        stream(["pull", "--ff-only", "--progress"], in: path, credential: credential)
    }

    static func clone(
        url: String,
        into destination: String,
        depth: Int? = nil,
        branch: String? = nil,
        credential: GitCredential? = nil
    ) -> AsyncStream<GitEvent> {
        var arguments = ["clone", "--progress"]
        if let depth, depth > 0 { arguments += ["--depth", String(depth)] }
        if let branch, !branch.isEmpty { arguments += ["--branch", branch] }
        arguments += ["--", url, destination]
        return stream(arguments, credential: credential)
    }

    private static func failureStream(_ message: String) -> AsyncStream<GitEvent> {
        AsyncStream { continuation in
            continuation.yield(.failure(message))
            continuation.yield(.finished(code: 1))
            continuation.finish()
        }
    }

    // MARK: 日志

    static func log(in path: String, limit: Int = 6) -> [GitCommit] {
        let separator = "\u{1F}"
        let format = "%h\(separator)%an\(separator)%ar\(separator)%s"
        let result = run(["log", "-n", String(limit), "--pretty=format:\(format)"], in: path)
        guard result.ok else { return [] }
        return result.out.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: Character(separator), omittingEmptySubsequences: false)
            guard parts.count >= 4 else { return nil }
            return GitCommit(
                hash: String(parts[0]),
                author: String(parts[1]),
                relativeDate: String(parts[2]),
                subject: String(parts[3])
            )
        }
    }

    // MARK: 目录

    /// 挑一个能用的位置：重名时自动加 -2、-3
    static func availableDirectory(in parent: String, name: String) -> String {
        let manager = FileManager.default
        var candidate = (parent as NSString).appendingPathComponent(name)
        var index = 2
        while manager.fileExists(atPath: candidate) {
            candidate = (parent as NSString).appendingPathComponent("\(name)-\(index)")
            index += 1
        }
        return candidate
    }

    /// 默认存放根目录：先用已有的常见目录，都没有就建一个 ~/Developer
    static func defaultRoot() -> String {
        let manager = FileManager.default
        let home = NSHomeDirectory()
        for name in ["Developer", "Projects", "Code"] {
            let path = (home as NSString).appendingPathComponent(name)
            if manager.fileExists(atPath: path) { return path }
        }
        let fallback = (home as NSString).appendingPathComponent("Developer")
        try? manager.createDirectory(atPath: fallback, withIntermediateDirectories: true)
        return fallback
    }

    /// 目录里有多少东西（判断是不是空的）
    static func isDirectoryEmpty(_ path: String) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: path) else { return false }
        return contents.filter { $0 != ".DS_Store" }.isEmpty
    }
}
