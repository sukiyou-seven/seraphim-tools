import AppKit
import Combine
import Foundation

/// 日志里的一行
struct GitLogLine: Identifiable, Hashable {
    let id = UUID()
    var text: String
    var isError: Bool = false
    var isNotice: Bool = false
}

/// Git 工具的状态。做成单例，切走再回来东西都还在。
@MainActor
final class GitStore: ObservableObject {
    static let shared = GitStore()

    // MARK: 克隆

    @Published var urlText = ""
    @Published var rootPath = GitEngine.defaultRoot()
    @Published var shallow = true
    @Published var cloning = false
    @Published var cloneProgress = 0
    @Published var cloneLog: [GitLogLine] = []
    @Published var clonedPath: String?
    @Published var cloneError: String?

    // MARK: 推送

    @Published var repoPath = ""
    @Published var snapshot: GitRepoSnapshot?
    @Published var loadingRepo = false
    @Published var commitMessage = ""
    @Published var pushing = false
    @Published var pushProgress = 0
    @Published var pushLog: [GitLogLine] = []
    @Published var pushError: String?
    @Published var pushSucceeded = false
    /// 选中的文件夹不是仓库时，用来引导「初始化」
    @Published var pendingInitPath: String?
    @Published var newRemoteInput = ""

    // MARK: 身份

    @Published var identityName = ""
    @Published var identityEmail = ""

    // MARK: 账号

    @Published var accountHost: GitHost = .github
    @Published var accountExpanded = false
    @Published var tokenInput = ""
    @Published var tokenSaved = false
    @Published var sshKeys: [GitSSHKey] = []
    @Published var sshWorking = false
    @Published var sshTestMessage: String?
    @Published var sshTestOK = false
    /// 公钥刚复制到剪贴板，用来把按钮图标换成对勾
    @Published var copiedPublicKeyPath: String?

    private let defaults = UserDefaults.standard
    private let credentials = GitCredentialStore.shared
    private var cloneTask: Task<Void, Never>?
    private var pushTask: Task<Void, Never>?
    private let logLimit = 500

    private init() {
        rootPath = defaults.string(forKey: "gitRootPath") ?? GitEngine.defaultRoot()
        repoPath = defaults.string(forKey: "gitLastRepo") ?? ""
        urlText = defaults.string(forKey: "gitLastURL") ?? ""
        if defaults.object(forKey: "gitShallow") != nil {
            shallow = defaults.bool(forKey: "gitShallow")
        }
        if let raw = defaults.string(forKey: "gitAccountHost"), let host = GitHost(rawValue: raw) {
            accountHost = host
        }
        accountExpanded = defaults.bool(forKey: "gitAccountExpanded")
        let identity = GitEngine.existingIdentity()
        identityName = identity.name
        identityEmail = identity.email
        refreshSSHKeys()
        refreshTokenState()
    }

    func persist() {
        defaults.set(rootPath, forKey: "gitRootPath")
        defaults.set(repoPath, forKey: "gitLastRepo")
        defaults.set(urlText, forKey: "gitLastURL")
        defaults.set(shallow, forKey: "gitShallow")
        defaults.set(accountHost.rawValue, forKey: "gitAccountHost")
        defaults.set(accountExpanded, forKey: "gitAccountExpanded")
    }

    // MARK: - 克隆：地址与目标

    /// 剥掉首尾引号空白后的输入
    private var trimmedURL: String {
        urlText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 解析出的仓库信息，解析不了就是 nil（界面据此禁用按钮）
    var parsedURL: GitRepoURL? {
        guard !trimmedURL.isEmpty else { return nil }
        return try? GitRepoURL.parse(trimmedURL)
    }

    var urlError: String? {
        guard !trimmedURL.isEmpty, parsedURL == nil else { return nil }
        do {
            _ = try GitRepoURL.parse(trimmedURL)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// 克隆会落在哪儿（重名自动加 -2）
    var cloneDestination: String? {
        guard let repo = parsedURL else { return nil }
        let root = rootPath.isEmpty ? GitEngine.defaultRoot() : rootPath
        return GitEngine.availableDirectory(in: root, name: repo.folderName)
    }

    /// 这个位置是不是已经有个同名仓库了（用来提示）
    var destinationAlreadyExists: Bool {
        guard let repo = parsedURL else { return false }
        let root = rootPath.isEmpty ? GitEngine.defaultRoot() : rootPath
        let plain = (root as NSString).appendingPathComponent(repo.folderName)
        return FileManager.default.fileExists(atPath: plain)
    }

    func pickRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选这里"
        panel.message = "选一个存放代码的文件夹"
        if panel.runModal() == .OK, let url = panel.url {
            rootPath = url.path
            persist()
        }
    }

    // MARK: - 克隆

    func startClone() {
        guard let repo = parsedURL, !cloning else { return }
        guard let destination = cloneDestination else { return }

        // 用哪个地址：用户怎么贴的就怎么用，SSH 形式直接走密钥
        let url = trimmedURL.hasPrefix("git@") || trimmedURL.hasPrefix("ssh://") ? trimmedURL : repo.httpsURL

        cloning = true
        cloneProgress = 0
        cloneLog = []
        cloneError = nil
        clonedPath = nil
        persist()

        appendClone("准备克隆 \(repo.slug) → \(destination)", notice: true)

        let credential = credential(for: repo.host)
        let depth = shallow ? 1 : nil

        cloneTask = Task { [weak self] in
            guard let self else { return }
            var exitCode: Int32 = -1
            for await event in GitEngine.clone(url: url, into: destination, depth: depth, credential: credential) {
                switch event {
                case .line(let text):
                    self.appendClone(text)
                case .failure(let text):
                    self.appendClone(text, error: true)
                case .progress(let percent):
                    self.cloneProgress = max(self.cloneProgress, percent)
                case .finished(let code):
                    exitCode = code
                }
            }
            self.cloning = false
            if exitCode == 0 {
                self.clonedPath = destination
                self.cloneProgress = 100
                self.appendClone("克隆完成", notice: true)
                // 顺手把推送页也指过来，用户下一步多半是推送
                self.repoPath = destination
                self.persist()
                self.loadRepository(destination)
            } else {
                self.cloneError = self.lastError(in: self.cloneLog)
                // 失败时清掉可能残留的空目录
                self.cleanupFailedClone(destination)
            }
        }
    }

    func cancelClone() {
        cloneTask?.cancel()
        cloneTask = nil
        cloning = false
        appendClone("已取消", notice: true)
    }

    /// git 失败时会留下一个只有 .git 的空壳，留着反而让用户困惑
    private func cleanupFailedClone(_ destination: String) {
        let manager = FileManager.default
        guard manager.fileExists(atPath: destination) else { return }
        let contents = (try? manager.contentsOfDirectory(atPath: destination))?
            .filter { $0 != ".DS_Store" } ?? []
        // 只动「除 .git 之外空无一物」的目录，别碰用户的东西
        guard contents == [".git"] else { return }
        let tracked = GitEngine.run(["ls-files"], in: destination).out
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let commits = GitEngine.log(in: destination, limit: 1)
        guard tracked.isEmpty, commits.isEmpty else { return }
        try? manager.removeItem(atPath: destination)
        appendClone("已清理失败留下的空目录", notice: true)
    }

    func revealCloned() {
        guard let clonedPath else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: clonedPath)
    }

    func openClonedInBrowser() {
        guard let repo = parsedURL, let url = URL(string: repo.webURL) else { return }
        NSWorkspace.shared.open(url)
    }

    private func appendClone(_ text: String, error: Bool = false, notice: Bool = false) {
        cloneLog.append(GitLogLine(text: text, isError: error, isNotice: notice))
        if cloneLog.count > logLimit { cloneLog.removeFirst(cloneLog.count - logLimit) }
    }

    // MARK: - 仓库快照

    func pickRepository() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "用这个"
        panel.message = "选一个 Git 仓库文件夹"
        if panel.runModal() == .OK, let url = panel.url {
            loadRepository(url.path)
        }
    }

    func loadRepository(_ path: String) {
        repoPath = path
        persist()
        loadingRepo = true
        pushError = nil
        pushSucceeded = false
        pendingInitPath = nil

        Task { [weak self] in
            let snapshot = await Task.detached { Self.readSnapshot(path) }.value
            guard let self else { return }
            self.snapshot = snapshot
            self.loadingRepo = false
            if !snapshot.isRepository {
                self.pendingInitPath = path
                self.newRemoteInput = ""
            }
        }
    }

    nonisolated private static func readSnapshot(_ path: String) -> GitRepoSnapshot {
        guard GitEngine.isRepository(at: path) else {
            return .notARepo(path: path)
        }
        let status = GitEngine.status(in: path)
        let remote = GitEngine.remoteURL(in: path)
        let host = remote.flatMap { try? GitRepoURL.parse($0) }?.host
        return GitRepoSnapshot(
            path: path,
            isRepository: true,
            status: status,
            remoteURL: remote,
            remoteHost: host,
            commits: GitEngine.log(in: path, limit: 5)
        )
    }

    func refreshSnapshot() {
        guard !repoPath.isEmpty else { return }
        let path = repoPath
        Task { [weak self] in
            let snapshot = await Task.detached { Self.readSnapshot(path) }.value
            self?.snapshot = snapshot
        }
    }

    /// 缺名字/邮箱时提醒一下（第一次提交的人常常卡在这）
    var needsIdentity: Bool {
        guard let snapshot, snapshot.isRepository else { return false }
        return !GitEngine.missingIdentity(in: snapshot.path).isEmpty
            && (identityName.isEmpty || identityEmail.isEmpty)
    }

    // MARK: - 初始化新仓库

    func initializeRepository() {
        guard let path = pendingInitPath else { return }
        pushing = true
        pushLog = []

        Task { [weak self] in
            guard let self else { return }
            let result = await Task.detached { GitEngine.initRepository(at: path) }.value
            self.pushing = false
            if result.ok {
                self.pushLog = [GitLogLine(text: "已经在 \(path) 建好 Git 仓库", isNotice: true)]
                self.pendingInitPath = nil
                if !self.newRemoteInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.applyRemote()
                } else {
                    self.loadRepository(path)
                }
            } else {
                self.pushError = result.friendlyError
            }
        }
    }

    /// 给刚初始化的仓库配上远程地址
    func applyRemote() {
        guard let snapshot else { return }
        let url = newRemoteInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        do {
            let repo = try GitRepoURL.parse(url)
            pushing = true
            let path = snapshot.path
            let useSSH = url.hasPrefix("git@") || url.hasPrefix("ssh://")
            let finalURL = useSSH ? repo.sshURL : repo.httpsURL
            Task { [weak self] in
                guard let self else { return }
                let result = await Task.detached { GitEngine.setRemote(finalURL, in: path) }.value
                self.pushing = false
                if result.ok {
                    self.newRemoteInput = ""
                    self.loadRepository(path)
                } else {
                    self.pushError = result.friendlyError
                }
            }
        } catch {
            pushError = error.localizedDescription
        }
    }

    // MARK: - 推送

    /// 当前仓库该用什么凭据。SSH 形式的远程不需要令牌。
    func credential(for host: GitHost) -> GitCredential? {
        credentials.credential(for: host)
    }

    private var currentCredential: GitCredential? {
        guard let snapshot, let remote = snapshot.remoteURL, let host = snapshot.remoteHost else { return nil }
        // SSH 地址靠本机密钥，不用令牌
        if remote.hasPrefix("git@") || remote.hasPrefix("ssh://") { return nil }
        return credential(for: host)
    }

    var canPush: Bool {
        guard let snapshot, snapshot.isRepository, !pushing else { return false }
        guard !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard snapshot.remoteURL != nil else { return false }
        // 没有改动也没有未推送的提交时，按钮就该灰着
        let status = snapshot.status
        let hasChanges = !(status?.changes.isEmpty ?? true)
        let hasAhead = (status?.ahead ?? 0) > 0
        return hasChanges || hasAhead
    }

    func startPush() {
        guard let snapshot, snapshot.isRepository, !pushing else { return }
        guard let remote = snapshot.remoteURL else {
            pushError = "这个仓库还没配远程地址，先在下面填一个"
            return
        }
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = snapshot.status
        let hasChanges = !(status?.changes.isEmpty ?? true)
        let needsUpstream = !GitEngine.hasUpstream(in: snapshot.path)
        let path = snapshot.path
        let credential = currentCredential
        let identity = (name: identityName, email: identityEmail)

        pushing = true
        pushProgress = 0
        pushLog = []
        pushError = nil
        pushSucceeded = false

        pushTask = Task { [weak self] in
            guard let self else { return }

            // 0. 身份没配的话先补上，不然提交会直接失败
            if !identity.name.isEmpty, !identity.email.isEmpty {
                let missing = await Task.detached { GitEngine.missingIdentity(in: path) }.value
                if !missing.isEmpty {
                    self.appendPush("先把提交用的名字和邮箱记上", notice: true)
                    _ = await Task.detached {
                        GitEngine.setIdentity(name: identity.name, email: identity.email, in: path)
                    }.value
                }
            }

            var exitCode: Int32 = 0

            // 1. 有改动就先提交
            if hasChanges {
                let staged = await Task.detached { GitEngine.stageAll(in: path) }.value
                guard staged.ok else {
                    self.finishPush(failure: staged.friendlyError)
                    return
                }
                self.appendPush("已暂存全部改动", notice: true)

                let committed = await Task.detached { GitEngine.commit(message: message, in: path) }.value
                if committed.ok {
                    self.appendPush("提交好了：\(message)", notice: true)
                } else {
                    self.finishPush(failure: committed.friendlyError)
                    return
                }
            } else {
                self.appendPush("没有新改动，直接推送已有的提交", notice: true)
            }

            // 2. 推送
            for await event in GitEngine.push(in: path, setUpstream: needsUpstream, credential: credential) {
                switch event {
                case .line(let text):
                    self.appendPush(text)
                case .failure(let text):
                    self.appendPush(text, error: true)
                case .progress(let percent):
                    self.pushProgress = max(self.pushProgress, percent)
                case .finished(let code):
                    exitCode = code
                }
            }

            self.pushing = false
            if exitCode == 0 {
                self.pushSucceeded = true
                self.commitMessage = ""
                self.pushProgress = 100
                self.refreshSnapshot()
            } else {
                self.pushError = self.lastError(in: self.pushLog)
                self.refreshSnapshot()
            }
        }
    }

    private func finishPush(failure: String) {
        pushing = false
        pushError = failure
    }

    func cancelPush() {
        pushTask?.cancel()
        pushTask = nil
        pushing = false
        appendPush("已取消", notice: true)
    }

    /// 远程有本地没有的提交时，拉一下再推
    func pullThenRetry() {
        guard let snapshot, snapshot.isRepository, !pushing else { return }
        let path = snapshot.path
        let credential = currentCredential
        pushing = true
        pushLog = []
        pushError = nil

        pushTask = Task { [weak self] in
            guard let self else { return }
            var exitCode: Int32 = -1
            self.appendPush("先把远程的更新拉下来", notice: true)
            for await event in GitEngine.pull(in: path, credential: credential) {
                switch event {
                case .line(let text): self.appendPush(text)
                case .failure(let text): self.appendPush(text, error: true)
                case .progress: break
                case .finished(let code): exitCode = code
                }
            }
            self.pushing = false
            if exitCode == 0 {
                self.refreshSnapshot()
                self.startPush()
            } else {
                self.pushError = self.lastError(in: self.pushLog)
                self.refreshSnapshot()
            }
        }
    }

    func openRemoteInBrowser() {
        guard let remote = snapshot?.remoteURL,
              let repo = try? GitRepoURL.parse(remote),
              let url = URL(string: repo.webURL) else { return }
        NSWorkspace.shared.open(url)
    }

    func revealRepository() {
        guard !repoPath.isEmpty else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: repoPath)
    }

    private func appendPush(_ text: String, error: Bool = false, notice: Bool = false) {
        pushLog.append(GitLogLine(text: text, isError: error, isNotice: notice))
        if pushLog.count > logLimit { pushLog.removeFirst(pushLog.count - logLimit) }
    }

    /// 从日志里挑出最像「原因」的那一行
    private func lastError(in log: [GitLogLine]) -> String {
        if let fatal = log.last(where: { $0.isError && $0.text.lowercased().contains("fatal") }) {
            return GitText.friendly(fatal.text)
        }
        if let error = log.last(where: { $0.isError }) {
            return GitText.friendly(error.text)
        }
        return "命令没有正常结束，看看下面的原始输出"
    }

    // MARK: - 身份

    func saveIdentity(global: Bool = true) {
        let name = identityName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = identityEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !email.isEmpty else { return }
        let path = repoPath.isEmpty ? NSHomeDirectory() : repoPath
        _ = GitEngine.setIdentity(name: name, email: email, in: path, global: global)
        refreshSnapshot()
    }

    // MARK: - 账号与密钥

    func selectHost(_ host: GitHost) {
        accountHost = host
        tokenInput = ""
        refreshTokenState()
        sshTestMessage = nil
        persist()
    }

    /// 同步一下「这个平台存没存令牌」的状态
    func refreshTokenState() {
        tokenSaved = credentials.has(for: accountHost)
    }

    var hasToken: Bool { tokenSaved }

    var maskedToken: String? { credentials.maskedToken(for: accountHost) }

    func saveToken() {
        let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        if credentials.save(token, for: accountHost) {
            tokenInput = ""
            tokenSaved = true
        }
    }

    func deleteToken() {
        _ = credentials.delete(for: accountHost)
        tokenSaved = false
    }

    func refreshSSHKeys() {
        sshKeys = SSHKeyManager.keys()
    }

    /// 没有密钥时一键生成一把
    func generateSSHKey() {
        guard !sshWorking else { return }
        sshWorking = true
        sshTestMessage = nil
        Task { [weak self] in
            guard let self else { return }
            let result: Result<GitSSHKey, Error> = await Task.detached {
                do {
                    return .success(try SSHKeyManager.generate(comment: SSHKeyManager.defaultComment()))
                } catch {
                    return .failure(error)
                }
            }.value
            self.sshWorking = false
            switch result {
            case .success(let key):
                self.refreshSSHKeys()
                self.sshTestMessage = "已经生成一把新的密钥（\(key.name)），复制公钥加到平台上就能用了"
                self.sshTestOK = true
            case .failure(let error):
                self.sshTestMessage = error.localizedDescription
                self.sshTestOK = false
            }
        }
    }

    func testSSHConnection() {
        guard !sshWorking else { return }
        sshWorking = true
        sshTestMessage = nil
        let host = accountHost
        Task { [weak self] in
            guard let self else { return }
            let result = await Task.detached { SSHKeyManager.testConnection(to: host) }.value
            self.sshWorking = false
            self.sshTestOK = result.ok
            self.sshTestMessage = result.message
        }
    }

    func copyPublicKey(_ key: GitSSHKey) {
        NSPasteboard.copyString(key.publicKey)
        copiedPublicKeyPath = key.privatePath
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if copiedPublicKeyPath == key.privatePath { copiedPublicKeyPath = nil }
        }
    }

    func openTokenPage() {
        guard let url = accountHost.tokenPage else { return }
        NSWorkspace.shared.open(url)
    }

    func openSSHKeyPage() {
        guard let url = accountHost.sshKeyPage else { return }
        NSWorkspace.shared.open(url)
    }
}
