import AppKit
import SwiftUI

/// 连通性探测：Ping（ICMP）与 Telnet（TCP + 收发数据）两个子模式。
struct ProbeView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case ping
        case telnet

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ping: return "Ping（ICMP）"
            case .telnet: return "Telnet（TCP）"
            }
        }

        var systemImage: String {
            switch self {
            case .ping: return "dot.radiowaves.left.and.right"
            case .telnet: return "rectangle.connected.to.line.below"
            }
        }
    }

    @AppStorage("netProbeMode") private var mode: Mode = .ping

    var body: some View {
        VStack(spacing: 0) {
            Picker("子模式", selection: $mode) {
                ForEach(Mode.allCases) { item in
                    Label(item.title, systemImage: item.systemImage).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 360)
            .padding(.vertical, 10)

            Divider()

            switch mode {
            case .ping:
                PingPanel()
            case .telnet:
                TelnetPanel()
            }
        }
    }
}

// MARK: - Ping

private struct PingPanel: View {
    @AppStorage("pingHost") private var host = "223.5.5.5"
    @AppStorage("pingFamily") private var family: IPAddressFamily = .any

    @State private var count: Double = 5
    @State private var continuous = false
    @State private var interval: Double = 0.5
    @State private var packetSize: Double = 56
    @State private var waitTimeout: Double = 1.5

    @State private var samples: [PingSample] = []
    @State private var notices: [String] = []
    @State private var resolvedAddress: String?
    @State private var resolvedHost: String?
    @State private var command = ""
    @State private var failure: String?
    @State private var isRunning = false
    @State private var runTask: Task<Void, Never>?
    @State private var didAutoRun = false
    @State private var toast: String?

    private var summary: PingSummary { PingSummary.from(samples: samples) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                formCard
                if !samples.isEmpty {
                    statsCard
                    LatencyChart(samples: samples)
                }
                if !notices.isEmpty || failure != nil {
                    logCard
                }
            }
            .padding(20)
        }
        .toast($toast)
        .onAppear {
            // 打开就 ping 一次，省得每次都要点一下（5 个包，最小代价）
            guard !didAutoRun, !isRunning else { return }
            didAutoRun = true
            start()
        }
        .onDisappear { runTask?.cancel() }
    }

    // MARK: 表单

    private var formCard: some View {
        ToolCard(title: "目标", systemImage: "target") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Text("主机")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("域名或 IP，比如 example.com", text: $host)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5, design: .monospaced))
                        .frame(maxWidth: 320)
                        .onSubmit { start() }

                    Picker("协议", selection: $family) {
                        ForEach(IPAddressFamily.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 170)

                    Spacer(minLength: 0)

                    if isRunning {
                        Button(role: .destructive) {
                            stop()
                        } label: {
                            Label("停止", systemImage: "stop.fill")
                        }
                    } else {
                        Button {
                            start()
                        } label: {
                            Label("开始 Ping", systemImage: "play.fill")
                        }
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }

                HStack(alignment: .top, spacing: 24) {
                    sliderBlock(
                        title: "次数",
                        value: continuous ? "持续" : "\(Int(count)) 次",
                        binding: $count,
                        range: 1...20,
                        step: 1,
                        enabled: !continuous
                    )

                    sliderBlock(
                        title: "间隔",
                        value: String(format: "%.2f 秒", interval),
                        binding: $interval,
                        range: PingEngine.minimumInterval...3,
                        step: 0.1,
                        enabled: true
                    )

                    sliderBlock(
                        title: "包大小",
                        value: "\(Int(packetSize)) 字节",
                        binding: $packetSize,
                        range: 8...1400,
                        step: 8,
                        enabled: true
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("等待上限")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f 秒", waitTimeout))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Slider(value: $waitTimeout, in: 0.2...10)
                            .controlSize(.small)
                            .frame(width: 140)
                    }

                    Spacer(minLength: 0)

                    Toggle("持续 Ping", isOn: $continuous)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                Text("非 root 运行时系统限制最小发包间隔为 0.2 秒；「持续 Ping」手动停止后才出统计。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)

                if !command.isEmpty {
                    Text(command)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                }
            }
        }
    }

    private func sliderBlock(
        title: String,
        value: String,
        binding: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        enabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
            Slider(value: binding, in: range, step: step)
                .controlSize(.small)
                .frame(width: 140)
                .disabled(!enabled)
        }
    }

    // MARK: 统计

    private var statsCard: some View {
        ToolCard(title: "统计", systemImage: "chart.bar") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    if let resolvedAddress {
                        NetStatusPill(text: resolvedAddress, tint: .blue, systemImage: "arrow.triangle.branch")
                    }
                    NetStatusPill(
                        text: "\(summary.received)/\(summary.transmitted) 收到",
                        tint: summary.lost > 0 ? .orange : .green,
                        systemImage: summary.lost > 0 ? "exclamationmark.circle" : "checkmark.circle"
                    )
                    if summary.lossPercent > 0 {
                        NetStatusPill(text: String(format: "丢包 %.0f%%", summary.lossPercent), tint: .orange)
                    }
                    Spacer(minLength: 0)
                    CopyIconButton(text: statText, help: "复制统计")
                }

                FlowRow(spacing: 8) {
                    NetStatTile(title: "最小", value: format(summary.minRTT), tint: .green)
                    NetStatTile(title: "平均", value: format(summary.avgRTT), tint: .primary)
                    NetStatTile(title: "最大", value: format(summary.maxRTT), tint: .orange)
                    NetStatTile(title: "抖动 (stddev)", value: format(summary.stddev), tint: .secondary)
                    NetStatTile(title: "已发送", value: "\(summary.transmitted) 包", tint: .secondary)
                }
            }
        }
    }

    private var statText: String {
        var lines: [String] = []
        if let resolvedHost, let resolvedAddress { lines.append("目标: \(resolvedHost) → \(resolvedAddress)") }
        lines.append("发送 \(summary.transmitted) / 收到 \(summary.received) / 丢包 \(String(format: "%.1f%%", summary.lossPercent))")
        lines.append("min/avg/max/stddev = \(format(summary.minRTT))/\(format(summary.avgRTT))/\(format(summary.maxRTT))/\(format(summary.stddev))")
        return lines.joined(separator: "\n")
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f ms", value)
    }

    // MARK: 日志

    private var logCard: some View {
        ToolCard(title: "输出", systemImage: "text.alignleft") {
            VStack(alignment: .leading, spacing: 8) {
                if let failure {
                    ErrorBanner(message: failure)
                }
                ForEach(Array(notices.suffix(30).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: 动作

    private func start() {
        let target = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            toast = "先填一个主机"
            NSSound.beep()
            return
        }

        runTask?.cancel()
        samples = []
        notices = []
        failure = nil
        resolvedAddress = nil
        resolvedHost = nil
        isRunning = true

        var options = PingOptions.initial
        options.host = target
        options.count = continuous ? 0 : Int(count)
        options.interval = interval
        options.packetSize = Int(packetSize)
        options.waitTimeout = waitTimeout
        options.family = family

        runTask = Task {
            for await event in PingEngine.run(options) {
                if Task.isCancelled { break }
                switch event {
                case .started(let text):
                    command = text
                case .resolved(let resolvedHostName, let address):
                    resolvedHost = resolvedHostName
                    resolvedAddress = address
                case .sample(let sample):
                    samples.append(sample)
                case .notice(let text):
                    notices.append(text)
                case .summary(let parsed):
                    notices.append(String(format: "统计：发送 %d / 收到 %d / 丢包 %.1f%%", parsed.transmitted, parsed.received, parsed.lossPercent))
                case .failure(let message):
                    failure = message
                    isRunning = false
                case .finished:
                    isRunning = false
                }
            }
            isRunning = false
        }
    }

    private func stop() {
        runTask?.cancel()
        runTask = nil
        isRunning = false
        toast = "已停止"
    }
}

// MARK: - 延迟条形图

private struct LatencyChart: View {
    let samples: [PingSample]

    private var maxTime: Double {
        max(1, samples.filter { !$0.timeout }.map(\.time).max() ?? 1)
    }

    var body: some View {
        ToolCard(title: "延迟", systemImage: "waveform.path") {
            VStack(alignment: .leading, spacing: 10) {
                Canvas { context, size in
                    guard !samples.isEmpty else { return }
                    let slot = size.width / CGFloat(samples.count)
                    let barWidth = max(2, min(18, slot * 0.6))
                    let base = size.height - 1

                    for (index, sample) in samples.enumerated() {
                        let centerX = slot * (CGFloat(index) + 0.5)
                        if sample.timeout {
                            let rect = CGRect(x: centerX - barWidth / 2, y: base - 4, width: barWidth, height: 4)
                            context.fill(Path(rect), with: .color(.orange.opacity(0.85)))
                            continue
                        }
                        let ratio = min(1, sample.time / maxTime)
                        let height = max(2, CGFloat(ratio) * (size.height - 6))
                        let rect = CGRect(x: centerX - barWidth / 2, y: base - height, width: barWidth, height: height)
                        context.fill(Path(rect), with: .color(color(for: sample.time)))
                    }

                    // 顶部基线
                    let axis = CGRect(x: 0, y: 0, width: size.width, height: 1)
                    context.fill(Path(axis), with: .color(.secondary.opacity(0.25)))
                }
                .frame(height: 86)

                HStack(spacing: 12) {
                    legend(color: .green, text: "< 50 ms")
                    legend(color: .yellow, text: "< 150 ms")
                    legend(color: .orange, text: "≥ 150 ms")
                    legend(color: .red, text: "超时")
                    Spacer(minLength: 0)
                    Text("纵轴按最慢的一包归一")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func color(for time: Double) -> Color {
        switch time {
        case ..<50: return .green
        case ..<150: return .yellow
        default: return .orange
        }
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(text).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Telnet

private struct TelnetPanel: View {
    @AppStorage("telnetHost") private var host = "127.0.0.1"
    @AppStorage("telnetPort") private var portText = "80"

    @StateObject private var session = TelnetSession()
    @State private var timeout: Double = 5
    @State private var input = ""
    @State private var appendNewline = true
    @State private var toast: String?

    private var port: UInt16? { UInt16(portText.trimmingCharacters(in: .whitespaces)) }

    var body: some View {
        VStack(spacing: 0) {
            formCard
            Divider()
            terminalCard
        }
        .toast($toast)
    }

    private var formCard: some View {
        ToolCard(title: "连接", systemImage: "cable.connector") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("主机")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("域名或 IP", text: $host)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5, design: .monospaced))
                        .frame(maxWidth: 260)
                        .onSubmit { connect() }

                    Text("端口")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("23", text: $portText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5, design: .monospaced))
                        .frame(width: 72)
                        .onSubmit { connect() }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("超时 \(String(format: "%.0f 秒", timeout))")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Slider(value: $timeout, in: 1...30)
                            .controlSize(.small)
                            .frame(width: 120)
                    }

                    Spacer(minLength: 0)

                    stateChip

                    if session.isConnected || session.isBusy {
                        Button(role: .destructive) {
                            session.disconnect()
                            toast = "已断开"
                        } label: {
                            Label("断开", systemImage: "xmark.circle")
                        }
                    } else {
                        Button {
                            connect()
                        } label: {
                            Label("连接", systemImage: "bolt.horizontal.circle")
                        }
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }

                HStack(spacing: 14) {
                    if let handshake = session.handshake, session.isConnected {
                        Text(String(format: "握手 %.1f ms", handshake))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    if !session.peer.isEmpty {
                        Text("对端 \(session.peer)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Text("↑ \(session.bytesOut) 字节 · ↓ \(session.bytesIn) 字节")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    Button {
                        session.clearScreen()
                    } label: {
                        Text("清屏").font(.system(size: 11))
                    }
                    .controlSize(.small)
                    .disabled(session.lines.isEmpty)
                }

                if !session.isConnected {
                    Text("用来验证端口通不通、看服务 banner。测 Web 端口可以直接发 GET / HTTP/1.0 —— 下面有现成的快捷指令。")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var stateChip: some View {
        Group {
            switch session.state {
            case .idle:
                NetStatusPill(text: "未连接", tint: .secondary, systemImage: "circle.dashed")
            case .connecting:
                NetStatusPill(text: "连接中…", tint: .orange, systemImage: "clock")
            case .connected:
                NetStatusPill(text: "已连接", tint: .green, systemImage: "checkmark.circle.fill")
            case .closed:
                NetStatusPill(text: "已断开", tint: .secondary, systemImage: "xmark.circle")
            case .failed(let message):
                NetStatusPill(text: message, tint: .red, systemImage: "exclamationmark.triangle.fill")
            }
        }
    }

    private var terminalCard: some View {
        VStack(spacing: 0) {
            terminalHeader
            Divider()
            terminalBody
            Divider()
            inputRow
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var terminalHeader: some View {
        HStack(spacing: 8) {
            Text("会话")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("\(session.lines.count) 行")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            quickSend("GET / HTTP/1.0", payload: "GET / HTTP/1.0")
            quickSend("HEAD / HTTP/1.1", payload: "HEAD / HTTP/1.1")
            quickSend("EHLO", payload: "EHLO test.local")
            quickSend("空行", payload: "")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func quickSend(_ title: String, payload: String) -> some View {
        Button {
            session.send(payload)
        } label: {
            Text(title).font(.system(size: 10.5, design: .monospaced))
        }
        .buttonStyle(.borderless)
        .disabled(!session.isConnected)
    }

    private var terminalBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(session.lines) { line in
                        TerminalLineRow(line: line)
                            .id(line.id)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 220)
            .onChange(of: session.lines.count) { _, _ in
                guard let last = session.lines.last else { return }
                withAnimation(.linear(duration: 0.1)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var inputRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(session.isConnected ? Color.green : Color.secondary)

            TextField("输入内容，回车发送", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, design: .monospaced))
                .onSubmit(sendInput)
                .disabled(!session.isConnected)

            Toggle("追加换行", isOn: $appendNewline)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))

            Button {
                sendInput()
            } label: {
                Label("发送", systemImage: "paperplane.fill")
                    .font(.system(size: 11.5))
            }
            .disabled(!session.isConnected || (input.isEmpty && appendNewline))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func connect() {
        guard let port, port > 0 else {
            toast = "端口填得不对"
            NSSound.beep()
            return
        }
        session.connect(host: host, port: port, timeout: timeout)
    }

    private func sendInput() {
        guard session.isConnected else { return }
        session.send(input, appendNewline: appendNewline)
        input = ""
    }
}

private struct TerminalLineRow: View {
    let line: TelnetLine

    private var tint: Color {
        switch line.kind {
        case .incoming: return .primary
        case .outgoing: return .blue
        case .system: return .secondary
        case .error: return .red
        }
    }

    private var prefix: String {
        switch line.kind {
        case .incoming: return ""
        case .outgoing: return "› "
        case .system: return "· "
        case .error: return "! "
        }
    }

    var body: some View {
        Text(prefix + line.text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(tint)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
