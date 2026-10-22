import AppKit
import SwiftUI

/// 不同节点类型的配色（Mermaid 那边的形状由引擎负责，这里只管界面）
extension FlowNodeKind {
    var tint: Color {
        switch self {
        case .start: return .green
        case .process: return .blue
        case .decision: return .orange
        case .io: return .teal
        case .subroutine: return .purple
        case .storage: return .brown
        }
    }
}

/// 流程图：拖节点 → 出 Mermaid 代码。
///
/// 不做自由画布。Mermaid 自己会排版，用户要管的是「有哪些步骤、谁接谁」，
/// 让他去拖坐标反而是多余的活儿。所以这里的「拖拽」是拖顺序——节点按列表顺序自动串起来。
struct ProtoFlowPanel: View {
    @ObservedObject private var store = ProtoStore.shared
    @AppStorage(AIDriveKeys.enabled) private var aiEnabled = false
    @State private var toast: String?
    @State private var confirmingClear = false
    @State private var aiText = ""
    @State private var aiWorking = false
    @State private var aiError: String?

    private var nodes: [FlowNode] { store.flow.nodes }
    private var mermaid: String { ProtoFlowEngine.mermaid(store.flow) }
    private var steps: [FlowPreviewStep] { ProtoFlowEngine.preview(store.flow) }
    private var warnings: [String] { ProtoFlowEngine.validate(store.flow) }

    /// AI 开时输出区显示的代码：生成过用 AI 的，失败或没生成回退本地
    private var displayedMermaid: String {
        if aiEnabled, aiError == nil { return aiText }
        return mermaid
    }

    var body: some View {
        ProtoSplit {
            presetCard
            AIDriveCard()
            headerCard
            nodesCard
        } right: {
            if aiEnabled {
                AIActionBar(
                    actionTitle: "AI 生成 Mermaid",
                    isWorking: aiWorking,
                    errorText: aiError,
                    onRun: { runAI() }
                )
            } else {
                warningsCard
                previewCard
            }
            codePane
        }
        .toast($toast)
        .confirmationDialog("清空所有节点？", isPresented: $confirmingClear) {
            Button("清空", role: .destructive) {
                store.flow.nodes = []
                toast = "已清空"
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清空后这些步骤就没了，想找回来只能重新加。")
        }
    }

    private func runAI() {
        let snapshot = store.flow
        guard !snapshot.nodes.isEmpty else {
            aiError = "左边先加几个节点，AI 才有得画。"
            return
        }
        aiWorking = true
        aiError = nil
        aiText = ""
        Task {
            do {
                let config = try await AIClient.resolveConfig()
                let prompt = ProtoAI.flow(snapshot)
                let raw = try await AIClient.complete(
                    provider: config.provider,
                    model: config.model,
                    system: prompt.system,
                    user: prompt.user,
                    temperature: 0.4,
                    maxTokens: 2048
                )
                await MainActor.run {
                    // 模型爱套 ```mermaid 围栏，剥掉再显示
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
                ProtoHint(text: "三个常见的流程，节点和分支都摆好了，改成你自己的。")

                ProtoPresetGrid(
                    presets: ProtoPresets.presets(for: .flow),
                    recentIDs: store.recentPresets
                ) { preset in
                    store.apply(preset)
                    toast = "已套用「\(preset.title)」"
                }
            }
        }
    }

    // MARK: - 标题与方向

    private var headerCard: some View {
        ToolCard(title: "图的名字和方向", systemImage: "textformat") {
            VStack(alignment: .leading, spacing: 13) {
                LabeledField(title: "标题") {
                    TextField("比如：请假审批流程", text: $store.flow.title)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5))
                }

                ProtoOptionRow(title: "方向", labelWidth: 42) {
                    ForEach(FlowDirection.allCases) { item in
                        ChipButton(title: item.title, isSelected: item == store.flow.direction) {
                            store.flow.direction = item
                        }
                    }
                }
                ProtoHint(text: "步骤多、名字长的时候横着放（从左到右）通常更好读。")
            }
        }
    }

    // MARK: - 节点

    private var nodesCard: some View {
        ToolCard(title: "流程步骤", systemImage: "list.number") {
            VStack(alignment: .leading, spacing: 10) {
                if nodes.isEmpty {
                    emptyNodes
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(nodes.enumerated()), id: \.element.id) { offset, node in
                            nodeCard(offset: offset, node: node)
                        }
                    }
                }

                Divider()

                HStack(spacing: 8) {
                    Button {
                        addNode(.process)
                    } label: {
                        Label("加个步骤", systemImage: "plus")
                            .font(.system(size: 11.5))
                    }
                    .controlSize(.small)

                    Button {
                        addNode(.decision)
                    } label: {
                        Label("加个判断", systemImage: "arrow.triangle.branch")
                            .font(.system(size: 11.5))
                    }
                    .controlSize(.small)

                    Spacer(minLength: 0)

                    if !nodes.isEmpty {
                        Button {
                            confirmingClear = true
                        } label: {
                            Text("清空").font(.system(size: 11.5))
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var emptyNodes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("还没有步骤。")
                .font(.system(size: 11.5))
            ProtoHint(text: "流程图最少要有「开始」和「结束」两个节点。上面挑个预设，或者直接点下面的按钮从零加。")
        }
        .padding(.vertical, 6)
    }

    private func nodeCard(offset: Int, node: FlowNode) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("\(offset + 1)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 14, alignment: .trailing)

                kindMenu(offset: offset, node: node)

                Spacer(minLength: 0)

                terminalButton(offset: offset, node: node)
                moveButton(offset: offset, delta: -1, systemImage: "chevron.up", disabled: offset == 0)
                moveButton(offset: offset, delta: 1, systemImage: "chevron.down", disabled: offset == nodes.count - 1)

                Button {
                    deleteNode(offset)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("删掉这一步")
            }

            TextField(node.kind.defaultText, text: $store.flow.nodes[offset].text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12.5))

            if node.kind == .decision {
                elseRow(offset: offset, node: node)
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(node.kind.tint.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(node.kind.tint.opacity(0.22))
        )
    }

    private func kindMenu(offset: Int, node: FlowNode) -> some View {
        Menu {
            ForEach(FlowNodeKind.allCases) { kind in
                Button {
                    store.flow.nodes[offset].kind = kind
                } label: {
                    Label("\(kind.title)（\(kind.shapeName)）", systemImage: kind.systemImage)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: node.kind.systemImage)
                    .font(.system(size: 9))
                Text(node.kind.title)
                    .font(.system(size: 10.5))
                Image(systemName: "chevron.down")
                    .font(.system(size: 6.5, weight: .semibold))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(node.kind.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(node.kind.tint)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("换成别的形状")
    }

    private func terminalButton(offset: Int, node: FlowNode) -> some View {
        Button {
            store.flow.nodes[offset].isTerminal.toggle()
        } label: {
            Image(systemName: node.isTerminal ? "stop.circle.fill" : "stop.circle")
                .font(.system(size: 11))
                .foregroundStyle(node.isTerminal ? Color.orange : Color.secondary)
        }
        .buttonStyle(.borderless)
        .help("流程到此结束：这一支走完就停，不再连向下面的节点")
    }

    private func moveButton(offset: Int, delta: Int, systemImage: String, disabled: Bool) -> some View {
        Button {
            store.flow.nodes.swapAt(offset, offset + delta)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .help(delta < 0 ? "往上挪" : "往下挪")
    }

    /// 判断节点的「不成立时去哪」。不画这条分支是常态，所以留一个显式的「不画」选项。
    private func elseRow(offset: Int, node: FlowNode) -> some View {
        HStack(spacing: 6) {
            Text("不成立时")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            Menu {
                Button("不画这条分支") {
                    store.flow.nodes[offset].elseTarget = nil
                }
                if nodes.count > 1 { Divider() }
                ForEach(Array(nodes.enumerated()), id: \.element.id) { targetOffset, target in
                    if targetOffset != offset {
                        Button("\(targetOffset + 1). \(target.displayText)") {
                            store.flow.nodes[offset].elseTarget = target.id
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(elseLabel(offset))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 6.5, weight: .semibold))
                }
                .font(.system(size: 10.5))
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(Color.primary.opacity(0.07), in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer(minLength: 0)
        }
        .padding(.leading, 20)
    }

    private func elseLabel(_ offset: Int) -> String {
        guard let target = store.flow.nodes[offset].elseTarget,
              let index = store.flow.nodes.firstIndex(where: { $0.id == target }) else {
            return "不画"
        }
        return "→ \(index + 1). \(store.flow.nodes[index].displayText)"
    }

    // MARK: - 节点操作

    private func addNode(_ kind: FlowNodeKind) {
        store.flow.nodes.append(FlowNode(kind: kind, text: ""))
    }

    private func deleteNode(_ offset: Int) {
        guard store.flow.nodes.indices.contains(offset) else { return }
        let removed = store.flow.nodes[offset].id
        store.flow.nodes.remove(at: offset)
        // 别人指向它的分支要一起清掉，不然会留下一条画不出来的线
        for index in store.flow.nodes.indices where store.flow.nodes[index].elseTarget == removed {
            store.flow.nodes[index].elseTarget = nil
        }
    }

    // MARK: - 校验

    @ViewBuilder
    private var warningsCard: some View {
        if !warnings.isEmpty {
            ToolCard(title: "画之前先看看", systemImage: "exclamationmark.triangle") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(warnings.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 6) {
                            Text("·")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                            Text(item)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 预览

    private var previewCard: some View {
        ToolCard(title: "大致长这样（\(store.flow.direction.title)）", systemImage: "eye") {
            VStack(alignment: .leading, spacing: 10) {
                if steps.isEmpty {
                    ProtoHint(text: "加了节点这里就会显示流程走向。想看排版精美的版本，用右下角的「导出 HTML 预览」。")
                } else {
                    VStack(spacing: 4) {
                        ForEach(steps) { step in
                            previewRow(step)
                            if step.hasNextEdge {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .frame(height: 9)
                            }
                        }
                    }
                    ProtoHint(text: "这只是走向示意，排版由 Mermaid 决定。")
                }
            }
        }
    }

    private func previewRow(_ step: FlowPreviewStep) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text("\(step.index + 1)")
                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 14, alignment: .trailing)

                Image(systemName: step.kind.systemImage)
                    .font(.system(size: 9.5))
                    .foregroundStyle(step.kind.tint)

                Text(step.text)
                    .font(.system(size: 11.5))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                if step.isTerminal {
                    Text("结束")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(step.kind.tint.opacity(0.09), in: shape(for: step.kind))
            .overlay(shape(for: step.kind).strokeBorder(step.kind.tint.opacity(0.32)))

            if let elseLine = step.elseLine {
                Text("不成立 → \(elseLine)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 26)
            }
        }
    }

    /// 开始 / 结束画成胶囊，其余用圆角矩形——形状细节交给 Mermaid，这一层只求一眼能分出来
    private func shape(for kind: FlowNodeKind) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: kind == .start ? 999 : 7, style: .continuous)
    }

    // MARK: - 代码

    private var codePane: some View {
        TextPane(
            title: aiEnabled ? "Mermaid 代码（AI 生成）" : "Mermaid 代码",
            text: .constant(displayedMermaid),
            isEditable: false,
            placeholder: aiEnabled ? "点上方「AI 生成 Mermaid」；出错时显示本地规则的代码" : "加个节点，代码就出来了",
            minHeight: 260,
            buttons: [
                PaneButton(systemImage: "doc.on.doc", help: "复制代码", tint: .accentColor) {
                    NSPasteboard.copyString(displayedMermaid)
                    toast = "已复制，粘到 mermaid.live 或直接发给 AI"
                },
                PaneButton(systemImage: "square.and.arrow.down", help: "保存为 .mmd 文件") {
                    if FilePicker.saveText(displayedMermaid, suggestedName: fileName + ".mmd") != nil {
                        toast = "已保存 \(fileName).mmd"
                    }
                },
                PaneButton(systemImage: "globe", help: "导出 HTML 预览（双击用浏览器打开就能看图）") {
                    exportHTML()
                },
                PaneButton(systemImage: "arrow.up.right.square", help: "打开 mermaid.live（代码要自己粘过去）") {
                    if let url = URL(string: "https://mermaid.live/") {
                        NSWorkspace.shared.open(url)
                        toast = "已打开 mermaid.live，把代码粘进去就能看图"
                    }
                },
            ]
        )
    }

    private func exportHTML() {
        let html = ProtoFlowEngine.htmlPreview(store.flow)
        if FilePicker.saveText(html, suggestedName: fileName + ".html") != nil {
            toast = "已导出，双击用浏览器打开"
        }
    }

    /// 文件名不能带路径分隔符和那几个 Windows 也不认的字符
    private var fileName: String {
        let raw = store.flow.effectiveTitle
        let cleaned = raw
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "流程图" : cleaned
    }
}
