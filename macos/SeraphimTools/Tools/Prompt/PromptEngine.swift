import Foundation

/// 提示词模板的引擎：变量解析与填充、检索、导入导出。
///
/// 全是纯函数，可以脱离界面单独测。
enum PromptEngine {

    // MARK: - 变量

    /// 变量占位符：`{{主题}}`、`{{ 主题 }}` 都认（内部空白会被 trim）。
    /// 里面不允许再出现花括号，所以 `{{a{{b}}}}` 这种畸形写法不会误伤。
    private static let placeholderRegex = try! NSRegularExpression(
        pattern: "\\{\\{\\s*([^{}]+?)\\s*\\}\\}"
    )

    private static func matches(in text: String) -> [NSTextCheckingResult] {
        placeholderRegex.matches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        )
    }

    /// 按出现顺序列出变量名，重复的只留一次
    static func variables(in body: String) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for match in matches(in: body) {
            guard let range = Range(match.range(at: 1), in: body) else { continue }
            let name = String(body[range])
            guard !name.isEmpty, !seen.contains(name) else { continue }
            seen.insert(name)
            result.append(name)
        }
        return result
    }

    /// 填充变量。没给值的默认保留占位符——留着才能一眼看出哪里还没填。
    static func fill(_ body: String, values: [String: String], keepUnfilled: Bool = true) -> String {
        let all = matches(in: body)
        guard !all.isEmpty else { return body }

        var result = body
        // 从后往前替换，前面的 range 才不会失效
        for match in all.reversed() {
            guard let full = Range(match.range(at: 0), in: result),
                  let nameRange = Range(match.range(at: 1), in: result) else { continue }
            let name = String(result[nameRange])
            guard let value = values[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                if !keepUnfilled { result.replaceSubrange(full, with: "") }
                continue
            }
            result.replaceSubrange(full, with: value)
        }
        return result
    }

    /// 还有哪些变量没填
    static func missingValues(in body: String, values: [String: String]) -> [String] {
        variables(in: body).filter {
            (values[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
        }
    }

    /// 正文里冒出过、但用户没声明成变量的花括号写法（提示用，不算错误）
    static func hasUnbalancedBraces(_ body: String) -> Bool {
        let opens = body.components(separatedBy: "{{").count - 1
        let closes = body.components(separatedBy: "}}").count - 1
        return opens != closes
    }

    // MARK: - 检索

    enum PromptSort: String, CaseIterable, Identifiable, Sendable {
        case usage = "常用优先"
        case recent = "最近修改"
        case title = "按标题"

        var id: String { rawValue }
    }

    /// 关键词按空格拆成多个词，要求全部命中（AND），那样比任一命中准得多。
    /// 匹配范围是标题 + 标签 + 正文 + 说明。
    static func search(
        _ templates: [PromptTemplate],
        keyword: String,
        category: PromptCategory? = nil,
        sort: PromptSort = .usage
    ) -> [PromptTemplate] {
        let words = keyword
            .lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "\u{3000}" || $0 == "," })
            .map(String.init)
            .filter { !$0.isEmpty }

        var list = templates.filter { template in
            if let category, template.category != category { return false }
            guard !words.isEmpty else { return true }
            let index = template.searchIndex
            return words.allSatisfy { index.contains($0) }
        }

        switch sort {
        case .usage:
            list.sort { lhs, rhs in
                if lhs.useCount != rhs.useCount { return lhs.useCount > rhs.useCount }
                return lhs.updatedAt > rhs.updatedAt
            }
        case .recent:
            list.sort { $0.updatedAt > $1.updatedAt }
        case .title:
            list.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        return list
    }

    /// 全部标签，按出现次数排序（界面上做标签云用）
    static func tagCounts(_ templates: [PromptTemplate]) -> [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for template in templates {
            for tag in template.displayTags {
                counts[tag, default: 0] += 1
            }
        }
        return counts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .map { (tag: $0.key, count: $0.value) }
    }

    /// 每个分类各有多少个模板（分类 chips 上的角标）
    static func categoryCounts(_ templates: [PromptTemplate]) -> [PromptCategory: Int] {
        var counts: [PromptCategory: Int] = [:]
        for template in templates {
            counts[template.category, default: 0] += 1
        }
        return counts
    }

    // MARK: - 导入导出

    static func exportData(_ templates: [PromptTemplate]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(PromptExportFile(templates: templates))
    }

    /// 导出成一段可以直接贴出去的纯文本（markdown 清单）
    static func exportMarkdown(_ templates: [PromptTemplate]) -> String {
        var lines: [String] = ["# 提示词模板", ""]
        for category in PromptCategory.ordered {
            let group = templates.filter { $0.category == category }
            guard !group.isEmpty else { continue }
            lines.append("## \(category.rawValue)")
            lines.append("")
            for template in group {
                let tags = template.displayTags.isEmpty ? "" : "　`\(template.displayTags.joined(separator: "` `"))`"
                lines.append("### \(template.title)\(tags)")
                lines.append("")
                if !template.note.isEmpty {
                    lines.append("> \(template.note)")
                    lines.append("")
                }
                lines.append("```text")
                lines.append(template.body)
                lines.append("```")
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 解码导入文件。三种形态都收：完整的导出文件、裸数组、单个模板对象。
    /// 这样用户从别人那儿拿到什么格式基本都能塞进来。
    static func decodeImport(_ data: Data) throws -> [PromptTemplate] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let file = try? decoder.decode(PromptExportFile.self, from: data) {
            return file.templates
        }
        if let list = try? decoder.decode([PromptTemplate].self, from: data) {
            return list
        }
        if let single = try? decoder.decode(PromptTemplate.self, from: data) {
            return [single]
        }

        // 日期不是 ISO8601（有些手写文件直接写数字）时再试一次
        let loose = JSONDecoder()
        loose.dateDecodingStrategy = .secondsSince1970
        if let file = try? loose.decode(PromptExportFile.self, from: data) { return file.templates }
        if let list = try? loose.decode([PromptTemplate].self, from: data) { return list }

        throw PromptImportError.unrecognized
    }

    enum PromptImportError: LocalizedError {
        case unrecognized

        var errorDescription: String? {
            switch self {
            case .unrecognized:
                return "认不出这个文件。要的是本工具导出的 .json，或者一个模板对象 / 模板数组。"
            }
        }
    }

    /// 合并去重：同标题同分类算重复。返回新的完整列表。
    static func merge(
        _ incoming: [PromptTemplate],
        into existing: [PromptTemplate]
    ) -> (list: [PromptTemplate], summary: PromptImportSummary) {
        var keys = Set(existing.map(\.dedupeKey))
        var list = existing
        var summary = PromptImportSummary()
        summary.total = incoming.count

        for template in incoming {
            var candidate = template
            // 老版本导出可能没有 id/时间戳，补上
            if candidate.title.trimmingCharacters(in: .whitespaces).isEmpty { candidate.title = "未命名模板" }
            if keys.contains(candidate.dedupeKey) {
                summary.skipped += 1
                continue
            }
            keys.insert(candidate.dedupeKey)
            candidate.updatedAt = Date()
            list.append(candidate)
            summary.added += 1
        }
        return (list, summary)
    }

    // MARK: - 杂项

    static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3000...0x303F,   // 中文标点
             0x3400...0x4DBF,   // 扩展 A
             0x4E00...0x9FFF,   // 基本区
             0xF900...0xFAFF,   // 兼容表意
             0xFF00...0xFFEF:   // 全角
            return true
        default:
            return false
        }
    }

    /// 只看汉字本身，不含中文标点。判重和取词时用这个，
    /// 否则「改这个。」和「改这个！」会被当成两句不同的话。
    static func isIdeograph(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }

    /// 把一段文字折成"前 N 字 + …"，列表里预览用
    static func preview(_ text: String, limit: Int = 90) -> String {
        let flat = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit)) + "…"
    }

    /// 从正文里猜一个标题（新建模板时不填标题也能有名字）
    static func suggestTitle(from body: String) -> String {
        let firstLine = body
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        var title = firstLine.trimmingCharacters(in: .whitespaces)
        title = title.replacingOccurrences(of: "#", with: "")
        // 去掉变量占位符，只留骨架文字
        title = title.replacingOccurrences(of: "\\{\\{[^{}]*\\}\\}", with: "", options: .regularExpression)
        title = title.trimmingCharacters(in: .whitespaces)
        if title.isEmpty { return "未命名模板" }
        return String(title.prefix(24))
    }
}
