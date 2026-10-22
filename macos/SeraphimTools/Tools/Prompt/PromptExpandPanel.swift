import AppKit
import SwiftUI

/// 提示词扩写：一句话 → 结构化提示词。
/// AI 驱动开 = 由模型扩写（真理解语义）；关 = 本地骨架 + 词库，零联网。
struct PromptExpandPanel: View {
    @AppStorage("promptExpandInput") private var input = ""
    @AppStorage("promptExpandTarget") private var target: PromptExpandTarget = .image
    @AppStorage("promptExpandDetail") private var detail: ExpandDetail = .standard
    @AppStorage("promptExpandLanguage") private var language: ExpandLanguage = .chinese
    @AppStorage("promptExpandStyle") private var style: PromptStyle = .auto
    @AppStorage("promptExpandAspect") private var aspect: PromptAspect = .none
    @AppStorage("promptExpandNegative") private var includeNegative = true
    @AppStorage(AIDriveKeys.enabled) private var aiEnabled = false

    @State private var aiText = ""
    @State private var aiWorking = false
    @State private var aiError: String?

    private var options: PromptExpandOptions {
        PromptExpandOptions(
            target: target,
            detail: detail,
            language: language,
            style: style,
            aspect: aspect,
            includeNegative: includeNegative
        )
    }

    private var expansion: PromptExpansion {
        PromptExpander.expand(input, options: options)
    }

    /// 输出区实际显示：AI 开且成功生成用 AI 的；否则本地结果
    private var displayedText: String {
        if aiEnabled, aiError == nil { return aiText }
        return expansion.text
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                inputCard
                optionsCard
                if aiEnabled {
                    AIActionBar(
                        actionTitle: "AI 扩写",
                        isWorking: aiWorking,
                        errorText: aiError,
                        onRun: { runAI() }
                    )
                } else {
                    feedbackCard
                }
                outputPane
            }
            .padding(20)
        }
    }

    // MARK: - AI 生成

    private func runAI() {
        let snapshot = input
        guard !snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            aiError = "先写一句话，AI 才有得扩。"
            return
        }
        aiWorking = true
        aiError = nil
        aiText = ""
        let currentOptions = options
        Task {
            do {
                let config = try await AIClient.resolveConfig()
                let prompt = PromptAI.expand(snapshot, options: currentOptions)
                let raw = try await AIClient.complete(
                    provider: config.provider,
                    model: config.model,
                    system: prompt.system,
                    user: prompt.user,
                    temperature: 0.7,
                    maxTokens: 4096
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

    // MARK: - 输入

    private var inputCard: some View {
        ToolCard(title: "一句话", systemImage: "text.cursor") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TextField(target.placeholder, text: $input)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                        .frame(maxWidth: 520)

                    Button {
                        input = sample
                    } label: {
                        Text("示例").font(.system(size: 11.5))
                    }
                    .controlSize(.small)

                    if !input.isEmpty {
                        Button {
                            input = ""
                        } label: {
                            Text("清空").font(.system(size: 11.5))
                        }
                        .controlSize(.small)
                    }

                    Spacer(minLength: 0)
                }

                FlowRow(spacing: 6) {
                    ForEach(PromptExpandTarget.allCases) { item in
                        ChipButton(title: item.rawValue, isSelected: item == target) {
                            target = item
                        }
                    }
                }

                Text(target.note)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sample: String {
        switch target {
        case .image: return "一只橘猫在窗台上晒太阳"
        case .copywriting: return "给一款降噪耳机写小红书种草笔记"
        case .code: return "用 Python 读一个大 CSV，统计每列缺失值比例"
        case .slides: return "给团队做一次季度复盘汇报"
        case .video: return "三条讲清为什么天空是蓝色的"
        }
    }

    // MARK: - 选项

    private var optionsCard: some View {
        ToolCard(title: "补到什么程度", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 10) {
                optionRow("详细程度") {
                    ForEach(ExpandDetail.allCases) { item in
                        ChipButton(title: item.rawValue, isSelected: item == detail) {
                            detail = item
                        }
                    }
                }

                optionRow("语言") {
                    ForEach(ExpandLanguage.allCases) { item in
                        ChipButton(title: item.rawValue, isSelected: item == language) {
                            language = item
                        }
                    }
                }

                if target == .image {
                    imageOptions
                }

                Text(detail.note + "　" + language.note)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func optionRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            FlowRow(spacing: 6) {
                content()
            }
            Spacer(minLength: 0)
        }
    }

    private var imageOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            optionRow("风格") {
                styleMenu
                ForEach([PromptStyle.photo, .cinematic, .anime, .render3D], id: \.self) { item in
                    ChipButton(title: item.rawValue, isSelected: item == style) {
                        style = item
                    }
                }
            }

            optionRow("画幅") {
                ForEach(PromptAspect.allCases) { item in
                    ChipButton(title: item.rawValue, isSelected: item == aspect) {
                        aspect = item
                    }
                }
            }

            optionRow("负向") {
                Toggle("带上负向提示词", isOn: $includeNegative)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11.5))
            }
        }
    }

    private var styleMenu: some View {
        Menu {
            ForEach(PromptStyle.allCases) { item in
                Button {
                    style = item
                } label: {
                    if item == style {
                        Label(item.rawValue, systemImage: "checkmark")
                    } else {
                        Text(item.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 10))
                Text(style.rawValue)
                    .font(.system(size: 11.5))
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

    // MARK: - 提示

    @ViewBuilder
    private var feedbackCard: some View {
        if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ToolCard(title: "工具做了什么", systemImage: "questionmark.circle") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(PromptExpander.disclaimer)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !expansion.filled.isEmpty {
                        feedbackList("自动补齐", expansion.filled, systemImage: "wand.and.stars", tint: .green)
                    }
                    if !expansion.todo.isEmpty {
                        feedbackList("必须你自己定", expansion.todo, systemImage: "hand.point.right", tint: .orange)
                    }
                    if !expansion.notes.isEmpty {
                        feedbackList("留意", expansion.notes, systemImage: "info.circle", tint: .secondary)
                    }
                }
            }
        }
    }

    private func feedbackList(
        _ title: String,
        _ items: [String],
        systemImage: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
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

    // MARK: - 输出

    private var outputPane: some View {
        TextPane(
            title: aiEnabled ? "结构化提示词（AI 生成）" : "结构化提示词",
            text: Binding(
                get: { displayedText },
                set: { _ in }
            ),
            isEditable: false,
            placeholder: aiEnabled ? "写一句话，点上方「AI 扩写」；出错时这里显示本地结果" : "上面写一句话，这里就会出结构化结果",
            minHeight: 240,
            buttons: [
                PaneButton(systemImage: "doc.on.doc", help: "复制结果") {
                    NSPasteboard.copyString(displayedText)
                }
            ]
        )
    }
}
