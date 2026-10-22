import AppKit
import SwiftUI

/// 需求转提示词：一份产品想法 → 一份能让 AI 直接开工的需求提示词。
struct ProtoRequirementPanel: View {
    @ObservedObject private var store = ProtoStore.shared
    @AppStorage(AIDriveKeys.enabled) private var aiEnabled = false
    @State private var toast: String?
    @State private var aiText = ""
    @State private var aiWorking = false
    @State private var aiError: String?

    private var output: ProtoOutput {
        ProtoRequirementEngine.build(store.requirement)
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
            featuresCard
            deliverablesCard
            constraintsCard
            extraCard
        } right: {
            if aiEnabled {
                AIActionBar(
                    actionTitle: "AI 生成需求提示词",
                    isWorking: aiWorking,
                    errorText: aiError,
                    onRun: { runAI() }
                )
            } else {
                ProtoFeedbackCard(output: output)
            }
            ProtoOutputPane(
                title: aiEnabled ? "需求提示词（AI 生成）" : "需求提示词",
                text: displayedText,
                placeholder: aiEnabled
                    ? "左边填完点上方按钮；出错时这里显示本地规则结果"
                    : "左边随便填一点，这里就开始出提示词了",
                saveAs: "需求提示词.md",
                onNotify: { toast = $0 }
            )
        }
        .toast($toast)
    }

    private func runAI() {
        let snapshot = store.requirement
        aiWorking = true
        aiError = nil
        aiText = ""
        Task {
            do {
                let config = try await AIClient.resolveConfig()
                let prompt = ProtoAI.requirement(snapshot)
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
                ProtoHint(text: "点一下就把下面的表单填好。改一个已有的，比从空白开始想快得多。")

                ProtoPresetGrid(
                    presets: ProtoPresets.presets(for: .requirement),
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
        ToolCard(title: "产品是什么", systemImage: "lightbulb") {
            VStack(alignment: .leading, spacing: 13) {
                LabeledField(title: "产品名称") {
                    TextField("比如：小铺鲜生", text: $store.requirement.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5))
                }

                LabeledField(title: "一句话说清", hint: "给谁、解决什么问题") {
                    TextField("比如：给社区生鲜店做的小程序，居民在线下单到店自提", text: $store.requirement.idea)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5))
                }

                LabeledField(title: "目标用户", hint: "写具体人群") {
                    TextField("比如：小区里 30~50 岁的居民，不愿再装 App", text: $store.requirement.audience)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5))
                }

                protoOption("落地形态", labelWidth: 58) {
                    ForEach(ProtoPlatform.allCases) { item in
                        ChipButton(title: item.title, isSelected: item == store.requirement.platform) {
                            store.requirement.platform = item
                        }
                    }
                }
                ProtoHint(text: store.requirement.platform.brief)

                protoOption("技术栈", labelWidth: 58) {
                    ForEach(ProtoStack.allCases) { item in
                        ChipButton(title: item.title, isSelected: item == store.requirement.stack) {
                            store.requirement.stack = item
                        }
                    }
                }
            }
        }
    }

    private func protoOption<Content: View>(
        _ title: String,
        labelWidth: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ProtoOptionRow(title: title, labelWidth: labelWidth, content: content)
    }

    // MARK: - 功能

    private var featuresCard: some View {
        ToolCard(title: "核心功能", systemImage: "checklist") {
            VStack(alignment: .leading, spacing: 8) {
                ProtoLinesEditor(
                    placeholder: "一行一个功能，也可以用顿号并排写：\n浏览商品、加入购物车、下单",
                    lines: $store.requirement.features,
                    minHeight: 108
                )
                ProtoHint(text: "不用写细，AI 会展开。但也别只写「一个购物功能」——它猜不出你要的是哪种。")
            }
        }
    }

    // MARK: - 输出物

    private var deliverablesCard: some View {
        ToolCard(title: "让 AI 交付什么", systemImage: "shippingbox") {
            VStack(alignment: .leading, spacing: 10) {
                FlowRow(spacing: 6) {
                    ForEach(ProtoDeliverable.allCases) { item in
                        ChipButton(
                            title: item.title,
                            isSelected: store.requirement.deliverables.contains(item)
                        ) {
                            toggle(item)
                        }
                    }
                }

                ProtoHint(text: sectionHint)
            }
        }
    }

    private func toggle(_ item: ProtoDeliverable) {
        if store.requirement.deliverables.contains(item) {
            store.requirement.deliverables.remove(item)
        } else {
            store.requirement.deliverables.insert(item)
        }
    }

    /// 把「钉死了多少小节」摆出来——这是这类提示词真正的分量所在
    private var sectionHint: String {
        let picked = ProtoDeliverable.allCases.filter { store.requirement.deliverables.contains($0) }
        guard !picked.isEmpty else {
            return "一项都没勾的话，默认只出 PRD。"
        }
        let sections = picked.reduce(0) { $0 + $1.outline.count }
        return "这 \(picked.count) 项会让提示词里钉死 \(sections) 个小节的骨架，AI 得逐节交代，漏哪节一眼就看出来。"
    }

    // MARK: - 约束

    private var constraintsCard: some View {
        ToolCard(title: "约束与红线", systemImage: "nosign") {
            VStack(alignment: .leading, spacing: 8) {
                ProtoLinesEditor(
                    placeholder: "一行一条：\n内网部署，依赖的服务不能出公网\n附件不超过 20MB",
                    lines: $store.requirement.constraints,
                    minHeight: 84
                )
                ProtoHint(text: "能想到的都写上。AI 不会主动避开你心里那个坑。")
            }
        }
    }

    // MARK: - 补充

    private var extraCard: some View {
        ToolCard(title: "补充说明", systemImage: "text.append") {
            LabeledField(title: "还有什么要交代的", hint: "可选") {
                TextField(
                    "比如：第一期只做单店，不做多门店，优惠券留到第二期",
                    text: $store.requirement.extra,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12.5))
                .lineLimit(2...5)
            }
        }
    }
}
