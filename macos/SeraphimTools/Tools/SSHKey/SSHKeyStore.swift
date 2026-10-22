import AppKit
import SwiftUI

// MARK: - 状态

/// 几个子页面共用一份扫描结果，来回切不用重新跑一遍。
///
/// 扫描要调 `ssh-keygen` 判断私钥有没有密码短语，所以一律放后台。
@MainActor
final class SSHKeyStore: ObservableObject {
    @Published var keys: [SSHKeyInfo] = []
    @Published var audit: [SSHPermissionReport] = []
    @Published var agent: SSHAgentStatus?
    @Published var knownHosts: [SSHKnownHostEntry] = []
    @Published var configs: [SSHConfigBlock] = []
    @Published var authorizedKeys: [SSHKeyEngine.ParsedPublicKey] = []

    @Published var loadingKeys = false
    @Published var loadingAudit = false
    @Published var loadingAgent = false
    @Published var loadingHosts = false

    @Published var toast: String?
    @Published var lastReload: Date?

    /// 有没有 ~/.ssh 目录（全新机器上可能还没建）
    var hasDirectory: Bool {
        FileManager.default.fileExists(atPath: SSHKeyEngine.sshDirectory)
    }

    var problemCount: Int {
        audit.filter(\.problem).count
    }

    // MARK: 加载

    func reloadKeys() async {
        guard !loadingKeys else { return }
        loadingKeys = true
        keys = await Task.detached(priority: .userInitiated) { SSHKeyEngine.scan() }.value
        loadingKeys = false
        lastReload = Date()
    }

    func reloadAudit() async {
        guard !loadingAudit else { return }
        loadingAudit = true
        audit = await Task.detached(priority: .userInitiated) { SSHKeyEngine.auditPermissions() }.value
        loadingAudit = false
    }

    func reloadAgent() async {
        guard !loadingAgent else { return }
        loadingAgent = true
        agent = await Task.detached(priority: .userInitiated) { SSHKeyEngine.agentStatus() }.value
        loadingAgent = false
    }

    func reloadHosts() async {
        guard !loadingHosts else { return }
        loadingHosts = true
        let result = await Task.detached(priority: .userInitiated) { () -> (
            [SSHKnownHostEntry], [SSHConfigBlock], [SSHKeyEngine.ParsedPublicKey]
        ) in
            (SSHKeyEngine.knownHosts(), SSHKeyEngine.configBlocks(), SSHKeyEngine.authorizedKeys())
        }.value
        knownHosts = result.0
        configs = result.1
        authorizedKeys = result.2
        loadingHosts = false
    }

    /// 刷新所有已经加载过的东西
    func reloadEverything() async {
        await reloadKeys()
        await reloadAudit()
        await reloadAgent()
        await reloadHosts()
    }

    // MARK: 动作

    func fixPermissions() async {
        let reports = audit
        let fixed = await Task.detached(priority: .userInitiated) {
            SSHKeyEngine.fixPermissions(reports)
        }.value
        if fixed.isEmpty {
            toast = "没有需要改的"
        } else {
            toast = "改好了 \(fixed.count) 处权限"
        }
        await reloadAudit()
    }

    func trash(_ key: SSHKeyInfo) async {
        do {
            let count = try await Task.detached(priority: .userInitiated) {
                try SSHKeyEngine.moveToTrash([key.privatePath, key.publicPath])
            }.value
            toast = "\(key.name) 已移到废纸篓（\(count) 个文件）"
            await reloadKeys()
            await reloadAudit()
        } catch {
            toast = error.localizedDescription
        }
    }

    func rebuildPublicKey(for key: SSHKeyInfo) async {
        do {
            _ = try await Task.detached(priority: .userInitiated) {
                try SSHKeyEngine.rebuildPublicKey(for: key)
            }.value
            toast = "公钥已从私钥重新导出"
            await reloadKeys()
        } catch {
            toast = error.localizedDescription
        }
    }

    func agentAdd(_ keys: [SSHKeyInfo], useKeychain: Bool) async {
        let paths = keys.map(\.privatePath)
        let result = await Task.detached(priority: .userInitiated) {
            SSHKeyEngine.agentAdd(paths, useKeychain: useKeychain)
        }.value
        toast = result.ok ? "已交给 agent（\(keys.count) 把）" : agentFailureText(result)
        await reloadAgent()
    }

    func agentRemove(_ key: SSHKeyInfo) async {
        let result = await Task.detached(priority: .userInitiated) {
            SSHKeyEngine.agentRemove([key.privatePath])
        }.value
        toast = result.ok ? "已从 agent 卸下" : agentFailureText(result)
        await reloadAgent()
    }

    func agentRemoveAll() async {
        let result = await Task.detached(priority: .userInitiated) {
            SSHKeyEngine.agentRemove([])
        }.value
        toast = result.ok ? "agent 里的钥匙都清空了" : agentFailureText(result)
        await reloadAgent()
    }

    func removeKnownHost(_ host: String) async {
        let result = await Task.detached(priority: .userInitiated) {
            SSHKeyEngine.removeKnownHost(host)
        }.value
        if result.ok {
            toast = "\(host) 的记录已删掉，下次连接会重新认识它"
            await reloadHosts()
        } else {
            toast = result.combined.isEmpty ? "没删掉（退出码 \(result.code)）" : result.combined
        }
    }

    private func agentFailureText(_ result: SSHExecResult) -> String {
        let text = result.combined
        if text.lowercased().contains("passphrase") {
            return "这把密钥有密码短语，在界面里输不了。去终端跑一次 ssh-add 就好了。"
        }
        return text.isEmpty ? "agent 没接受（退出码 \(result.code)）" : text
    }
}

// MARK: - 主视图

struct SSHKeyToolView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case keys
        case audit
        case agent
        case hosts
        case connect

        var id: String { rawValue }

        var title: String {
            switch self {
            case .keys: return "密钥"
            case .audit: return "体检"
            case .agent: return "agent"
            case .hosts: return "主机"
            case .connect: return "连通"
            }
        }

        var systemImage: String {
            switch self {
            case .keys: return "key.horizontal"
            case .audit: return "checkmark.shield"
            case .agent: return "square.stack.3d.up"
            case .hosts: return "server.rack"
            case .connect: return "antenna.radiowaves.left.and.right"
            }
        }
    }

    @AppStorage("sshMode") private var mode: Mode = .keys
    @StateObject private var store = SSHKeyStore()

    var body: some View {
        VStack(spacing: 0) {
            Picker("模式", selection: $mode) {
                ForEach(Mode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            switch mode {
            case .keys:
                SSHKeyListView(store: store)
            case .audit:
                SSHAuditView(store: store)
            case .agent:
                SSHAgentView(store: store)
            case .hosts:
                SSHHostsView(store: store)
            case .connect:
                SSHConnectView(store: store)
            }
        }
        .toast($store.toast)
    }
}

// MARK: - 共用小组件

/// 一键复制 + 反馈。密钥相关的按钮几乎都要复制点东西。
struct SSHCopyButton: View {
    let title: String
    let systemImage: String
    let text: () -> String
    var onCopied: (() -> Void)?

    var body: some View {
        Button {
            let value = text()
            guard !value.isEmpty else { return }
            NSPasteboard.copyString(value)
            onCopied?()
        } label: {
            Label(title, systemImage: systemImage).font(.system(size: 11.5))
        }
        .controlSize(.small)
    }
}

/// 密钥类型 / 状态的小徽章
struct SSHBadge: View {
    let text: String
    var tint: Color = .secondary
    var systemImage: String?

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .medium))
            }
            Text(text).font(.system(size: 10.5, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

/// 一段等宽文本 + 复制按钮（公钥、指纹、路径都用它）
struct SSHCodeRow: View {
    let title: String
    let value: String
    var tint: Color = .primary
    var lineLimit: Int = 1

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
                .padding(.top, 3)
            Text(value)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(tint)
                .textSelection(.enabled)
                .lineLimit(lineLimit)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !value.isEmpty {
                CopyIconButton(text: value)
            }
        }
    }
}

/// 没数据时的统一空状态
struct SSHEmptyHint: View {
    let systemImage: String
    let title: String
    var detail: String = ""

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}
