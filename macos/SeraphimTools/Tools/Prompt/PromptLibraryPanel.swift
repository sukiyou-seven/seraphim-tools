import AppKit
import SwiftUI

/// 提示词模板库：本地存、分类、标签检索、变量填充、导入导出。
struct PromptLibraryPanel: View {
    @ObservedObject private var store = PromptStore.shared
    @AppStorage("promptKeyword") private var keyword = ""
    @AppStorage("promptCategoryFilter") private var categoryFilter = "all"
    @AppStorage("promptSort") private var sort: PromptEngine.PromptSort = .usage
    /// 展开的是哪一张卡。存下来是有用的——填到一半切走工具再回来，卡片还是开着的
    @AppStorage("promptExpandedID") private var expandedID = ""

    /// 变量填的值。键是「模板 id#变量名」，这样不同模板的同名变量不会串。
    @State private var values: [String: String] = [:]
    /// 填过的值也存一份，切走工具再回来不用重填
    @AppStorage("promptValuesJSON") private var valuesJSON = "{}"
    @State private var valuesLoaded = false
    @State private var editingID: UUID?
    @State private var draft = PromptTemplate(title: "", category: .custom, body: "")
    @State private var toast: String?
    @State private var importError: String?

    private var categoryFilterValue: PromptCategory? {
        categoryFilter == "all" ? nil : PromptCategory(rawValue: categoryFilter)
    }

    private var list: [PromptTemplate] {
        PromptEngine.search(store.templates, keyword: keyword, category: categoryFilterValue, sort: sort)
    }

    private var counts: [PromptCategory: Int] { PromptEngine.categoryCounts(store.templates) }
    private var tags: [(tag: String, count: Int)] { Array(PromptEngine.tagCounts(store.templates).prefix(14)) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                toolbarCard
                if let importError {
                    ErrorBanner(message: importError)
                }
                listSection
            }
            .padding(20)
        }
        .toast($toast)
        .onAppear {
            guard !valuesLoaded else { return }
            valuesLoaded = true
            if let data = valuesJSON.data(using: .utf8),
               let dict = try? JSONDecoder().decode([String: String].self, from: data) {
                values = dict
            }
        }
        .onChange(of: values) { _, newValue in
            guard valuesLoaded else { return }
            if let data = try? JSONEncoder().encode(newValue),
               let text = String(data: data, encoding: .utf8) {
                valuesJSON = text
            }
        }
    }

    // MARK: - 工具栏

    private var toolbarCard: some View {
        ToolCard(title: "模板库", systemImage: "square.stack.3d.up") {
            VStack(alignment: .leading, spacing: 12) {
                searchRow
                categoryRow
                if !tags.isEmpty {
                    tagRow
                }
            }
        }
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("搜标题、标签、正文内容", text: $keyword)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                if !keyword.isEmpty {
                    Button {
                        keyword = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
            .frame(maxWidth: 320)

            Text("\(list.count) / \(store.templates.count) 个")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer(minLength: 0)

            sortMenu
            moreMenu

            Button {
                startCreating()
            } label: {
                Label("新建", systemImage: "plus")
                    .font(.system(size: 11.5))
            }
            .controlSize(.small)
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(PromptEngine.PromptSort.allCases) { item in
                Button {
                    sort = item
                } label: {
                    if item == sort {
                        Label(item.rawValue, systemImage: "checkmark")
                    } else {
                        Text(item.rawValue)
                    }
                }
            }
            Divider()
            Button("清空使用计数") {
                store.resetUsage()
                toast = "排序还原成按修改时间"
            }
        } label: {
            Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                .font(.system(size: 11.5))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var moreMenu: some View {
        Menu {
            Button("导入模板…") { importTemplates() }
            Button("导出全部（JSON）…") { exportAll() }
            Button("导出全部（Markdown）…") { exportMarkdown() }
            Divider()
            Button("恢复内置示例模板") {
                let summary = store.restoreBuiltins()
                toast = summary.text
            }
        } label: {
            Label("导入导出", systemImage: "square.and.arrow.up.on.square")
                .font(.system(size: 11.5))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var categoryRow: some View {
        FlowRow(spacing: 6) {
            ChipButton(title: "全部 \(store.templates.count)", isSelected: categoryFilter == "all") {
                categoryFilter = "all"
            }
            ForEach(PromptCategory.allCases) { item in
                let count = counts[item] ?? 0
                ChipButton(
                    title: count > 0 ? "\(item.rawValue) \(count)" : item.rawValue,
                    isSelected: categoryFilter == item.rawValue,
                    isEnabled: count > 0 || categoryFilter == item.rawValue
                ) {
                    categoryFilter = item.rawValue
                }
            }
        }
    }

    private var tagRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("标签")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)

            FlowRow(spacing: 5) {
                ForEach(tags, id: \.tag) { item in
                    Button {
                        keyword = item.tag
                    } label: {
                        Text("\(item.tag) \(item.count)")
                            .font(.system(size: 10.5))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.10), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("按「\(item.tag)」筛选")
                }
            }
        }
    }

    // MARK: - 列表

    @ViewBuilder
    private var listSection: some View {
        if store.isEmpty {
            emptyCard(
                title: "模板库是空的",
                message: "点右上角「新建」自己攒一个，或者从「导入导出」里恢复内置示例——里面按 AI 绘图 / 文案 / 代码 / PPT / 短视频脚本分好了类。"
            )
        } else if list.isEmpty {
            emptyCard(
                title: "没有匹配的模板",
                message: keyword.isEmpty
                    ? "这个分类下还没有模板。"
                    : "换个关键词试试，或者把分类切回「全部」。搜索会在标题、标签、正文和说明里一起找。"
            )
        } else {
            ForEach(list) { template in
                PromptTemplateCard(
                    template: template,
                    values: $values,
                    toast: $toast,
                    editingID: $editingID,
                    expandedID: $expandedID,
                    draft: $draft,
                    onStartEdit: {
                        draft = template
                        editingID = template.id
                    }
                )
            }
        }
    }

    private func emptyCard(title: String, message: String) -> some View {
        ToolCard(title: "提示", systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 动作

    private func startCreating() {
        draft = PromptTemplate(title: "", category: categoryFilterValue ?? .custom, body: "")
        editingID = draft.id
        categoryFilter = "all"
        keyword = ""
        toast = "填完标题和正文点保存"
    }

    private func importTemplates() {
        guard let url = FilePicker.pick(title: "导入提示词模板") else { return }
        do {
            let data = try Data(contentsOf: url)
            let templates = try PromptEngine.decodeImport(data)
            let summary = store.importTemplates(templates)
            importError = nil
            toast = summary.text
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            importError = "导入失败：\(message)"
        }
    }

    private func exportAll() {
        guard !store.templates.isEmpty else {
            importError = "模板库是空的，没有可导出的内容。"
            return
        }
        do {
            let data = try PromptEngine.exportData(store.templates)
            guard let text = String(data: data, encoding: .utf8) else { return }
            if FilePicker.saveText(text, suggestedName: "prompt-templates.json") != nil {
                importError = nil
                toast = "已导出 \(store.templates.count) 个模板"
            }
        } catch {
            importError = "导出失败：\(error.localizedDescription)"
        }
    }

    private func exportMarkdown() {
        guard !store.templates.isEmpty else {
            importError = "模板库是空的，没有可导出的内容。"
            return
        }
        if FilePicker.saveText(PromptEngine.exportMarkdown(store.templates),
                               suggestedName: "prompt-templates.md") != nil {
            importError = nil
            toast = "已导出 Markdown"
        }
    }
}

// MARK: - 单张模板卡

private struct PromptTemplateCard: View {
    let template: PromptTemplate
    @Binding var values: [String: String]
    @Binding var toast: String?
    @Binding var editingID: UUID?
    @Binding var expandedID: String
    @Binding var draft: PromptTemplate
    let onStartEdit: () -> Void

    @ObservedObject private var store = PromptStore.shared

    private var isEditing: Bool { editingID == template.id }
    private var expanded: Bool { expandedID == template.id.uuidString }

    private func toggleExpanded() {
        withAnimation(.easeInOut(duration: 0.18)) {
            expandedID = expanded ? "" : template.id.uuidString
        }
    }

    private var variables: [String] { PromptEngine.variables(in: template.body) }

    private func key(_ name: String) -> String { "\(template.id.uuidString)#\(name)" }

    private func value(for name: String) -> Binding<String> {
        Binding(
            get: { values[key(name)] ?? "" },
            set: { values[key(name)] = $0 }
        )
    }

    private var filled: String {
        var map: [String: String] = [:]
        for name in variables { map[name] = values[key(name)] ?? "" }
        return PromptEngine.fill(template.body, values: map)
    }

    private var missing: [String] {
        var map: [String: String] = [:]
        for name in variables { map[name] = values[key(name)] ?? "" }
        return PromptEngine.missingValues(in: template.body, values: map)
    }

    var body: some View {
        ToolCard {
            if isEditing {
                PromptTemplateEditor(draft: $draft, isNew: !store.contains(id: template.id)) {
                    store.insert(draft)
                    editingID = nil
                    toast = "已新建「\(draft.title)」"
                } onSave: {
                    store.update(draft)
                    editingID = nil
                    toast = "已保存"
                } onCancel: {
                    editingID = nil
                }
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if expanded {
                Divider().opacity(0.4)
                detail
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                toggleExpanded()
            } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }
            .buttonStyle(.borderless)

            Button {
                toggleExpanded()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(template.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)
                        if template.isBuiltin {
                            NoticeTag(text: "内置", systemImage: "bookmark", tint: .secondary)
                        }
                    }
                    Text(PromptEngine.preview(template.body, limit: 76))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            ForEach(Array(template.displayTags.prefix(4)), id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 10))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                    .foregroundStyle(.secondary)
            }

            NoticeTag(text: template.category.rawValue, systemImage: template.category.systemImage, tint: .accentColor)

            if !variables.isEmpty {
                NoticeTag(text: "\(variables.count) 个变量", systemImage: "curlybraces", tint: .orange)
            }

            if template.useCount > 0 {
                Text("用过 \(template.useCount) 次")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            CopyIconButton(text: template.body, help: "复制原文")

            Menu {
                Button("编辑") { onStartEdit() }
                Button("复刻一份") {
                    store.duplicate(id: template.id)
                    toast = "已复刻"
                }
                Button("导出这一个…") { exportOne() }
                Divider()
                Button("删除", role: .destructive) {
                    store.remove(id: template.id)
                    toast = "已删除「\(template.title)」"
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !template.note.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .padding(.top, 2)
                    Text(template.note)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }

            if !variables.isEmpty {
                variableInputs
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("填充结果")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(PromptStats.measure(filled).brief)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    if !missing.isEmpty {
                        NoticeTag(text: "还有 \(missing.count) 个没填", systemImage: "exclamationmark.circle", tint: .orange)
                    }
                }

                Text(filled)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10))
                    )
            }

            HStack(spacing: 10) {
                Button {
                    NSPasteboard.copyString(filled)
                    store.markUsed(id: template.id)
                    toast = missing.isEmpty ? "已复制，可直接粘给 AI" : "已复制（\(missing.count) 个变量还是占位符）"
                } label: {
                    Label("复制填充结果", systemImage: "doc.on.doc").font(.system(size: 11.5))
                }
                .controlSize(.small)

                Button {
                    for name in variables { values[key(name)] = "" }
                } label: {
                    Text("清空变量").font(.system(size: 11.5))
                }
                .controlSize(.small)
                .disabled(variables.isEmpty)

                Spacer(minLength: 0)
            }
        }
        .padding(.leading, 20)
    }

    private var variableInputs: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("变量")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            ForEach(variables, id: \.self) { name in
                HStack(spacing: 8) {
                    Text("{{\(name)}}")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.orange)
                        .frame(width: 150, alignment: .leading)
                        .lineLimit(1)
                    TextField("填这里", text: value(for: name))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(maxWidth: 420)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func exportOne() {
        let single = [template]
        guard let data = try? PromptEngine.exportData(single),
              let text = String(data: data, encoding: .utf8) else { return }
        let name = template.title.replacingOccurrences(of: "/", with: "-") + ".json"
        if FilePicker.saveText(text, suggestedName: name) != nil {
            toast = "已导出「\(template.title)」"
        }
    }
}

// MARK: - 编辑器

private struct PromptTemplateEditor: View {
    @Binding var draft: PromptTemplate
    let isNew: Bool
    let onInsert: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var tagsText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(isNew ? "新建模板" : "编辑模板")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if !isNew {
                    NoticeTag(text: "改动会立刻覆盖原模板", systemImage: "exclamationmark.triangle", tint: .orange)
                }
            }

            HStack(spacing: 10) {
                TextField("标题", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5))
                    .frame(maxWidth: 260)

                Menu {
                    ForEach(PromptCategory.allCases) { item in
                        Button {
                            draft.category = item
                        } label: {
                            if item == draft.category {
                                Label(item.rawValue, systemImage: "checkmark")
                            } else {
                                Text(item.rawValue)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: draft.category.systemImage)
                            .font(.system(size: 10))
                        Text(draft.category.rawValue)
                            .font(.system(size: 11.5))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                TextField("标签，用逗号分隔", text: $tagsText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(maxWidth: 240)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("正文")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("用 {{变量名}} 做占位符，保存后会自动生成对应的输入框")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    if PromptEngine.hasUnbalancedBraces(draft.body) {
                        NoticeTag(text: "花括号不配对", systemImage: "exclamationmark.triangle", tint: .orange)
                    }
                }

                TextEditor(text: $draft.body)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 150)
                    .background(
                        Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10))
                    )
            }

            TextField("说明 / 使用注意（选填）", text: $draft.note)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            if !PromptEngine.variables(in: draft.body).isEmpty {
                HStack(spacing: 6) {
                    Text("识别到")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    ForEach(PromptEngine.variables(in: draft.body), id: \.self) { name in
                        Text(name)
                            .font(.system(size: 10.5, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 10) {
                Button {
                    commit()
                } label: {
                    Label(isNew ? "保存" : "保存修改", systemImage: "checkmark").font(.system(size: 11.5))
                }
                .controlSize(.small)
                .disabled(draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    onCancel()
                } label: {
                    Text("取消").font(.system(size: 11.5))
                }
                .controlSize(.small)

                Spacer(minLength: 0)
            }
        }
        .onAppear {
            tagsText = draft.displayTags.joined(separator: ", ")
        }
    }

    private func commit() {
        if draft.title.trimmingCharacters(in: .whitespaces).isEmpty {
            draft.title = PromptEngine.suggestTitle(from: draft.body)
        }
        draft.tags = tagsText
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if isNew {
            onInsert()
        } else {
            onSave()
        }
    }
}
