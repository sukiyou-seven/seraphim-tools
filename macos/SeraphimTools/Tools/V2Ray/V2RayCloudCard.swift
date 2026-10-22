import AppKit
import SwiftUI

/// 云端一键安装：默认收起来，只占一行；要用的时候展开。
struct CloudInstallCard: View {
    @ObservedObject var installer: CloudInstaller
    let core: CoreCandidate?
    @Binding var expanded: Bool
    let onImported: (V2RayNode) -> Void

    @AppStorage("v2raySSHHost") private var host = ""
    @AppStorage("v2raySSHPort") private var sshPort = 22
    @AppStorage("v2raySSHUser") private var user = "root"
    @AppStorage("v2raySSHAuth") private var authRaw = SSHAuthMode.key.rawValue
    @AppStorage("v2raySSHKeyPath") private var keyPath = "~/.ssh/id_rsa"
    @AppStorage("v2rayCloudMode") private var modeRaw = ServerMode.vlessReality.rawValue
    @AppStorage("v2rayCloudPort") private var cloudPort = 443
    @AppStorage("v2rayCloudSNI") private var serverName = "www.microsoft.com"
    @AppStorage("v2rayCloudPath") private var wsPath = "/seraphim"
    @AppStorage("v2rayCloudRemark") private var remark = "云端节点"

    @State private var password = ""
    @State private var checkNote = ""
    @State private var checking = false
    @State private var showCloudLog = false

    private var authMode: SSHAuthMode {
        SSHAuthMode(rawValue: authRaw) ?? .key
    }

    private var mode: ServerMode {
        ServerMode(rawValue: modeRaw) ?? .vlessReality
    }

    var body: some View {
        ToolCard(title: "云端安装", systemImage: "cloud") {
            VStack(alignment: .leading, spacing: 10) {
                header
                if expanded { form }
            }
        }
        .onChange(of: installer.node) { _, newValue in
            if let newValue { onImported(newValue) }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                Label(expanded ? "收起" : "展开", systemImage: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11.5))
            }
            .controlSize(.small)

            Text("在一台服务器上装好 Xray 服务端，装完直接把节点链接塞回上面的列表。")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if installer.running {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small)
                    Text("安装中").font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Button("取消") { installer.cancel() }
                    .controlSize(.small)
            }
        }
    }

    // MARK: 表单

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            serverRows
            Divider()
            targetRows
            Divider()
            actionRow
            if !checkNote.isEmpty {
                Text(checkNote)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            if !installer.steps.isEmpty { stepList }
        }
    }

    private var serverRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("服务器")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .leading)
                TextField("IP 或域名", text: $host)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5, design: .monospaced))
                    .frame(maxWidth: 240)

                Text("SSH 端口")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("22", value: $sshPort, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5, design: .monospaced))
                    .frame(width: 68)

                Text("用户")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("root", text: $user)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5, design: .monospaced))
                    .frame(width: 96)

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Text("登录方式")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .leading)

                FlowRow(spacing: 8) {
                    ForEach(SSHAuthMode.allCases) { item in
                        ChipButton(title: item.title, isSelected: item == authMode) {
                            authRaw = item.rawValue
                        }
                    }
                }

                if authMode == .password {
                    SecureField("登录密码（不保存）", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5, design: .monospaced))
                        .frame(maxWidth: 240)
                } else {
                    TextField("私钥路径", text: $keyPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5, design: .monospaced))
                        .frame(maxWidth: 300)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var targetRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("装什么")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .leading)
                FlowRow(spacing: 8) {
                    ForEach(ServerMode.allCases) { item in
                        ChipButton(title: item.title, isSelected: item == mode) {
                            modeRaw = item.rawValue
                            cloudPort = item.defaultPort
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            Text(mode.detail)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)

            HStack(spacing: 10) {
                Text("服务端口")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .leading)
                TextField("443", value: $cloudPort, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5, design: .monospaced))
                    .frame(width: 78)

                if mode.needsRealityKeys {
                    Text("伪装域名")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("www.microsoft.com", text: $serverName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5, design: .monospaced))
                        .frame(maxWidth: 240)
                        .help("REALITY 借用这个站点的 TLS 证书特征，填一个能正常访问的大站")
                }

                if mode.needsPath {
                    Text("WS 路径")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("/seraphim", text: $wsPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5, design: .monospaced))
                        .frame(maxWidth: 160)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Text("节点备注")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .leading)
                TextField("云端节点", text: $remark)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5, design: .default))
                    .frame(maxWidth: 220)
                Spacer(minLength: 0)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                checkConnection()
            } label: {
                if checking {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small)
                        Text("测试中").font(.system(size: 11.5))
                    }
                } else {
                    Label("测试连接", systemImage: "bolt.horizontal.circle")
                        .font(.system(size: 11.5))
                }
            }
            .controlSize(.small)
            .disabled(checking || installer.running || host.isEmpty)

            Button {
                install()
            } label: {
                Label("一键安装", systemImage: "arrow.down.to.line")
                    .font(.system(size: 11.5))
            }
            .controlSize(.small)
            .disabled(installer.running || host.isEmpty || core == nil)
            .help(core == nil ? "需要先有本地内核（用它生成 REALITY 密钥）" : "连上去装服务端")

            if installer.node != nil {
                Text("装好了，节点已回填到上面的列表")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.green)
            }

            Spacer(minLength: 0)
        }
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(installer.steps) { step in
                HStack(spacing: 7) {
                    Image(systemName: icon(for: step.state))
                        .font(.system(size: 10.5))
                        .foregroundStyle(tint(for: step.state))
                    Text(step.title)
                        .font(.system(size: 11.5))
                    if !step.detail.isEmpty {
                        Text(step.detail)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
            }

            if !installer.log.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showCloudLog.toggle() }
                } label: {
                    Label(showCloudLog ? "收起原始输出" : "看原始输出", systemImage: showCloudLog ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11))
                }
                .controlSize(.small)

                if showCloudLog {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(installer.log.suffix(200).enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: 150)
                    .background(
                        Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                }
            }
        }
    }

    private func icon(for state: InstallStepState) -> String {
        switch state {
        case .pending: return "circle"
        case .running: return "clock"
        case .done: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private func tint(for state: InstallStepState) -> Color {
        switch state {
        case .pending: return .secondary
        case .running: return .orange
        case .done: return .green
        case .failed: return .red
        }
    }

    // MARK: 动作

    private func hostConfig() -> SSHHostConfig {
        SSHHostConfig(
            host: host.trimmingCharacters(in: .whitespaces),
            port: sshPort,
            user: user,
            authMode: authMode,
            password: password,
            keyPath: keyPath
        )
    }

    private func plan() -> CloudInstallPlan {
        CloudInstallPlan(
            mode: mode,
            port: cloudPort,
            serverName: serverName.trimmingCharacters(in: .whitespaces),
            wsPath: wsPath,
            remark: remark
        )
    }

    private func checkConnection() {
        checking = true
        checkNote = ""
        installer.check(host: hostConfig()) { ok, detail in
            checking = false
            checkNote = ok ? "连上了：\(detail)" : "连不上：\(detail)"
        }
    }

    private func install() {
        guard let corePath = core?.path else { return }
        checkNote = "开始安装，第一次装大概要一两分钟"
        showCloudLog = true
        installer.install(host: hostConfig(), plan: plan(), corePath: corePath)
    }
}
