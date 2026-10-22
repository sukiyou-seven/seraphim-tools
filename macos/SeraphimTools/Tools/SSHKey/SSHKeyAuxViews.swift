import AppKit
import SwiftUI

// MARK: - 体检

/// 权限体检。ssh 对私钥权限很挑，权限太开它会直接拒绝用，
/// 报错还只说一句 "Permissions … are too open"，很容易懵。
struct SSHAuditView: View {
    @ObservedObject var store: SSHKeyStore

    private var problems: [SSHPermissionReport] {
        store.audit.filter(\.problem)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                summaryCard

                if store.audit.isEmpty, !store.loadingAudit {
                    ToolCard(title: "没有可检查的东西", systemImage: "checkmark.shield") {
                        SSHEmptyHint(
                            systemImage: "folder.badge.questionmark",
                            title: "~/.ssh 目录还不存在",
                            detail: "生成第一把密钥之后，这里会列出目录、私钥、公钥的权限情况。"
                        )
                    }
                } else {
                    reportCard
                    explainCard
                }
            }
            .padding(20)
        }
        .task { await store.reloadAudit() }
    }

    private var summaryCard: some View {
        ToolCard(title: "体检结果", systemImage: "checkmark.shield") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(store.audit.count)")
                            .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        Text("检查项").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(problems.count)")
                            .font(.system(size: 17, weight: .semibold, design: .monospaced))
                            .foregroundStyle(problems.isEmpty ? .green : .red)
                        Text("有问题").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)

                    Button {
                        Task { await store.fixPermissions() }
                    } label: {
                        Label("一键修复", systemImage: "wrench.and.screwdriver.fill").font(.system(size: 11.5))
                    }
                    .controlSize(.small)
                    .disabled(problems.filter(\.canFix).isEmpty)

                    Button {
                        Task { await store.reloadAudit() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .disabled(store.loadingAudit)
                }

                if problems.isEmpty {
                    NoticeTag(text: "该紧的地方都是紧的", systemImage: "checkmark.seal.fill", tint: .green)
                } else {
                    NoticeTag(text: "有 \(problems.count) 处该修一下，点右边的按钮可以一次改好",
                              systemImage: "exclamationmark.triangle.fill", tint: .red)
                }
            }
        }
    }

    private var reportCard: some View {
        ToolCard(title: "逐项检查", systemImage: "list.bullet.rectangle") {
            VStack(spacing: 6) {
                ForEach(store.audit) { report in
                    reportRow(report)
                }
            }
        }
    }

    private func reportRow(_ report: SSHPermissionReport) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName(report.level))
                .font(.system(size: 12))
                .foregroundStyle(tint(report.level))
                .frame(width: 16)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(report.label)
                        .font(.system(size: 12, weight: .medium))
                    SSHBadge(text: report.level.title, tint: tint(report.level))
                    Spacer(minLength: 0)
                    if report.actual != nil {
                        Text("\(report.actualText)")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(tint(report.level))
                        if report.problem {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Text(report.expectedText)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(.green)
                        }
                    }
                }
                Text(report.reason)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(report.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint(report.level).opacity(report.problem ? 0.07 : 0.03))
        )
    }

    private func iconName(_ level: SSHPermissionLevel) -> String {
        switch level {
        case .critical: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .ok: return "checkmark.circle.fill"
        }
    }

    private func tint(_ level: SSHPermissionLevel) -> Color {
        switch level {
        case .critical: return .red
        case .warning: return .orange
        case .ok: return .green
        }
    }

    private var explainCard: some View {
        ToolCard(title: "为什么权限这么较真", systemImage: "questionmark.circle") {
            VStack(alignment: .leading, spacing: 8) {
                explainRow("600", "私钥：只有你能读写。同组或其他人有任何权限位，ssh 就会报 “Permissions 0644 for 'id_rsa' are too open” 并且拒绝使用这把钥匙")
                explainRow("700", "~/.ssh 目录：只有你能进。目录太开的话，别人能读到里面的东西，ssh 一样会拦")
                explainRow("644", "公钥：本来就是给别人看的，谁都能读没关系，但别让其他人能改")
                explainRow("600", "config / authorized_keys：里面写着主机名、用户名和能登录本机的公钥，别让其他人读到或改到")
            }
        }
    }

    private func explainRow(_ mode: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(mode)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - agent

struct SSHAgentView: View {
    @ObservedObject var store: SSHKeyStore
    @State private var useKeychain = false

    private var loadedFingerprints: Set<String> {
        Set(store.agent?.keys.map(\.fingerprint) ?? [])
    }

    /// agent 里已经有的那把，就别重复加载了
    private var loadableKeys: [SSHKeyInfo] {
        store.keys.filter { !loadedFingerprints.contains($0.fingerprintSHA256) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                statusCard
                loadedCard
                controlCard
                explainCard
            }
            .padding(20)
        }
        .task {
            await store.reloadKeys()
            await store.reloadAgent()
        }
    }

    private var statusCard: some View {
        ToolCard(title: "ssh-agent 状态", systemImage: "square.stack.3d.up") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Circle()
                        .fill((store.agent?.available ?? false) ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(store.agent?.available == true ? "可用" : "不可用")
                        .font(.system(size: 12.5, weight: .medium))
                    Text(store.agent?.message ?? "正在检查…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button {
                        Task { await store.reloadAgent() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .disabled(store.loadingAgent)
                }

                if let socket = store.agent?.socket {
                    SSHCodeRow(title: "socket", value: socket)
                } else {
                    Text("没读到 SSH_AUTH_SOCK。这个 App 不是从终端启动的，环境变量可能没带上——终端里的 ssh 通常还是能正常用 agent 的。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var loadedCard: some View {
        ToolCard(title: "已加载的钥匙", systemImage: "key.horizontal") {
            if let keys = store.agent?.keys, !keys.isEmpty {
                VStack(spacing: 6) {
                    ForEach(keys) { key in
                        HStack(spacing: 10) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(key.comment.isEmpty ? "（没有注释）" : key.comment)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                Text(key.fingerprint)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 6)
                            if !key.algorithm.isEmpty {
                                SSHBadge(text: key.algorithm, tint: .secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.035))
                        )
                    }
                }
            } else {
                SSHEmptyHint(
                    systemImage: "key.slash",
                    title: "agent 里现在没有钥匙",
                    detail: "加载之后，用这把密钥的 ssh / git 操作就不用再输密码短语了。"
                )
            }
        }
    }

    private var controlCard: some View {
        ToolCard(title: "加载与卸载", systemImage: "plusminus.circle") {
            VStack(alignment: .leading, spacing: 12) {
                FlowRow(spacing: 6) {
                    ForEach(store.keys) { key in
                        ChipButton(
                            title: key.name,
                            isSelected: loadedFingerprints.contains(key.fingerprintSHA256)
                        ) {
                            if loadedFingerprints.contains(key.fingerprintSHA256) {
                                Task { await store.agentRemove(key) }
                            } else {
                                Task { await store.agentAdd([key], useKeychain: useKeychain) }
                            }
                        }
                    }
                }

                if store.keys.isEmpty {
                    Text("~/.ssh 里还没有密钥，去「密钥」页先生成一把。")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 12) {
                    Toggle("有密码短语时存进系统钥匙串", isOn: $useKeychain)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11.5))

                    Spacer(minLength: 0)

                    Button {
                        Task { await store.agentAdd(loadableKeys, useKeychain: useKeychain) }
                    } label: {
                        Label("全部加载", systemImage: "arrow.down.circle").font(.system(size: 11.5))
                    }
                    .controlSize(.small)
                    .disabled(loadableKeys.isEmpty)

                    Button {
                        Task { await store.agentRemoveAll() }
                    } label: {
                        Label("全部卸下", systemImage: "arrow.up.circle").font(.system(size: 11.5))
                    }
                    .controlSize(.small)
                    .disabled((store.agent?.keys.isEmpty ?? true))
                }

                Text(useKeychain
                     ? "开启后会把密码短语存进 macOS 钥匙串，带密码短语的密钥也能自动用上。系统可能弹一次授权框。"
                     : "不开的话，有密码短语的密钥在界面里加不了——它需要交互输入密码短语。去终端跑一次 ssh-add 即可。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var explainCard: some View {
        ToolCard(title: "agent 是干什么的", systemImage: "questionmark.circle") {
            VStack(alignment: .leading, spacing: 8) {
                Text("把私钥交给 agent 之后，用它的 ssh / git 操作就不必反复输密码短语，密钥也不用在磁盘上到处放。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("agent 是跟着登录会话走的：重启、或者会话结束之后就空了，需要重新加载。所以带密码短语的密钥想长期省事，勾上钥匙串那个选项。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("没有密码短语的密钥其实不太需要 agent——它本来就能直接用。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 主机

struct SSHHostsView: View {
    @ObservedObject var store: SSHKeyStore

    @State private var search = ""
    @State private var showAllHosts = false
    @State private var hostToRemove = ""
    @State private var confirmRemove = false

    private var filteredHosts: [SSHKnownHostEntry] {
        let keyword = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !keyword.isEmpty else { return store.knownHosts }
        return store.knownHosts.filter { entry in
            entry.rawLine.lowercased().contains(keyword)
                || entry.hosts.contains { $0.lowercased().contains(keyword) }
        }
    }

    private var visibleHosts: [SSHKnownHostEntry] {
        showAllHosts ? filteredHosts : Array(filteredHosts.prefix(60))
    }

    private var distinctHostCount: Int {
        var set = Set<String>()
        for entry in store.knownHosts {
            if entry.isHashed {
                set.insert("（哈希）\(entry.id)")
            } else {
                for host in entry.hosts { set.insert(host) }
            }
        }
        return set.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                knownHostsCard
                configCard
                authorizedCard
            }
            .padding(20)
        }
        .task { await store.reloadHosts() }
        .alert("删掉 \(hostToRemove) 的主机记录？", isPresented: $confirmRemove) {
            Button("删掉", role: .destructive) {
                Task { await store.removeKnownHost(hostToRemove) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("服务器换过系统或重装过之后，会报 “REMOTE HOST IDENTIFICATION HAS CHANGED”。把旧记录删掉，下次连接重新认一次就好了。ssh-keygen 会自己留一份 .old 备份。")
        }
    }

    // MARK: known_hosts

    private var knownHostsCard: some View {
        ToolCard(title: "认识过的主机（known_hosts）", systemImage: "server.rack") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    Text("\(store.knownHosts.count)")
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    Text("条记录").font(.system(size: 10)).foregroundStyle(.tertiary)
                    Text("\(distinctHostCount)")
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .padding(.leading, 10)
                    Text("个主机").font(.system(size: 10)).foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    Button {
                        Task { await store.reloadHosts() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .disabled(store.loadingHosts)
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    TextField("按主机名或指纹里的内容过滤", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    if !search.isEmpty {
                        Button {
                            search = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack(spacing: 8) {
                    TextField("要忘掉的主机，比如 old.example.com", text: $hostToRemove)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: 280)
                    Button {
                        let target = hostToRemove.trimmingCharacters(in: .whitespaces)
                        guard !target.isEmpty else { return }
                        self.hostToRemove = target
                        confirmRemove = true
                    } label: {
                        Label("忘掉这个主机", systemImage: "trash").font(.system(size: 11.5))
                    }
                    .controlSize(.small)
                    .disabled(hostToRemove.trimmingCharacters(in: .whitespaces).isEmpty)
                    Spacer(minLength: 0)
                }

                if store.knownHosts.isEmpty {
                    SSHEmptyHint(
                        systemImage: "server.rack",
                        title: "还没连过任何主机",
                        detail: "第一次 ssh 到一台机器时，它的主机公钥会被记在这里，下次连接时用来确认对面还是它。"
                    )
                } else {
                    VStack(spacing: 4) {
                        ForEach(visibleHosts) { entry in
                            hostRow(entry)
                        }
                    }
                    if filteredHosts.count > visibleHosts.count {
                        Button("还有 \(filteredHosts.count - visibleHosts.count) 条，全部显示") {
                            showAllHosts = true
                        }
                        .controlSize(.small)
                        .font(.system(size: 11.5))
                    }
                }
            }
        }
    }

    private func hostRow(_ entry: SSHKnownHostEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.marker == "@revoked" ? "xmark.shield.fill" : "lock.shield.fill")
                .font(.system(size: 11))
                .foregroundStyle(entry.marker == "@revoked" ? .red : .green)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(entry.displayHosts)
                        .font(.system(size: 11.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    SSHBadge(text: entry.algorithmTitle, tint: .secondary)
                    if let marker = entry.marker {
                        SSHBadge(text: marker, tint: .orange)
                    }
                }
                Text(entry.fingerprint.isEmpty ? "（指纹算不出来）" : entry.fingerprint)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            Text("第 \(entry.lineNumber) 行")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)

            if let first = entry.hosts.first {
                Button {
                    hostToRemove = first
                    confirmRemove = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("删掉 \(first) 的记录")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    // MARK: config

    private var configCard: some View {
        ToolCard(title: "SSH 配置（~/.ssh/config）", systemImage: "doc.text") {
            if store.configs.isEmpty {
                SSHEmptyHint(
                    systemImage: "doc.badge.plus",
                    title: store.hasConfigCheck ? "config 里没有 Host 配置" : "还没有 config 文件",
                    detail: "配置里可以给主机起短名字、指定用哪把钥匙。用不到就不用管它。"
                )
            } else {
                VStack(spacing: 6) {
                    ForEach(store.configs) { block in
                        configRow(block)
                    }
                }
            }
        }
    }

    private func configRow(_ block: SSHConfigBlock) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: block.isGlobal ? "globe" : "server.rack")
                    .font(.system(size: 11))
                    .foregroundStyle(block.isGlobal ? Color.secondary : Color.accentColor)
                Text(block.title)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if block.forwardAgent {
                    SSHBadge(text: "ForwardAgent", tint: .orange)
                }
                Spacer(minLength: 0)
                Text("第 \(block.lineNumber) 行")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            }

            Text(block.summary)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !block.identityFiles.isEmpty {
                ForEach(block.identityFiles, id: \.self) { file in
                    HStack(spacing: 6) {
                        Image(systemName: block.missingIdentityFiles.contains(file)
                              ? "exclamationmark.triangle.fill" : "key.horizontal")
                            .font(.system(size: 9))
                            .foregroundStyle(block.missingIdentityFiles.contains(file) ? Color.red : Color.secondary)
                        Text(file)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(block.missingIdentityFiles.contains(file) ? Color.red : Color.secondary)
                        if block.missingIdentityFiles.contains(file) {
                            Text("这个文件不存在")
                                .font(.system(size: 10))
                                .foregroundStyle(.red)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
    }

    // MARK: authorized_keys

    private var authorizedCard: some View {
        ToolCard(title: "允许登入本机的公钥（authorized_keys）", systemImage: "person.badge.key") {
            VStack(alignment: .leading, spacing: 10) {
                if store.authorizedKeys.isEmpty {
                    SSHEmptyHint(
                        systemImage: "lock.open",
                        title: "没有 authorized_keys，或者里面是空的",
                        detail: "这个文件是给「别人 ssh 进这台机器」用的。只往外连的话用不到它。"
                    )
                } else {
                    NoticeTag(text: "这里的每一条，都是一把能直接登进这台机器的钥匙",
                              systemImage: "lock.open.fill", tint: .orange)
                    VStack(spacing: 6) {
                        ForEach(Array(store.authorizedKeys.enumerated()), id: \.offset) { _, key in
                            authorizedRow(key)
                        }
                    }
                }

                if store.hasDirectory {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [URL(fileURLWithPath: SSHKeyEngine.sshDirectory)]
                        )
                    } label: {
                        Label("在访达中打开 ~/.ssh", systemImage: "folder").font(.system(size: 11.5))
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func authorizedRow(_ key: SSHKeyEngine.ParsedPublicKey) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "key.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(key.comment.isEmpty ? "（没有注释）" : key.comment)
                        .font(.system(size: 11.5))
                        .lineLimit(1)
                    SSHBadge(text: key.keyType, tint: .secondary)
                }
                Text(key.sha256)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            CopyIconButton(text: key.sha256)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }
}

// MARK: - 连通

struct SSHConnectView: View {
    @ObservedObject var store: SSHKeyStore

    @AppStorage("sshConnectTarget") private var target: SSHProbeTarget = .github
    @AppStorage("sshConnectHost") private var customHost = ""
    @AppStorage("sshConnectPort") private var customPort = 22
    @AppStorage("sshConnectUser") private var customUser = "git"
    @AppStorage("sshConnectIdentity") private var identityPath = ""

    @State private var isTesting = false
    @State private var result: SSHProbeResult?
    @State private var testedTarget = ""

    private var host: String {
        target == .custom ? customHost.trimmingCharacters(in: .whitespaces) : target.host
    }

    private var user: String {
        target == .custom ? (customUser.isEmpty ? "git" : customUser) : target.user
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                targetCard
                identityCard
                resultCard
            }
            .padding(20)
        }
        .task { await store.reloadKeys() }
    }

    private var targetCard: some View {
        ToolCard(title: "测哪台机器", systemImage: "antenna.radiowaves.left.and.right") {
            VStack(alignment: .leading, spacing: 12) {
                FlowRow(spacing: 6) {
                    ForEach(SSHProbeTarget.allCases) { item in
                        ChipButton(title: item.title, isSelected: item == target) {
                            target = item
                            result = nil
                        }
                    }
                }

                if target == .custom {
                    HStack(spacing: 10) {
                        labeledField("主机") {
                            TextField("git.example.com", text: $customHost)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 220)
                        }
                        labeledField("端口") {
                            TextField("22", value: $customPort, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 70)
                        }
                        labeledField("用户") {
                            TextField("git", text: $customUser)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 90)
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    HStack(spacing: 8) {
                        Text("目标 \(user)@\(host)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if let page = target.sshKeyPage {
                            Button {
                                NSWorkspace.shared.open(page)
                            } label: {
                                Label("去添加公钥", systemImage: "arrow.up.right.square").font(.system(size: 11.5))
                            }
                            .controlSize(.small)
                        }
                        Spacer(minLength: 0)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await test() }
                    } label: {
                        Label("测试连通", systemImage: "bolt.horizontal.circle").font(.system(size: 12))
                    }
                    .controlSize(.small)
                    .disabled(isTesting || host.isEmpty)

                    if isTesting {
                        ProgressView().controlSize(.small)
                        Text("正在握手…").font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var identityCard: some View {
        ToolCard(title: "用哪把钥匙", systemImage: "key.horizontal") {
            VStack(alignment: .leading, spacing: 10) {
                FlowRow(spacing: 6) {
                    ChipButton(title: "自动（按 ssh 默认顺序）", isSelected: identityPath.isEmpty) {
                        identityPath = ""
                    }
                    ForEach(store.keys) { key in
                        ChipButton(title: key.name, isSelected: identityPath == key.privatePath) {
                            identityPath = key.privatePath
                        }
                    }
                }

                if identityPath.isEmpty {
                    Text("不指定的话，ssh 会按自己的顺序挨个试。多把钥匙并存时，有时你以为是 A 在起作用，其实是 B。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("只试这一把，别的钥匙不参与。这样能明确回答「这把钥匙在这个平台上到底能不能用」。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var resultCard: some View {
        ToolCard(title: "结果", systemImage: "bolt.horizontal.circle") {
            VStack(alignment: .leading, spacing: 12) {
                if isTesting {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在连 \(host)…").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                } else if let result {
                    resultBody(result)
                } else {
                    Text("点「测试连通」，看看平台认不认本机的钥匙。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("这一步是真实网络连接：会解析域名、建立 TCP、交换密钥、做认证。整个过程通常 1-3 秒。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func resultBody(_ result: SSHProbeResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: result.ok ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(result.ok ? .green : .red)
                Text(result.ok ? "通了" : "没通")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(result.ok ? .green : .red)
                Text("· \(testedTarget)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Text(result.message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !result.account.isEmpty {
                HStack(spacing: 8) {
                    Text("平台认出来的账号")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(result.account)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.green)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.green.opacity(0.08))
                )
            }

            if let accepted = result.acceptedKey {
                SSHCodeRow(title: "平台认了", value: accepted, tint: .green, lineLimit: 2)
            }

            if !result.offeredKeys.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("客户端试过的钥匙")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    ForEach(Array(result.offeredKeys.enumerated()), id: \.offset) { _, key in
                        Text("· \(key)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            if !result.ok {
                Text(result.offeredKeys.isEmpty
                     ? "一把钥匙都没送出去。多半是指定的密钥文件不存在，或者本机根本没有可用的私钥。"
                     : "平台试过上面的钥匙但都拒绝了。把公钥加到平台的 SSH 设置里，或者换一把再试。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DisclosureGroup {
                ScrollView {
                    Text(result.rawOutput.isEmpty ? "（没有输出）" : result.rawOutput)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .padding(8)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            } label: {
                Text("完整握手输出").font(.system(size: 11.5))
            }
        }
    }

    private func test() async {
        isTesting = true
        let currentHost = host
        let currentUser = user
        let currentPort = target == .custom ? customPort : 22
        let identity = identityPath.isEmpty ? nil : identityPath
        testedTarget = "\(currentUser)@\(currentHost):\(currentPort)"

        let value = await Task.detached(priority: .userInitiated) {
            SSHKeyEngine.probe(host: currentHost, user: currentUser, port: currentPort, identityFile: identity)
        }.value

        result = value
        isTesting = false
    }
}

// MARK: - 小扩展

extension SSHKeyStore {
    /// config 文件在不在（用于空状态文案）
    var hasConfigCheck: Bool { SSHKeyEngine.hasConfig() }
}
