import SwiftUI

// MARK: - 平台样式

extension GitHost {
    /// 各家的识别色。GitHub 用主题前景色，两个主题下都清楚。
    var tint: Color {
        switch self {
        case .github: return .primary
        case .gitee: return .red
        case .other: return .secondary
        }
    }

    var accent: Color {
        switch self {
        case .github: return .indigo
        case .gitee: return .red
        case .other: return .gray
        }
    }
}

/// 平台徽章：图标 + 名字
struct GitHostBadge: View {
    var host: GitHost
    var domain: String?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: host.systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(domain ?? host.title)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(host.accent.opacity(0.14), in: Capsule())
        .foregroundStyle(host.accent)
    }
}

/// 状态小胶囊
struct GitPill: View {
    var text: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .semibold))
            }
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.13), in: Capsule())
        .foregroundStyle(tint)
    }
}

// MARK: - 进度条

/// 细长进度条。不确定进度时显示为流动的条纹。
struct GitProgressBar: View {
    var value: Double
    var active: Bool
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                if active && value <= 0 {
                    Capsule()
                        .fill(tint.opacity(0.55))
                        .frame(width: geometry.size.width * 0.32)
                        .offset(x: indeterminateOffset(width: geometry.size.width))
                        .animation(
                            .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                            value: active
                        )
                } else {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(0, geometry.size.width * min(1, max(0, value / 100))))
                        .animation(.easeOut(duration: 0.25), value: value)
                }
            }
        }
        .frame(height: 4)
    }

    private func indeterminateOffset(width: CGFloat) -> CGFloat {
        active ? width * 0.68 : 0
    }
}

// MARK: - 日志面板

/// 命令输出面板。等宽字体，错误行标红，自动跟到底部。
struct GitLogPane: View {
    var lines: [GitLogLine]
    var placeholder: String = "还没有输出"
    var minHeight: CGFloat = 150
    var maxHeight: CGFloat = 260

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if lines.isEmpty {
                        Text(placeholder)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(lines) { line in
                            Text(line.text)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(color(for: line))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                }
                .padding(10)
            }
            .frame(minHeight: minHeight, maxHeight: maxHeight)
            .background(
                Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10))
            )
            .onChange(of: lines.count) { _, _ in
                guard let last = lines.last else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func color(for line: GitLogLine) -> Color {
        if line.isError { return .red }
        if line.isNotice { return .accentColor }
        return .primary
    }
}

// MARK: - 变更文件行

struct GitChangeRow: View {
    var change: GitFileChange

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: change.kind.symbol)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .frame(width: 14)

            if let directory = change.directory {
                Text(directory + "/")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
            }
            Text(change.fileName)
                .font(.system(size: 11.5))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            if let original = change.originalPath {
                Text("← \(original)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(change.staged ? "待提交" : change.kind.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(change.staged ? Color.accentColor : tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(
                    (change.staged ? Color.accentColor : tint).opacity(0.12),
                    in: Capsule()
                )
        }
        .help(change.path)
    }

    private var tint: Color {
        switch change.kind {
        case .added, .untracked: return .green
        case .modified, .typeChanged: return .orange
        case .deleted: return .red
        case .renamed, .copied: return .blue
        case .conflicted: return .purple
        case .unknown: return .secondary
        }
    }
}

// MARK: - 路径展示

/// 只读的路径框，带一个选目录按钮
struct GitPathField: View {
    var title: String
    var path: String
    var placeholder: String = "还没选"
    var systemImage: String = "folder"
    var actionTitle: String = "选择"
    var onPick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))

                Text(path.isEmpty ? placeholder : shorten(path))
                    .font(.system(size: 11.5, design: path.isEmpty ? .default : .monospaced))
                    .foregroundStyle(path.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(path)

                Spacer(minLength: 6)

                Button(actionTitle, action: onPick)
                    .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10))
            )
        }
    }

    private func shorten(_ value: String) -> String {
        let home = NSHomeDirectory()
        return value.hasPrefix(home) ? "~" + value.dropFirst(home.count) : value
    }
}

// MARK: - 主按钮

/// 大一点的行动按钮，带忙碌状态
struct GitActionButton: View {
    var title: String
    var systemImage: String
    var tint: Color = .accentColor
    var busy: Bool = false
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                enabled ? tint : Color.primary.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .foregroundStyle(enabled ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
    }
}

// MARK: - 折叠卡片

/// 可折叠的卡片容器（账号设置用，默认收起不占地方）
struct GitCollapsibleCard<Content: View>: View {
    var title: String
    var systemImage: String
    var subtitle: String
    @Binding var expanded: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Divider().padding(.horizontal, 14)
                content
                    .padding(14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }
}
