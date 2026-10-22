import Foundation

// MARK: - 目标类型

enum PromptExpandTarget: String, CaseIterable, Identifiable, Sendable {
    case image = "绘图"
    case copywriting = "文案"
    case code = "代码"
    case slides = "PPT"
    case video = "短视频脚本"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .image: return "photo.artframe"
        case .copywriting: return "text.quote"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .slides: return "rectangle.on.rectangle"
        case .video: return "video"
        }
    }

    var placeholder: String {
        switch self {
        case .image: return "一句话就够了，比如「一只橘猫在窗台上晒太阳」"
        case .copywriting: return "比如「给一款降噪耳机写小红书种草笔记」"
        case .code: return "比如「用 Python 读 CSV 并做缺失值统计」"
        case .slides: return "比如「给团队做一次季度复盘汇报」"
        case .video: return "比如「三条讲清为什么天空是蓝色」"
        }
    }

    /// 这一类的骨架能自动补到什么程度——写在界面上，别让人以为工具会算命
    var note: String {
        switch self {
        case .image: return "细节、光线、构图、画质都能按词库补上，是五类里补得最满的"
        case .copywriting: return "平台和受众能从输入里认出来；「想让人做什么」必须你自己定"
        case .code: return "语言能认出来；输入输出、边界条件得你补，这几项不写清模型只能猜"
        case .slides: return "大纲骨架是现成的；听众、页数、目的得你补"
        case .video: return "分镜结构是现成的；平台、时长、观众得你补"
        }
    }
}

enum ExpandDetail: String, CaseIterable, Identifiable, Sendable {
    case brief = "简洁"
    case standard = "标准"
    case rich = "详尽"

    var id: String { rawValue }

    var note: String {
        switch self {
        case .brief: return "只保留必要的几项，粘贴出去不啰嗦"
        case .standard: return "日常够用"
        case .rich: return "补满细节，再附一份自检清单"
        }
    }
}

enum ExpandLanguage: String, CaseIterable, Identifiable, Sendable {
    case chinese = "中文"
    case english = "英文"
    case both = "中英对照"

    var id: String { rawValue }

    var note: String {
        switch self {
        case .chinese: return "标签和词都用中文"
        case .english: return "全英文。绘图类提示词用英文更稳，主流模型权重都偏英文"
        case .both: return "结构化部分给中文，另附一条英文的可用提示词"
        }
    }
}

enum PromptStyle: String, CaseIterable, Identifiable, Sendable {
    case auto = "自动"
    case photo = "写实摄影"
    case cinematic = "电影感"
    case render3D = "3D 渲染"
    case anime = "二次元动漫"
    case cyberpunk = "赛博朋克"
    case watercolor = "水彩"
    case oil = "油画"
    case flat = "扁平插画"
    case pixel = "像素风"
    case film = "复古胶片"
    case minimal = "极简主义"

    var id: String { rawValue }

    var term: PromptTerm? {
        guard self != .auto else { return nil }
        return PromptWordBank.styles.first { $0.zh == rawValue }
    }
}

enum PromptAspect: String, CaseIterable, Identifiable, Sendable {
    case none = "不指定"
    case square = "1:1"
    case wide = "16:9"
    case tall = "9:16"
    case classic = "3:2"
    case photo = "2:3"

    var id: String { rawValue }
    var isNone: Bool { self == .none }
    /// Midjourney 的画幅参数
    var flag: String? { isNone ? nil : "--ar \(rawValue)" }
}

// MARK: - 选项与结果

struct PromptExpandOptions: Sendable {
    var target: PromptExpandTarget = .image
    var detail: ExpandDetail = .standard
    var language: ExpandLanguage = .chinese
    var style: PromptStyle = .auto
    var aspect: PromptAspect = .none
    var includeNegative = true
}

struct PromptExpansion: Sendable {
    var text = ""
    /// 工具自己补了什么、哪里是猜的
    var filled: [String] = []
    /// 必须由用户决定的栏位（骨架里用「待补」标出来了）
    var todo: [String] = []
    var notes: [String] = []

    var isEmpty: Bool { text.isEmpty }

    var todoCount: Int { todo.count }
}

// MARK: - 引擎

/// 一句话 → 结构化提示词。
///
/// **本地规则式扩写，不调用任何大模型。** 做法是把一句话套进这个类型的成熟骨架，
/// 再从词库按主体类别补细节。所以「待补」那几栏是真的需要用户自己判断——
/// 工具不乱猜，猜错比留空更坑。
enum PromptExpander {

    static let disclaimer = "本地规则式扩写：套骨架 + 词库补细节，不调用大模型。「待补」的栏位是真需要你自己定，工具不猜。"

    static func expand(_ raw: String, options: PromptExpandOptions) -> PromptExpansion {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            return PromptExpansion(
                text: "",
                filled: [],
                todo: [],
                notes: ["先写一句话。哪怕只有「一只猫」也能扩，写越具体扩得越准。"]
            )
        }
        switch options.target {
        case .image: return expandImage(input, options)
        case .copywriting: return expandCopy(input, options)
        case .code: return expandCode(input, options)
        case .slides: return expandSlides(input, options)
        case .video: return expandVideo(input, options)
        }
    }

    // MARK: - 绘图

    private struct Section {
        let zhLabel: String
        let enLabel: String
        let terms: [PromptTerm]
    }

    private static func expandImage(_ input: String, _ options: PromptExpandOptions) -> PromptExpansion {
        var expansion = PromptExpansion()
        let lowered = input.lowercased()

        // 主体类别 → 该类特有的细节
        let concept = PromptWordBank.concepts.first { item in
            item.keywords.contains { lowered.contains($0.lowercased()) }
        }
        let pool = concept?.details ?? PromptWordBank.genericDetails
        if let concept {
            expansion.filled.append("主体类别认成「\(concept.key)」，细节按这一类补")
        } else {
            expansion.notes.append("没认出主体属于哪一类，细节按通用方向补。主体写具体一点（「一只橘猫」比「猫」）会明显更准。")
        }
        let detailCount: Int
        switch options.detail {
        case .brief: detailCount = 2
        case .standard: detailCount = 3
        case .rich: detailCount = 5
        }
        let details = Array(pool.prefix(detailCount))

        // 风格：用户选了就听他的；没选但输入里写了风格就不叠加；否则按主体类别推
        var styleTerm: PromptTerm?
        if let chosen = options.style.term {
            styleTerm = chosen
            expansion.filled.append("风格用你选的「\(chosen.zh)」")
        } else if PromptWordBank.styleKeywords.contains(where: { lowered.contains($0) }) {
            expansion.notes.append("输入里已经带风格词了，不再叠加默认风格，免得两种风格打架。")
        } else if let concept {
            styleTerm = concept.style
            expansion.filled.append("风格按主体类别推成「\(concept.style.zh)」")
        } else {
            styleTerm = PromptWordBank.styles.first
            expansion.filled.append("风格用默认的「\(PromptWordBank.styles.first?.zh ?? "写实摄影")」")
        }

        let lighting = detect(PromptWordBank.lighting, hints: lightingHints, in: lowered)
            ?? PromptWordBank.lighting[0]
        let composition = detect(PromptWordBank.compositions, hints: compositionHints, in: lowered)
            ?? PromptWordBank.compositions[0]
        var color: PromptTerm? = detect(PromptWordBank.colors, hints: colorHints, in: lowered)
        if color == nil, options.detail != .brief {
            color = PromptWordBank.colors[0]
            expansion.filled.append("色彩按默认暖色调补")
        }

        var sections: [Section] = [
            Section(zhLabel: "主体", enLabel: "Subject", terms: [PromptTerm(input, input)]),
            Section(zhLabel: "细节", enLabel: "Details", terms: details),
        ]
        if let styleTerm {
            sections.append(Section(zhLabel: "风格", enLabel: "Style", terms: [styleTerm]))
        }
        sections.append(Section(zhLabel: "光线", enLabel: "Lighting", terms: [lighting]))
        sections.append(Section(zhLabel: "构图", enLabel: "Composition", terms: [composition]))
        if let color {
            sections.append(Section(zhLabel: "色彩", enLabel: "Palette", terms: [color]))
        }
        sections.append(Section(zhLabel: "画质", enLabel: "Quality",
                                terms: [PromptWordBank.quality(options.detail)]))

        let negatives = options.includeNegative ? PromptWordBank.negative(options.detail) : []
        let aspect = options.aspect

        var blocks: [String] = []
        switch options.language {
        case .chinese:
            blocks.append(structured(sections, language: .chinese))
            blocks.append("可直接粘贴（一行版）：\n" + oneLine(sections, negatives: negatives, aspect: aspect, language: .chinese))
        case .english:
            blocks.append(structured(sections, language: .english))
            blocks.append("One-liner:\n" + oneLine(sections, negatives: negatives, aspect: aspect, language: .english))
        case .both:
            blocks.append(structured(sections, language: .chinese))
            blocks.append("可直接粘贴（一行版）：\n" + oneLine(sections, negatives: negatives, aspect: aspect, language: .chinese))
            blocks.append("English prompt:\n" + oneLine(sections, negatives: negatives, aspect: aspect, language: .english))
        }

        if !negatives.isEmpty {
            let joined = negatives.map { options.language == .english ? $0.en : $0.zh }.joined(separator: "，")
            blocks.append("负向提示词：\n" + joined)
            expansion.notes.append("负向提示词在 Midjourney 里可以并进一行（--no lowres, blurry…）；Stable Diffusion 有自己的负向输入框，填在那里。")
        }

        expansion.text = blocks.joined(separator: "\n\n")
        if aspect.isNone {
            expansion.notes.append("没指定画幅。主图建议先定画幅再生成，不然出图比例不合适等于白跑。")
        }
        if options.language != .chinese, input.unicodeScalars.contains(where: PromptEngine.isCJK) {
            expansion.notes.append("主体那一段保留了你输入的中文——工具不做翻译。英文权重确实更稳，建议自己把主体也换成英文再粘。")
        }
        expansion.todo = []
        return expansion
    }

    private static let lightingHints = ["逆光", "侧光", "柔光", "硬光", "顶光", "底光", "霓虹", "黄金时刻",
                                        "蓝调", "伦勃朗", "体积光", "自然光", "背光", "烛光", "阴天"]
    private static let compositionHints = ["特写", "近景", "中景", "远景", "全景", "俯拍", "鸟瞰", "仰拍",
                                           "平视", "过肩", "三分", "对称", "微距", "广角", "长焦"]
    private static let colorHints = ["暖色", "冷色", "低饱和", "莫兰迪", "撞色", "对比色", "单色", "黑白",
                                     "大地色", "复古色"]

    /// 用户输入里已经写了这一项（风格 / 光线 / 构图），就别再补一个冲突的
    private static func detect(_ terms: [PromptTerm], hints: [String], in lowered: String) -> PromptTerm? {
        if let hint = hints.first(where: { lowered.contains($0.lowercased()) }),
           let term = terms.first(where: { $0.zh.contains(hint) || $0.en.lowercased().contains(hint.lowercased()) }) {
            return term
        }
        return terms.first { lowered.contains($0.zh.lowercased()) && $0.zh.count >= 4 }
    }

    private static func structured(_ sections: [Section], language: ExpandLanguage) -> String {
        sections.map { section in
            let label = language == .english ? section.enLabel : section.zhLabel
            let separator = language == .english ? ", " : "，"
            let values = section.terms.map { language == .english ? $0.en : $0.zh }
            return "\(label)\(language == .english ? ":" : "：")\(values.joined(separator: separator))"
        }
        .joined(separator: "\n")
    }

    private static func oneLine(
        _ sections: [Section],
        negatives: [PromptTerm],
        aspect: PromptAspect,
        language: ExpandLanguage
    ) -> String {
        let separator = language == .english ? ", " : "，"
        var parts: [String] = []
        for section in sections {
            parts.append(contentsOf: section.terms.map { language == .english ? $0.en : $0.zh })
        }
        // 画幅参数直接写成 --ar，两种语言都这么用——它是参数不是描述，
        // 中文版的一行往往也要原样粘到 Midjourney 里
        if let flag = aspect.flag { parts.append(flag) }

        if !negatives.isEmpty, language == .english {
            parts.append("--no " + negatives.map(\.en).joined(separator: ", "))
        }
        return parts.joined(separator: separator)
    }

    // MARK: - 文案

    private static func expandCopy(_ input: String, _ options: PromptExpandOptions) -> PromptExpansion {
        var expansion = PromptExpansion()
        let platform = PromptWordBank.firstMatch(PromptWordBank.platformCues, in: input)
        let audience = PromptWordBank.firstMatch(PromptWordBank.audienceCues, in: input)
        let domain = PromptWordBank.firstMatch(PromptWordBank.domainCues, in: input)

        if let platform { expansion.filled.append("从输入里认出平台：\(platform)") } else { expansion.todo.append("发布平台") }
        if let audience { expansion.filled.append("从输入里认出受众：\(audience)") } else { expansion.todo.append("目标受众") }
        if let domain { expansion.filled.append("从输入里认出领域：\(domain)") }
        expansion.todo.append("想让人看完做什么")
        expansion.todo.append("篇幅与形式")
        if options.detail != .brief {
            expansion.todo.append("禁忌（不能提竞品 / 不能绝对化用语 / 平台违规词）")
        }

        let platformText = platform ?? "（待补：小红书 / 公众号 / 抖音 / B 站…）"
        let audienceText = audience ?? "（待补：谁看到这条？写具体一点，比如「刚开始健身的上班族」）"
        let domainText = domain ?? "通用"

        let zh = """
        你是内容写手，擅长写「\(domainText)」方向的内容。
        发布平台：\(platformText)

        任务：\(input)

        需要你确认的栏位：
        - 目标受众：\(audienceText)
        - 想让人看完做什么：（待补——这一栏决定整篇的落点，是点链接、是收藏、还是记住一个观点）
        - 篇幅与形式：（待补：多少字、要不要分点、要不要配标题）
        \(options.detail == .brief ? "" : "- 禁忌：（待补：不能提竞品、不能有绝对化用语、平台违规词）")

        要求：
        - 开头一句用具体场景或痛点抓注意力，不要「大家好」这种开头
        - 正文分 2–4 段，每段一个点，每个点配一个具体例子或细节
        - 结尾给一个明确行动号召，不要用「欢迎留言」这种空洞收尾
        - 口语化，不堆形容词，不用感叹号撑情绪
        - 不要出现「最」「第一」「百分百」这类绝对化用语（广告法会找上门）

        输出格式：先给正文，再给 \(options.detail == .rich ? "5" : "3") 个标题备选，最后列出你做了什么取舍。
        """

        let en = """
        You write content for \(platform ?? "(platform TBD)"), specialising in \(domainText), aimed at \(audience ?? "(audience TBD)").

        Task: \(input)

        Fields to confirm:
        - Audience: \(audience ?? "(TBD — be specific, e.g. office workers new to fitness)")
        - Desired action after reading: (TBD — this decides the whole piece)
        - Length and format: (TBD)

        Requirements:
        - Open with a concrete scene or pain point, not a generic greeting
        - 2–4 body paragraphs, one point each, each with a concrete example
        - End with an explicit call to action
        - Conversational tone, no adjective stacking, no exclamation marks
        - No absolute claims ("the best", "100%")

        Output: the copy first, then \(options.detail == .rich ? "5" : "3") headline options, then the trade-offs you made.
        """

        expansion.text = compose(zh, en, language: options.language)
        return expansion
    }

    // MARK: - 代码

    private static func expandCode(_ input: String, _ options: PromptExpandOptions) -> PromptExpansion {
        var expansion = PromptExpansion()
        let language = PromptWordBank.firstMatch(PromptWordBank.languageCues, in: input)
        if let language {
            expansion.filled.append("从输入里认出语言 / 技术栈：\(language)")
        } else {
            expansion.todo.append("语言与版本")
        }
        expansion.todo.append("输入 / 输出")
        expansion.todo.append("边界条件")
        if options.detail != .brief {
            expansion.todo.append("运行环境与依赖限制")
        }

        let languageText = language ?? "（待补：语言 + 版本，比如 Python 3.12）"

        let zh = """
        你是资深 \(languageText) 工程师。

        任务：\(input)

        输入 / 输出：（待补——说清传什么进去、期望吐出什么；有样例数据最好贴一段）
        边界条件：（待补——空值 / 0 / 越界 / 并发 / 超时，哪几条要处理）
        \(options.detail == .brief ? "" : "运行环境与依赖：（待补——版本、能不能引第三方库、部署到哪）")

        要求：
        - 直接给完整可运行的代码，不要用省略号糊过去
        - 关键逻辑写注释说明「为什么」，不解释「是什么」
        - 出错路径显式处理，不要吞异常，也不要用裸的 catch 一律忽略
        - 命名说人话，别用 data1 / tmp2 这种

        最后：列出你没把握的地方和需要我确认的点，不要替我猜。
        输出格式：代码 + 简短说明，不要逐行解释。
        """

        let en = """
        You are a senior \(language ?? "(language TBD)") engineer.

        Task: \(input)

        Input / output: (TBD — what goes in, what comes out; paste a sample if you have one)
        Edge cases: (TBD — empty / zero / out of range / concurrency / timeout)
        \(options.detail == .brief ? "" : "Runtime and dependencies: (TBD — versions, third-party libs allowed?)")

        Requirements:
        - Provide complete, runnable code — no ellipsis
        - Comment the "why", not the "what"
        - Handle error paths explicitly, never swallow exceptions
        - Sensible names, no data1 / tmp2

        Finally: list what you are unsure about and what you need me to confirm.
        Output: code plus a short explanation, no line-by-line narration.
        """

        expansion.text = compose(zh, en, language: options.language)
        return expansion
    }

    // MARK: - PPT

    private static func expandSlides(_ input: String, _ options: PromptExpandOptions) -> PromptExpansion {
        var expansion = PromptExpansion()
        let audience = PromptWordBank.firstMatch(PromptWordBank.audienceCues, in: input)
        if let audience {
            expansion.filled.append("从输入里认出听众：\(audience)")
        } else {
            expansion.todo.append("听众是谁")
        }
        expansion.todo.append("页数与时长")
        expansion.todo.append("汇报目的")

        let audienceText = audience ?? "（待补：听众是谁，他们的关注点决定详略）"

        let zh = """
        为「\(input)」做一份 PPT。

        听众：\(audienceText)
        页数与时长：（待补——建议按「一页一分钟」估）
        汇报目的：（待补——想让人做什么决定？没有目的的汇报会变成念稿）

        请给：
        1. 一句话主线：整份 PPT 想让人记住的唯一结论
        2. 逐页大纲，格式：页码 | 标题 | 3 个要点 | 用什么图或数据支撑
        3. 每页一句讲稿要点（20 字以内，我照着展开）
        4. 听众最可能问的三个问题与回答要点

        \(options.detail == .rich ? "另外给：开头 30 秒的开场说法、结尾的一句话收束、可能被质疑的数据点及应对。\n\n" : "")约束：
        - 严格按页数，宁可少讲也不要挤
        - 每页只讲一件事，标题写成结论而不是名词短语
        - 没有数据的页也标出「这里该放什么图」
        """

        let en = """
        Build a slide deck outline for: \(input)

        Audience: \(audience ?? "(TBD)")
        Page count / duration: (TBD — one minute per slide is a good rule)
        Goal: (TBD — what decision should the audience make?)

        Provide:
        1. One-line thesis: the single thing they should remember
        2. Page-by-page outline: number | title | 3 bullet points | what chart or data supports it
        3. One speaker note per page (under 20 words)
        4. The three most likely questions and short answers

        Constraints:
        - Stick to the page count; cutting content beats cramming
        - One idea per page; write titles as conclusions, not noun phrases
        - Even without data, mark what visual belongs on each page
        """

        expansion.text = compose(zh, en, language: options.language)
        return expansion
    }

    // MARK: - 短视频脚本

    private static func expandVideo(_ input: String, _ options: PromptExpandOptions) -> PromptExpansion {
        var expansion = PromptExpansion()
        let platform = PromptWordBank.firstMatch(PromptWordBank.platformCues, in: input)
        let audience = PromptWordBank.firstMatch(PromptWordBank.audienceCues, in: input)
        if let platform {
            expansion.filled.append("从输入里认出平台：\(platform)")
        } else {
            expansion.todo.append("发布平台")
        }
        if let audience {
            expansion.filled.append("从输入里认出观众：\(audience)")
        } else {
            expansion.todo.append("目标观众")
        }
        expansion.todo.append("时长")

        let platformText = platform ?? "（待补：抖音 / 视频号 / B 站 / 小红书）"
        let audienceText = audience ?? "（待补：谁刷到这条会停下来？）"

        let zh = """
        写一条短视频脚本。

        主题：\(input)
        平台：\(platformText)
        时长：（待补——15 秒 / 30 秒 / 60 秒，长度决定能讲几个点）
        目标观众：\(audienceText)

        按分镜给，每段标注时间：| 时间 | 画面 | 口播 | 字幕 |

        结构：
        - 前 3 秒：用反常识结论或具体数字抓人，不要铺垫
        - 中段：3 个递进的点，每个配一个生活化比喻
        - 结尾：一句话总结 + 明确的行动号召，说清「为什么值得关注你」

        \(options.detail == .rich ? "另外给：封面文案、标题备选 3 条、评论区引导语、可能被抬杠的点及回应。\n\n" : "")要求：
        - 口播按每秒 4–5 个字控制长度，写完自己数一遍
        - 一句话不超过 20 字，念着不顺就拆开
        - 字幕只留关键词，不要把口播全文搬上去
        """

        let en = """
        Write a short-video script.

        Topic: \(input)
        Platform: \(platform ?? "(TBD)")
        Duration: (TBD — 15s / 30s / 60s decides how many points fit)
        Audience: \(audience ?? "(TBD)")

        Give it as a shot list: | time | visual | voiceover | caption |

        Structure:
        - First 3 seconds: a counter-intuitive claim or a concrete number, no setup
        - Middle: 3 progressive points, each with an everyday analogy
        - End: one-line summary plus an explicit call to action

        Requirements:
        - Voiceover at 4–5 characters per second; count it
        - One sentence per breath
        - Captions carry keywords only, not the full script
        """

        expansion.text = compose(zh, en, language: options.language)
        return expansion
    }

    // MARK: - 拼装

    private static func compose(_ zh: String, _ en: String, language: ExpandLanguage) -> String {
        switch language {
        case .chinese: return zh
        case .english: return en
        case .both: return zh + "\n\n———— English ————\n\n" + en
        }
    }
}
