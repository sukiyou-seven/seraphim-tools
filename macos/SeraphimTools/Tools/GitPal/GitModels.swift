import Foundation

// MARK: - 托管平台

/// 支持的代码托管平台。只做「普通用户会用到的两件事」：克隆和推送。
enum GitHost: String, CaseIterable, Identifiable, Sendable {
    case github
    case gitee
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .github: return "GitHub"
        case .gitee: return "Gitee"
        case .other: return "其他仓库"
        }
    }

    /// 官方域名。other 没有固定域名（自建 GitLab / Gitea 这类）。
    var domain: String? {
        switch self {
        case .github: return "github.com"
        case .gitee: return "gitee.com"
        case .other: return nil
        }
    }

    var systemImage: String {
        switch self {
        case .github: return "cat"
        case .gitee: return "leaf"
        case .other: return "shippingbox"
        }
    }

    /// 从域名反推平台
    static func from(domain: String) -> GitHost {
        let lower = domain.lowercased()
        if lower == "github.com" || lower.hasSuffix(".github.com") { return .github }
        if lower == "gitee.com" || lower.hasSuffix(".gitee.com") { return .gitee }
        return .other
    }

    /// 申请访问令牌的页面
    var tokenPage: URL? {
        switch self {
        case .github:
            return URL(string: "https://github.com/settings/tokens/new?scopes=repo&description=SeraphimTools")
        case .gitee:
            return URL(string: "https://gitee.com/profile/personal_access_tokens")
        case .other:
            return nil
        }
    }

    /// 添加 SSH 公钥的页面
    var sshKeyPage: URL? {
        switch self {
        case .github: return URL(string: "https://github.com/settings/ssh/new")
        case .gitee: return URL(string: "https://gitee.com/profile/sshkeys")
        case .other: return nil
        }
    }

    /// 令牌填写提示（各家的叫法不一样）
    var tokenPlaceholder: String {
        switch self {
        case .github: return "ghp_… 或 github_pat_…"
        case .gitee: return "在「个人访问令牌」里生成"
        case .other: return "访问令牌"
        }
    }

    /// HTTPS 认证时用什么当用户名。令牌本身才是密码，用户名各家的习惯不同。
    var tokenUsername: String {
        switch self {
        case .github: return "x-access-token"
        case .gitee: return "oauth2"
        case .other: return "git"
        }
    }

    /// 令牌申请时需要勾的权限说明
    var tokenScopeHint: String {
        switch self {
        case .github: return "勾选 repo（私有仓库还需要 workflow 才能改 CI）"
        case .gitee: return "勾选 projects 和 pull_requests"
        case .other: return "需要读写仓库的权限"
        }
    }
}

// MARK: - 仓库地址

enum GitURLError: LocalizedError {
    case empty
    case unrecognized(String)
    case missingOwner
    case missingName

    var errorDescription: String? {
        switch self {
        case .empty:
            return "还没填仓库地址"
        case .unrecognized(let text):
            return "看不懂这个地址：\(text)"
        case .missingOwner:
            return "地址里没有用户名"
        case .missingName:
            return "地址里没有仓库名"
        }
    }
}

/// 仓库地址。四种写法都能吃进来，再统一吐出 https / ssh / 网页三种形式。
struct GitRepoURL: Hashable, Sendable {
    var host: GitHost
    /// 真实域名。自建服务（GitLab 之类）会保留原样，不会被归一成 github.com。
    var domain: String
    /// 非标准端口。自建服务常挂在 8443 这种端口上，不能丢。
    var port: String?
    var owner: String
    var name: String
    /// 用户原始输入，出错时好回显
    var raw: String

    /// owner/repo
    var slug: String { "\(owner)/\(name)" }

    /// 域名带端口（需要时）
    private var hostWithPort: String {
        guard let port, !port.isEmpty else { return domain }
        return "\(domain):\(port)"
    }

    var httpsURL: String { "https://\(hostWithPort)/\(owner)/\(name).git" }
    var sshURL: String {
        guard let port, !port.isEmpty else { return "git@\(domain):\(owner)/\(name).git" }
        // 带端口时 scp 风格有歧义，必须写成 ssh:// 形式
        return "ssh://git@\(domain):\(port)/\(owner)/\(name).git"
    }
    /// 网页地址，用来「在浏览器里打开」
    var webURL: String { "https://\(hostWithPort)/\(owner)/\(name)" }

    func url(for mode: GitAuthMode) -> String {
        mode == .ssh ? sshURL : httpsURL
    }

    /// 常用缩写（github 上的 owner/repo 官方就叫这个名字）
    var shortSlug: String { slug }

    // MARK: 解析

    /// 支持这几种写法：
    /// - `https://github.com/owner/repo.git`
    /// - `git@github.com:owner/repo.git`
    /// - `ssh://git@github.com/owner/repo.git`
    /// - `github.com/owner/repo`（省了协议）
    /// - `https://github.com/owner/repo/tree/main/src`（网页地址带着路径也能认出仓库）
    static func parse(_ text: String) throws -> GitRepoURL {
        var work = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 从网页复制时经常连引号一起带进来
        work = work.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’<>"))
        guard !work.isEmpty else { throw GitURLError.empty }

        // 地址里不该有空格和换行，有的话多半是用户贴错了别的东西
        guard !work.contains("\n"), !work.contains(" ") else {
            throw GitURLError.unrecognized(text)
        }

        var domain = ""
        var path = ""
        /// scp 风格里识别出来的端口
        var scpPort: String?

        if let atIndex = work.firstIndex(of: "@"), let colonIndex = work[atIndex...].firstIndex(of: ":") {
            // scp 风格：git@host:owner/repo.git
            // 先看有没有 ssh:// 前缀，那种用冒号判断会错
            if work.hasPrefix("ssh://") {
                (domain, path) = try splitSchemeURL(work, scheme: "ssh://")
            } else {
                let hostPart = work[work.index(after: atIndex)..<colonIndex]
                domain = String(hostPart)
                path = String(work[work.index(after: colonIndex)...])

                // scp 风格本来不支持自定义端口，但用户经常照着 ssh:// 的写法填。
                // 冒号后第一段是纯数字就当成端口，别把它错当成 owner。
                let head = path.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
                if head.count == 2, !head[0].isEmpty, head[0].allSatisfy({ $0.isNumber }) {
                    scpPort = String(head[0])
                    path = String(head[1])
                }
            }
        } else if let range = work.range(of: "://") {
            let scheme = String(work[work.startIndex..<range.lowerBound]).lowercased()
            guard ["http", "https", "ssh", "git", "ftps"].contains(scheme) else {
                throw GitURLError.unrecognized(text)
            }
            (domain, path) = try splitSchemeURL(work, scheme: "\(scheme)://")
        } else {
            // 裸域名：github.com/owner/repo
            (domain, path) = splitHostAndPath(work)
        }

        domain = domain.lowercased()
        // 去掉可能残留的用户名
        if let at = domain.lastIndex(of: "@") { domain = String(domain[domain.index(after: at)...]) }

        // 剥出端口。自建服务挂在 8443 这类端口上很常见，不能当垃圾扔掉。
        var port: String? = scpPort
        if let colon = domain.lastIndex(of: ":") {
            let candidate = String(domain[domain.index(after: colon)...])
            if !candidate.isEmpty, candidate.allSatisfy({ $0.isNumber }) {
                port = candidate
                domain = String(domain[domain.startIndex..<colon])
            }
        }
        guard !domain.isEmpty, domain.contains(".") else { throw GitURLError.unrecognized(text) }

        // 网页地址常带 ?tab=readme 或 #readme 这种尾巴，先切掉
        if let cut = path.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            path = String(path[path.startIndex..<cut])
        }

        let segments = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard segments.count >= 2 else {
            if segments.isEmpty { throw GitURLError.missingOwner }
            throw GitURLError.missingName
        }

        var owner = segments[0]
        var name = segments[1]

        // 网页地址常带尾缀，去掉
        if name.hasSuffix(".git") { name = String(name.dropLast(4)) }
        // 有些平台（如 GitLab 子组）路径会更深，这里只取前两段，够普通用户用了
        if owner.hasSuffix(".git") { owner = String(owner.dropLast(4)) }

        guard !owner.isEmpty else { throw GitURLError.missingOwner }
        guard !name.isEmpty else { throw GitURLError.missingName }

        // 简单合法性：不允许空格和斜杠
        guard !owner.contains(" "), !name.contains(" "), !name.contains("/") else {
            throw GitURLError.unrecognized(text)
        }

        return GitRepoURL(
            host: GitHost.from(domain: domain),
            domain: domain,
            port: port,
            owner: owner,
            name: name,
            raw: text
        )
    }

    /// 拆成 域名 + 路径（带协议）
    private static func splitSchemeURL(_ work: String, scheme: String) throws -> (String, String) {
        var body = String(work.dropFirst(scheme.count))
        // 去掉 user@
        if let at = body.firstIndex(of: "@") {
            // 但要小心路径里也可能有 @，只取第一个 @ 之前的用户部分
            let head = body[body.startIndex..<at]
            if !head.contains("/") { body = String(body[body.index(after: at)...]) }
        }
        return splitHostAndPath(body)
    }

    /// 按第一个斜杠拆域名和路径
    private static func splitHostAndPath(_ text: String) -> (String, String) {
        guard let slash = text.firstIndex(of: "/") else { return (text, "") }
        return (String(text[text.startIndex..<slash]), String(text[text.index(after: slash)...]))
    }

    /// 本地目录名：默认用仓库名，重名时由调用方处理
    var folderName: String { name }
}

// MARK: - 连接方式

enum GitAuthMode: String, CaseIterable, Identifiable, Sendable {
    /// 有 SSH 密钥就用 SSH，没有就用令牌
    case automatic
    case ssh
    case token

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "自动"
        case .ssh: return "SSH 密钥"
        case .token: return "访问令牌"
        }
    }

    var hint: String {
        switch self {
        case .automatic: return "有 SSH 密钥就走密钥，否则用令牌"
        case .ssh: return "不用输密码，钥匙在本机 ~/.ssh 里"
        case .token: return "用一串令牌当密码，适合没有密钥的情况"
        }
    }
}

// MARK: - 仓库状态

/// 单个文件的变化
struct GitFileChange: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case added
        case modified
        case deleted
        case renamed
        case copied
        case typeChanged
        case untracked
        case conflicted
        case unknown

        var title: String {
            switch self {
            case .added: return "新增"
            case .modified: return "修改"
            case .deleted: return "删除"
            case .renamed: return "重命名"
            case .copied: return "复制"
            case .typeChanged: return "类型变化"
            case .untracked: return "新文件"
            case .conflicted: return "冲突"
            case .unknown: return "变更"
            }
        }

        var symbol: String {
            switch self {
            case .added: return "plus.circle.fill"
            case .modified: return "pencil.circle.fill"
            case .deleted: return "minus.circle.fill"
            case .renamed: return "arrow.right.circle.fill"
            case .copied: return "doc.on.doc.fill"
            case .typeChanged: return "arrow.triangle.2.circlepath"
            case .untracked: return "questionmark.circle.fill"
            case .conflicted: return "exclamationmark.triangle.fill"
            case .unknown: return "circle.fill"
            }
        }

        /// 可以提交的变化（冲突得先解决，忽略文件不算）
        var isCommittable: Bool {
            switch self {
            case .untracked, .unknown: return true
            default: return true
            }
        }
    }

    var path: String
    var kind: Kind
    /// 是否已经放进暂存区
    var staged: Bool
    /// 重命名时的原名
    var originalPath: String?

    var id: String { "\(kind.rawValue)|\(path)" }

    var displayName: String { path }
    var fileName: String { (path as NSString).lastPathComponent }
    var directory: String? {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty || dir == "." ? nil : dir
    }
}

/// 工作区状态快照
struct GitStatus: Sendable {
    var branch: String
    var upstream: String?
    var ahead: Int = 0
    var behind: Int = 0
    var changes: [GitFileChange] = []
    /// 仓库里还一次都没提交过
    var hasCommits: Bool = true
    /// 空仓库（没有 HEAD）
    var isUnborn: Bool = false

    var isEmpty: Bool { changes.isEmpty }

    var stagedCount: Int { changes.filter(\.staged).count }
    var unstagedCount: Int { changes.count - stagedCount }

    /// 一句话概括，界面上大字显示
    var headline: String {
        if isUnborn { return "还没有提交过内容" }
        if changes.isEmpty { return "没有未提交的改动" }
        return "\(changes.count) 个文件有改动"
    }

    /// 分支相对远程的说明
    var trackingText: String? {
        guard upstream != nil else { return nil }
        if ahead == 0, behind == 0 { return "和远程一致" }
        var parts: [String] = []
        if ahead > 0 { parts.append("本地多 \(ahead) 个提交") }
        if behind > 0 { parts.append("远程多 \(behind) 个提交") }
        return parts.joined(separator: " · ")
    }
}

/// 一条提交记录
struct GitCommit: Identifiable, Hashable, Sendable {
    var hash: String
    var author: String
    var relativeDate: String
    var subject: String

    var id: String { hash }
}

/// 打开一个本地目录时拿到的一整套信息
struct GitRepoSnapshot: Sendable {
    var path: String
    var isRepository: Bool
    var status: GitStatus?
    var remoteURL: String?
    var remoteHost: GitHost?
    var commits: [GitCommit] = []

    var folderName: String { (path as NSString).lastPathComponent }

    static func notARepo(path: String) -> GitRepoSnapshot {
        GitRepoSnapshot(path: path, isRepository: false, status: nil, remoteURL: nil, remoteHost: nil)
    }
}

// MARK: - 认证材料

/// 一次 git 调用的认证信息，只在内存里停留
struct GitCredential: Sendable {
    /// 令牌本身（当作密码用）
    var token: String
    /// 用户名，各家习惯不同
    var username: String
    var mode: GitAuthMode

    static let none = GitCredential(token: "", username: "", mode: .automatic)

    var isEmpty: Bool { token.isEmpty }
}

// MARK: - SSH 密钥

struct GitSSHKey: Identifiable, Hashable, Sendable {
    var privatePath: String
    var publicPath: String
    /// 公钥内容（ssh-ed25519 AAAA… 注释）
    var publicKey: String
    /// ssh-keygen -lf 出来的指纹
    var fingerprint: String
    var algorithm: String

    var id: String { privatePath }
    var name: String { (privatePath as NSString).lastPathComponent }
    var hasPublicKey: Bool { !publicKey.isEmpty }
}

// MARK: - 执行事件

/// 一条命令执行过程中的事件，界面直接照着渲染
enum GitEvent: Sendable {
    /// 普通输出行
    case line(String)
    /// 进度百分比（clone 时 "Receiving objects: 45%"）
    case progress(Int)
    /// 标红的输出行
    case failure(String)
    /// 结束
    case finished(code: Int32)

    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}

// MARK: - 错误文案

enum GitText {
    /// 把 git 的英文报错翻成人话
    static func friendly(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "命令没有返回内容" }

        let lower = text.lowercased()

        if lower.contains("could not resolve host") || lower.contains("name or service not known") {
            return "连不上服务器，检查一下网络（或代理设置）"
        }
        if lower.contains("couldn't connect to server") || lower.contains("failed to connect to")
            || lower.contains("connection timed out") || lower.contains("operation timed out") {
            return "连不上服务器。检查网络，或者确认一下代理有没有开"
        }
        if lower.contains("connect tunnel failed")
            || (lower.contains("proxy") && lower.contains("failed")) {
            return "代理服务器拒绝了这次连接。检查一下代理设置，或者把代理关掉再试"
        }
        if lower.contains("permission denied (publickey)") {
            return "SSH 密钥没被平台认可。把公钥加到账号的 SSH 设置里，或者改用访问令牌"
        }
        if lower.contains("authentication failed") || lower.contains("invalid username or password")
            || lower.contains("could not read username") {
            return "认证没过。检查访问令牌是不是过期了、权限够不够"
        }
        if lower.contains("repository not found")
            || (lower.contains("not found") && lower.contains("repository")) {
            return "仓库不存在，或者这个令牌没有权限看它"
        }
        if lower.contains("already exists and is not an empty directory") {
            return "目标文件夹里已经有东西了，换个位置或者换个名字"
        }
        if lower.contains("destination path") && lower.contains("already exists") {
            return "目标文件夹已经存在"
        }
        if lower.contains("failed to push some refs") && lower.contains("behind") {
            return "远程有你本地没有的提交，先把远程的拉下来再推"
        }
        if lower.contains("rejected") {
            return "远程拒绝了这个推送。可能没有写权限，或者需要先拉取远程的更新"
        }
        if lower.contains("nothing to commit") {
            return "没有需要提交的改动"
        }
        if lower.contains("not a git repository") {
            return "这个文件夹还不是 Git 仓库"
        }
        if lower.contains("ssl certificate problem") {
            return "证书校验失败（自建服务常见），换个网络环境试试"
        }
        if lower.contains("timeout") || lower.contains("timed out") {
            return "连接超时了，网络不太通畅"
        }
        if lower.contains("connection refused") {
            return "对方拒绝连接"
        }
        return text
    }

    /// 从 git 输出里挑出百分比
    static func progressPercent(from line: String) -> Int? {
        guard line.contains("%") else { return nil }
        // Receiving objects:  45% (123/456), 1.2 MiB | 3.4 MiB/s
        guard let percentRange = line.range(of: "%") else { return nil }
        let head = line[line.startIndex..<percentRange.lowerBound]
        let digits = head.reversed().prefix { $0.isNumber }.reversed()
        guard !digits.isEmpty, let value = Int(String(digits)) else { return nil }
        return min(100, max(0, value))
    }
}
