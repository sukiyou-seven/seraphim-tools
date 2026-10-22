import AppKit
import SwiftUI

/// 提示词压缩：删掉没信息量的部分，换回 token。
/// AI 驱动开 = 结果由模型产出（还能理解语义，删得更准）；关 = 本地规则，零联网。
struct PromptCompressPanel: View {
    @AppStorage("promptCompressSource") private var source = ""
    @AppStorage("promptCompressGroups") private var groupsRaw = "politeness,filler,verbose,duplicate,whitespace"
    @AppStorage(AIDriveKeys.enabled) private var aiEnabled = false

    @State private var result = PromptCompressionResult()
    @State private var working = false
    @State private var aiText = ""
    @State private var aiWorking = false
    @State private var aiError: String?

    /// AI 开时输出区实际显示的内容：生成过用 AI 的，失败或没生成时回退本地规则结果
    private var displayedText: String {
        if aiEnabled, aiError == nil { return aiText }
        return result.text
    }

    private var enabledGroups: Set<CompressionGroup> {
        Set(groupsRaw.split(separator: ",").compactMap { CompressionGroup.group(storageKey: String($0)) })
    }

    /// 任务键：原文或开关一变就重算，中间的连续输入会被取消掉
    private var computeKey: String { "\(groupsRaw)\u{1}\(source)" }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                AIDriveCard()
                optionsCard
                inputPane
                if aiEnabled {
                    aiActionBar
                } else {
                    statsCard
                }
                outputPane
            }
            .padding(20)
        }
        .task(id: computeKey) {
            await recompute()
        }
    }

    // MARK: - AI 生成

    private var aiActionBar: some View {
        AIActionBar(
            actionTitle: "AI 压缩",
            isWorking: aiWorking,
            errorText: aiError,
            onRun: { runAI() }
        )
    }

    private func runAI() {
        let snapshot = source
        guard !snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            aiError = "先在左边贴一段提示词，AI 才有得压。"
            return
        }
        aiWorking = true
        aiError = nil
        aiText = ""
        Task {
            do {
                let config = try await AIClient.resolveConfig()
                // 分组开关只管本地规则；AI 模式的删减标准写在 system 里，判断交给模型
                let prompt = PromptAI.compress(snapshot, allowedGroups: [])
                let raw = try await AIClient.complete(
                    provider: config.provider,
                    model: config.model,
                    system: prompt.system,
                    user: prompt.user,
                    temperature: 0.4,
                    maxTokens: 2048
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

    // MARK: - 选项

    private var optionsCard: some View {
        ToolCard(title: "压缩什么", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 10) {
                FlowRow(spacing: 6) {
                    ForEach(CompressionGroup.allCases) { group in
                        ChipButton(
                            title: group.rawValue,
                            isSelected: enabledGroups.contains(group),
                            isEnabled: true
                        ) {
                            toggle(group)
                        }
                    }
                }

                Text("只删「删了不影响模型理解」的东西：套话、垫词、冗长表达、重复、多余空白。代码块、引号里的内容和 {{变量}} 整段保留，一个字符都不动。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func toggle(_ group: CompressionGroup) {
        var next = enabledGroups
        if next.contains(group) {
            next.remove(group)
        } else {
            next.insert(group)
        }
        groupsRaw = CompressionGroup.allCases
            .filter { next.contains($0) }
            .map(\.storageKey)
            .joined(separator: ",")
    }

    // MARK: - 输入

    private var inputPane: some View {
        TextPane(
            title: "原文",
            text: $source,
            isEditable: true,
            placeholder: "把写长的提示词贴进来。比如「你好，麻烦你帮我写一个函数，需要注意的是要进行输入校验，谢谢」",
            minHeight: 170,
            buttons: [
                PaneButton(systemImage: "sparkles", help: "填一段示例") { loadSample() },
                PaneButton(systemImage: "trash", help: "清空") { source = "" },
            ]
        )
    }

    private func loadSample() {
        source = """
        你好，麻烦你帮我写一个数据清洗脚本，非常感谢。

        我的需求是：读取一个 CSV 文件，然后进行缺失值的统计。需要注意的是要进行分块处理，
        与此同时还要把结果输出成表格。在文件很大的时候，如果内存不足，希望能给出提示。

        请务必写出完整可运行的代码，谢谢！
        """
    }

    // MARK: - 统计

    private var statsCard: some View {
        ToolCard(title: "压缩结果", systemImage: "chart.bar") {
            VStack(alignment: .leading, spacing: 12) {
                metricsRow
                if working {
                    Text("正在算…")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                } else if result.isEmptyResult {
                    Text("左边贴一段提示词，这里会实时给出压缩结果和削减明细。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                } else if result.hits.isEmpty {
                    NoticeTag(text: "没找到可精简的内容，这段已经挺干净了", systemImage: "checkmark.seal", tint: .green)
                } else {
                    hitList
                }
            }
        }
    }

    private var metricsRow: some View {
        HStack(spacing: 22) {
            metric("字符", result.deltaText)
            metric("削减", result.percentText)
            metric("token", result.tokenText)
            metric("命中", result.totalHits > 0 ? "\(result.totalHits) 处" : "—")
            Spacer(minLength: 0)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
        }
    }

    private var hitList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(result.hits) { hit in
                HStack(spacing: 8) {
                    Image(systemName: hit.group.systemImage)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 14)
                    Text(hit.title)
                        .font(.system(size: 11.5))
                    Spacer(minLength: 8)
                    Text("×\(hit.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                )
            }
        }
    }

    // MARK: - 输出

    private var outputPane: some View {
        TextPane(
            title: aiEnabled ? "压缩后（AI 生成）" : "压缩后",
            text: Binding(
                get: { displayedText },
                set: { _ in }
            ),
            isEditable: false,
            placeholder: aiEnabled ? "点上方「AI 压缩」生成；出错时这里会显示本地规则的结果" : "压缩结果会出现在这里",
            minHeight: 170,
            buttons: [
                PaneButton(systemImage: "doc.on.doc", help: "复制结果") {
                    NSPasteboard.copyString(displayedText)
                }
            ]
        )
    }

    // MARK: - 计算

    private func recompute() async {
        let snapshot = source
        let groups = enabledGroups
        guard !snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            result = PromptCompressionResult()
            working = false
            return
        }
        working = true
        // 敲字的时候别每一下都算一遍：规则有三十来条，长文本上还是会卡的
        try? await Task.sleep(nanoseconds: 160_000_000)
        if Task.isCancelled { return }
        let computed = await Task.detached(priority: .userInitiated) {
            PromptCompressor.compress(snapshot, enabled: groups)
        }.value
        if Task.isCancelled { return }
        result = computed
        working = false
    }
}
