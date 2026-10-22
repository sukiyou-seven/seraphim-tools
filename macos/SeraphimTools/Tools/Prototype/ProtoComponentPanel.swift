import AppKit
import SwiftUI

/// 组件描述生成：描述想要的按钮 / 弹窗 / 表单 → 一份 AI 能照着实现的组件规格。
struct ProtoComponentPanel: View {
    @ObservedObject private var store = ProtoStore.shared
    @AppStorage(AIDriveKeys.enabled) private var aiEnabled = false
    @State private var toast: String?
    @State private var aiText = ""
    @State private var aiWorking = false
    @State private var aiError: String?

    private var output: ProtoOutput {
        ProtoComponentEngine.build(store.component)
    }

    private var displayedText: String {
        if aiEnabled, aiError == nil { return aiText }
        return output.text
    }

    var body: some View {
        ProtoSplit {
            presetCard
            AIDriveCard()
            basicsCard
            propsCard
            variantsCard
            interactionsCard
            optionsCard
            extraCard
        } right: {
            if aiEnabled {
                AIActionBar(
                    actionTitle: "AI 生成组件规格",
                    isWorking: aiWorking,
                    errorText: aiError,
                    onRun: { runAI() }
                )
            } else {
                ProtoFeedbackCard(output: output)
            }
            ProtoOutputPane(
                title: aiEnabled ? "组件规格提示词（AI 生成）" : "组件规格提示词",
                text: displayedText,
                placeholder: aiEnabled
                    ? "左边描述你想要的组件，点上方按钮；出错时显示本地规则结果"
                    : "左边描述你想要的组件，这里就出规格",
                saveAs: "组件规格.md",
                onNotify: { toast = $0 }
            )
        }
        .toast($toast)
    }

    private func runAI() {
        let snapshot = store.component
        aiWorking = true
        aiError = nil
        aiText = ""
        Task {
            do {
                let config = try await AIClient.resolveConfig()
                let prompt = ProtoAI.component(snapshot)
                let raw = try await AIClient.complete(
                    provider: config.provider,
                    model: config.model,
                    system: prompt.system,
                    user: prompt.user,
                    temperature: 0.7,
                    maxTokens: 8192
                )
                await MainActor.run {
                    aiText = AIClient.stripCodeFence(raw)
                    aiWorking = false
                }
            } catch {
                await MainActor.run {
                    aiError = error.localizedDescription
                    aiWorking = false
                }
            }
        }
    }

    // MARK: - 预设

    private var presetCard: some View {
        ToolCard(title: "从预设开始", systemImage: "square.stack.3d.up") {
            VStack(alignment: .leading, spacing: 10) {
                ProtoHint(text: "这五个都是日常最常要的，属性表已经填好了。")

                ProtoPresetGrid(
                    presets: ProtoPresets.presets(for: .component),
                    recentIDs: store.recentPresets
                ) { preset in
                    store.apply(preset)
                    toast = "已套用「\(preset.title)」"
                }
            }
        }
    }

    // MARK: - 基本信息

    private var basicsCard: some View {
        ToolCard(title: "要做什么组件", systemImage: "square.on.square") {
            VStack(alignment: .leading, spacing: 13) {
                LabeledField(title: "组件名称") {
                    TextField("比如：主按钮", text: $store.component.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5))
                }

                ProtoOptionRow(title: "组件类型", labelWidth: 58) {
                    ForEach(ProtoComponentKind.allCases) { item in
                        ChipButton(title: item.title, isSelected: item == store.component.kind) {
                            store.component.kind = item
                        }
                    }
                }
                ProtoHint(text: "组成部分和常见坑会按这个类型自动带上。")

                LabeledField(title: "它是干什么用的", hint: "决定规格的方向") {
                    TextField("比如：表单提交的主要操作，同一屏只应该出现一个", text: $store.component.purpose)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5))
                }

                ProtoOptionRow(title: "形态", labelWidth: 58) {
                    ForEach(ProtoPlatform.allCases) { item in
                        ChipButton(title: item.title, isSelected: item == store.component.platform) {
                            store.component.platform = item
                        }
                    }
                }

                ProtoOptionRow(title: "技术栈", labelWidth: 58) {
                    ForEach(ProtoStack.allCases) { item in
                        ChipButton(title: item.title, isSelected: item == store.component.stack) {
                            store.component.stack = item
                        }
                    }
                }
            }
        }
    }

    // MARK: - 属性

    private var propsCard: some View {
        ToolCard(title: "要暴露哪些属性", systemImage: "slider.horizontal.below.rectangle") {
            VStack(alignment: .leading, spacing: 8) {
                ProtoLinesEditor(
                    placeholder: "一行一个，写「名字: 说明」最有用：\nlabel: 按钮文字\ntone: 语气，默认主要\nloading: 是否加载中",
                    lines: $store.component.props,
                    minHeight: 100
                )
                ProtoHint(text: store.component.props.isEmpty
                          ? "留空的话会让 AI 先提一版建议给你确认——但最核心的那个可调项，还是你自己定更准。"
                          : "超过 8 个属性的组件通常该拆成两个。")
            }
        }
    }

    // MARK: - 变体

    private var variantsCard: some View {
        ToolCard(title: "要支持哪些变体", systemImage: "square.stack.3d.up") {
            VStack(alignment: .leading, spacing: 10) {
                FlowRow(spacing: 6) {
                    ForEach(ProtoVariant.allCases) { item in
                        ChipButton(title: item.title, isSelected: store.component.variants.contains(item)) {
                            toggleVariant(item)
                        }
                    }
                }

                if let picked = firstPickedVariant {
                    ProtoHint(text: "举个例：「\(picked.title)」会展开成——\(picked.brief)。")
                } else {
                    ProtoHint(text: "只做一种样子的组件，第二次用就会被硬改成别的样子。")
                }
            }
        }
    }

    private func toggleVariant(_ item: ProtoVariant) {
        if store.component.variants.contains(item) {
            store.component.variants.remove(item)
        } else {
            store.component.variants.insert(item)
        }
    }

    private var firstPickedVariant: ProtoVariant? {
        ProtoVariant.allCases.first { store.component.variants.contains($0) }
    }

    // MARK: - 交互

    private var interactionsCard: some View {
        ToolCard(title: "交互与反馈", systemImage: "cursorarrow.click") {
            VStack(alignment: .leading, spacing: 8) {
                ProtoLinesEditor(
                    placeholder: "一行一条：\n点下去立刻进入加载态，防止重复提交\n失败时退出加载态并提示",
                    lines: $store.component.interactions,
                    minHeight: 90
                )
                ProtoHint(text: "重点是「做完之后停下来是什么样」，失败路径尤其别漏。")
            }
        }
    }

    // MARK: - 附加要求

    private var optionsCard: some View {
        ToolCard(title: "还要带什么", systemImage: "checklist") {
            VStack(alignment: .leading, spacing: 12) {
                ProtoToggleRow(
                    title: "无障碍要求",
                    hint: "键盘可达、焦点可见、纯图标要有标签",
                    isOn: $store.component.includeA11y
                )
                Divider()
                ProtoToggleRow(
                    title: "验收要点",
                    hint: "每条都能用眼睛或键盘验证，不是「代码要优雅」这种空话",
                    isOn: $store.component.includeTesting
                )
            }
        }
    }

    // MARK: - 补充

    private var extraCard: some View {
        ToolCard(title: "补充说明", systemImage: "text.append") {
            LabeledField(title: "还有什么要交代的", hint: "可选") {
                TextField(
                    "比如：危险语气时，默认焦点不要落在确认按钮上",
                    text: $store.component.extra,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12.5))
                .lineLimit(2...5)
            }
        }
    }
}
