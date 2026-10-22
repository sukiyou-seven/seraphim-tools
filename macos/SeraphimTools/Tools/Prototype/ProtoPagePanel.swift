import AppKit
import SwiftUI

/// 页面原型描述生成器：一句「这页要干什么」→ 一段能直接丢给 AI 的文字原型。
struct ProtoPagePanel: View {
    @ObservedObject private var store = ProtoStore.shared
    @AppStorage(AIDriveKeys.enabled) private var aiEnabled = false
    @State private var toast: String?
    @State private var aiText = ""
    @State private var aiWorking = false
    @State private var aiError: String?

    private var output: ProtoOutput {
        ProtoPageEngine.build(store.page)
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
            fieldsCard
            actionsCard
            statesCard
            extraCard
        } right: {
            if aiEnabled {
                AIActionBar(
                    actionTitle: "AI 生成页面原型",
                    isWorking: aiWorking,
                    errorText: aiError,
                    onRun: { runAI() }
                )
            } else {
                ProtoFeedbackCard(output: output)
            }
            ProtoOutputPane(
                title: aiEnabled ? "页面原型描述（AI 生成）" : "页面原型描述",
                text: displayedText,
                placeholder: aiEnabled
                    ? "左边写一句「这一页要干什么」，点上方按钮；出错时显示本地规则结果"
                    : "左边写一句「这一页要干什么」，这里就开始出描述",
                saveAs: "页面原型.md",
                onNotify: { toast = $0 }
            )
        }
        .toast($toast)
    }

    private func runAI() {
        let snapshot = store.page
        aiWorking = true
        aiError = nil
        aiText = ""
        Task {
            do {
                let config = try await AIClient.resolveConfig()
                let prompt = ProtoAI.page(snapshot)
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
                ProtoHint(text: "挑一个最接近的页面，字段和操作都填好了，改改就能用。")

                ProtoPresetGrid(
                    presets: ProtoPresets.presets(for: .page),
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
        ToolCard(title: "这一页是什么", systemImage: "rectangle.on.rectangle") {
            VStack(alignment: .leading, spacing: 13) {
                LabeledField(title: "页面名称") {
                    TextField("比如：商品列表", text: $store.page.pageName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5))
                }

                ProtoOptionRow(title: "页面类型", labelWidth: 58) {
                    ForEach(ProtoPageKind.allCases) { item in
                        ChipButton(title: item.title, isSelected: item == store.page.kind) {
                            store.page.kind = item
                        }
                    }
                }
                ProtoHint(text: "区域骨架和注意事项会按这个类型自动补。")

                LabeledField(title: "这一页要干什么", hint: "用户来这儿是要完成什么") {
                    TextField("比如：快速扫过在售商品，找到想买的并进详情", text: $store.page.purpose)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5))
                }

                ProtoOptionRow(title: "形态", labelWidth: 58) {
                    ForEach(ProtoPlatform.allCases) { item in
                        ChipButton(title: item.title, isSelected: item == store.page.platform) {
                            store.page.platform = item
                        }
                    }
                }
                ProtoHint(text: store.page.platform.brief)

                ProtoOptionRow(title: "技术栈", labelWidth: 58) {
                    ForEach(ProtoStack.allCases) { item in
                        ChipButton(title: item.title, isSelected: item == store.page.stack) {
                            store.page.stack = item
                        }
                    }
                }
            }
        }
    }

    // MARK: - 字段

    private var fieldsCard: some View {
        ToolCard(title: "这一页要展示什么", systemImage: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 8) {
                ProtoLinesEditor(
                    placeholder: "一行一个字段，想说明格式就写「字段: 说明」：\n商品图: 1:1 方图\n价格\n库存标签: 快没了才显示",
                    lines: $store.page.fields,
                    minHeight: 108
                )
                ProtoHint(text: "列表页一般 3 个主要字段 + 1 个次要字段就到顶了，再多会挤成一团。")
            }
        }
    }

    // MARK: - 操作

    private var actionsCard: some View {
        ToolCard(title: "用户能做什么", systemImage: "hand.tap") {
            VStack(alignment: .leading, spacing: 8) {
                ProtoLinesEditor(
                    placeholder: "一行一个操作：\n点商品进详情\n下拉刷新\n左滑删除",
                    lines: $store.page.actions,
                    minHeight: 84
                )
                ProtoHint(text: "写「点什么、之后去哪」这种粒度的最有用。")
            }
        }
    }

    // MARK: - 状态

    private var statesCard: some View {
        ToolCard(title: "要处理哪些状态", systemImage: "arrow.triangle.2.circlepath") {
            VStack(alignment: .leading, spacing: 10) {
                FlowRow(spacing: 6) {
                    ForEach(ProtoPageState.allCases) { item in
                        ChipButton(title: item.title, isSelected: store.page.states.contains(item)) {
                            toggleState(item)
                        }
                    }
                }

                if let picked = firstPickedState {
                    ProtoHint(text: "举个例：勾了「\(picked.title)」，描述里就会写「\(picked.brief)」。")
                } else {
                    ProtoHint(text: "加载中和没有数据这两态是必做的——页面空白时用户会以为坏了。")
                }
            }
        }
    }

    private func toggleState(_ item: ProtoPageState) {
        if store.page.states.contains(item) {
            store.page.states.remove(item)
        } else {
            store.page.states.insert(item)
        }
    }

    private var firstPickedState: ProtoPageState? {
        ProtoPageState.allCases.first { store.page.states.contains($0) }
    }

    // MARK: - 补充

    private var extraCard: some View {
        ToolCard(title: "补充说明", systemImage: "text.append") {
            LabeledField(title: "还有什么要交代的", hint: "可选") {
                TextField(
                    "比如：两列网格排布，不要做成一行一条",
                    text: $store.page.extra,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12.5))
                .lineLimit(2...5)
            }
        }
    }
}
