import Foundation

/// 组件描述生成：描述想要的按钮 / 弹窗 / 表单 → 一份 AI 能照着实现的组件规格。
///
/// 组件难做的原因往往不是功能复杂，而是**边界没交代**：变体有几档、禁用时什么样、
/// 文案长两倍会不会撑破。所以这里把「由哪几部分组成」和「要支持哪些变体」
/// 从组件类型的知识里带出来，用户只需要填他真正关心的那几项。
enum ProtoComponentEngine {

    static func build(_ input: ProtoComponentInput) -> ProtoOutput {
        var filled: [String] = []
        var todo: [String] = []
        var notes: [String] = []
        var warnings: [String] = []

        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let purpose = input.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        let props = ProtoText.items(input.props.joined(separator: "\n"))
        let interactions = ProtoText.items(input.interactions.joined(separator: "\n"))
        let extra = input.extra.trimmingCharacters(in: .whitespacesAndNewlines)

        // ── 输入体检 ──
        if name.isEmpty && purpose.isEmpty {
            warnings.append("组件名字和用途都是空的。写一句「它是干什么用的」，生成出来的规格才不会跑偏。")
        }
        if purpose.isEmpty {
            warnings.append("没写用途。同一个「按钮」用在表单提交和用在不重要的次要操作上，规格完全不同。")
        }
        if props.isEmpty {
            warnings.append("属性一个都没写，这一节会交给 AI 自己提一版建议——但核心那一两个可调项还是你定更准。")
        }
        if input.variants.isEmpty {
            warnings.append("变体一个都没勾。只做一种样子的组件，用第二次就会被硬改成别的样子。")
        }

        // ── 必须你自己定的部分 ──
        if props.isEmpty {
            todo.append("属性表：至少想清楚「这个组件最核心的一个可调项是什么」（按钮是语气？表格是列定义？弹窗是标题和按钮文案？）。")
        }
        if interactions.isEmpty {
            todo.append("交互：点一下之后发生什么、失败了怎么提示。这一项写清楚，AI 才写得出像样的反馈逻辑。")
        }
        if input.stack == .lowCode {
            todo.append("低代码平台：不同平台的组件能力差得远。确认一下你要的组件在目标平台里是内置的还是要自己拼，这决定了规格该怎么写。")
        }

        // ── 工具补了什么 ──
        filled.append("按「\(input.kind.title)」这一类组件，补了 \(input.kind.parts.count) 条组成部分——漏块是做组件最常见的问题（比如按钮忘了加载态）。")
        if !input.variants.isEmpty {
            let ordered = ProtoVariant.allCases.filter { input.variants.contains($0) }
            filled.append("为 \(ordered.count) 个变体写了各自的要求：\(ordered.map(\.title).joined(separator: " / "))。")
        }
        if !input.kind.focus.isEmpty {
            filled.append("带上了 \(input.kind.focus.count) 条这类组件的常见坑。")
        }
        if input.includeA11y {
            filled.append("补了无障碍要求（键盘可达、焦点可见、纯图标要有标签）——这一块自己写很容易漏。")
        }
        if input.includeTesting {
            filled.append("补了验收要点，每条都是能用眼睛或键盘验证的，不是「代码要优雅」这种空话。")
        }

        // ── 留意 ──
        if props.count > 8 {
            notes.append("属性列了 \(props.count) 个。超过 8 个的组件通常该拆成两个，或者把少用的那个改成组合式传入。")
        }
        if input.variants.contains(.tone) && input.kind == .button {
            notes.append("按钮加了语气变体时，记得约定「同一屏只出现一个主要语气」——不然页面上会冒出一堆抢注意力的按钮。")
        }
        if input.kind == .modal && input.variants.contains(.tone) {
            notes.append("弹窗的语气变体主要是给危险操作用的（删除、解绑）。别让普通确认弹窗也长成红的。")
        }

        // ── 拼正文 ──
        var out: [String] = []

        out.append("""
        我要一个「\(name.isEmpty ? "未命名组件" : name)」组件。下面是它的完整规格，
        请严格按规格实现。**有歧义的地方先问我，不要自己加功能。**
        """.trimmingCharacters(in: .whitespacesAndNewlines))

        out.append("# 组件规格：\(name.isEmpty ? "未命名组件" : name)")

        var meta: [String] = []
        meta.append("- **形态**：\(input.platform.title) —— \(input.platform.brief)")
        meta.append("- **组件类型**：\(input.kind.title)")
        if input.stack != .unspecified {
            meta.append("- **技术栈**：\(input.stack.brief)")
        } else {
            meta.append("- **技术栈**：不限（你选最合适的，并说明理由）")
        }
        out.append(meta.joined(separator: "\n"))

        if !purpose.isEmpty {
            out.append("## 用途\n" + purpose)
        }

        out.append("## 由哪几部分组成\n" + ProtoText.numbered(input.kind.parts))

        if props.isEmpty {
            out.append("## 属性\n我还没定属性表。请你先根据上面的用途提一版建议（属性名 / 类型 / 默认值 / 说明），**等我确认之后再写实现**。")
        } else {
            out.append("## 属性（Props）\n" + propsBlock(props))
        }

        if !input.variants.isEmpty {
            let ordered = ProtoVariant.allCases.filter { input.variants.contains($0) }
            let block = ordered.map { "- **\($0.title)**：\($0.brief)" }.joined(separator: "\n")
            out.append("## 要支持的变体\n" + block)
        }

        if !interactions.isEmpty {
            out.append("## 交互与反馈\n" + ProtoText.numbered(interactions))
        }

        if input.includeA11y {
            out.append("## 无障碍\n" + ProtoText.bulleted([
                "纯图标的部分要有可读的标签，读屏能念出来",
                "键盘 Tab 能走到它，并且有可见的焦点样式",
                "点按区域不小于 44×44pt，不要只让文字可点",
                "状态变化（加载、出错）要让读屏能感知到",
                "颜色不能是唯一的区分手段（选中态别只靠换个颜色）",
            ]))
        }

        if input.includeTesting {
            out.append("## 验收要点\n" + ProtoText.bulleted([
                "所有变体能在一页里同时摆出来对照着看",
                "只用键盘操作能完整走一遍，焦点在哪始终看得见",
                "把文案长度翻倍，布局不破、不溢出、不遮挡",
                "把文案清空、填超长内容、填只含数字的内容，三种情况都不崩",
                "连续快速点击触发区，不会重复触发",
            ]))
        }

        if !extra.isEmpty {
            out.append("## 补充说明\n" + extra)
        }

        out.append("## 输出要求\n" + ProtoText.bulleted([
            "一个组件一个文件，样式和逻辑写在一起方便搬运",
            "属性要有默认值，不传也能正常渲染出至少一种样子",
            "不要在组件里写死具体业务文案，文案一律从属性传进来",
            "结尾附一段最小可用的调用示例",
            "规格里没提到的功能不要加；确实缺的，列在最后「需要你确认」里",
        ]))

        return ProtoOutput(
            text: out.joined(separator: "\n\n"),
            filled: filled,
            todo: todo,
            notes: notes,
            warnings: warnings
        )
    }

    /// 属性和字段用的是同一套解析：写了 `名字: 说明` 就排表格
    private static func propsBlock(_ props: [String]) -> String {
        let parsed = props.map { line -> (name: String, note: String) in
            for separator in [": ", "：", ":"] {
                if let range = line.range(of: separator) {
                    let name = String(line[line.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let note = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty && !note.isEmpty {
                        return (name, note)
                    }
                }
            }
            return (line, "")
        }

        if parsed.contains(where: { !$0.note.isEmpty }) {
            var rows = ["| 属性 | 说明 |", "| --- | --- |"]
            for item in parsed {
                rows.append("| \(item.name) | \(item.note.isEmpty ? "—" : item.note) |")
            }
            return rows.joined(separator: "\n")
        }

        return ProtoText.bulleted(parsed.map(\.name))
    }
}
