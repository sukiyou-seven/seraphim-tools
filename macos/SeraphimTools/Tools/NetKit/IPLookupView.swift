import AppKit
import SwiftUI

/// IP 查询：本机公网地址（含 IPv4 / IPv6 分别问）与任意 IP 的归属地。
struct IPLookupView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case own
        case geo

        var id: String { rawValue }

        var title: String {
            switch self {
            case .own: return "本机公网 IP"
            case .geo: return "IP 归属地"
            }
        }
    }

    @AppStorage("netIPScope") private var scope: Scope = .own
    @AppStorage("netIPTarget") private var target = "8.8.8.8"

    @State private var reports: [IPReport] = []
    @State private var isLoading = false
    @State private var queryTask: Task<Void, Never>?
    @State private var disabledProviders: Set<String> = []
    @State private var didAutoQuery = false
    @State private var toast: String?

    private var providers: [IPProvider] {
        let pool = scope == .own ? IPProviders.ownIP : IPProviders.geo
        return pool.filter { !disabledProviders.contains($0.id) }
    }

    // MARK: - 主体

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                queryCard
                if !reports.isEmpty {
                    summaryCard
                }
                ForEach(reports) { report in
                    ProviderReportCard(report: report, showOwnership: scope == .own)
                }
                if reports.isEmpty, !isLoading {
                    emptyHint
                }
            }
            .padding(20)
        }
        .toast($toast)
        .onAppear {
            guard !didAutoQuery, scope == .own else { return }
            didAutoQuery = true
            run()
        }
        .onDisappear { queryTask?.cancel() }
        .onChange(of: scope) { _, _ in
            reports = []
            if scope == .own { run() }
        }
    }

    // MARK: - 查询卡片

    private var queryCard: some View {
        ToolCard(title: "查询对象", systemImage: "globe") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Picker("范围", selection: $scope) {
                        ForEach(Scope.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)

                    if scope == .geo {
                        TextField("IP 或域名，比如 8.8.8.8 / github.com", text: $target)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12.5, design: .monospaced))
                            .frame(maxWidth: 320)
                            .onSubmit { run() }
                    }

                    Spacer(minLength: 0)

                    if isLoading {
                        Button(role: .destructive) {
                            stop()
                        } label: {
                            Label("停止", systemImage: "stop.fill")
                        }
                    } else {
                        Button {
                            run()
                        } label: {
                            Label("查询", systemImage: "bolt.fill")
                        }
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    NetSectionLabel(
                        title: "查询接口",
                        systemImage: "antenna.radiowaves.left.and.right",
                        trailing: "并发打过去，谁先回来先显示，单个失败不影响其他"
                    )
                    FlowRow(spacing: 6) {
                        ForEach(scope == .own ? IPProviders.ownIP : IPProviders.geo) { provider in
                            ChipButton(
                                title: provider.name,
                                isSelected: !disabledProviders.contains(provider.id)
                            ) {
                                if disabledProviders.contains(provider.id) {
                                    disabledProviders.remove(provider.id)
                                } else {
                                    disabledProviders.insert(provider.id)
                                }
                            }
                        }
                    }
                }

                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在查询 \(providers.count) 个接口…")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                } else if scope == .geo {
                    Text("归属地信息由第三方接口提供，城市级仅供参考。")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - 汇总

    private var summaryCard: some View {
        ToolCard(title: "汇总", systemImage: "square.stack.3d.up") {
            VStack(alignment: .leading, spacing: 12) {
                FlowRow(spacing: 8) {
                    if let ipv4 = firstAddress(family: "IPv4") {
                        NetStatTile(title: "公网 IPv4", value: ipv4, tint: .primary)
                    }
                    if let ipv6 = firstAddress(family: "IPv6") {
                        NetStatTile(title: "公网 IPv6", value: shortIPv6(ipv6), tint: .primary, hint: ipv6)
                    }
                    if let location = firstField("归属地") {
                        NetStatTile(title: "归属地", value: location, tint: .primary)
                    }
                    if let isp = firstField("ISP") ?? firstField("运营商") ?? firstField("公司") {
                        NetStatTile(title: "运营商 / 公司", value: isp, tint: .primary)
                    }
                    if let asn = firstField("ASN") {
                        NetStatTile(title: "ASN", value: asn, tint: .primary)
                    }
                }

                HStack(spacing: 10) {
                    Text("共 \(reports.count) 个接口返回，\(failureCount) 个失败")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    CopyIconButton(text: summaryText, help: "复制汇总")
                }
            }
        }
    }

    private var failureCount: Int {
        reports.filter { $0.address == "—" }.count
    }

    private var summaryText: String {
        var lines: [String] = []
        if let ipv4 = firstAddress(family: "IPv4") { lines.append("公网 IPv4: \(ipv4)") }
        if let ipv6 = firstAddress(family: "IPv6") { lines.append("公网 IPv6: \(ipv6)") }
        for report in reports where report.address != "—" {
            let fields = report.fields
                .filter { ["归属地", "ISP", "运营商", "ASN", "公司"].contains($0.label) }
                .map { "\($0.label)=\($0.value)" }
                .joined(separator: " ")
            lines.append("\(report.provider): \(report.address) \(fields)")
        }
        return lines.joined(separator: "\n")
    }

    private func firstAddress(family: String) -> String? {
        reports.first { $0.family == family && $0.address != "—" }?.address
    }

    private func firstField(_ label: String) -> String? {
        for report in reports where report.address != "—" {
            if let field = report.fields.first(where: { $0.label == label }), !field.value.isEmpty {
                return field.value
            }
        }
        return nil
    }

    /// 长的 IPv6 在方块里放不下，中间掐掉
    private func shortIPv6(_ text: String) -> String {
        guard text.count > 22 else { return text }
        return "\(text.prefix(11))…\(text.suffix(8))"
    }

    private var emptyHint: some View {
        ToolCard(title: "怎么用", systemImage: "questionmark.circle") {
            VStack(alignment: .leading, spacing: 8) {
                Text("· 「本机公网 IP」：问一圈公共接口，顺便拿到运营商和归属地；IPv4 与 IPv6 分开问，因为有些线路只通其中一种。")
                Text("· 「IP 归属地」：填 IP 或域名都行，三个接口各给一份结果，互相印证。")
                Text("· 接口都是公开免费的，偶尔超时或者改格式很正常，失败的那张卡片会写明原因。")
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 动作

    private func run() {
        let selected = providers
        guard !selected.isEmpty else {
            toast = "至少留一个查询接口"
            NSSound.beep()
            return
        }

        let targetText = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if scope == .geo, targetText.isEmpty {
            toast = "先填一个要查的 IP 或域名"
            NSSound.beep()
            return
        }

        queryTask?.cancel()
        reports = []
        isLoading = true

        let currentScope = scope
        queryTask = Task {
            let stream = currentScope == .own
                ? IPLookupEngine.ownAddress(providers: selected)
                : IPLookupEngine.geo(ip: targetText, providers: selected)

            for await report in stream {
                if Task.isCancelled { break }
                reports.append(report)
            }
            isLoading = false
        }
    }

    private func stop() {
        queryTask?.cancel()
        queryTask = nil
        isLoading = false
        toast = "已停止"
    }
}

// MARK: - 单个接口的结果卡片

private struct ProviderReportCard: View {
    let report: IPReport
    let showOwnership: Bool

    private var failed: Bool { report.address == "—" }

    var body: some View {
        ToolCard(title: report.provider, systemImage: failed ? "exclamationmark.triangle" : "checkmark.circle") {
            VStack(alignment: .leading, spacing: 10) {
                header
                if failed {
                    ErrorBanner(message: report.fields.first?.value ?? "查询失败")
                } else {
                    Text(report.address)
                        .font(.system(size: 19, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                    fieldRows
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if showOwnership {
                NetStatusPill(
                    text: report.family,
                    tint: report.family == "IPv6" ? .purple : .blue,
                    systemImage: "network"
                )
            } else {
                NetStatusPill(text: report.family, tint: .blue, systemImage: "network")
            }
            Text(report.providerNote)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if !failed {
                CopyIconButton(
                    text: "\(report.address)\n" + report.fields.map { "\($0.label): \($0.value)" }.joined(separator: "\n"),
                    help: "复制这张卡片"
                )
            }
            if report.elapsed > 0 {
                Text(String(format: "%.0f ms", report.elapsed))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var fieldRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(report.fields) { field in
                if field.label != "地址族" {
                    NetFieldRow(label: field.label, value: field.value, highlight: field.highlight)
                }
            }
        }
    }
}
