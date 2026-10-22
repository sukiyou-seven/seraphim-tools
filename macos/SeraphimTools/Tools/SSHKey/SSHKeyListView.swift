import AppKit
import SwiftUI

/// 密钥页：本机有哪些钥匙、每把的底细、生成新的。
struct SSHKeyListView: View {
    @ObservedObject var store: SSHKeyStore

    @AppStorage("sshKeyAlgorithm") private var algorithm: SSHKeyAlgorithm = .ed25519
    @AppStorage("sshKeyName") private var name = ""
    @AppStorage("sshKeyComment") private var comment = ""
    @AppStorage("sshKeyExpanded") private var expandedKey = ""
    @AppStorage("sshKeyShowMD5") private var showMD5 = false

    /// 密码短语不落盘，也不留在内存里过夜
    @State private var passphrase = ""
    @State private var showPassphrase = false

    @State private var isGenerating = false
    @State private var justGenerated: SSHKeyInfo?
    @State private var deletingKey: SSHKeyInfo?
    @State private var confirmTrash = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                overviewCard

                ForEach(store.keys) { key in
                    keyCard(key)
                }

                if store.keys.isEmpty, !store.loadingKeys {
                    emptyCard
                }

                generateCard
            }
            .padding(20)
        }
        .task { await store.reloadKeys() }
        .alert("把这个密钥移到废纸篓？", isPresented: $confirmTrash, presenting: deletingKey) { key in
            Button("移到废纸篓", role: .destructive) {
                Task { await store.trash(key) }
                deletingKey = nil
            }
            Button("取消", role: .cancel) { deletingKey = nil }
        } message: { key in
            Text("会把 \(key.name) 和 \(key.publicPath.isEmpty ? "" : key.name + ".pub") 一起移到废纸篓——不是直接删除，还能捞回来。已经加到平台账号上的那把公钥不会跟着消失，需要你自己去平台删。")
        }
    }

    // MARK: 概览

    private var overviewCard: some View {
        ToolCard(title: "本机密钥", systemImage: "key.horizontal") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 18) {
                    statTile("\(store.keys.count)", "密钥", tint: store.keys.isEmpty ? .secondary : .accentColor)
                    statTile(agentText, "agent 已加载", tint: agentCount == 0 ? .secondary : .green)
                    statTile("\(store.problemCount)", "权限问题", tint: store.problemCount == 0 ? .green : .red)
                    Spacer(minLength: 0)
                    Button {
                        Task { await store.reloadKeys() }
                    } label: {
                        Label("重新扫描", systemImage: "arrow.clockwise").font(.system(size: 11.5))
                    }
                    .controlSize(.small)
                    .disabled(store.loadingKeys)
                }

                Text(SSHKeyEngine.sshDirectory)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)

                if !store.hasDirectory {
                    NoticeTag(text: "还没有 ~/.ssh 目录，生成第一把密钥时会自动建",
                              systemImage: "info.circle", tint: .orange)
                }
            }
        }
    }

    private var agentCount: Int {
        store.agent?.keys.count ?? 0
    }

    private var agentText: String {
        guard let agent = store.agent else { return "—" }
        guard agent.available else { return "不可用" }
        return "\(agent.keys.count)"
    }

    private func statTile(_ value: String, _ title: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private var emptyCard: some View {
        ToolCard(title: "空空如也", systemImage: "tray") {
            SSHEmptyHint(
                systemImage: "key.slash",
                title: "这台机器上还没有 SSH 密钥",
                detail: "在下面生成一把，然后把公钥粘到 GitHub / Gitee 之类的账号设置里就能用了。"
            )
        }
    }

    // MARK: 单把密钥

    private func keyCard(_ key: SSHKeyInfo) -> some View {
        let expanded = expandedKey == key.id
        return ToolCard(title: key.name, systemImage: "key.horizontal") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    SSHBadge(text: key.strengthTitle,
                             tint: key.algorithmTitle == "RSA" && key.bits <= 2048 ? .orange : .accentColor,
                             systemImage: "shield.lefthalf.filled")
                    SSHBadge(text: key.lockState.title,
                             tint: key.lockState == .passphrase ? .green : .secondary,
                             systemImage: key.lockState == .passphrase ? "lock.fill" : "lock.open")
                    if !key.hasPublicFile {
                        SSHBadge(text: "缺公钥文件", tint: .red, systemImage: "exclamationmark.triangle.fill")
                    }
                    if key.permissionsTooOpen {
                        SSHBadge(text: "权限太开 \(key.permissionsText)", tint: .red,
                                 systemImage: "exclamationmark.shield.fill")
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Text(key.shortFingerprint)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if !key.comment.isEmpty {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(key.comment)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    if let created = key.createdAt {
                        Text(Self.dateFormatter.string(from: created))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                }

                if expanded {
                    Divider().opacity(0.5)
                    details(key)
                }

                actions(key, expanded: expanded)
            }
        }
    }

    private func details(_ key: SSHKeyInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("指纹")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .leading)
                ChipButton(title: "SHA256", isSelected: !showMD5) { showMD5 = false }
                ChipButton(title: "MD5", isSelected: showMD5) { showMD5 = true }
                Spacer(minLength: 0)
            }

            let fingerprint = showMD5 ? key.fingerprintMD5 : key.fingerprintSHA256
            HStack(spacing: 8) {
                Text(fingerprint.isEmpty ? "算不出来（公钥文件缺失或损坏）" : fingerprint)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(fingerprint.isEmpty ? .tertiary : .primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !fingerprint.isEmpty {
                    CopyIconButton(text: fingerprint)
                }
                Spacer(minLength: 0)
            }
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

            if !key.publicKey.isEmpty {
                SSHCodeRow(title: "公钥", value: key.publicKey, lineLimit: 3)
            }
            SSHCodeRow(title: "私钥", value: key.privatePath)
            SSHCodeRow(title: "公钥文件", value: key.hasPublicFile ? key.publicPath : "（不存在）",
                       tint: key.hasPublicFile ? .primary : .red)

            HStack(spacing: 16) {
                Text("权限 \(key.permissionsText)")
                    .font(.system(size: 11))
                    .foregroundStyle(key.permissionsTooOpen ? .red : .secondary)
                Text(ByteFormatter.string(key.privateSize))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let modified = key.modifiedAt {
                    Text("改动于 \(Self.dateFormatter.string(from: modified))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if key.permissionsTooOpen {
                VStack(alignment: .leading, spacing: 6) {
                    NoticeTag(text: "权限 \(key.permissionsText) 太开，ssh 会拒绝使用这把私钥",
                              systemImage: "exclamationmark.shield.fill", tint: .red)
                    Button {
                        Task {
                            _ = SSHKeyEngine.chmod(key.privatePath, 0o600)
                            store.toast = "已把 \(key.name) 改回 600"
                            await store.reloadKeys()
                            await store.reloadAudit()
                        }
                    } label: {
                        Label("改成 600", systemImage: "wrench.and.screwdriver").font(.system(size: 11.5))
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func actions(_ key: SSHKeyInfo, expanded: Bool) -> some View {
        HStack(spacing: 10) {
            SSHCopyButton(
                title: "复制公钥", systemImage: "doc.on.doc",
                text: { key.publicKey.isEmpty ? "" : key.publicKey + "\n" }
            ) {
                store.toast = "公钥已复制，粘到平台的 SSH 设置里就行"
            }
            .disabled(key.publicKey.isEmpty)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedKey = expanded ? "" : key.id
                }
            } label: {
                Label(expanded ? "收起" : "详情", systemImage: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11.5))
            }
            .controlSize(.small)

            if !key.hasPublicFile, key.lockState != .passphrase {
                Button {
                    Task { await store.rebuildPublicKey(for: key) }
                } label: {
                    Label("补出公钥", systemImage: "wand.and.stars").font(.system(size: 11.5))
                }
                .controlSize(.small)
                .help("从私钥重新导出 .pub 文件")
            }

            Spacer(minLength: 0)

            Menu {
                Button("交给 ssh-agent") {
                    Task { await store.agentAdd([key], useKeychain: false) }
                }
                if key.lockState == .passphrase {
                    Button("交给 agent（存进钥匙串）") {
                        Task { await store.agentAdd([key], useKeychain: true) }
                    }
                }
                Button("在访达中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: key.privatePath)])
                }
                Divider()
                Button("移到废纸篓", role: .destructive) {
                    deletingKey = key
                    confirmTrash = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 32)
        }
    }

    // MARK: 生成

    private var generateCard: some View {
        ToolCard(title: "生成新密钥", systemImage: "wand.and.stars") {
            VStack(alignment: .leading, spacing: 12) {
                FlowRow(spacing: 6) {
                    ForEach(SSHKeyAlgorithm.allCases) { item in
                        ChipButton(title: item.title, isSelected: item == algorithm) {
                            algorithm = item
                        }
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    if algorithm.isRecommended {
                        NoticeTag(text: "推荐", systemImage: "hand.thumbsup.fill", tint: .green)
                    }
                    Text(algorithm.note)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                fieldRow("文件名") {
                    TextField(algorithm.defaultName, text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 220)
                }

                fieldRow("注释") {
                    TextField(SSHKeyEngine.defaultComment(), text: $comment)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(width: 260)
                }

                fieldRow("密码短语") {
                    HStack(spacing: 8) {
                        if showPassphrase {
                            TextField("留空就不设", text: $passphrase)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 220)
                        } else {
                            SecureField("留空就不设", text: $passphrase)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                                .frame(width: 220)
                        }
                        Button {
                            showPassphrase.toggle()
                        } label: {
                            Image(systemName: showPassphrase ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        Spacer(minLength: 0)
                    }
                }

                Text(passphrase.isEmpty
                     ? "不设密码短语：用起来最省事（一键推送、开机自动拉取都能直接用）。磁盘上的私钥本身是 600 权限，别人读不到。"
                     : "设了密码短语：私钥被拷走也用不了。代价是每次用都得输一次，除非交给 agent 或者存进系统钥匙串。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        Task { await generate() }
                    } label: {
                        Label("生成", systemImage: "plus.circle").font(.system(size: 12))
                    }
                    .controlSize(.small)
                    .disabled(isGenerating)

                    if isGenerating {
                        ProgressView().controlSize(.small)
                    }

                    Spacer(minLength: 0)
                }

                if let key = justGenerated {
                    Divider().opacity(0.5)
                    generatedResult(key)
                }
            }
        }
    }

    private func fieldRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func generatedResult(_ key: SSHKeyInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NoticeTag(text: "\(key.name) 生成好了", systemImage: "checkmark.seal.fill", tint: .green)

            SSHCodeRow(title: "公钥", value: key.publicKey, lineLimit: 3)

            HStack(spacing: 10) {
                Button {
                    NSPasteboard.copyString(key.publicKey + "\n")
                    store.toast = "公钥已复制"
                } label: {
                    Label("复制公钥", systemImage: "doc.on.doc").font(.system(size: 11.5))
                }
                .controlSize(.small)

                Menu {
                    ForEach(SSHProbeTarget.allCases.filter { $0.sshKeyPage != nil }) { target in
                        Button("去 \(target.title) 添加") {
                            if let page = target.sshKeyPage { NSWorkspace.shared.open(page) }
                        }
                    }
                } label: {
                    Label("去平台添加", systemImage: "arrow.up.right.square").font(.system(size: 11.5))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 130)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: key.privatePath)])
                } label: {
                    Label("在访达中显示", systemImage: "folder").font(.system(size: 11.5))
                }
                .controlSize(.small)

                Spacer(minLength: 0)
            }

            Text("下一步：把公钥加到平台的 SSH 设置里，然后去「连通」页点一下测试，看平台认不认。")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func generate() async {
        isGenerating = true
        let request = SSHKeyEngine.GenerateRequest(
            algorithm: algorithm,
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? algorithm.defaultName : name,
            comment: comment,
            passphrase: passphrase
        )
        do {
            let key = try await Task.detached(priority: .userInitiated) {
                try SSHKeyEngine.generate(request)
            }.value
            justGenerated = key
            expandedKey = key.id
            passphrase = ""
            store.toast = "\(key.name) 已生成"
            await store.reloadKeys()
        } catch {
            store.toast = error.localizedDescription
        }
        isGenerating = false
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
