import AppKit
import SwiftUI

/// DNS 查询：记录表 + 指定服务器 + 反向解析 + 本机 DNS 配置速查。
struct DNSLookupView: View {
    @AppStorage("dnsName") private var name = "example.com"
    @AppStorage("dnsType") private var type: DNSRecordType = .a

    @State private var server = ""
    @State private var useTCP = false
    @State private var checkDNSSEC = false
    @State private var trace = false
    @State private var timeout: Double = 5

    @State private var result: DNSResult?
    @State private var isRunning = false
    @State private var runTask: Task<Void, Never>?
    @State private var config: LocalDNSConfig?
    @State private var showRaw = false
    @State private var didAutoRun = false
    @State private var toast: String?

    private let serverPresets: [(String, String)] = [
        ("系统默认", ""),
        ("阿里 DNS", "223.5.5.5"),
        ("腾讯 DNS", "119.29.29.29"),
        ("Google", "8.8.8.8"),
        ("Cloudflare", "1.1.1.1"),
        ("Quad9", "9.9.9.9"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                queryCard
                if let result {
                    DNSResultCard(result: result, showRaw: $showRaw)
                }
                configCard
            }
            .padding(20)
        }
        .toast($toast)
        .onAppear {
            if config == nil { loadConfig() }
            // 打开就查一次记着的域名，省得每次都要点一下
            guard !didAutoRun, !isRunning else { return }
            didAutoRun = true
            run()
        }
        .onDisappear { runTask?.cancel() }
    }

    // MARK: 查询

    private var queryCard: some View {
        ToolCard(title: "查询", systemImage: "magnifyingglass") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    TextField("域名或 IP（查 PTR 时填 IP）", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5, design: .monospaced))
                        .frame(maxWidth: 320)
                        .onSubmit { run() }

                    TextField("@DNS 服务器，留空用系统默认", text: $server)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5, design: .monospaced))
                        .frame(maxWidth: 220)

                    Menu {
                        ForEach(serverPresets, id: \.1) { item in
                            Button("\(item.0)\(item.1.isEmpty ? "" : " · \(item.1)")") {
                                server = item.1
                            }
                        }
                    } label: {
                        Text("预置").font(.system(size: 11.5))
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 60)

                    Spacer(minLength: 0)

                    if isRunning {
                        Button(role: .destructive) { stop() } label: {
                            Label("停止", systemImage: "stop.fill")
                        }
                    } else {
                        Button { run() } label: {
                            Label("查询", systemImage: "bolt.fill")
                        }
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    NetSectionLabel(title: "记录类型", systemImage: "list.bullet.indent", trailing: "当前：\(type.explanation)")
                    FlowRow(spacing: 6) {
                        ForEach(DNSRecordType.allCases) { item in
                            ChipButton(title: item.rawValue, isSelected: type == item) {
                                type = item
                                if result != nil { run() }
                            }
                        }
                    }
                }

                HStack(spacing: 20) {
                    Toggle("TCP 查询 (+tcp)", isOn: $useTCP).toggleStyle(.checkbox)
                    Toggle("要 DNSSEC 记录 (+dnssec)", isOn: $checkDNSSEC).toggleStyle(.checkbox)
                    Toggle("递归追踪 (+trace)", isOn: $trace).toggleStyle(.checkbox)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("超时 \(Int(timeout)) 秒")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Slider(value: $timeout, in: 1...20, step: 1)
                            .controlSize(.small)
                            .frame(width: 140)
                    }

                    Spacer(minLength: 0)
                }

                Text("「递归追踪」会从根服务器一路问到权威服务器，慢（好几秒）但能看清解析路径。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: 本机配置

    private var configCard: some View {
        ToolCard(title: "本机 DNS 配置", systemImage: "gearshape.2") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("来自 scutil --dns 与 /etc/hosts")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    Button {
                        loadConfig()
                    } label: {
                        Label("重新读取", systemImage: "arrow.clockwise")
                            .font(.system(size: 11.5))
                    }
                    .controlSize(.small)
                }

                if let config {
                    if config.resolvers.isEmpty {
                        Text("没读到 resolver 配置")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(config.resolvers) { resolver in
                            resolverRow(resolver)
                        }
                    }

                    if !config.searchDomains.isEmpty {
                        NetFieldRow(label: "搜索域", value: config.searchDomains.joined(separator: ", "))
                    }

                    if !config.hosts.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            NetSectionLabel(title: "/etc/hosts", systemImage: "doc.text", trailing: "\(config.hosts.count) 条，会盖过 DNS")
                            ForEach(config.hosts.prefix(12)) { entry in
                                HStack(spacing: 8) {
                                    Text(entry.ip)
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundStyle(entry.isLocal ? Color.secondary : Color.accentColor)
                                        .frame(width: 130, alignment: .leading)
                                    Text(entry.names.joined(separator: "  "))
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                    Spacer(minLength: 0)
                                }
                            }
                            if config.hosts.count > 12 {
                                Text("……还有 \(config.hosts.count - 12) 条")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                } else {
                    Text("正在读取…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func resolverRow(_ resolver: DNSResolverInfo) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("#\(resolver.id)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 26, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(resolver.servers.isEmpty ? "（无 nameserver）" : resolver.servers.joined(separator: "  "))
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    if let interface = resolver.interface {
                        Text("网卡 \(interface)").font(.system(size: 10))
                    }
                    if !resolver.domains.isEmpty {
                        Text("域 \(resolver.domains.joined(separator: ","))").font(.system(size: 10))
                    }
                    if let flags = resolver.flags {
                        Text(flags).font(.system(size: 10))
                    }
                }
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    // MARK: 动作

    private func run() {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            toast = "先填一个域名或 IP"
            NSSound.beep()
            return
        }

        runTask?.cancel()
        isRunning = true

        let query = DNSEngine.Query(
            name: target,
            type: type,
            server: server,
            trace: trace,
            useTCP: useTCP,
            checkDNSSEC: checkDNSSEC,
            timeout: timeout
        )

        runTask = Task {
            let outcome = await DNSEngine.lookup(query)
            if Task.isCancelled { return }
            result = outcome
            isRunning = false
            if let failure = outcome.failure, outcome.answers.isEmpty {
                toast = failure
            } else {
                toast = "查到 \(outcome.answers.count) 条记录"
            }
        }
    }

    private func stop() {
        runTask?.cancel()
        runTask = nil
        isRunning = false
        toast = "已停止"
    }

    private func loadConfig() {
        Task {
            let loaded = await Task.detached { DNSEngine.localConfig() }.value
            config = loaded
        }
    }
}

// MARK: - 结果卡片

private struct DNSResultCard: View {
    let result: DNSResult
    @Binding var showRaw: Bool

    var body: some View {
        ToolCard(title: "结果", systemImage: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 14) {
                statusRow
                if let failure = result.failure {
                    ErrorBanner(message: failure)
                } else if let hint = result.statusHint, result.answers.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle").foregroundStyle(.orange)
                        Text(hint)
                            .font(.system(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.orange.opacity(0.10))
                    )
                }
                if !result.answers.isEmpty {
                    answerSection
                }
                if !result.authority.isEmpty {
                    extraSection(title: "权威段（AUTHORITY）", systemImage: "building.columns", records: result.authority)
                }
                if !result.additional.isEmpty {
                    extraSection(title: "附加段（ADDITIONAL）", systemImage: "plus.rectangle.on.rectangle", records: result.additional)
                }
                rawSection
            }
        }
    }

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                NetStatusPill(
                    text: result.status,
                    tint: statusTint,
                    systemImage: statusTint == .green ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                )
                NetStatusPill(text: "\(result.answers.count) 条记录", tint: .secondary)
                if !result.flags.isEmpty {
                    NetStatusPill(text: result.flags, tint: .secondary)
                }
                if let responseTime = result.queryTime {
                    NetStatusPill(text: "\(responseTime) ms", tint: .secondary, systemImage: "stopwatch")
                } else {
                    NetStatusPill(text: String(format: "%.0f ms", result.elapsed), tint: .secondary, systemImage: "stopwatch")
                }
                Spacer(minLength: 0)
                CopyIconButton(text: summaryText, help: "复制结果")
            }
            NetFieldRow(label: "查询", value: "\(result.query)  \(result.type.rawValue)\(result.isTrace ? "  +trace" : "")")
            NetFieldRow(label: "服务器", value: result.server)
        }
    }

    private var statusTint: Color {
        switch result.status.uppercased() {
        case "NOERROR": return .green
        case "NXDOMAIN": return .orange
        default: return .red
        }
    }

    private var summaryText: String {
        result.answers
            .map { "\($0.name)\t\($0.ttlText)\t\($0.recordClass)\t\($0.type)\t\($0.value)" }
            .joined(separator: "\n")
    }

    private var answerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            NetSectionLabel(title: "应答段（ANSWER）", systemImage: "text.bubble")
            ForEach(result.answers) { record in
                DNSRecordRow(record: record)
            }
        }
    }

    private func extraSection(title: String, systemImage: String, records: [DNSRecord]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NetSectionLabel(title: title, systemImage: systemImage)
            ForEach(records) { record in
                DNSRecordRow(record: record)
            }
        }
    }

    private var rawSection: some View {
        DisclosureGroup(isExpanded: $showRaw) {
            Text(result.raw.isEmpty ? "（无输出）" : result.raw)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        } label: {
            Text("dig 原始输出")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct DNSRecordRow: View {
    let record: DNSRecord

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(record.type)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(tint.opacity(0.15), in: Capsule())
                .foregroundStyle(tint)
                .frame(width: 62)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.value)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Text(record.name)
                        .font(.system(size: 10))
                    Text("TTL \(record.ttlText)\(record.ttlHint.map { "（\($0)）" } ?? "")")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            CopyIconButton(text: record.value, help: "复制这条记录")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
    }

    private var tint: Color {
        switch record.type {
        case "A": return .blue
        case "AAAA": return .purple
        case "CNAME": return .teal
        case "MX": return .orange
        case "TXT": return .green
        case "NS": return .indigo
        default: return .secondary
        }
    }
}
