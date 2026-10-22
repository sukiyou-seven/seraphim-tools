import AppKit
import SwiftUI

/// 正则：边写边看匹配，带模板库和语法速查。
struct RegexToolView: View {
    @AppStorage("regexPattern") private var pattern = ""
    @AppStorage("regexText") private var text = ""
    @AppStorage("regexTemplate") private var template = ""

    @State private var options = RegexOptions()
    @State private var matches: [RegexMatchInfo] = []
    @State private var segments: [RegexSegment] = []
    @State private var patternInfo: RegexEngine.PatternInfo?
    @State private var errorMessage: String?
    @State private var toast: String?
    @State private var showCheatsheet = false

    private let displayLimit = 300

    private var taskKey: String {
        "\(pattern)|\(options.flagLetters)|\(text.count)|\(text.hashValue)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                patternCard
                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }
                textCard
                resultCard
                replaceCard
                snippetCard
                if showCheatsheet {
                    cheatsheetCard
                }
            }
            .padding(20)
        }
        .toast($toast)
        .task(id: taskKey) {
            recompute()
        }
    }

    // MARK: - 表达式

    private var patternCard: some View {
        ToolCard(title: "正则表达式", systemImage: "text.magnifyingglass") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("/")
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    TextField("输入正则，比如 \\d{3}-\\d{4}", text: $pattern)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                    Text("/\(options.flagLetters)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                    Button {
                        if let string = NSPasteboard.general.string(forType: .string) {
                            pattern = string.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderless)
                    .help("粘贴")
                    Button {
                        pattern = ""
                        text = ""
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("清空")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(errorMessage == nil ? Color.primary.opacity(0.12) : Color.orange.opacity(0.6))
                )

                FlowRow(spacing: 8) {
                    flagToggle("i", "忽略大小写", $options.ignoreCase)
                    flagToggle("m", "多行（^ $ 匹配行首尾）", $options.anchorsMatchLines)
                    flagToggle("s", "点匹配换行", $options.dotMatchesLineSeparators)
                    flagToggle("x", "忽略空白与注释", $options.allowCommentsAndWhitespace)
                    flagToggle("w", "Unicode 词边界", $options.unicodeWordBoundaries)
                }

                HStack(spacing: 10) {
                    if let patternInfo {
                        Text("捕获分组 \(patternInfo.captureGroups) 个")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        if !patternInfo.namedGroups.isEmpty {
                            Text("命名分组：\(patternInfo.namedGroups.map { "$\($0)" }.joined(separator: " "))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        if patternInfo.hasLookaround {
                            NoticeTag(text: "含前后顾", systemImage: "eye.trianglebadge.exclamationmark", tint: .blue)
                        }
                    }
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { showCheatsheet.toggle() }
                    } label: {
                        Label(showCheatsheet ? "收起语法" : "语法速查", systemImage: "book")
                            .font(.system(size: 11.5))
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func flagToggle(_ letter: String, _ help: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            HStack(spacing: 5) {
                Text(letter)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(binding.wrappedValue ? Color.accentColor : .secondary)
                Text(help)
                    .font(.system(size: 11))
            }
        }
        .toggleStyle(.checkbox)
    }

    // MARK: - 测试文本

    private var textCard: some View {
        TextPane(
            title: "测试文本",
            text: $text,
            placeholder: "把要被匹配的文本贴到这里…",
            minHeight: 150,
            buttons: [
                PaneButton(systemImage: "doc.on.clipboard", help: "从剪贴板粘贴") {
                    if let string = NSPasteboard.general.string(forType: .string) {
                        text = string
                    } else {
                        toast = "剪贴板里没有文本"
                        NSSound.beep()
                    }
                },
                PaneButton(systemImage: "trash", help: "清空") { text = "" },
            ]
        )
    }

    // MARK: - 匹配结果

    private var resultCard: some View {
        ToolCard(title: "匹配结果", systemImage: "checklist") {
            if pattern.isEmpty {
                Text("写上正则，这里会立刻显示匹配结果。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if text.isEmpty {
                Text("上面填一段测试文本就能看到匹配了。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Text("命中 \(matches.count) 处")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(matches.isEmpty ? Color.secondary : Color.accentColor)
                        if matches.count > displayLimit {
                            NoticeTag(text: "列表只展示前 \(displayLimit) 条", systemImage: "list.number", tint: .orange)
                        }
                        Spacer(minLength: 0)
                        CopyIconButton(text: matches.map(\.text).joined(separator: "\n"), help: "复制全部命中内容")
                    }

                    highlighted

                    if !matches.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(matches.prefix(displayLimit))) { match in
                                matchRow(match)
                            }
                        }
                    }
                }
            }
        }
    }

    private var highlighted: some View {
        ScrollView {
            Text(highlightedText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(minHeight: 90, maxHeight: 280)
        .background(
            Color(nsColor: .textBackgroundColor),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10))
        )
    }

    private var highlightedText: AttributedString {
        var result = AttributedString()
        let baseFont = Font.system(size: 12.5, design: .monospaced)

        for segment in segments {
            var piece = AttributedString(segment.text)
            piece.font = baseFont
            if segment.isMatch {
                piece.backgroundColor = Color.accentColor.opacity(0.26)
                piece.foregroundColor = .primary
                piece.inlinePresentationIntent = .stronglyEmphasized
            } else {
                piece.foregroundColor = .secondary
            }
            result += piece
        }

        if result.characters.isEmpty {
            result = AttributedString(text.isEmpty ? "" : text)
        }
        return result
    }

    private func matchRow(_ match: RegexMatchInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("#\(match.id)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 30, alignment: .leading)
                Text(match.text.isEmpty ? "（空匹配）" : match.text)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2)
                    .textSelection(.enabled)
                Spacer(minLength: 6)
                Text("位置 \(match.rangeText)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                CopyIconButton(text: match.text)
            }

            if !match.groups.isEmpty {
                FlowRow(spacing: 6) {
                    ForEach(match.groups) { group in
                        HStack(spacing: 4) {
                            Text("$\(group.id)")
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Text(group.text ?? "未参与")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(group.isEmpty ? .tertiary : .primary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.05), in: Capsule())
                    }
                }
                .padding(.leading, 38)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.028))
        )
    }

    // MARK: - 替换

    private var replaceCard: some View {
        ToolCard(title: "替换预览", systemImage: "arrow.triangle.swap") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("替换为")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("用 $1 引用分组，\\n 换行", text: $template)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5, design: .monospaced))
                        .frame(maxWidth: 340)
                    Spacer(minLength: 0)
                }

                FlowRow(spacing: 6) {
                    ForEach(RegexLibrary.templateTokens) { token in
                        Button {
                            template += token.token
                        } label: {
                            HStack(spacing: 4) {
                                Text(token.token)
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                Text(token.meaning)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.05), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("点击追加到替换模板")
                    }
                }

                if let outcome = replacement {
                    HStack(spacing: 8) {
                        Text("替换后共 \(outcome.count) 处生效")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        CopyIconButton(text: outcome.output, help: "复制替换结果")
                    }
                    Text(outcome.output.isEmpty ? "（空）" : outcome.output)
                        .font(.system(size: 12.5, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(
                            Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.10))
                        )
                } else {
                    Text("填上替换内容，这里实时给出结果；留空就是删掉匹配到的部分。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var replacement: RegexEngine.ReplaceOutcome? {
        guard !pattern.isEmpty, !text.isEmpty else { return nil }
        return try? RegexEngine.replace(in: text, pattern: pattern, options: options, template: template)
    }

    // MARK: - 模板库

    private var snippetCard: some View {
        ToolCard(title: "常用模板", systemImage: "square.stack.3d.up") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(RegexLibrary.categories, id: \.self) { category in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(category)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)

                        FlowRow(spacing: 6) {
                            ForEach(RegexLibrary.snippets(in: category)) { snippet in
                                Button {
                                    apply(snippet)
                                } label: {
                                    Text(snippet.title)
                                        .font(.system(size: 11.5))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.primary.opacity(0.06), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .help(snippet.note)
                            }
                        }
                    }
                }
            }
        }
    }

    private func apply(_ snippet: RegexSnippet) {
        pattern = snippet.pattern
        if text.isEmpty || text == lastSample {
            text = snippet.sample
            lastSample = snippet.sample
        }
        toast = "已套用「\(snippet.title)」"
    }

    // MARK: - 语法速查

    private var cheatsheetCard: some View {
        ToolCard(title: "语法速查", systemImage: "book") {
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 8)], spacing: 6) {
                    ForEach(RegexLibrary.tokens) { token in
                        Button {
                            pattern += token.token
                        } label: {
                            HStack(spacing: 8) {
                                Text(token.token)
                                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 64, alignment: .leading)
                                Text(token.meaning)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                            )
                        }
                        .buttonStyle(.plain)
                        .help("点击插入")
                    }
                }
            }
        }
    }

    // MARK: - 计算

    @State private var lastSample = ""

    private func recompute() {
        guard !pattern.isEmpty else {
            matches = []
            segments = []
            patternInfo = nil
            errorMessage = nil
            return
        }

        do {
            patternInfo = try RegexEngine.info(pattern, options: options)
            let found = try RegexEngine.matches(in: text, pattern: pattern, options: options)
            matches = found
            segments = found.isEmpty ? [] : RegexEngine.segments(in: text, matches: found)
            errorMessage = nil
        } catch {
            matches = []
            segments = []
            patternInfo = nil
            errorMessage = error.localizedDescription
        }
    }
}
