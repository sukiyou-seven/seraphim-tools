import AppKit
import SwiftUI

/// 一键推送：选仓库 → 写一句说明 → 推上去
struct GitPushView: View {
    @ObservedObject var store: GitStore
    @State private var dropTargeted = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                repositoryCard

                if let snapshot = store.snapshot {
                    if snapshot.isRepository {
                        if let status = snapshot.status {
                            statusCard(snapshot: snapshot, status: status)
                        }
                        if store.needsIdentity { identityCard }
                        pushCard(snapshot: snapshot)
                    } else {
                        notARepoCard
                    }
                }

                GitAccountCard(store: store)
            }
            .padding(20)
        }
        .onAppear(perform: loadLastRepositoryIfNeeded)
    }

    /// 之前用过的仓库直接接着用，不用每次重新选
    private func loadLastRepositoryIfNeeded() {
        guard store.snapshot == nil, !store.repoPath.isEmpty, !store.loadingRepo else { return }
        store.loadRepository(store.repoPath)
    }

    // MARK: 选择仓库

    private var repositoryCard: some View {
        ToolCard(title: "仓库位置", systemImage: "folder") {
            VStack(alignment: .leading, spacing: 12) {
                GitPathField(
                    title: "要推送的文件夹",
                    path: store.repoPath,
                    placeholder: "还没选，或者把文件夹拖进来",
                    systemImage: "shippingbox",
                    actionTitle: "选择文件夹",
                    onPick: { store.pickRepository() }
                )

                HStack(spacing: 8) {
                    Button {
                        store.pickRepository()
                    } label: {
                        Label("选择", systemImage: "folder.badge.plus")
                            .font(.system(size: 11.5))
                    }
                    .controlSize(.small)

                    if !store.repoPath.isEmpty {
                        Button {
                            store.refreshSnapshot()
                        } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
                                .font(.system(size: 11.5))
                        }
                        .controlSize(.small)

                        Button {
                            store.revealRepository()
                        } label: {
                            Label("在访达中打开", systemImage: "folder")
                                .font(.system(size: 11.5))
                        }
                        .controlSize(.small)
                    }

                    Spacer(minLength: 0)

                    if store.loadingRepo {
                        ProgressView().controlSize(.small)
                    } else if store.snapshot?.isRepository == true {
                        GitPill(text: "Git 仓库", systemImage: "checkmark.seal.fill", tint: .green)
                    }
                }

                if dropTargeted {
                    Text("松开就把这个文件夹设为要推送的仓库")
                        .font(.system(size: 11))
                        .foregroundStyle(.accent)
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        dropTargeted ? Color.accentColor : Color.clear,
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )
            )
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { return false }
                store.loadRepository(url.path)
                return true
            } isTargeted: { targeted in
                withAnimation(.easeOut(duration: 0.12)) { dropTargeted = targeted }
            }
        }
    }

    // MARK: 状态

    private func statusCard(snapshot: GitRepoSnapshot, status: GitStatus) -> some View {
        ToolCard(title: "当前状态", systemImage: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 12) {
                headlineRow(snapshot: snapshot, status: status)

                if !status.changes.isEmpty {
                    changeList(status)
                } else if status.isUnborn {
                    emptyHint(
                        text: "这个仓库还一次都没提交过，写一句说明就能推第一次",
                        systemImage: "sparkles"
                    )
                } else if (status.ahead) > 0 {
                    emptyHint(
                        text: "工作区没有新改动，本地有 \(status.ahead) 个提交等着推上去",
                        systemImage: "arrow.up.circle"
                    )
                } else {
                    emptyHint(text: "没有需要推送的内容", systemImage: "checkmark.circle")
                }

                if !snapshot.commits.isEmpty {
                    Divider()
                    recentCommits(snapshot)
                }
            }
        }
    }

    private func headlineRow(snapshot: GitRepoSnapshot, status: GitStatus) -> some View {
        HStack(spacing: 10) {
            GitPill(text: status.branch, systemImage: "arrow.triangle.branch", tint: .blue)

            Text(status.headline)
                .font(.system(size: 12, weight: .medium))

            if let tracking = status.trackingText {
                GitPill(
                    text: tracking,
                    systemImage: status.ahead > 0 ? "arrow.up.circle.fill" : "equal.circle",
                    tint: status.ahead > 0 ? .orange : .secondary
                )
            }

            Spacer(minLength: 6)

            if let remote = snapshot.remoteURL {
                Button {
                    store.openRemoteInBrowser()
                } label: {
                    HStack(spacing: 6) {
                        GitHostBadge(host: snapshot.remoteHost ?? .other, domain: remoteHostText(remote))
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help(remote)
            } else {
                GitPill(text: "还没配远程地址", systemImage: "exclamationmark.triangle.fill", tint: .orange)
            }
        }
    }

    private func remoteHostText(_ remote: String) -> String? {
        (try? GitRepoURL.parse(remote))?.slug
    }

    private func changeList(_ status: GitStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("改动明细")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                Text("\(status.changes.count)")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(status.changes) { change in
                        GitChangeRow(change: change)
                    }
                }
            }
            .frame(maxHeight: 176)
        }
    }

    private func recentCommits(_ snapshot: GitRepoSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("最近提交")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            ForEach(snapshot.commits) { commit in
                HStack(spacing: 8) {
                    Text(commit.hash)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text(commit.subject)
                        .font(.system(size: 11.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text("\(commit.author) · \(commit.relativeDate)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func emptyHint(text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
    }

    // MARK: 身份

    private var identityCard: some View {
        ToolCard(title: "先留个名字", systemImage: "person.text.rectangle") {
            VStack(alignment: .leading, spacing: 10) {
                Text("提交记录上要署名，填一次以后都不用再填了。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    LabeledField(title: "名字") {
                        TextField("张三", text: $store.identityName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }
                    LabeledField(title: "邮箱") {
                        TextField("zhangsan@example.com", text: $store.identityEmail)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }
                }

                Button {
                    store.saveIdentity(global: true)
                } label: {
                    Label("记住", systemImage: "checkmark")
                        .font(.system(size: 11.5))
                }
                .controlSize(.small)
                .disabled(store.identityName.trimmingCharacters(in: .whitespaces).isEmpty
                          || store.identityEmail.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: 推送

    private func pushCard(snapshot: GitRepoSnapshot) -> some View {
        ToolCard(title: "推送", systemImage: "arrow.up.circle") {
            VStack(alignment: .leading, spacing: 12) {
                commitField(snapshot: snapshot)
                actionRow(snapshot: snapshot)

                if store.pushing || !store.pushLog.isEmpty {
                    GitProgressBar(
                        value: Double(store.pushProgress),
                        active: store.pushing,
                        tint: store.pushError == nil ? .accentColor : .orange
                    )
                    GitLogPane(lines: store.pushLog, placeholder: "准备开始")
                }

                if let error = store.pushError {
                    ErrorBanner(message: error)
                }
                if store.pushSucceeded {
                    successBanner
                }
            }
        }
    }

    private func commitField(snapshot: GitRepoSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("这次改了什么")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("一句话说明，比如：修了登录页的错别字", text: $store.commitMessage, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .lineLimit(1...3)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10))
                )
                .onSubmit { if store.canPush { store.startPush() } }

            if store.commitMessage.trimmingCharacters(in: .whitespaces).isEmpty,
               (snapshot.status?.changes.isEmpty == false) {
                Text("有改动要提交的话，这里得填一句")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func actionRow(snapshot: GitRepoSnapshot) -> some View {
        HStack(spacing: 10) {
            GitActionButton(
                title: store.pushing ? "正在推送…" : "一键推送",
                systemImage: "arrow.up.circle.fill",
                busy: store.pushing,
                enabled: store.canPush,
                action: { store.startPush() }
            )

            if store.pushing {
                Button("取消") { store.cancelPush() }
                    .buttonStyle(.link)
                    .font(.system(size: 11.5))
            } else if let status = snapshot.status, status.behind > 0 {
                Button {
                    store.pullThenRetry()
                } label: {
                    Label("先拉取远程的 \(status.behind) 个更新，再推", systemImage: "arrow.down.circle")
                        .font(.system(size: 11.5))
                }
                .controlSize(.small)
            }

            Spacer(minLength: 0)

            if snapshot.remoteURL == nil {
                Text("还没有远程地址，先在下面配一个")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var successBanner: some View {
        Label("推送完成，远程仓库已经更新", systemImage: "checkmark.seal.fill")
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.green)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.green.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.green.opacity(0.25))
            )
    }

    // MARK: 还不是仓库

    private var notARepoCard: some View {
        ToolCard(title: "这个文件夹还不是 Git 仓库", systemImage: "questionmark.folder") {
            VStack(alignment: .leading, spacing: 12) {
                Text("要推送，得先把文件夹变成一个 Git 仓库，并且告诉它推到哪个远程地址。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)

                LabeledField(title: "远程仓库地址（可选）") {
                    TextField("https://github.com/用户名/仓库.git", text: $store.newRemoteInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5, design: .monospaced))
                }

                HStack(spacing: 10) {
                    GitActionButton(
                        title: store.pushing ? "处理中…" : "在这里建一个 Git 仓库",
                        systemImage: "plus.rectangle.on.folder",
                        busy: store.pushing,
                        enabled: store.pendingInitPath != nil,
                        action: { store.initializeRepository() }
                    )

                    Text("已有的文件都会保留，只是加上版本管理")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)

                    Spacer(minLength: 0)
                }

                if let error = store.pushError {
                    ErrorBanner(message: error)
                }
            }
        }
    }
}

/// 带标题的输入框，横向排列用
struct LabeledField<Content: View>: View {
    var title: String
    var hint: String?
    @ViewBuilder var content: Content

    init(title: String, hint: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.hint = hint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                if let hint {
                    Text(hint)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            content
        }
    }
}
