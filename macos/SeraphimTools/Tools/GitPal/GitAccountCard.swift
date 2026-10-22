import AppKit
import SwiftUI

/// 账号与密钥。默认折叠，只占一行 —— 克隆公开仓库根本用不到它。
struct GitAccountCard: View {
    @ObservedObject var store: GitStore
    @State private var revealToken = false

    var body: some View {
        GitCollapsibleCard(
            title: "账号与密钥",
            systemImage: "key.horizontal",
            subtitle: subtitle,
            expanded: $store.accountExpanded
        ) {
            VStack(alignment: .leading, spacing: 14) {
                hostPicker
                Divider()
                sshSection
                Divider()
                tokenSection
            }
        }
        .onAppear { store.refreshTokenState() }
    }

    private var subtitle: String {
        var parts: [String] = []
        if store.hasToken { parts.append("已存 \(store.accountHost.title) 令牌") }
        if !store.sshKeys.isEmpty { parts.append("本机有 \(store.sshKeys.count) 把 SSH 密钥") }
        return parts.isEmpty ? "克隆公开仓库用不上；推自己的仓库时再来配" : parts.joined(separator: " · ")
    }

    // MARK: 平台

    private var hostPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("平台")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            FlowRow(spacing: 8) {
                ForEach(GitHost.allCases) { host in
                    ChipButton(
                        title: host.title,
                        isSelected: store.accountHost == host
                    ) {
                        store.selectHost(host)
                    }
                }
            }
        }
    }

    // MARK: SSH

    private var sshSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Text("SSH 密钥")
                    .font(.system(size: 11, weight: .semibold))
                GitPill(text: "推荐", tint: .green)
                Spacer(minLength: 0)
                if store.sshWorking {
                    ProgressView().controlSize(.small)
                }
            }

            Text("钥匙留在本机，不用输密码，也不会过期。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            if store.sshKeys.isEmpty {
                notFoundKeyRow
            } else {
                ForEach(store.sshKeys) { key in
                    keyRow(key)
                }
            }

            HStack(spacing: 10) {
                Button {
                    store.testSSHConnection()
                } label: {
                    Label("测试连通", systemImage: "bolt.horizontal")
                        .font(.system(size: 11))
                }
                .controlSize(.small)
                .disabled(store.sshKeys.isEmpty || store.sshWorking || store.accountHost.domain == nil)

                Button {
                    store.openSSHKeyPage()
                } label: {
                    Label("去 \(store.accountHost.title) 添加公钥", systemImage: "arrow.up.forward.square")
                        .font(.system(size: 11))
                }
                .controlSize(.small)
                .disabled(store.accountHost.sshKeyPage == nil)

                Spacer(minLength: 0)
            }

            if let message = store.sshTestMessage {
                resultLine(message, ok: store.sshTestOK)
            }
        }
    }

    private var notFoundKeyRow: some View {
        HStack(spacing: 10) {
            Label("本机还没找到 SSH 密钥", systemImage: "key.slash")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            Spacer(minLength: 6)

            Button {
                store.generateSSHKey()
            } label: {
                Label("生成一把", systemImage: "wand.and.stars")
                    .font(.system(size: 11))
            }
            .controlSize(.small)
            .disabled(store.sshWorking)
            .help("没有密码短语的 ed25519 密钥，放在 ~/.ssh/id_ed25519")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }

    private func keyRow(_ key: GitSSHKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)

                Text(key.name)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))

                if !key.algorithm.isEmpty {
                    GitPill(text: key.algorithm, tint: .secondary)
                }

                Spacer(minLength: 6)

                Button {
                    store.copyPublicKey(key)
                } label: {
                    Label(
                        store.copiedPublicKeyPath == key.privatePath ? "已复制" : "复制公钥",
                        systemImage: store.copiedPublicKeyPath == key.privatePath ? "checkmark" : "doc.on.doc"
                    )
                    .font(.system(size: 11))
                }
                .controlSize(.small)
            }

            if !key.fingerprint.isEmpty {
                Text(key.fingerprint)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }

    // MARK: 令牌

    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Text("访问令牌")
                    .font(.system(size: 11, weight: .semibold))
                if store.tokenSaved {
                    GitPill(text: "已保存", systemImage: "checkmark.circle.fill", tint: .green)
                }
                Spacer(minLength: 0)
            }

            if store.tokenSaved {
                savedTokenRow
            } else {
                tokenInputRow
            }

            Text(tokenHint)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var savedTokenRow: some View {
        HStack(spacing: 10) {
            if let masked = store.maskedToken {
                Text(masked)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Text("存在系统钥匙串里")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)

            Spacer(minLength: 6)

            Button {
                store.deleteToken()
            } label: {
                Label("清除", systemImage: "trash")
                    .font(.system(size: 11))
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            Color.green.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }

    private var tokenInputRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Group {
                    if revealToken {
                        TextField(store.accountHost.tokenPlaceholder, text: $store.tokenInput)
                    } else {
                        SecureField(store.accountHost.tokenPlaceholder, text: $store.tokenInput)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5, design: .monospaced))

                Button {
                    revealToken.toggle()
                } label: {
                    Image(systemName: revealToken ? "eye.slash" : "eye")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(revealToken ? "藏起来" : "看一眼")

                Button {
                    store.openTokenPage()
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .disabled(store.accountHost.tokenPage == nil)
                .help("打开令牌申请页面")
            }

            HStack(spacing: 10) {
                Button {
                    store.saveToken()
                } label: {
                    Label("保存", systemImage: "checkmark")
                        .font(.system(size: 11))
                }
                .controlSize(.small)
                .disabled(store.tokenInput.trimmingCharacters(in: .whitespaces).isEmpty)

                Text("保存后会用它自动登录，不用每次输")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 0)
            }
        }
    }

    private var tokenHint: String {
        switch store.accountHost {
        case .github:
            return "在 GitHub 的 Settings → Developer settings → Personal access tokens 里生成，勾上 repo。"
        case .gitee:
            return "在 Gitee 的「设置 → 私人令牌」里生成，勾上 projects。"
        case .other:
            return "自建服务请到它自己的设置页里生成访问令牌。"
        }
    }

    private func resultLine(_ message: String, ok: Bool) -> some View {
        Label(message, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.system(size: 11))
            .foregroundStyle(ok ? Color.green : Color.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}
