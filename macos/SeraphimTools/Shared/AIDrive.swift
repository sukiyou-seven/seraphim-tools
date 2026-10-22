import AppKit
import SwiftUI

// MARK: - AI 驱动配置卡
//
// 「AI 驱动」是全局配置（aiDriveEnabled / aiProviderID / aiModel 三个 AppStorage 键）：
// 在任何一个工具里改，别的工具立刻跟着变。
// 能不能用由 key 说了算——key 复用「API 余额」工具的钥匙串，没填就明说去哪填。

struct AIDriveCard: View {
    @AppStorage(AIDriveKeys.enabled) private var enabled = false
    @AppStorage(AIDriveKeys.providerID) private var providerID = "deepseek"
    @AppStorage(AIDriveKeys.model) private var model = ""

    @State private var keyReady: Bool?

    private var provider: AIProviderOption? { AICatalog.option(id: providerID) }

    var body: some View {
        ToolCard(title: "AI 驱动", systemImage: "sparkles") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Toggle(isOn: $enabled) {
                        Text("结果由 AI 生成")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                    Text("关 = 本地规则生成，不联网")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }

                if enabled {
                    if let provider {
                        FlowRow(spacing: 6) {
                            ForEach(AICatalog.chatProviders) { item in
                                ChipButton(title: item.name, isSelected: item.id == providerID) {
                                    providerID = item.id
                                    model = item.models.first ?? ""
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            Text("模型")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            modelMenu(provider: provider)
                            TextField("手输模型 ID", text: $model)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11.5, design: .monospaced))
                                .frame(maxWidth: 230)
                        }

                        keyStatus
                    }

                    Text("模型列表可能过时——对不上就直接手输官方文档里的模型 ID。key 和「API 余额」工具共用，填一次就够。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task(id: providerID) { await refreshKeyStatus() }
        .onChange(of: enabled) { _, isOn in
            if isOn { Task { await refreshKeyStatus() } }
        }
    }

    private var keyStatus: some View {
        HStack(spacing: 6) {
            switch keyReady {
            case true:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
                Text("key 已就绪（\(provider?.name ?? "")）")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            case false:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                Text("\(provider?.name ?? "这家") 还没填 key——去「API 余额」工具填，生成按钮会先拦住你")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            case nil:
                Text("正在检查 key…")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }

    private func modelMenu(provider: AIProviderOption) -> some View {
        Menu {
            ForEach(provider.models, id: \.self) { item in
                Button {
                    model = item
                } label: {
                    if item == model {
                        Label(item, systemImage: "checkmark")
                    } else {
                        Text(item)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "cpu")
                    .font(.system(size: 10))
                Text(model.isEmpty ? "选模型" : model)
                    .font(.system(size: 11.5, design: .monospaced))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.07), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func refreshKeyStatus() async {
        guard enabled else { return }
        keyReady = await AIClient.keyExists(for: providerID)
    }
}

// MARK: - 生成动作条
//
// 接了 AI 驱动的面板在输出区上方放一条：显示用哪个模型、给一个生成按钮、
// 转圈和报错都在这条里。真正的请求和结果归面板自己管。

struct AIActionBar: View {
    /// 按钮文案，比如「AI 生成需求提示词」
    var actionTitle: String
    var isWorking: Bool
    var errorText: String?
    var onRun: () -> Void

    @AppStorage(AIDriveKeys.providerID) private var providerID = "deepseek"
    @AppStorage(AIDriveKeys.model) private var model = ""

    var body: some View {
        ToolCard(title: "AI 生成", systemImage: "sparkles") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        onRun()
                    } label: {
                        Label(actionTitle, systemImage: "paperplane.fill")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isWorking)

                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在等模型回复，最长两分钟…")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    } else if let provider = AICatalog.option(id: providerID) {
                        Text("\(provider.name) · \(model.isEmpty ? provider.models.first ?? "" : model)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                if let errorText {
                    NoticeTag(text: errorText, systemImage: "exclamationmark.triangle.fill", tint: .orange)
                }
            }
        }
    }
}
