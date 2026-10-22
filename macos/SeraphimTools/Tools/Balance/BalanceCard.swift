import SwiftUI

// MARK: - 配色

enum BalancePalette {
    static let colors: [Color] = [
        .blue, .purple, .teal, .orange, .pink, .indigo,
        .green, .brown, .cyan, .red, .mint, .yellow,
    ]

    /// 厂商徽标底色：用 id 算个稳定 hash，同一个厂商每次都是同一个颜色
    static func color(for id: String) -> Color {
        var hash = 5381
        for scalar in id.unicodeScalars {
            hash = (hash &* 33) &+ Int(scalar.value)
        }
        return colors[abs(hash) % colors.count]
    }

    static func tint(_ status: BalanceStatus) -> Color {
        switch status {
        case .ok: return .green
        case .unconfigured: return .secondary
        case .unauthorized, .malformed: return .red
        case .exhausted: return .red
        case .notFound: return .secondary
        case .rateLimited, .serverError, .networkError, .parseFailed: return .orange
        }
    }
}

// MARK: - 厂商徽标

struct BalanceBadge: View {
    let provider: BalanceProvider
    var size: CGFloat = 34

    private var initial: String {
        guard let first = provider.name.first else { return "?" }
        return String(first).uppercased()
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(BalancePalette.color(for: provider.id).opacity(0.18))
            .overlay(
                Text(initial)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(BalancePalette.color(for: provider.id))
            )
            .frame(width: size, height: size)
    }
}

// MARK: - 厂商卡

struct BalanceProviderCard: View {
    let provider: BalanceProvider
    let report: BalanceReport?
    let isRunning: Bool
    let isConfigured: Bool
    let maskedKey: String?
    let threshold: Double
    let isExpanded: Bool

    var onDetect: () -> Void
    var onEditKey: () -> Void
    var onDeleteKey: () -> Void
    var onToggleExpand: () -> Void
    var onEditCustom: (() -> Void)?
    var onDeleteCustom: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            tags
            keyRow
            if let report {
                BalanceResultBlock(
                    provider: provider,
                    report: report,
                    threshold: threshold,
                    isExpanded: isExpanded,
                    onToggleExpand: onToggleExpand
                )
            }
            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    private var borderColor: Color {
        guard let report else { return Color.primary.opacity(0.08) }
        switch report.status {
        case .ok where isLow: return Color.orange.opacity(0.45)
        case .ok: return Color.green.opacity(0.32)
        case .unconfigured: return Color.primary.opacity(0.08)
        default: return BalancePalette.tint(report.status).opacity(0.35)
        }
    }

    private var isLow: Bool {
        guard let primary = report?.primaryAmount, !primary.kind.isSpending else { return false }
        return threshold > 0 && primary.value < threshold
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            BalanceBadge(provider: provider)
            VStack(alignment: .leading, spacing: 1) {
                Text(provider.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Text(provider.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            statusIndicator
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if isRunning {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .frame(width: 18, height: 18)
        } else if let report, report.status != .unconfigured {
            Image(systemName: report.status.systemImage)
                .font(.system(size: 13))
                .foregroundStyle(BalancePalette.tint(report.status))
        }
    }

    private var tags: some View {
        FlowRow(spacing: 5) {
            NoticeTag(
                text: provider.capability.title,
                systemImage: provider.capability.systemImage,
                tint: provider.capability == .balance ? .teal : .secondary
            )
            if provider.capability == .balance, provider.confidence == .unverified {
                NoticeTag(text: "接口未证实", systemImage: "questionmark.circle", tint: .orange)
            }
            if provider.isCustom {
                NoticeTag(text: "自定义", systemImage: "person.crop.square", tint: .purple)
            }
        }
    }

    @ViewBuilder
    private var keyRow: some View {
        if isConfigured, let maskedKey {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
                Text(maskedKey)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button("换", action: onEditKey)
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)
                Button("删", action: onDeleteKey)
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
        } else {
            Button(action: onEditKey) {
                Label("填 API Key", systemImage: "key.horizontal")
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.13), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(action: onDetect) {
                Label(provider.capability == .balance ? "查余额" : "探活", systemImage: "arrow.clockwise")
                    .font(.system(size: 11.5))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isConfigured ? Color.accentColor : Color.secondary)
            .disabled(!isConfigured || isRunning)

            if let report, !isRunning {
                Text(metaText(report))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if provider.isCustom {
                Menu {
                    Button("编辑", action: { onEditCustom?() })
                    Button("删除", role: .destructive, action: { onDeleteCustom?() })
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 16)
            } else {
                Link(destination: URL(string: provider.consoleURL) ?? URL(string: "https://example.com")!) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                }
                .help("打开控制台看余额")
            }
        }
    }

    private func metaText(_ report: BalanceReport) -> String {
        let seconds = Int(Date().timeIntervalSince(report.queriedAt))
        let ago: String
        if seconds < 60 { ago = "刚刚" }
        else if seconds < 3600 { ago = "\(seconds / 60) 分钟前" }
        else { ago = "\(seconds / 3600) 小时前" }
        return "\(ago) · \(report.latencyMS)ms"
    }
}

// MARK: - 结果块

struct BalanceResultBlock: View {
    let provider: BalanceProvider
    let report: BalanceReport
    let threshold: Double
    let isExpanded: Bool
    var onToggleExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch report.status {
            case .ok:
                okBody
            case .unconfigured:
                EmptyView()
            default:
                problemBody
            }

            if !report.fields.isEmpty || !report.rawBody.isEmpty {
                disclosure
                if isExpanded {
                    BalanceRawBlock(report: report)
                }
            }
        }
    }

    // MARK: 成功

    @ViewBuilder
    private var okBody: some View {
        if let primary = report.primaryAmount {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(BalanceEngine.money(primary.value, currency: primary.currency))
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(amountColor(primary))
                if isLow(primary) {
                    NoticeTag(text: isZero(primary) ? "已用完" : "低于阈值", systemImage: "exclamationmark.triangle.fill", tint: .orange)
                }
                Spacer(minLength: 0)
                CopyIconButton(text: BalanceEngine.money(primary.value, currency: primary.currency), help: "复制金额")
            }
        } else {
            Label(report.headline, systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.green)
        }

        if !report.secondaryAmounts.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(report.secondaryAmounts) { amount in
                    HStack(spacing: 6) {
                        Text(amount.label)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Text(BalanceEngine.money(amount.value, currency: amount.currency))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(amount.kind.isSpending ? .secondary : .primary)
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
        }

        if !report.detail.isEmpty {
            Text(report.detail)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 失败

    private var problemBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: report.status.systemImage)
                    .font(.system(size: 11))
                Text(report.headline)
                    .font(.system(size: 11.5, weight: .medium))
                if report.httpStatus > 0 {
                    Text("HTTP \(report.httpStatus)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(BalancePalette.tint(report.status))

            if !report.detail.isEmpty {
                Text(report.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(BalancePalette.tint(report.status).opacity(0.09))
        )
    }

    // MARK: 原始返回

    private var disclosure: some View {
        Button(action: onToggleExpand) {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                Text("原始返回")
                    .font(.system(size: 10.5))
                Text("\(report.fields.count) 个字段")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: 工具

    private func isZero(_ amount: BalanceAmount) -> Bool { amount.value <= 0.000_000_1 }

    private func isLow(_ amount: BalanceAmount) -> Bool {
        threshold > 0 && amount.value < threshold && !amount.kind.isSpending
    }

    private func amountColor(_ amount: BalanceAmount) -> Color {
        if isZero(amount) { return .red }
        if isLow(amount) { return .orange }
        return .primary
    }
}

// MARK: - 原始返回块

struct BalanceRawBlock: View {
    let report: BalanceReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !report.fields.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(report.fields) { field in
                        HStack(spacing: 6) {
                            Text(field.path)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(field.isMoney ? Color.accentColor : .secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text(field.value)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
            }

            if !report.rawBody.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("响应原文")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        CopyIconButton(text: report.rawBody, help: "复制原文")
                    }
                    Text(JSONBeautifier.pretty(report.rawBody) ?? report.rawBody)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
            }
        }
    }
}
