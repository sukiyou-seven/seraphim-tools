import Foundation

// MARK: - 提示词工具的 AI 指令
//
// AI 驱动开关打开后，压缩 / 扩写的结果由模型生成。这里只负责把「工具已经知道的
// 上下文」（用户输入、选项、允许删什么）翻译成 system + user 两条消息，
// 请求和结果展示归面板管。

enum PromptAI {

    // MARK: 压缩

    static func compress(_ text: String, allowedGroups: [CompressionGroup]) -> (system: String, user: String) {
        let system = """
        你是提示词压缩器。把用户发来的提示词精简：删掉没有信息量的部分，换成直给的表达。

        规则：
        - 只删「删了不影响模型理解」的内容：礼貌套话、语气垫词、冗长表达、重复的句子、多余空白和标点。
        - 代码块、行内代码、各种引号里的内容、{{变量}} 占位符，一个字符都不能动。
        - 「大概 10 分钟」「请务必」「请注意」这类带信息量的词要保留。
        - 不许改变原意，不许新增要求，不许删具体约束和数字。
        - 只输出压缩后的提示词正文，不要任何解释、前后缀或代码围栏。
        """

        let groupNames = allowedGroups.isEmpty
            ? "全部类别"
            : allowedGroups.map(\.rawValue).joined(separator: "、")
        let user = """
        允许删减的类别：\(groupNames)。

        原文：
        \(text)
        """
        return (system, user)
    }

    // MARK: 扩写

    static func expand(_ input: String, options: PromptExpandOptions) -> (system: String, user: String) {
        let system = """
        你是资深提示词工程师，擅长把一句话需求扩写成结构化、细节丰富的专业提示词。
        输出要求：
        - 按用户指定的目标类型组织成多个小节，每个小节一个加粗标题。
        - 拿不准的细节不要编造具体值——写「（待定：……）」并说明为什么需要用户定。
        - 只输出提示词本身，不要解释你做了什么。
        """

        var lines: [String] = []
        lines.append("目标类型：\(options.target.rawValue)（\(options.target.note)）")
        lines.append("详细程度：\(options.detail.rawValue)——\(detailNote(options.detail))")
        lines.append("输出语言：\(options.language.rawValue)")

        if options.target == .image {
            if options.style != .auto {
                lines.append("风格：\(options.style.rawValue)（必须贯穿全文，不要只在风格节提一句）")
            } else {
                lines.append("风格：你来定一个最适合主体的，并在风格节里说明为什么")
            }
            if options.aspect != .none {
                lines.append("画幅：\(options.aspect.rawValue)，在结尾输出参数 \(options.aspect.flag ?? "--ar")")
            }
            lines.append(options.includeNegative ? "要附一段负向提示词（--no 参数或单独一节）" : "不需要负向提示词")
        }

        lines.append("""
        用户的一句话：
        \(input)
        """)
        return (system, lines.joined(separator: "\n"))
    }

    private static func detailNote(_ detail: ExpandDetail) -> String {
        switch detail {
        case .brief: return "每个小节 1-2 行，能省则省"
        case .standard: return "每个小节 2-4 行，重点展开"
        case .rich: return "充分展开，细节给足"
        }
    }
}
