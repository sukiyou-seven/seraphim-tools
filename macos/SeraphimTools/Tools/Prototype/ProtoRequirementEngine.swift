import Foundation

/// 需求转提示词：脑子里一个想法 → 一份能让 AI 直接开工的需求提示词。
///
/// 这类提示词的质量不取决于辞藻，取决于**有没有把结构钉死**：
/// 告诉 AI 该输出哪几节、每节要写什么、哪些地方不许它自由发挥。
/// 所以这里最重的一块是「按勾选的输出物拼章节骨架」。
enum ProtoRequirementEngine {

    static func build(_ input: ProtoRequirementInput) -> ProtoOutput {
        var filled: [String] = []
        var todo: [String] = []
        var notes: [String] = []
        var warnings: [String] = []

        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let idea = input.idea.trimmingCharacters(in: .whitespacesAndNewlines)
        let audience = input.audience.trimmingCharacters(in: .whitespacesAndNewlines)
        let features = ProtoText.items(input.features.joined(separator: "\n"))
        let constraints = ProtoText.items(input.constraints.joined(separator: "\n"))
        let extra = input.extra.trimmingCharacters(in: .whitespacesAndNewlines)

        // ── 输入体检 ──
        if name.isEmpty && idea.isEmpty {
            warnings.append("产品名称和一句话描述都还是空的，先写一句「这玩意儿是干什么的」，哪怕只有几个字。")
        }
        if features.isEmpty {
            warnings.append("核心功能一条都没写。哪怕先列三五个动词短语也够——AI 拿到空清单只会自己编一套。")
        }
        if input.deliverables.isEmpty {
            warnings.append("没勾任何输出物，默认按 PRD 来输出。想要页面描述或数据模型，勾上会让提示词精确很多。")
        }

        // ── 必须你自己定的部分 ──
        if audience.isEmpty {
            todo.append("目标用户：这是 AI 猜不出来的一项。写上具体人群（比如「25~35 岁、一线城市、自己做小生意的店主」），比你写十句功能描述都管用。")
        }
        if input.stack == .unspecified {
            todo.append("技术栈：你选的「不限」会把选择权交给 AI。如果心里已经有数（比如公司只用 Vue），选上，AI 就不会给你一套用不上的方案。")
        }
        if input.platform == .admin {
            todo.append("权限模型：管理后台一定要先想清楚有几种角色、每种角色能看什么。这一项建议你自己列出来，AI 编的权限表多数不能直接用。")
        }

        // ── 工具补了什么 ──
        filled.append("把「\(input.platform.title)」展开成一句形态约束（\(firstSentence(input.platform.brief))），免得 AI 按网页的习惯给你做小程序。")
        if input.stack != .unspecified {
            filled.append("钉死了技术栈：\(input.stack.brief)")
        }
        let deliverables = input.deliverables.isEmpty ? [ProtoDeliverable.prd] : ProtoDeliverable.allCases.filter { input.deliverables.contains($0) }
        filled.append("按 \(deliverables.count) 项输出物各写好了章节骨架，共 \(deliverables.reduce(0) { $0 + $1.outline.count }) 个小节——AI 少了自由发挥的余地，你验收时也好对。")
        if !features.isEmpty {
            filled.append("功能清单整理成了 \(features.count) 条带编号的条目。")
        }
        filled.append("补了一段「拿不准的列进待确认，不要自己编」——不写这句，AI 会一本正经地编出一堆你根本没提过的需求。")

        if features.count > 6 {
            notes.append("功能列了 \(features.count) 条。如果里面有明显的主次，建议在提示词后面另加一句「按我的顺序理解优先级」，否则 AI 会自己重排。")
        }
        if !constraints.isEmpty {
            notes.append("约束写了 \(constraints.count) 条，会原样带进提示词，AI 通常会照做。")
        }
        if name.count > 24 {
            notes.append("产品名偏长，AI 输出时可能反复复述。可以在提示词里补一句简称。")
        }

        // ── 拼正文 ──
        var out: [String] = []

        out.append("# 角色")
        out.append("""
        你是一位既做过产品、也能写前端代码的工程师。下面是我对一个产品的完整想法，
        请先按要求输出文档，**不要直接开始写代码**。
        """.trimmingCharacters(in: .whitespacesAndNewlines))

        out.append("# 我的产品")
        var brief: [String] = []
        if !name.isEmpty { brief.append("- 名称：\(name)") }
        if !idea.isEmpty { brief.append("- 一句话描述：\(idea)") }
        if !audience.isEmpty {
            brief.append("- 目标用户：\(audience)")
        } else {
            brief.append("- 目标用户：（还没定，你可以给建议，但要标出来是建议）")
        }
        brief.append("- 落地形态：\(input.platform.title) —— \(input.platform.brief)")
        if input.stack != .unspecified {
            brief.append("- 技术栈：\(input.stack.brief)")
        } else {
            brief.append("- 技术栈：不限，你按最合适的选，但要说明为什么选它")
        }
        out.append(brief.joined(separator: "\n"))

        if !features.isEmpty {
            out.append("# 核心功能")
            out.append(ProtoText.numbered(features))
        }

        out.append("# 我要你输出什么")
        out.append("""
        请严格按下面的章节和顺序输出。**不要增删章节，不要把小节合并或跳过。**
        """.trimmingCharacters(in: .whitespacesAndNewlines))

        let ordinals = ["一", "二", "三", "四", "五", "六", "七", "八"]
        for (index, deliverable) in deliverables.enumerated() {
            let ordinal = index < ordinals.count ? ordinals[index] : "\(index + 1)"
            var section = "## \(ordinal)、\(deliverable.title)\n"
            section += ProtoText.numbered(deliverable.outline)
            out.append(section)
        }

        if !constraints.isEmpty {
            out.append("# 必须遵守的约束")
            out.append(ProtoText.bulleted(constraints))
        }

        if !extra.isEmpty {
            out.append("# 补充说明")
            out.append(extra)
        }

        out.append("# 输出要求")
        out.append(ProtoText.bulleted([
            "全文用中文，Markdown 格式；一级用 ##，具体内容用 ###",
            "这一轮不要写实现代码，先把结构和描述说清楚",
            "每条功能都要给验收标准：能点哪里、看到什么算完成",
            "需要做决定但没写的，放进最后的「待确认」章节来问我，**不要自己编一个填上去**",
            "如果你觉得我的想法里有明显矛盾或做不通的地方，单独列一节指出来，别默默改掉",
        ]))

        return ProtoOutput(
            text: out.joined(separator: "\n\n"),
            filled: filled,
            todo: todo,
            notes: notes,
            warnings: warnings
        )
    }

    /// 取一句话（形态说明可能很长，塞进「做了什么」列表里要短一点）
    private static func firstSentence(_ text: String) -> String {
        let head = text.split(separator: "，").first.map(String.init) ?? text
        return head
    }
}
