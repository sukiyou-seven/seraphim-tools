import Foundation

// MARK: - 分组

/// 压缩规则的用途分组。界面上按组开关——有人就是想把「其实」留着，
/// 让他能单独关掉那一类，而不是整体放弃压缩。
enum CompressionGroup: String, CaseIterable, Identifiable, Sendable {
    case politeness = "礼貌套话与致谢"
    case filler = "语气垫词"
    case verbose = "冗长表达"
    case duplicate = "重复内容"
    case whitespace = "空白与标点"

    var id: String { rawValue }

    /// 存偏好用的稳定键。rawValue 是给人看的中文文案，文案会改，
    /// 存储键不能跟着变——不然老用户升级后所有分组开关都会静默失灵。
    var storageKey: String {
        switch self {
        case .politeness: return "politeness"
        case .filler: return "filler"
        case .verbose: return "verbose"
        case .duplicate: return "duplicate"
        case .whitespace: return "whitespace"
        }
    }

    static func group(storageKey: String) -> CompressionGroup? {
        allCases.first { $0.storageKey == storageKey }
    }

    var systemImage: String {
        switch self {
        case .politeness: return "hand.wave"
        case .filler: return "ellipsis.bubble"
        case .verbose: return "text.redaction"
        case .duplicate: return "doc.on.doc"
        case .whitespace: return "space"
        }
    }

    var note: String {
        switch self {
        case .politeness: return "「请帮我」「谢谢」「麻烦你」——删了不影响模型理解任务"
        case .filler: return "「其实」「基本上」「可以说」——没有信息量的语气词"
        case .verbose: return "「进行优化」→「优化」「由于这个原因」→「因此」"
        case .duplicate: return "同一句话说了两遍，只留第一遍"
        case .whitespace: return "多余空行、行尾空格、叠起来的标点"
        }
    }
}

// MARK: - 命中记录

struct CompressionHit: Identifiable, Sendable {
    let id: String
    let group: CompressionGroup
    let title: String
    var count: Int
}

// MARK: - 结果

struct PromptCompressionResult: Sendable {
    var text = ""
    var hits: [CompressionHit] = []
    var before = PromptStats()
    var after = PromptStats()
    var rounds = 0
    /// 规则互相影响时可能需要多跑几轮；跑不收敛说明有规则在打架
    var converged = true

    var savedCharacters: Int { max(0, before.characters - after.characters) }
    var savedTokens: Int { max(0, before.estimatedTokens - after.estimatedTokens) }

    var savedPercent: Double {
        guard before.characters > 0 else { return 0 }
        return Double(savedCharacters) / Double(before.characters) * 100
    }

    var totalHits: Int { hits.reduce(0) { $0 + $1.count } }

    var isEmptyResult: Bool { before.characters == 0 }
    var changed: Bool { savedCharacters > 0 }

    /// "1280 → 860 字符"
    var deltaText: String { "\(before.characters) → \(after.characters) 字符" }

    var percentText: String {
        guard before.characters > 0 else { return "—" }
        if savedCharacters == 0 { return "没有可精简的内容" }
        return String(format: "省 %.0f%%", savedPercent)
    }

    var tokenText: String { "≈ \(before.estimatedTokens) → \(after.estimatedTokens) token" }
}

// MARK: - 引擎

/// 规则式压缩。
///
/// 只做「明显没有信息量」的删减：套话、垫词、冗长表达、重复、空白。
/// 任何需要理解语义才能判断能不能删的东西都不碰——这条线守不住，
/// 压缩就会开始吃掉提示词的关键约束，那比不压还糟。
///
/// 保护区（代码块、行内代码、引号内容、`{{变量}}`）整段原样保留：
/// 那些地方的字面内容本身就是指令的一部分，一个字符都不该动。
enum PromptCompressor {

    // MARK: 对外入口

    static func compress(
        _ text: String,
        enabled: Set<CompressionGroup> = Set(CompressionGroup.allCases)
    ) -> PromptCompressionResult {
        var result = PromptCompressionResult()
        result.before = PromptStats.measure(text)
        result.after = result.before

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            result.rounds = 0
            return result
        }

        var current = text
        var counter: [String: Int] = [:]
        var order: [String] = []
        var groupOf: [String: CompressionGroup] = [:]

        // 规则之间会互相开门：删掉「请帮我」之后两行才变得一模一样。
        // 所以跑到不动为止——收敛即幂等，压两遍和压一遍结果必然相同。
        let maxRounds = 4
        var rounds = 0
        while rounds < maxRounds {
            rounds += 1
            let next = onePass(current, enabled: enabled,
                               counter: &counter, order: &order, groupOf: &groupOf)
            if next == current { break }
            current = next
        }
        result.rounds = rounds
        result.converged = rounds < maxRounds
        if result.converged { result.rounds = max(0, rounds - 1) }

        result.text = current
        result.after = PromptStats.measure(current)
        result.hits = order.compactMap { title -> CompressionHit? in
            guard let count = counter[title], count > 0 else { return nil }
            return CompressionHit(id: title,
                                  group: groupOf[title] ?? .verbose,
                                  title: title,
                                  count: count)
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.title < rhs.title
        }
        return result
    }

    // MARK: 一轮

    private static func onePass(
        _ text: String,
        enabled: Set<CompressionGroup>,
        counter: inout [String: Int],
        order: inout [String],
        groupOf: inout [String: CompressionGroup]
    ) -> String {
        // 末尾补一个哨兵换行，让最后一行也算"有行尾"。
        // 不补的话，「行尾致谢」这类规则会把片段边界当成行尾——
        // 「请帮我运行 `git commit`」的「运行 」会被当成行尾空格削掉，
        // 变成「运行`git commit`」，中文和行内代码就粘一起了。
        let sentinel = "\n"
        var pieces = split(text + sentinel)

        // 1. 保护区外的片段过一遍正则规则
        for index in pieces.indices where !pieces[index].isProtected {
            pieces[index].text = run(rules, on: pieces[index].text, enabled: enabled,
                                     counter: &counter, order: &order, groupOf: &groupOf)
        }
        var output = pieces.map(\.text).joined()
        if output.hasSuffix(sentinel) { output.removeLast() }

        // 2. 整行判重。要在拼回去之后做，否则被变量切碎的行会误判；
        //    同时按当前文本重新算一次保护区范围，落在保护区里的行一律跳过。
        if enabled.contains(.duplicate) {
            output = removeDuplicateLines(output, counter: &counter, order: &order, groupOf: &groupOf)
        }

        // 3. 收边：掐掉整段前后的空行
        if enabled.contains(.whitespace) {
            output = trimEdges(output)
        }
        return output
    }

    private static func run(
        _ rules: [Rule],
        on text: String,
        enabled: Set<CompressionGroup>,
        counter: inout [String: Int],
        order: inout [String],
        groupOf: inout [String: CompressionGroup]
    ) -> String {
        let original = text
        var current = text
        for rule in rules where enabled.contains(rule.group) {
            guard let regex = rule.regex else { continue }
            let ns = current as NSString
            let range = NSRange(location: 0, length: ns.length)
            let count = regex.numberOfMatches(in: current, options: [], range: range)
            guard count > 0 else { continue }
            current = regex.stringByReplacingMatches(
                in: current, options: [], range: range, withTemplate: rule.template
            )
            tally(rule.title, group: rule.group, count: count,
                  counter: &counter, order: &order, groupOf: &groupOf)
        }
        // 删掉句首的「Please」「Can you」之后，剩下的首字母得补回大写，
        // 不然 "Please write a function" 会变成 "write a function"。
        // 只在原文首字母本来就大写、删完变小时才动，不改用户自己写的小写开头。
        if let first = original.first, first.isUppercase,
           let newFirst = current.first, newFirst.isLowercase {
            current = newFirst.uppercased() + current.dropFirst()
        }
        return current
    }

    private static func tally(
        _ title: String, group: CompressionGroup, count: Int,
        counter: inout [String: Int], order: inout [String], groupOf: inout [String: CompressionGroup]
    ) {
        if counter[title] == nil { order.append(title) }
        counter[title, default: 0] += count
        groupOf[title] = group
    }

    // MARK: - 保护区

    private struct Piece {
        var text: String
        var isProtected: Bool
    }

    /// 代码块、行内代码、各种引号里的内容、`{{变量}}` 一律不动。
    /// 认不出来宁可当保护区——少删一点没损失，删错一处整个提示词就废了。
    private static let protectedRegex = try! NSRegularExpression(
        pattern: "```[\\s\\S]*?```|`[^`\\n]*`|\\{\\{[^{}]*\\}\\}|\"[^\"\\n]*\"|“[^”\\n]*”|「[^」\\n]*」|『[^』\\n]*』|'[^'\\n]*'|‘[^’\\n]*’",
        options: []
    )

    private static func protectedRanges(_ text: String) -> [NSRange] {
        let ns = text as NSString
        return protectedRegex
            .matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map(\.range)
    }

    private static func split(_ text: String) -> [Piece] {
        let ns = text as NSString
        var pieces: [Piece] = []
        var cursor = 0
        for match in protectedRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                let chunk = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                pieces.append(Piece(text: chunk, isProtected: false))
            }
            pieces.append(Piece(text: ns.substring(with: match.range), isProtected: true))
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            pieces.append(Piece(text: ns.substring(from: cursor), isProtected: false))
        }
        return pieces
    }

    // MARK: - 重复行

    private static func removeDuplicateLines(
        _ text: String,
        counter: inout [String: Int],
        order: inout [String],
        groupOf: inout [String: CompressionGroup]
    ) -> String {
        let guarded = protectedRanges(text)
        var seen: Set<String> = []
        var kept: [String] = []
        var removed = 0
        var location = 0

        for line in text.components(separatedBy: "\n") {
            let lineRange = NSRange(location: location, length: (line as NSString).length)
            location += lineRange.length + 1

            // 保护区里的行（代码块内、引号内）绝不参与判重；
            // 表格行也不参与——两行内容相同不等于其中一行是多余的，
            // 删掉会直接毁掉表格结构
            let isProtected = guarded.contains { NSIntersectionRange($0, lineRange).length > 0 }
            let isTableRow = line.contains("|")
            let key = duplicateKey(line)

            // 太短的行（空行、`-`、`##`）也不参与，否则结构标记会被误伤。
            // 门槛按归一化后的字符数算 3 个字——中文三个字已经是完整的意思了，
            // 「写一个函数」这种必须能判重，门槛再高一点就什么都删不掉了。
            guard !isProtected, !isTableRow, key.count >= 3 else {
                kept.append(line)
                continue
            }
            if seen.contains(key) {
                removed += 1
                continue
            }
            seen.insert(key)
            kept.append(line)
        }

        if removed > 0 {
            tally("重复的行 / 句子", group: .duplicate, count: removed,
                  counter: &counter, order: &order, groupOf: &groupOf)
        }
        return kept.joined(separator: "\n")
    }

    /// 归一化：去掉 markdown 结构标记、空白和标点后再比。
    /// 只留字母数字和汉字——「改这个。」和「改这个！」算同一句。
    private static func duplicateKey(_ line: String) -> String {
        var value = line.trimmingCharacters(in: .whitespaces)
        value = value.replacingOccurrences(
            of: "^(?:[-*+>]|\\d+[.、)]|#{1,6})[ \\t]*",
            with: "",
            options: .regularExpression
        )
        var output = ""
        for scalar in value.unicodeScalars
        where CharacterSet.alphanumerics.contains(scalar) || PromptEngine.isIdeograph(scalar) {
            output.unicodeScalars.append(scalar)
        }
        return output.lowercased()
    }

    // MARK: - 收边

    private static func trimEdges(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 规则表
    //
    // 保守是第一原则：任何一条规则如果可能吃到有信息量的内容，就不写。
    // 比如「大概」是真实的不确定表达（「大概 10 分钟」），所以只删带逗号的
    // 「其实，」「基本上，」这种明显垫话的形态。

    private struct Rule {
        let group: CompressionGroup
        let title: String
        let template: String
        let regex: NSRegularExpression?

        init(_ group: CompressionGroup, _ title: String, _ pattern: String, _ template: String,
             options: NSRegularExpression.Options = []) {
            self.group = group
            self.title = title
            self.template = template
            self.regex = try? NSRegularExpression(pattern: pattern, options: options)
        }
    }

    private static let ml: NSRegularExpression.Options = [.anchorsMatchLines]
    private static let mlCI: NSRegularExpression.Options = [.anchorsMatchLines, .caseInsensitive]

    private static let rules: [Rule] = [

        // MARK: 礼貌套话

        // 问候语必须带标点才删——「你好」后面没标点可能是在讲这个词本身
        Rule(.politeness, "行首问候语",
             "^[ \\t]*(?:你好|您好|嗨|哈喽|(?<![A-Za-z])(?:hi|hello|hey)(?![A-Za-z]))[ \\t]*[，,、~～.!！:：][ \\t]*",
             "", options: mlCI),

        Rule(.politeness, "「请帮我 / 麻烦你」",
             "^[ \\t]*(?:请你?帮我|请帮忙|麻烦你?帮我|麻烦帮我|帮我|请教你)[ \\t]*[，,、]?[ \\t]*",
             "", options: ml),

        // 单独的「麻烦」「拜托」必须带逗号才删，
        // 否则「麻烦的地方在于」会被削成「的地方在于」
        Rule(.politeness, "「麻烦 / 拜托」+ 逗号",
             "^[ \\t]*(?:麻烦|拜托|劳驾)[ \\t]*[，,、][ \\t]*",
             "", options: ml),

        // 「请务必」「请注意」是真要求，不能删，所以排除这些后续字
        Rule(.politeness, "行首光杆「请」",
             "^[ \\t]*请(?![求教问勿务注记参看])[ \\t]*",
             "", options: ml),

        Rule(.politeness, "「我想请你 / 能不能帮我」",
             "^[ \\t]*(?:我想?(?:请你|让你|要你)|我希望你能|我需要你|我要你|能不能帮我|可以帮我|可不可以帮我|能否帮我)[ \\t]*[，,、]?[ \\t]*",
             "", options: ml),

        Rule(.politeness, "英文 please",
             "^[ \\t]*(?:please|pls)[ \\t]+",
             "", options: mlCI),

        Rule(.politeness, "英文 I want you to",
             "^[ \\t]*(?:i (?:want|need|would like|'d like) you to|can you|could you(?: please)?|would you)[ \\t]+",
             "", options: mlCI),

        Rule(.politeness, "行尾致谢",
             "[ \\t]*[，,]?[ \\t]*(?:谢谢你了?|谢谢啦|谢谢|非常感谢|多谢了?|感谢|辛苦你了?|辛苦啦|辛苦了|麻烦你了|麻烦啦|拜托了)[ \\t]*[。.!！~～]*[ \\t]*(?=\\n)",
             "", options: ml),

        Rule(.politeness, "英文致谢",
             "[ \\t]*[，,]?[ \\t]*(?:thank you(?: very much)?|thanks(?: a lot| so much)?|thanks in advance)[.!]?[ \\t]*(?=\\n)",
             "", options: mlCI),

        // MARK: 语气垫词

        Rule(.filler, "「其实 / 基本上 / 总的来说」",
             "(?:其实|基本上|总的来说|总体而言|某种程度上|一定程度上|可以说是|不得不说|说白了|严格来说|客观来讲)[，,][ \\t]*",
             ""),

        Rule(.filler, "「可能吧 / 也许吧」",
             "(?:可能吧|也许吧|大概吧|应该吧|差不多吧)[，,]?[ \\t]*",
             ""),

        Rule(.filler, "英文垫词",
             "(?<![A-Za-z])(?:basically|essentially|actually|in fact|to be honest|honestly speaking)[,]?[ \\t]*",
             "", options: .caseInsensitive),

        Rule(.filler, "叠用程度副词",
             "(非常|特别|十分|相当|真的)\\1+",
             "$1"),

        Rule(.filler, "英文叠用副词",
             "(?<![A-Za-z])(very|really|quite|extremely)[ \\t]+\\1(?![A-Za-z])",
             "$1", options: .caseInsensitive),

        // MARK: 冗长表达

        Rule(.verbose, "「需要注意的是」",
             "需要注意的是|值得注意的是|需要说明的是|要注意的是",
             "注意"),

        Rule(.verbose, "英文 it is worth noting that",
             "(?<![A-Za-z])(?:it is worth noting that|it should be noted that|please note that)(?![A-Za-z])",
             "Note:", options: .caseInsensitive),

        // 「进行缺失值统计」这种中间夹了宾语的也要能瘦下来：
        // 夹的那一小截（最多 4 字）原样保留，只把「进行」这个轻动词去掉
        Rule(.verbose, "「进行 / 加以 / 予以」+ 动词",
             "(?:进行|加以|予以)([^，。；\\n]{0,4}?)(优化|分析|修改|处理|检查|整理|调整|确认|验证|讨论|评估|说明|考虑|测试|部署|实现|完善|简化|重写|统计|转换|计算|解析|渲染|加载|上传|下载|备份|同步|迁移|重构|审核|校对|排序|抽取|比对)",
             "$1$2"),

        Rule(.verbose, "「做出」+ 名词",
             "做出(决定|选择|判断|调整|改动)",
             "$1"),

        Rule(.verbose, "「由于这个原因」",
             "(?:由于|因为|出于|基于)(?:这个|该)原因",
             "因此"),

        Rule(.verbose, "「与此同时 / 除此之外」",
             "与此同时|除此之外",
             "同时"),

        Rule(.verbose, "「为了能够 / 以便于」",
             "为了能够|以便于",
             "为了"),

        Rule(.verbose, "「在大多数情况下」",
             "在(?:大多数|通常|一般)情况下",
             "通常"),

        Rule(.verbose, "「如果可以的话」",
             "(?:如果|要是|若)?可以的话[，,]?[ \\t]*",
             ""),

        Rule(.verbose, "「在…的时候」",
             "在([^，。；\\n]{1,10}?)的时候",
             "$1时"),

        Rule(.verbose, "「我的需求是」",
             "我的?(?:需求|要求)(?:是|如下)[：:]?[ \\t]*",
             "需求："),

        Rule(.verbose, "英文 in order to",
             "(?<![A-Za-z])(?:in order to|for the purpose of)(?![A-Za-z])",
             "to", options: .caseInsensitive),

        Rule(.verbose, "英文 due to the fact that",
             "(?<![A-Za-z])(?:due to the fact that|owing to the fact that)(?![A-Za-z])",
             "because", options: .caseInsensitive),

        Rule(.verbose, "英文 at this point in time",
             "(?<![A-Za-z])at this point in time(?![A-Za-z])",
             "now", options: .caseInsensitive),

        Rule(.verbose, "英文 a large number of",
             "(?<![A-Za-z])a (?:large|great|significant) (?:number|amount) of(?![A-Za-z])",
             "many", options: .caseInsensitive),

        Rule(.verbose, "英文 make a decision / is able to",
             "(?<![A-Za-z])(?:make a decision|make a choice)(?![A-Za-z])",
             "decide", options: .caseInsensitive),

        Rule(.verbose, "英文 is able to / has the ability to",
             "(?<![A-Za-z])(?:is able to|are able to|has the ability to|have the ability to)(?![A-Za-z])",
             "can", options: .caseInsensitive),

        Rule(.verbose, "英文 in the event that",
             "(?<![A-Za-z])in the event that(?![A-Za-z])",
             "if", options: .caseInsensitive),

        Rule(.verbose, "英文 with regard to / prior to",
             "(?<![A-Za-z])(?:with (?:regard|respect) to|prior to)(?![A-Za-z])",
             "about", options: .caseInsensitive),

        // MARK: 空白与标点

        Rule(.whitespace, "多余空行",
             "\\n{3,}",
             "\n\n"),

        Rule(.whitespace, "行尾空白",
             "[ \\t]+(?=\\n)",
             ""),

        Rule(.whitespace, "行内多余空格",
             "(?<=\\S)[ \\t]{2,}",
             " "),

        Rule(.whitespace, "叠起来的标点",
             "([！？!?。~～])\\1+",
             "$1"),

        // 中文标点前后不留空格。后面那条要排掉 markdown 标记与列表符号——
        // 「**重点：** 后面的话」里的那个空格是有用的
        Rule(.whitespace, "中文标点前的空格",
             "[ \\t]+([，。、；：！？（）【】「」『』])",
             "$1"),

        Rule(.whitespace, "中文标点后的空格",
             "([，。、；：！？（）【】「」『』])[ \\t]+(?![*_`#>|\\-])",
             "$1"),

        Rule(.whitespace, "全角空格",
             "\u{3000}",
             " "),
    ]
}
