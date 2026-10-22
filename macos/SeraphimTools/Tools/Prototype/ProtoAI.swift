import Foundation

// MARK: - 原型助手的 AI 指令
//
// AI 驱动开关打开后，四个模式的生成结果由模型产出。这里把表单数据 +
// 模型里现成的元数据（输出物骨架 / 页面区域 / 组件组成 / Mermaid 规则）
// 翻译成 system + user，请求与展示归面板管。

enum ProtoAI {

    private static func bulletList(_ items: [String]) -> String {
        items.map { "- \($0)" }.joined(separator: "\n")
    }

    // MARK: 需求

    static func requirement(_ input: ProtoRequirementInput) -> (system: String, user: String) {
        let system = """
        你是资深产品经理，擅长把粗糙的产品想法整理成能直接开工的需求文档。
        要求：
        - 按用户指定的交付物逐项输出，每个交付物是一个二级标题，里面的小节必须覆盖用户给的骨架，一节都不能漏。
        - 功能描述要具体到「用户做什么、系统怎么响应」，不要停留在复述功能名。
        - 拿不准的地方（定价、账号体系、第三方依赖这类）集中列在最后一节「待确认」，给出选项和你的建议，不要替用户拍板。
        - 输出 Markdown，语言：中文。
        """

        let deliverables = ProtoDeliverable.allCases
            .filter { input.deliverables.contains($0) }
            .map { "\($0.title)（必须包含小节：\($0.outline.joined(separator: "、"))）" }

        let picked = deliverables.isEmpty ? "PRD 需求文档（用户没勾，默认只出这个）" : deliverables.joined(separator: "\n")

        let user = """
        产品名称：\(input.name.isEmpty ? "（未提供，你起一个临时的）" : input.name)
        一句话：\(input.idea.isEmpty ? "（未提供）" : input.idea)
        目标用户：\(input.audience.isEmpty ? "（未提供，按产品形态合理假设并标注）" : input.audience)
        落地形态：\(input.platform.title)
        技术栈：\(input.stack == .unspecified ? "由你推荐并在文档开头说明理由" : input.stack.title)

        核心功能：
        \(input.features.isEmpty ? "（未提供，按产品形态推断核心功能并标注为假设）" : bulletList(input.features))

        约束与红线：
        \(input.constraints.isEmpty ? "（无）" : bulletList(input.constraints))

        补充说明：\(input.extra.isEmpty ? "（无）" : input.extra)

        要交付的内容与对应骨架：
        \(picked)
        """
        return (system, user)
    }

    // MARK: 页面

    static func page(_ input: ProtoPageInput) -> (system: String, user: String) {
        let system = """
        你是产品设计师，擅长写「给 AI 看的页面原型描述」——读者会照着它直接生成页面代码。
        要求：
        - 自上而下按区域组织：每个区域一个小节，写清这个区域放什么、长什么样、有什么交互。
        - 字段写成表格（字段 / 说明 / 呈现方式）。
        - 用户勾选的每一种页面状态都要写一节：空的时候长什么样、用户该看到什么。
        - 末尾加一节「这个页面最容易做砸的点」，给 3-5 条。
        - 拿不准的数据来源和文案写「（待定：……）」，不要编。
        - 输出 Markdown，语言：中文。
        """

        let states = ProtoPageState.allCases
            .filter { input.states.contains($0) }
            .map { "\($0.title)——\($0.brief)" }

        let user = """
        页面名称：\(input.pageName.isEmpty ? "（未提供）" : input.pageName)
        页面类型：\(input.kind.title)
        这页要干什么：\(input.purpose.isEmpty ? "（未提供，按页面类型合理推断）" : input.purpose)
        落地形态：\(input.platform.title)
        技术栈：\(input.stack == .unspecified ? "由你推荐" : input.stack.title)

        这类页面的典型区域划分（必须逐个覆盖）：
        \(bulletList(input.kind.zones))

        这类页面的设计要点：
        \(bulletList(input.kind.focus))

        字段：
        \(input.fields.isEmpty ? "（未提供，你按用途补一版并标注为建议）" : bulletList(input.fields))

        操作与交互：
        \(input.actions.isEmpty ? "（未提供，你按用途补一版并标注为建议）" : bulletList(input.actions))

        要覆盖的页面状态：
        \(states.isEmpty ? "加载中、空数据（页面默认必做）" : bulletList(states))

        补充说明：\(input.extra.isEmpty ? "（无）" : input.extra)
        """
        return (system, user)
    }

    // MARK: 组件

    static func component(_ input: ProtoComponentInput) -> (system: String, user: String) {
        let system = """
        你是组件库设计者，擅长写「给 AI 看的组件规格」——读者会照着它实现组件代码或低代码配置。
        要求：
        - 按小节组织：用途 / 属性表（属性 / 类型 / 默认值 / 说明）/ 组成结构 / 状态与变体 / 交互与反馈 / 无障碍 / 验收要点。
        - 属性表必须完整覆盖用户给的属性，缺的常用属性你来补并标注「建议补充」。
        - 每个勾选的变体写清「什么时候出现、长什么样、行为差在哪」。
        - 拿不准的写「（待定：……）」，不要编。
        - 输出 Markdown，语言：中文。
        """

        let variants = ProtoVariant.allCases
            .filter { input.variants.contains($0) }
            .map { "\($0.title)——\($0.brief)" }

        var extra: [String] = []
        if input.includeA11y { extra.append("包含无障碍小节（键盘操作、读屏、对比度）") }
        if input.includeTesting { extra.append("包含验收要点小节（可直接当测试用例）") }

        let user = """
        组件名称：\(input.name.isEmpty ? "（未提供）" : input.name)
        组件类型：\(input.kind.title)
        用途：\(input.purpose.isEmpty ? "（未提供，按组件类型合理推断）" : input.purpose)
        落地形态：\(input.platform.title)
        技术栈：\(input.stack == .unspecified ? "由你推荐" : input.stack.title)

        这类组件的典型组成（必须逐项覆盖）：
        \(bulletList(input.kind.parts))

        这类组件的常见坑：
        \(bulletList(input.kind.focus))

        属性：
        \(input.props.isEmpty ? "（未提供，你先提一版等用户确认）" : bulletList(input.props))

        要覆盖的变体：
        \(variants.isEmpty ? "（无）" : bulletList(variants))

        交互与反馈：
        \(input.interactions.isEmpty ? "（未提供，你按组件类型补一版并标注为建议）" : bulletList(input.interactions))

        额外要求：\(extra.isEmpty ? "（无）" : bulletList(extra))
        补充说明：\(input.extra.isEmpty ? "（无）" : input.extra)
        """
        return (system, user)
    }

    // MARK: 流程图

    static func flow(_ input: ProtoFlowInput) -> (system: String, user: String) {
        let system = """
        你是流程图工程师，输出 Mermaid flowchart 代码。硬性规则：
        - 节点 id 用 N1、N2…… 按顺序编号，与节点文字完全脱钩。
        - 形状：开始/结束用 stadium（[("文字")]），处理用矩形（[文字]），判断用菱形（{文字}），输入输出用平行四边形（[/文字/]），子流程用双边框（[[文字]]），数据用圆柱（[(文字)]）。
        - 文字里出现双引号、方括号、圆括号、花括号、竖线、尖括号、井号时，整个文字用双引号包裹，内部的 " 转义成 #quot;。
        - 判断节点必须有两条边：|是| 和 |否|，分别指向不同节点；分支汇合后可以共用后续节点。
        - 图方向用 \(input.direction.mermaid)。
        - 只输出 Mermaid 代码本身（可以带 ```mermaid 围栏），不要任何解释。
        """

        var lines: [String] = []
        lines.append("流程名称：\(input.title.isEmpty ? "（未提供）" : input.title)")
        lines.append("步骤（按顺序）：")
        for (index, node) in input.nodes.enumerated() {
            var line = "\(index + 1). [\(node.kind.title)] \(node.displayText)"
            if node.kind == .decision, let target = node.elseTarget,
               let targetIndex = input.nodes.firstIndex(where: { $0.id == target }) {
                line += "（条件不成立时走第 \(targetIndex + 1) 步，标签「\(node.elseLabel)」）"
            }
            if node.isTerminal {
                line += "（流程到此结束，后面不连）"
            }
            lines.append(line)
        }
        lines.append("把这些步骤画成 Mermaid 流程图，判断节点记得画「是 / 否」两条边。")
        return (system, lines.joined(separator: "\n"))
    }
}
