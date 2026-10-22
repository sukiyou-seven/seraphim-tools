import AppKit
import SwiftUI

/// 一键克隆：贴地址 → 选位置 → 开始
struct GitCloneView: View {
    @ObservedObject var store: GitStore

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                addressCard
                if store.cloning || !store.cloneLog.isEmpty {
                    progressCard
                }
                if let error = store.cloneError {
                    ErrorBanner(message: error)
                }
                GitAccountCard(store: store)
            }
            .padding(20)
        }
        .onAppear(perform: fillFromClipboardIfPossible)
    }

    // MARK: 地址卡片

    private var addressCard: some View {
        ToolCard(title: "仓库地址", systemImage: "link") {
            VStack(alignment: .leading, spacing: 12) {
                addressField
                destinationSection
                optionsRow
                actionRow
            }
        }
    }

    private var addressField: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                TextField("粘贴仓库地址，比如 https://github.com/用户名/仓库", text: $store.urlText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                    .onSubmit { if store.parsedURL != nil && !store.cloning { store.startClone() } }

                PasteIconButton { paste() }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(strokeColor)
            )

            recognisedLine
        }
    }

    private var strokeColor: Color {
        if store.urlError != nil { return .red.opacity(0.55) }
        if store.parsedURL != nil { return .green.opacity(0.45) }
        return Color.primary.opacity(0.10)
    }

    @ViewBuilder
    private var recognisedLine: some View {
        if let error = store.urlError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
        } else if let repo = store.parsedURL {
            HStack(spacing: 7) {
                GitHostBadge(host: repo.host, domain: repo.domain)
                Text(repo.slug)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                if repo.port != nil {
                    GitPill(text: "端口 \(repo.port ?? "")", tint: .secondary)
                }
                Spacer(minLength: 4)
                Text("仓库名：\(repo.folderName)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        } else {
            Text("GitHub、Gitee 或者任何 Git 服务都能用。网页地址、SSH 地址都认。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: 保存位置

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GitPathField(
                title: "保存到",
                path: store.rootPath,
                systemImage: "folder",
                actionTitle: "换个位置",
                onPick: { store.pickRoot() }
            )

            if let destination = store.cloneDestination {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text("会存到 " + shorten(destination))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    if store.destinationAlreadyExists {
                        GitPill(text: "重名，自动加序号", systemImage: "info.circle", tint: .orange)
                    }
                }
            }
        }
    }

    private func shorten(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    // MARK: 选项与按钮

    private var optionsRow: some View {
        HStack(spacing: 14) {
            Toggle(isOn: $store.shallow) {
                Text("只下最新的一个版本（更快）")
                    .font(.system(size: 11.5))
            }
            .toggleStyle(.checkbox)
            .help("勾上就只下载最新一次提交，历史记录不下。想留着完整历史就把勾去掉。")

            Spacer(minLength: 0)

            if let repo = store.parsedURL {
                Button {
                    store.openClonedInBrowser()
                } label: {
                    Label("在浏览器打开", systemImage: "safari")
                        .font(.system(size: 11))
                }
                .buttonStyle(.link)
                .help(repo.webURL)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            GitActionButton(
                title: store.cloning ? "正在克隆…" : "一键克隆",
                systemImage: "arrow.down.circle.fill",
                busy: store.cloning,
                enabled: store.parsedURL != nil && !store.cloning && GitEngine.isAvailable,
                action: { store.startClone() }
            )

            if store.cloning {
                Button("取消") { store.cancelClone() }
                    .buttonStyle(.link)
                    .font(.system(size: 11.5))
            }

            if !GitEngine.isAvailable {
                Label("没找到 git，先执行 xcode-select --install", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            Spacer(minLength: 0)

            if let url = store.parsedURL?.httpsURL {
                CopyIconButton(text: url, help: "复制 HTTPS 地址")
            }
            if let url = store.parsedURL?.sshURL {
                CopyIconButton(text: url, help: "复制 SSH 地址")
            }
        }
    }

    // MARK: 进度与结果

    private var progressCard: some View {
        ToolCard(title: "进度", systemImage: "terminal") {
            VStack(alignment: .leading, spacing: 10) {
                GitProgressBar(
                    value: Double(store.cloneProgress),
                    active: store.cloning,
                    tint: store.cloneError == nil ? .accentColor : .orange
                )

                GitLogPane(lines: store.cloneLog, placeholder: "准备开始")

                if let path = store.clonedPath {
                    successRow(path)
                }
            }
        }
    }

    private func successRow(_ path: String) -> some View {
        HStack(spacing: 10) {
            Label("已经放在 \(shorten(path))", systemImage: "checkmark.seal.fill")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.green)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 6)

            Button {
                store.revealCloned()
            } label: {
                Label("在访达中打开", systemImage: "folder")
                    .font(.system(size: 11))
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.green.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.green.opacity(0.25))
        )
    }

    // MARK: 剪贴板

    /// 打开页面时，如果剪贴板里正好是个仓库地址，直接填进来
    private func fillFromClipboardIfPossible() {
        guard store.urlText.isEmpty else { return }
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        guard (try? GitRepoURL.parse(text)) != nil else { return }
        store.urlText = text
    }

    private func paste() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        store.urlText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 输入框右边的小粘贴按钮
private struct PasteIconButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help("从剪贴板粘贴")
    }
}
