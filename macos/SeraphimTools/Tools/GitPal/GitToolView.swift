import SwiftUI

/// Git 助手：只做两件事 —— 一键克隆、一键推送。
struct GitToolView: View {
    @ObservedObject private var store = GitStore.shared
    @AppStorage("gitMode") private var mode = "clone"

    var body: some View {
        VStack(spacing: 0) {
            if !GitEngine.isAvailable {
                missingGitBanner
            }
            tabBar
            Divider()
            content
        }
        .onDisappear { store.persist() }
    }

    // MARK: 顶部切换

    private var tabBar: some View {
        HStack(spacing: 8) {
            ChipButton(title: "一键克隆", isSelected: mode == "clone") {
                mode = "clone"
            }
            ChipButton(title: "一键推送", isSelected: mode == "push") {
                mode = "push"
                if !store.repoPath.isEmpty, store.snapshot == nil {
                    store.loadRepository(store.repoPath)
                }
            }

            Spacer(minLength: 0)

            if let version = gitVersionText {
                Text(version)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var gitVersionText: String? {
        guard let version = GitEngine.version() else { return nil }
        return "git \(version)"
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case "push":
            GitPushView(store: store)
        default:
            GitCloneView(store: store)
        }
    }

    private var missingGitBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("这台机器上没找到 git。在「终端」里执行一次 xcode-select --install 就能装好。")
                .font(.system(size: 11.5))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
    }
}
