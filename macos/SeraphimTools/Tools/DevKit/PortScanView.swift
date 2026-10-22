import AppKit
import SwiftUI

/// 端口检测：TCP 连通性探测 + 本机监听端口速查。
struct PortScanView: View {
    @AppStorage("scanHost") private var host = "127.0.0.1"
    @AppStorage("scanPorts") private var portsText = "22, 80, 443, 3000, 3306, 5432, 6379, 8080, 8443, 27017"

    @State private var timeout: Double = 1.0
    @State private var concurrency: Double = 64

    @State private var results: [PortScanResult] = []
    @State private var isScanning = false
    @State private var scanned = 0
    @State private var total = 0
    @State private var scanTask: Task<Void, Never>?

    @State private var listeners: [PortScanner.LocalListener] = []
    @State private var isLoadingListeners = false
    @State private var addresses: [PortScanner.LocalAddress] = []

    @State private var killTarget: PortScanner.LocalListener?
    @State private var showKillDialog = false
    @State private var killingPID: Int?

    @State private var toast: String?

    private var orderedResults: [PortScanResult] {
        results.sorted { lhs, rhs in
            if lhs.state != rhs.state {
                return rank(lhs.state) < rank(rhs.state)
            }
            return lhs.port < rhs.port
        }
    }

    private func rank(_ state: PortState) -> Int {
        switch state {
        case .open: return 0
        case .closed: return 1
        case .filtered: return 2
        case .failed: return 3
        }
    }

    private var openCount: Int { results.filter { $0.state == .open }.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                targetCard
                if !results.isEmpty || isScanning {
                    resultCard
                }
                listenerCard
            }
            .padding(20)
        }
        .toast($toast)
        .confirmationDialog(
            "结束进程",
            isPresented: $showKillDialog,
            titleVisibility: .visible,
            presenting: killTarget
        ) { target in
            Button("结束「\(target.command)」（PID \(target.pid)）", role: .destructive) {
                executeKill(target)
            }
            Button("取消", role: .cancel) {}
        } message: { target in
            Text("监听端口 \(target.port)。先发 SIGTERM 给它 2 秒善后，不退自动 SIGKILL；未保存的数据会丢。")
        }
        .onAppear {
            if addresses.isEmpty {
                addresses = PortScanner.localAddresses()
            }
            // 打开就自动读一次本机监听端口——纯本地 lsof，毫秒级，没有网络行为
            if listeners.isEmpty && !isLoadingListeners {
                refreshListeners()
            }
        }
        .onDisappear {
            scanTask?.cancel()
        }
    }

    // MARK: - 目标

    private var targetCard: some View {
        ToolCard(title: "扫描目标", systemImage: "network") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Text("主机")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("IP 或域名，比如 127.0.0.1 / example.com", text: $host)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5, design: .monospaced))
                        .frame(maxWidth: 300)

                    Menu {
                        ForEach(addresses) { address in
                            Button("\(address.interface) · \(address.address)") {
                                host = address.address
                            }
                        }
                        Button("127.0.0.1（本机）") { host = "127.0.0.1" }
                    } label: {
                        Text("本机地址").font(.system(size: 11.5))
                    }
                    .menuStyle(.borderlessButton)

                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("端口")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("80, 443, 8000-8010", text: $portsText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5, design: .monospaced))
                        .lineLimit(2...4)

                    FlowRow(spacing: 6) {
                        ForEach(PortGroup.all) { group in
                            Button {
                                portsText = group.ports.map(String.init).joined(separator: ", ")
                            } label: {
                                Text(group.title)
                                    .font(.system(size: 11.5))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.06), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .help(group.ports.map(String.init).joined(separator: ", "))
                        }
                    }
                }

                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("超时")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f 秒", timeout))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        Slider(value: $timeout, in: 0.2...5)
                            .controlSize(.small)
                            .frame(width: 180)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("并发")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(concurrency)) 个连接")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        Slider(value: $concurrency, in: 8...256, step: 8)
                            .controlSize(.small)
                            .frame(width: 180)
                    }

                    Spacer(minLength: 0)

                    if isScanning {
                        Button(role: .destructive) {
                            stopScan()
                        } label: {
                            Label("停止", systemImage: "stop.fill")
                        }
                    } else {
                        Button {
                            startScan()
                        } label: {
                            Label("开始扫描", systemImage: "bolt.fill")
                        }
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }

                if isScanning {
                    VStack(alignment: .leading, spacing: 5) {
                        ProgressView(value: Double(scanned), total: Double(max(total, 1)))
                            .controlSize(.small)
                        Text("已探测 \(scanned) / \(total) 个端口，发现 \(openCount) 个开放")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 结果

    private var resultCard: some View {
        ToolCard(title: "扫描结果", systemImage: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(host)
                        .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    if openCount > 0 {
                        NoticeTag(text: "\(openCount) 个开放", systemImage: "checkmark.circle.fill", tint: .green)
                    } else if !isScanning {
                        NoticeTag(text: "没有开放端口", systemImage: "slash.circle", tint: .secondary)
                    }
                    Spacer(minLength: 0)
                    if !results.isEmpty {
                        CopyIconButton(
                            text: orderedResults
                                .filter { $0.state == .open }
                                .map { "\($0.port)\t\($0.service)" }
                                .joined(separator: "\n"),
                            help: "复制开放端口列表"
                        )
                    }
                }

                ForEach(orderedResults) { result in
                    resultRow(result)
                }
            }
        }
    }

    private func resultRow(_ result: PortScanResult) -> some View {
        HStack(spacing: 12) {
            Text(String(result.port))
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .frame(width: 58, alignment: .trailing)

            stateBadge(result.state)

            Text(result.service)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
                .lineLimit(1)

            if let latency = result.latency {
                Text(String(format: "%.0f ms", latency))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            } else if let note = result.note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            if let local = localListener(forPort: result.port) {
                Text("PID \(local.pid) · \(local.command)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if killingPID == local.pid {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Button {
                        killTarget = local
                        showKillDialog = true
                    } label: {
                        Image(systemName: "xmark.octagon")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.red.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    .help("结束「\(local.command)」（PID \(local.pid)）")
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(result.state == .open ? Color.green.opacity(0.07) : Color.primary.opacity(0.028))
        )
    }

    private func stateBadge(_ state: PortState) -> some View {
        let tint: Color
        switch state {
        case .open: tint = .green
        case .closed: tint = .secondary
        case .filtered: tint = .orange
        case .failed: tint = .red
        }
        return Text(state.title)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
            .frame(width: 46)
    }

    // MARK: - 本机监听

    private var listenerCard: some View {
        ToolCard(title: "本机正在监听的端口", systemImage: "dot.radiowaves.left.and.right") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("读一下 lsof，看看这台机器上都有谁在占端口。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)

                    if !listeners.isEmpty {
                        Button {
                            let unique = Array(Set(listeners.map(\.port))).sorted()
                            portsText = unique.map(String.init).joined(separator: ", ")
                            toast = "已填入 \(unique.count) 个端口"
                        } label: {
                            Text("填入端口框").font(.system(size: 11.5))
                        }
                        .controlSize(.small)
                    }

                    Button {
                        refreshListeners()
                    } label: {
                        Label(isLoadingListeners ? "读取中…" : "读取", systemImage: "arrow.clockwise")
                            .font(.system(size: 11.5))
                    }
                    .controlSize(.small)
                    .disabled(isLoadingListeners)
                }

                if !listeners.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 8)], spacing: 8) {
                        ForEach(listeners) { item in
                            HStack(spacing: 8) {
                                Text(String(item.port))
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.command)
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                    Text("\(item.address) · PID \(item.pid)")
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)

                                if killingPID == item.pid {
                                    ProgressView()
                                        .controlSize(.mini)
                                } else {
                                    Button {
                                        killTarget = item
                                        showKillDialog = true
                                    } label: {
                                        Image(systemName: "xmark.octagon")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Color.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("结束「\(item.command)」（PID \(item.pid)）")
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                            )
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button {
                                    killTarget = item
                                    showKillDialog = true
                                } label: {
                                    Label("结束进程…", systemImage: "xmark.octagon")
                                }
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(String(item.port), forType: .string)
                                    toast = "已复制端口 \(item.port)"
                                } label: {
                                    Label("复制端口", systemImage: "doc.on.doc")
                                }
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(String(item.pid), forType: .string)
                                    toast = "已复制 PID \(item.pid)"
                                } label: {
                                    Label("复制 PID", systemImage: "doc.on.doc")
                                }
                            }
                        }
                    }
                } else if !isLoadingListeners {
                    Text("还没读。点右上角「读取」看结果。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - 动作

    private func startScan() {
        let expansion = PortScanner.expand(portsText)
        guard !expansion.ports.isEmpty else {
            toast = expansion.errors.first ?? "没有可扫描的端口"
            NSSound.beep()
            return
        }
        if !expansion.errors.isEmpty {
            toast = expansion.errors.first
        }

        let targetHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetHost.isEmpty else {
            toast = "先填一个主机地址"
            NSSound.beep()
            return
        }

        scanTask?.cancel()
        results = []
        scanned = 0
        total = expansion.ports.count
        isScanning = true

        let timeoutValue = timeout
        let concurrencyValue = Int(concurrency)

        scanTask = Task {
            for await result in PortScanner.scan(
                host: targetHost,
                ports: expansion.ports,
                timeout: timeoutValue,
                concurrency: concurrencyValue
            ) {
                if Task.isCancelled { break }
                results.append(result)
                scanned += 1
            }
            isScanning = false
            if !Task.isCancelled {
                let found = results.filter { $0.state == .open }.count
                toast = found > 0 ? "扫描完成，\(found) 个端口开放" : "扫描完成，没有开放端口"
            }
        }
    }

    private func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        toast = "已停止"
    }

    private func refreshListeners() {
        isLoadingListeners = true
        Task {
            let found = await PortScanner.localListeners()
            listeners = found
            isLoadingListeners = false
            if found.isEmpty {
                toast = "没读到监听中的端口"
            }
        }
    }

    // MARK: - 结束进程

    /// 只有目标是本机时，扫描结果才可能对应得上本机进程
    private var isLocalTarget: Bool {
        let target = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { return false }
        if ["127.0.0.1", "localhost", "::1", "0.0.0.0"].contains(target) { return true }
        return addresses.contains { $0.address.lowercased() == target }
    }

    private func localListener(forPort port: UInt16) -> PortScanner.LocalListener? {
        guard isLocalTarget else { return nil }
        return listeners.first { $0.port == port }
    }

    private func executeKill(_ target: PortScanner.LocalListener) {
        killingPID = target.pid
        Task {
            let outcome = await PortScanner.killProcess(pid: target.pid, command: target.command)
            killingPID = nil
            if outcome.ok {
                toast = outcome.message
                refreshListeners()
            } else {
                toast = outcome.message
                NSSound.beep()
            }
        }
    }
}
