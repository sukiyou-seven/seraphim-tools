import AppKit
import SwiftUI

/// v2ray / Xray：本地代理 + 云端一键安装
struct V2RayView: View {
    @ObservedObject private var store = V2RayStore.shared
    @ObservedObject private var runtime = V2RayRuntime.shared
    @StateObject private var cloud = CloudInstaller()

    @State private var cores: [CoreCandidate] = []
    @State private var selectedCore: CoreCandidate?
    @State private var toast: String?
    @State private var downloading = false
    @State private var note = ""
    @State private var pasteText = ""
    @State private var showLog = false
    @AppStorage("v2rayCloudExpanded") private var showCloud = false
    @AppStorage("v2rayAutoConnect") private var autoConnect = false
    @State private var proxyBusy = false
    /// 打开时若勾了"自动连上"，等内核就位后再启动一次
    @State private var pendingAutoStart = false
    /// 上一次会话（App 重启前）落盘的错误记录，进页面就提醒，别让"上次为什么断"永远成谜
    @State private var previousSessionErrors: [String] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !previousSessionErrors.isEmpty {
                    PreviousSessionCard(errors: previousSessionErrors) {
                        previousSessionErrors = []
                    }
                }

                CoreCard(
                    store: store,
                    cores: cores,
                    current: selectedCore,
                    downloading: downloading,
                    note: note,
                    onPick: { selectedCore = $0 },
                    onRescan: { refreshCores() },
                    onDownload: downloadCore,
                    onChooseFile: chooseCoreFile
                )

                ProxyCard(
                    store: store,
                    proxy: runtime.proxy,
                    useSystemProxy: runtime.useSystemProxy,
                    core: selectedCore,
                    busy: proxyBusy,
                    autoConnect: Binding(get: { autoConnect }, set: { autoConnect = $0 }),
                    onStart: startProxy,
                    onStop: stopProxy,
                    onRestart: restartProxy,
                    onToggleSystemProxy: { runtime.setSystemProxy($0) }
                )

                NodesCard(
                    store: store,
                    pasteText: $pasteText,
                    selected: store.selectedNode,
                    onImport: { importPaste() },
                    onImportClipboard: importClipboard,
                    onSelect: { selectNode($0) },
                    onDelete: { store.remove($0) },
                    onCopy: { copyLink($0) },
                    onTest: { store.testLatency(for: $0) },
                    onTestAll: { store.testAll() }
                )

                LogCard(proxy: runtime.proxy, expanded: $showLog)

                CloudInstallCard(
                    installer: cloud,
                    core: selectedCore,
                    expanded: $showCloud,
                    onImported: { node in
                        let added = store.add([node])
                        store.select(node)
                        toast = added > 0 ? "云端节点已加进列表" : "这个节点已经在列表里了"
                    }
                )
            }
            .padding(20)
        }
        .toast($toast)
        .onAppear {
            // 先把上次会话的错误捞出来（要在任何新会话写分隔符之前读）
            previousSessionErrors = ProxySessionLog.previousSessionErrorLines()
            runtime.installShutdownHook()
            // 先跟系统里的实际代理状态对个账：上次要是没还原干净，这里会顺手收拾掉，
            // 不然界面显示"没开"、系统里其实指着本机端口，网就断了
            runtime.reconcileSystemProxy()
            if cores.isEmpty {
                pendingAutoStart = autoConnect
                refreshCores()
            }
        }
        .onChange(of: runtime.message) { _, newValue in
            guard let newValue else { return }
            toast = newValue
            runtime.message = nil
        }
    }

    // MARK: 内核

    private func refreshCores(preferring path: String? = nil) {
        if cores.isEmpty { note = "正在准备内核…" }
        let extra = store.manualCorePath.isEmpty ? [] : [store.manualCorePath]
        let keep = selectedCore
        Task {
            // 内置内核随 App 一起走，用户不必自己去装 v2rayN 或下文件
            var installFailure: String?
            if !BundledCore.isInstalled {
                installFailure = await Task.detached(priority: .userInitiated) { () -> String? in
                    do {
                        try BundledCore.ensureInstalled()
                        return nil
                    } catch {
                        return error.localizedDescription
                    }
                }.value
            }

            let list = await CoreLocator.scanAsync(extraPaths: extra)
            await MainActor.run {
                cores = list
                if let path, let match = list.first(where: { $0.path == path }) {
                    selectedCore = match
                } else if let keep, list.contains(where: { $0.path == keep.path }) {
                    selectedCore = keep
                } else {
                    selectedCore = list.first
                }

                if let installFailure {
                    note = "内置内核没能释放出来：\(installFailure)"
                } else if list.isEmpty {
                    note = "没有可用内核。这个机型没有内置包时，可以点「下载内核」在线取一份。"
                } else if note == "正在准备内核…" || note.hasPrefix("没找到") || note.hasPrefix("内置内核") {
                    note = ""
                }

                // 勾了"打开就自动连上"的话，等内核和节点都齐了再启
                if pendingAutoStart {
                    pendingAutoStart = false
                    if selectedCore != nil, store.selectedNode != nil, !runtime.proxy.isRunning {
                        startProxy()
                    }
                }
            }
        }
    }

    private func chooseCoreFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "选一个 xray 或 v2ray 可执行文件"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.manualCorePath = url.path
        store.persist()
        refreshCores(preferring: url.path)
        toast = "已指定内核：\(url.lastPathComponent)"
    }

    private func downloadCore() {
        guard !downloading else { return }
        downloading = true
        note = "正在问 GitHub 要最新版本号…"
        Task {
            do {
                let path = try await CoreDownloader.install(kind: .xray) { progress, written, total in
                    let percent = Int(progress * 100)
                    let mb = Double(written) / 1_048_576
                    let totalMB = Double(total) / 1_048_576
                    Task { @MainActor in
                        self.note = String(format: "下载中 %d%%（%.1f / %.1f MB）", percent, mb, totalMB)
                    }
                }
                await MainActor.run {
                    self.downloading = false
                    self.note = "已装到 \(path)"
                    self.refreshCores(preferring: path)
                    self.toast = "内核已就绪"
                }
            } catch {
                await MainActor.run {
                    self.downloading = false
                    self.note = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.toast = "内核下载失败"
                }
            }
        }
    }

    // MARK: 代理

    private func startProxy() {
        proxyBusy = true
        runtime.start(core: selectedCore, node: store.selectedNode)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { proxyBusy = false }
    }

    private func stopProxy() {
        proxyBusy = true
        runtime.stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proxyBusy = false }
    }

    private func restartProxy() {
        proxyBusy = true
        runtime.restart(core: selectedCore, node: store.selectedNode)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { proxyBusy = false }
    }

    private func selectNode(_ node: V2RayNode) {
        store.select(node)
        if runtime.isRunning {
            toast = "换节点了，正在重启代理"
            restartProxy()
        }
    }

    // MARK: 节点导入

    private func importPaste() {
        let result = ShareLink.parseLines(pasteText)
        finishImport(result, source: "粘贴内容")
    }

    private func importClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            toast = "剪贴板里没有文本"
            return
        }
        pasteText = text
        finishImport(ShareLink.parseLines(text), source: "剪贴板")
    }

    private func finishImport(_ result: (nodes: [V2RayNode], failures: [(String, String)]), source: String) {
        guard !result.nodes.isEmpty else {
            if let first = result.failures.first {
                toast = "没读出节点：\(first.1)"
            } else {
                toast = "没找到可识别的链接"
            }
            return
        }
        let added = store.add(result.nodes)
        pasteText = ""
        var text = "\(source)：识别 \(result.nodes.count) 条，新增 \(added) 条"
        if !result.failures.isEmpty { text += "，\(result.failures.count) 条没认出来" }
        toast = text
    }

    private func copyLink(_ node: V2RayNode) {
        NSPasteboard.copyString(ShareLink.link(for: node))
        toast = "链接已复制"
    }
}

// MARK: - 状态胶囊

struct V2RayPill: View {
    let text: String
    var tint: Color = .secondary
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9.5))
            }
            Text(text).font(.system(size: 10.5, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.15), in: Capsule())
        .foregroundStyle(tint)
    }
}

/// 小统计块
struct V2RayTile: View {
    let title: String
    let value: String
    var tint: Color = .primary
    var mono = true

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 12.5, weight: .medium, design: mono ? .monospaced : .default))
                .foregroundStyle(tint)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(minWidth: 92, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }
}

// MARK: - 内核卡

private struct CoreCard: View {
    @ObservedObject var store: V2RayStore
    let cores: [CoreCandidate]
    let current: CoreCandidate?
    let downloading: Bool
    let note: String
    let onPick: (CoreCandidate) -> Void
    let onRescan: () -> Void
    let onDownload: () -> Void
    let onChooseFile: () -> Void

    var body: some View {
        ToolCard(title: "内核", systemImage: "cpu") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if let current {
                        V2RayPill(
                            text: "\(current.kind.title) \(current.version.isEmpty ? "" : current.version)",
                            tint: .green,
                            systemImage: "checkmark.seal.fill"
                        )
                        Text(current.source)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                        Text(current.path)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.quaternary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    } else {
                        V2RayPill(text: "没找到内核", tint: .orange, systemImage: "exclamationmark.triangle.fill")
                    }

                    Spacer(minLength: 0)

                    if cores.count > 1 {
                        Menu {
                            ForEach(cores) { candidate in
                                Button {
                                    onPick(candidate)
                                } label: {
                                    Text("\(candidate.kind.title) \(candidate.version) · \(candidate.source)")
                                }
                            }
                        } label: {
                            Label("切换", systemImage: "arrow.left.arrow.right")
                                .font(.system(size: 11.5))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    Button {
                        onChooseFile()
                    } label: {
                        Label("手动指定", systemImage: "folder")
                            .font(.system(size: 11.5))
                    }
                    .controlSize(.small)

                    Button {
                        onRescan()
                    } label: {
                        Label("重新检测", systemImage: "arrow.clockwise")
                            .font(.system(size: 11.5))
                    }
                    .controlSize(.small)

                    Button {
                        onDownload()
                    } label: {
                        if downloading {
                            HStack(spacing: 5) {
                                ProgressView().controlSize(.small)
                                Text("下载中").font(.system(size: 11.5))
                            }
                        } else {
                            Label("下载内核", systemImage: "arrow.down.circle")
                                .font(.system(size: 11.5))
                        }
                    }
                    .controlSize(.small)
                    .disabled(downloading)
                }

                if !note.isEmpty {
                    Text(note)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("工具箱自带 Xray 内核，打开就能用，不需要自己装 v2rayN 或者下文件；也可以用「手动指定」换成机器上现成的，或者在线更新一份。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - 代理控制卡

private struct ProxyCard: View {
    @ObservedObject var store: V2RayStore
    @ObservedObject var proxy: V2RayProxy
    let useSystemProxy: Bool
    let core: CoreCandidate?
    let busy: Bool
    @Binding var autoConnect: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void
    let onToggleSystemProxy: (Bool) -> Void

    private var stateTint: Color {
        switch proxy.state {
        case .running: return .green
        case .starting, .stopping: return .orange
        case .failed: return .red
        case .idle: return .secondary
        }
    }

    private var stateIcon: String {
        switch proxy.state {
        case .running: return "checkmark.circle.fill"
        case .starting, .stopping: return "clock"
        case .failed: return "exclamationmark.triangle.fill"
        case .idle: return "circle.dashed"
        }
    }

    var body: some View {
        ToolCard(title: "本地代理", systemImage: "shield.lefthalf.filled") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    controlRow
                    portRow
                    if proxy.isRunning { runningDetail }
                }
            }
        }
    }

    private var controlRow: some View {
        HStack(spacing: 10) {
            V2RayPill(text: proxy.state.title, tint: stateTint, systemImage: stateIcon)

            if proxy.isRunning {
                Button(role: .destructive) {
                    onStop()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                }
                Button {
                    onRestart()
                } label: {
                    Label("重启", systemImage: "arrow.clockwise")
                }
                .disabled(busy)
            } else {
                Button {
                    onStart()
                } label: {
                    Label("启动", systemImage: "play.fill")
                }
                .disabled(busy || core == nil || store.selectedNode == nil)
                .keyboardShortcut(.return, modifiers: .command)
            }

            Spacer(minLength: 0)

            Toggle("打开工具箱就自动连上", isOn: $autoConnect)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .help("进入这个页面时自动启动代理，省得每次手点")

            Toggle("系统代理", isOn: Binding(
                get: { useSystemProxy },
                set: { onToggleSystemProxy($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .help("把 macOS 的 HTTP/HTTPS/SOCKS 代理指到本地端口，关闭时按原来的状态还原")
        }
    }

    private var portRow: some View {
        HStack(spacing: 14) {
            Text("本地端口")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Text("SOCKS").font(.system(size: 11)).foregroundStyle(.tertiary)
                TextField("10808", value: $store.socksPort, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 74)
                    .onSubmit { store.persist() }
            }

            HStack(spacing: 6) {
                Text("HTTP").font(.system(size: 11)).foregroundStyle(.tertiary)
                TextField("10809", value: $store.httpPort, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 74)
                    .onSubmit { store.persist() }
            }

            Toggle("大陆网站直连", isOn: $store.bypassChina)
                .toggleStyle(.checkbox)
                .help("按 geosite:cn 域名列表让国内站点不走代理（不看 IP，免得被 DNS 污染带偏）")
                .onChange(of: store.bypassChina) { _, _ in store.persist() }

            Text("改完端口或分流要重启一次才生效")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)

            Spacer(minLength: 0)
        }
    }

    private var runningDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                V2RayTile(title: "SOCKS5", value: "127.0.0.1:\(store.socksPort)")
                V2RayTile(title: "HTTP", value: "127.0.0.1:\(store.httpPort)")
                V2RayTile(title: "已运行", value: proxy.uptimeText ?? "—", mono: false)
                V2RayTile(title: "当前节点", value: proxy.nodeName.isEmpty ? "—" : proxy.nodeName, mono: false)
            }

            healthRow

            Text("浏览器/终端里把代理设成 127.0.0.1:\(store.socksPort)，或者直接打开上面的系统代理开关。")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
    }

    /// 端口听起来在监听不代表真能出去，所以起完之后过一次真实请求，把结果摆在明面上
    private var healthRow: some View {
        HStack(spacing: 8) {
            switch proxy.health {
            case .unknown:
                V2RayPill(text: "连通性未检测", tint: .secondary, systemImage: "questionmark.circle")
            case .testing:
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small)
                    Text("正在实际请求一次…").font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
            case .ok:
                V2RayPill(text: proxy.health.title, tint: .green, systemImage: "checkmark.seal.fill")
            case .partial:
                V2RayPill(text: proxy.health.title, tint: .orange, systemImage: "exclamationmark.triangle.fill")
            case .failed:
                V2RayPill(text: proxy.health.title, tint: .red, systemImage: "xmark.octagon.fill")
            }

            Button("测一次") { proxy.verifyConnectivity() }
                .controlSize(.small)
                .disabled(proxy.health.isBusy)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - 节点卡

private struct NodesCard: View {
    @ObservedObject var store: V2RayStore
    @Binding var pasteText: String
    let selected: V2RayNode?
    let onImport: () -> Void
    let onImportClipboard: () -> Void
    let onSelect: (V2RayNode) -> Void
    let onDelete: (V2RayNode) -> Void
    let onCopy: (V2RayNode) -> Void
    let onTest: (V2RayNode) -> Void
    let onTestAll: () -> Void

    var body: some View {
        ToolCard(title: "节点", systemImage: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 12) {
                importer
                if store.nodes.isEmpty {
                    Text("还没有节点。把 vmess:// vless:// trojan:// ss:// 分享链接粘到上面，一行一条，批量也行。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                } else {
                    nodeList
                }
            }
        }
    }

    private var importer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $pasteText)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(height: 62)
                .padding(6)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10))
                )
                .overlay(alignment: .topLeading) {
                    if pasteText.isEmpty {
                        Text("vmess://… 一行一条，可以整段订阅内容直接贴")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.quaternary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 9)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 8) {
                Button {
                    onImport()
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                        .font(.system(size: 11.5))
                }
                .controlSize(.small)
                .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    onImportClipboard()
                } label: {
                    Label("从剪贴板导入", systemImage: "doc.on.clipboard")
                        .font(.system(size: 11.5))
                }
                .controlSize(.small)

                Spacer(minLength: 0)

                Text(store.nodes.isEmpty ? "" : "共 \(store.nodes.count) 个节点")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)

                Button {
                    onTestAll()
                } label: {
                    if store.testing {
                        HStack(spacing: 5) {
                            ProgressView().controlSize(.small)
                            Text("测速中").font(.system(size: 11.5))
                        }
                    } else {
                        Label("全部测速", systemImage: "bolt.horizontal")
                            .font(.system(size: 11.5))
                    }
                }
                .controlSize(.small)
                .disabled(store.nodes.isEmpty || store.testing)
            }
        }
    }

    private var nodeList: some View {
        VStack(spacing: 6) {
            ForEach(store.nodes) { node in
                NodeRow(
                    node: node,
                    selected: selected?.id == node.id,
                    latency: store.latencyText(node),
                    latencyValue: store.latency[node.id],
                    onSelect: { onSelect(node) },
                    onDelete: { onDelete(node) },
                    onCopy: { onCopy(node) },
                    onTest: { onTest(node) }
                )
            }
        }
    }
}

private struct NodeRow: View {
    let node: V2RayNode
    let selected: Bool
    let latency: String
    let latencyValue: Int?
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onCopy: () -> Void
    let onTest: () -> Void

    private var latencyTint: Color {
        guard let value = latencyValue else { return .secondary }
        if value < 0 { return .red }
        if value < 120 { return .green }
        if value < 300 { return .orange }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSelect) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("选中这个节点")

            VStack(alignment: .leading, spacing: 2) {
                Text(node.displayName)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                Text(node.summary)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button(action: onTest) {
                Text(latency)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(latencyTint)
                    .frame(width: 62, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .help("点一下测这个节点的握手延迟")

            Menu {
                Button("复制分享链接", action: onCopy)
                Button("测速", action: onTest)
                Divider()
                Button("删除", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - 日志卡

/// 上次会话留下的错误记录。内核死掉、App 被强杀之后，失败原因只存内存的话
/// 下次打开就什么都不剩了——这里从落盘日志里把上次的错误捞出来摆在最上面。
private struct PreviousSessionCard: View {
    let errors: [String]
    var onDismiss: () -> Void

    var body: some View {
        ToolCard(title: "上次会话有错误记录", systemImage: "exclamationmark.triangle") {
            VStack(alignment: .leading, spacing: 8) {
                Text("上次用的时候记录到下面这些错误。如果上次就是「实测无效」，原因大概率在这里面：")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(errors.suffix(8).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Color.red.opacity(0.85))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if errors.count > 8 {
                        Text("… 还有 \(errors.count - 8) 条，完整记录见 runtime/proxy-session.log")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack {
                    Button {
                        NSPasteboard.copyString(ProxySessionLog.fileURL.path)
                    } label: {
                        Label("复制日志路径", systemImage: "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .controlSize(.small)

                    Spacer(minLength: 0)

                    Button("知道了") { onDismiss() }
                        .controlSize(.small)
                }
            }
        }
    }
}

private struct LogCard: View {
    @ObservedObject var proxy: V2RayProxy
    @Binding var expanded: Bool

    var body: some View {
        ToolCard(title: "运行日志", systemImage: "doc.plaintext") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                    } label: {
                        Label(expanded ? "收起" : "展开", systemImage: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11.5))
                    }
                    .controlSize(.small)

                    Text(proxy.logs.isEmpty ? "还没有日志" : "\(proxy.logs.count) 行")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)

                    Spacer(minLength: 0)

                    Button {
                        proxy.clearLogs()
                    } label: {
                        Text("清空").font(.system(size: 11.5))
                    }
                    .controlSize(.small)
                    .disabled(proxy.logs.isEmpty)

                    if let path = proxy.configPath.isEmpty ? nil : proxy.configPath {
                        Button {
                            NSPasteboard.copyString(path)
                        } label: {
                            Label("复制配置路径", systemImage: "doc.on.doc")
                                .font(.system(size: 11.5))
                        }
                        .controlSize(.small)
                    }
                }

                if expanded {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(proxy.logs.suffix(300)) { line in
                                Text(line.text)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(line.isError ? Color.red.opacity(0.9) : Color.secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: 190)
                    .background(
                        Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                }
            }
        }
    }
}
