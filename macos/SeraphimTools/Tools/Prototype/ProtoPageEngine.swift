import Foundation

/// 页面原型描述生成器：一句「这页要干什么」→ 一段自上而下的文字原型。
///
/// 输出的成品是**可以直接整段丢给 AI** 的：开头两行是给 AI 的指令，
/// 中间是原型描述（人也能读懂），结尾是输出要求。
enum ProtoPageEngine {

    static func build(_ input: ProtoPageInput) -> ProtoOutput {
        var filled: [String] = []
        var todo: [String] = []
        var notes: [String] = []
        var warnings: [String] = []

        let pageName = input.pageName.trimmingCharacters(in: .whitespacesAndNewlines)
        let purpose = input.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = ProtoText.items(input.fields.joined(separator: "\n"))
        let actions = ProtoText.items(input.actions.joined(separator: "\n"))
        let extra = input.extra.trimmingCharacters(in: .whitespacesAndNewlines)

        // ── 输入体检 ──
        if pageName.isEmpty && purpose.isEmpty {
            warnings.append("页面名字和它要干什么都是空的——至少写一句「用户来这一页是要做什么」。")
        } else if purpose.isEmpty {
            warnings.append("没写页面目标。这一项决定了整页的信息优先级，值得补一句。")
        }
        if fields.isEmpty && actions.isEmpty {
            warnings.append("字段和操作都还没写，生成出来的会比较骨架。补上这两项，描述才有肉。")
        }
        if input.states.isEmpty {
            warnings.append("一个状态都没勾。加载中和没有数据这两态是必做的，不然页面出现空白时看起来就像坏了。")
        }

        // ── 必须你自己定的部分 ──
        if actions.isEmpty {
            todo.append("用户能做的操作：这一项直接决定按钮放哪、点击跳哪。写三条就够（比如「点商品进详情」「左滑删除」「右上角切换排序」）。")
        }
        if fields.isEmpty {
            todo.append("要展示的字段：先列每一条上最想让人看到的信息。列表页一般 3 个主要字段 + 1 个次要字段就到顶了。")
        }
        todo.append("区域划分用的是「\(input.kind.title)」的通用骨架，跟你脑子里那版可能不一样——直接在这段文字上改，比让我猜准得多。")

        // ── 工具补了什么 ──
        filled.append("按「\(input.kind.title)」这一类页面的常规分区，补了 \(input.kind.zones.count) 个自上而下的区域骨架。")
        filled.append("把「\(input.platform.title)」展开成一句形态约束（\(input.platform.brief)），页面尺寸和交互习惯会跟着这个走。")
        if !input.states.isEmpty {
            let ordered = ProtoPageState.allCases.filter { input.states.contains($0) }
            filled.append("按勾选补了 \(ordered.count) 种状态的具体表现写法：\(ordered.map(\.title).joined(separator: " / "))。")
        }
        if !input.kind.focus.isEmpty {
            filled.append("带上了 \(input.kind.focus.count) 条这类页面最容易做砸的地方当约束。")
        }
        filled.append("末尾加了输出要求：让 AI 先确认理解、再动手，并且不许编我没写过的东西。")

        // ── 留意 ──
        if fields.count > 6 {
            notes.append("字段写了 \(fields.count) 个。列表类页面超过 6 个字段就会挤，考虑把次要信息挪进详情页。")
        }
        if actions.count > 5 {
            notes.append("操作列了 \(actions.count) 条，同屏超过 5 个操作点，用户会不知道该点哪个。建议挑出 1 个主操作。")
        }
        if input.kind == .dashboard && fields.count < 3 {
            notes.append("看板页的指标太少，撑不起来。建议至少 4 个关键数字加一张趋势图。")
        }

        // ── 拼正文 ──
        var out: [String] = []

        out.append("""
        你要实现下面这个页面。请先按这份原型描述把页面结构说清楚（对着描述确认一遍你的理解），
        确认没有歧义之后再动手写代码。
        """.trimmingCharacters(in: .whitespacesAndNewlines))

        out.append("# 页面原型：\(pageName.isEmpty ? "未命名页面" : pageName)")

        var meta: [String] = []
        meta.append("- **形态**：\(input.platform.title) —— \(input.platform.brief)")
        meta.append("- **页面类型**：\(input.kind.title)")
        if input.stack != .unspecified {
            meta.append("- **技术栈**：\(input.stack.brief)")
        } else {
            meta.append("- **技术栈**：不限（你选最合适的，并说明选择理由）")
        }
        out.append(meta.joined(separator: "\n"))

        if !purpose.isEmpty {
            out.append("## 这个页面要干什么\n" + purpose)
        }

        out.append("## 布局骨架（从上到下）\n" + ProtoText.numbered(input.kind.zones))

        if !fields.isEmpty {
            out.append("## 要展示的字段\n" + fieldBlock(fields))
        }

        if !actions.isEmpty {
            out.append("## 用户能做的操作\n" + ProtoText.numbered(actions))
        }

        // 交互行为：把操作展开成「点了之后发生什么」的追问，
        // 很多人写需求时只写「可以删除」，没想过删完停下来是什么样
        if !actions.isEmpty {
            out.append("## 交互要交代清楚的细节\n" + ProtoText.bulleted([
                "每个操作点了之后发生什么，失败又怎样（要给出提示文案的写法）",
                "跳转到别的页面时，返回后原来的位置和筛选条件要不要保留",
                "哪些操作需要二次确认（涉及删除、支付、退出的），哪些不要",
                "连续点击同一个按钮时怎么防重复",
            ]))
        }

        if !input.states.isEmpty {
            let ordered = ProtoPageState.allCases.filter { input.states.contains($0) }
            let block = ordered.map { "- **\($0.title)**：\($0.brief)" }.joined(separator: "\n")
            out.append("## 各种状态下这一页长什么样\n" + block)
        }

        if !input.kind.focus.isEmpty {
            out.append("## 这类页面容易做砸的地方（实现时避开）\n" + ProtoText.bulleted(input.kind.focus))
        }

        if !extra.isEmpty {
            out.append("## 补充说明\n" + extra)
        }

        var require: [String] = [
            "先在回答开头用 5 行以内复述你理解的页面结构和信息层级，等我确认",
            "然后给出实现，按上面列的区域顺序来组织",
            "所有文案都要写具体的示例文字，不要留 `标题1`、`{内容}` 这类占位符",
            "上面没写到的东西不要自己加功能；如果确实缺，列在最后「需要你确认」里问我",
        ]
        if input.platform == .miniProgram {
            require.append("用 rpx 做尺寸单位，注意小程序没有 DOM，别用浏览器专属 API")
        }
        out.append("## 输出要求\n" + ProtoText.bulleted(require))

        return ProtoOutput(
            text: out.joined(separator: "\n\n"),
            filled: filled,
            todo: todo,
            notes: notes,
            warnings: warnings
        )
    }

    /// 字段清单：只要有一条写了 `名字: 说明`，就排成表格；否则用列表。
    /// 全用表格会在「只写了名字」的场景下留一堆空格子，反而难看。
    private static func fieldBlock(_ fields: [String]) -> String {
        let parsed = fields.map { line -> (name: String, note: String) in
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
            var rows = ["| 字段 | 说明 |", "| --- | --- |"]
            for item in parsed {
                rows.append("| \(item.name) | \(item.note.isEmpty ? "—" : item.note) |")
            }
            return rows.joined(separator: "\n")
        }

        return ProtoText.bulleted(parsed.map(\.name))
    }
}
