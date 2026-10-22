import SwiftUI

// MARK: - 筛选

enum BalanceFilter: String, CaseIterable, Identifiable {
    case all
    case configured
    case balance
    case probe
    case problem

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .configured: return "已填 Key"
        case .balance: return "可查余额"
        case .probe: return "仅探活"
        case .problem: return "有问题"
        }
    }
}

// MARK: - 弹窗

private enum BalanceSheet: Identifiable {
    case key(BalanceProvider)
    case custom(CustomProvider, isNew: Bool)

    var id: String {
        switch self {
        case .key(let provider): return "key:" + provider.id
        case .custom(let provider, _): return "custom:" + provider.id
        }
    }
}

// MARK: - 主界面

/// 大模型 API 余额。
///
/// 一句话概括这个工具的立场：**能查的查，不能查的说清楚**。各家的开放程度差得远，
/// 硬凑一个统一的「余额」数字只会骗人，所以每家一张卡，各说各能做到什么。
struct BalanceToolView: View {
    @ObservedObject private var center = BalanceCenter.shared

    @AppStorage("balanceKeyword") private var keyword = ""
    @AppStorage("balanceFilter") private var filter: BalanceFilter = .all
    @AppStorage("balanceThreshold") private var threshold = 10.0
    @AppStorage("balanceExpandedID") private var expandedID = ""
    @AppStorage("balanceShowCustom") private var showCustom = true
    @AppStorage("balanceAutoRefresh") private var autoRefresh = true

    @State private var sheet: BalanceSheet?
    @State private var toast: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BalanceSummaryBar(
                    configured: center.configured.count,
                    total: center.allProviders.count,
                    attention: center.attentionCount(providers: center.allProviders),
                    totals: center.totals(providers: center.allProviders),
                    running: center.running.count,
                    threshold: $threshold,
                    onDetectAll: detectAll,
                    onCopy: copySummary
                )

                BalanceToolbar(
                    keyword: $keyword,
                    filter: $filter,
                    visible: visibleProviders.count,
                    onExpandAll: nil
                )

                if visibleProviders.isEmpty {
                    BalanceEmptyState(filter: filter, keyword: keyword)
                } else {
                    providerGrid
                }

                if showCustom {
                    BalanceCustomSection(
                        customs: center.customs,
                        onAdd: { openCustom(nil) },
                        onEdit: { openCustom($0) }
                    )
                }

                BalanceHelpCard(showCustom: $showCustom, autoRefresh: $autoRefresh)
            }
            .padding(20)
        }
        .sheet(item: $sheet) { target in
            switch target {
            case .key(let provider):
                BalanceKeySheet(
                    provider: provider,
                    existingMask: center.maskedKey(for: provider.id),
                    onSave: { key in
                        Task {
                            let ok = await center.saveKey(key, for: provider.id)
                            guard ok else {
                                toast = "保存到钥匙串失败"
                                return
                            }
                            toast = "已保存，开始检测…"
                            await center.detect(provider)
                        }
                    },
                    onDelete: {
                        Task { await center.deleteKey(for: provider.id) }
                        toast = "已删除 \(provider.name) 的 Key"
                    }
                )
            case .custom(let seed, let isNew):
                BalanceCustomSheet(seed: seed, isNew: isNew) { item in
                    if isNew {
                        _ = center.addCustom(item)
                        toast = "已添加 \(item.name)"
                    } else {
                        center.updateCustom(item)
                        toast = "已更新"
                    }
                }
            }
        }
        .toast($toast)
        .task {
            await center.bootstrap()
            // 打开就刷新一遍。只跑填了 key 的、且这次会话还没查过的——切工具来回
            // 不会反复打接口。想关掉的话，说明卡里有开关。
            if autoRefresh, !center.configured.isEmpty, center.reports.isEmpty {
                await center.detectAll(center.allProviders)
            }
        }
    }

    // MARK: 列表

    private var providerGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 336), spacing: 12)],
            spacing: 12
        ) {
            ForEach(visibleProviders) { provider in
                BalanceProviderCard(
                    provider: provider,
                    report: center.reports[provider.id],
                    isRunning: center.running.contains(provider.id),
                    isConfigured: center.configured.contains(provider.id),
                    maskedKey: center.maskedKey(for: provider.id),
                    threshold: threshold,
                    isExpanded: expandedID == provider.id,
                    onDetect: { Task { await center.detect(provider) } },
                    onEditKey: { sheet = .key(provider) },
                    onDeleteKey: { deleteKey(provider) },
                    onToggleExpand: {
                        expandedID = expandedID == provider.id ? "" : provider.id
                    },
                    onEditCustom: customItem(for: provider).map { item in
                        { sheet = .custom(item, isNew: false) }
                    },
                    onDeleteCustom: customItem(for: provider).map { item in
                        { deleteCustom(item) }
                    }
                )
            }
        }
    }

    /// 自定义厂商在网格里的卡片，要能找回它对应的那条配置才能编辑
    private func customItem(for provider: BalanceProvider) -> CustomProvider? {
        guard provider.isCustom else { return nil }
        return center.customs.first { "custom:" + $0.id == provider.id }
    }

    private var visibleProviders: [BalanceProvider] {
        var list = center.allProviders

        switch filter {
        case .all:
            break
        case .configured:
            list = list.filter { center.configured.contains($0.id) }
        case .balance:
            list = list.filter { $0.capability == .balance }
        case .probe:
            list = list.filter { $0.capability == .probe }
        case .problem:
            list = list.filter { center.reports[$0.id]?.status.needsAttention == true }
        }

        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let tokens = trimmed
                .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "，" || $0 == "\u{3000}" })
                .map(String.init)
            list = list.filter { provider in
                let haystack = [
                    provider.name,
                    provider.subtitle,
                    provider.id,
                    provider.note,
                    provider.domain,
                ].joined(separator: " ").lowercased()
                return tokens.allSatisfy { haystack.contains($0.lowercased()) }
            }
        }
        return list
    }

    // MARK: 动作

    private func detectAll() {
        let providers = center.allProviders
        Task {
            if center.configured.isEmpty {
                toast = "还没填过 Key，先给一家填上"
                return
            }
            toast = "开始检测 \(center.configured.count) 家…"
            await center.detectAll(providers)
        }
    }

    private func deleteKey(_ provider: BalanceProvider) {
        Task {
            await center.deleteKey(for: provider.id)
            toast = "已删除 \(provider.name) 的 Key"
        }
    }

    private func openCustom(_ existing: CustomProvider?) {
        if let existing {
            sheet = .custom(existing, isNew: false)
        } else {
            sheet = .custom(
                CustomProvider(
                    name: "",
                    baseURL: "https://",
                    balanceURL: "",
                    note: ""
                ),
                isNew: true
            )
        }
    }

    private func deleteCustom(_ provider: CustomProvider) {
        Task {
            await center.removeCustom(id: provider.id)
            toast = "已删除 \(provider.name)"
        }
    }

    private func copySummary() {
        NSPasteboard.copyString(summaryText())
        toast = "已复制汇总"
    }

    /// 汇总成一段纯文本，方便贴到别处
    private func summaryText() -> String {
        var lines: [String] = ["大模型 API 余额 · 检测汇总", ""]

        let configured = center.configuredProviders
        if configured.isEmpty {
            lines.append("（还没有配置任何 Key）")
        }

        for provider in configured {
            guard let report = center.reports[provider.id] else {
                lines.append("· \(provider.name)：\(provider.capability == .balance ? "可查余额" : "仅探活")，尚未检测")
                continue
            }
            if report.status == .ok {
                if let primary = report.primaryAmount {
                    var line = "· \(provider.name)：\(BalanceEngine.money(primary.value, currency: primary.currency))"
                    let others = report.secondaryAmounts
                        .map { "\($0.label) \(BalanceEngine.money($0.value, currency: $0.currency))" }
                    if !others.isEmpty {
                        line += "（" + others.joined(separator: "，") + "）"
                    }
                    lines.append(line)
                } else {
                    lines.append("· \(provider.name)：\(report.headline)")
                }
            } else {
                lines.append("· \(provider.name)：\(report.headline)\(report.httpStatus > 0 ? " (HTTP \(report.httpStatus))" : "")")
            }
        }

        let totals = center.totals(providers: center.allProviders)
        if !totals.isEmpty {
            lines.append("")
            let text = totals.map { BalanceEngine.money($0.value, currency: $0.currency) }
            lines.append("已知余额合计：" + text.joined(separator: " + "))
        }

        lines.append("")
        lines.append("（Token 用量与账单以各平台控制台为准）")
        return lines.joined(separator: "\n")
    }
}

// MARK: - 汇总条

struct BalanceSummaryBar: View {
    let configured: Int
    let total: Int
    let attention: Int
    let totals: [(currency: String, value: Double)]
    let running: Int
    @Binding var threshold: Double
    var onDetectAll: () -> Void
    var onCopy: () -> Void

    var body: some View {
        ToolCard(title: "概览", systemImage: "chart.bar.doc.horizontal") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 18) {
                    metric("已填 Key", "\(configured) / \(total)", tint: configured > 0 ? .accentColor : .secondary)
                    metric("有问题", "\(attention)", tint: attention > 0 ? .orange : .secondary)
                    totalMetric
                    Spacer(minLength: 0)
                    actions
                }

                HStack(spacing: 8) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text("低于")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("", value: $threshold, format: .number.precision(.fractionLength(0...2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 68)
                        .font(.system(size: 11, design: .monospaced))
                    Text("就标黄（不区分币种）")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private var totalMetric: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("已知余额合计")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            if totals.isEmpty {
                Text("—")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    ForEach(totals, id: \.currency) { item in
                        Text(BalanceEngine.money(item.value, currency: item.currency))
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                    }
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if running > 0 {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small).scaleEffect(0.65)
                    Text("检测中 \(running)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Button(action: onCopy) {
                Label("复制汇总", systemImage: "doc.on.doc")
                    .font(.system(size: 11.5))
            }
            Button(action: onDetectAll) {
                Label("全部检测", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11.5))
            }
            .disabled(running > 0)
        }
    }
}

// MARK: - 工具条

struct BalanceToolbar: View {
    @Binding var keyword: String
    @Binding var filter: BalanceFilter
    let visible: Int
    var onExpandAll: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("搜厂商名、域名、说明", text: $keyword)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !keyword.isEmpty {
                    Button {
                        keyword = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                }
                Spacer(minLength: 6)
                Text("\(visible) 家")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            FlowRow(spacing: 6) {
                ForEach(BalanceFilter.allCases) { item in
                    ChipButton(title: item.title, isSelected: filter == item) {
                        filter = item
                    }
                }
            }
        }
    }
}

// MARK: - 空态

struct BalanceEmptyState: View {
    let filter: BalanceFilter
    let keyword: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var title: String {
        if !keyword.isEmpty { return "没有匹配「\(keyword)」的厂商" }
        switch filter {
        case .configured: return "还没有填过任何 Key"
        case .problem: return "所有检测过的都没问题"
        default: return "没有厂商"
        }
    }

    private var hint: String {
        if !keyword.isEmpty { return "换个关键词，或者把筛选切回「全部」" }
        switch filter {
        case .configured: return "在任意一张卡上点「填 API Key」，Key 会存进系统钥匙串"
        case .problem: return "有问题的厂商会出现在这里，方便集中处理"
        default: return "换个筛选条件看看"
        }
    }
}
