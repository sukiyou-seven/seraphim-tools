import Foundation

/// 流程图的预览行（界面照着画简易示意图用）
struct FlowPreviewStep: Identifiable, Sendable {
    let id: UUID
    let index: Int
    let kind: FlowNodeKind
    let text: String
    /// 判断节点的「否则」去哪（已经渲染成人话）；不是判断节点或没画就是 nil
    let elseLine: String?
    /// 这个节点是否跟下一个节点连了线
    let hasNextEdge: Bool
    /// 标了「流程到此结束」
    let isTerminal: Bool
}

/// 拖节点 → 出 Mermaid 代码。
///
/// 这里最容易出错的两件事，都单独处理了：
/// 1. **节点 id 不能直接拿用户的文字**——中文、空格、括号全会让 Mermaid 解析失败，
///    所以统一编号成 N1/N2，文字放标签里。
/// 2. **标签里的特殊字符**必须用引号裹起来，而且引号本身要转成 `#quot;`。
enum ProtoFlowEngine {

    // MARK: - 生成

    static func mermaid(_ input: ProtoFlowInput) -> String {
        guard !input.nodes.isEmpty else {
            return """
            flowchart \(input.direction.mermaid)
                %% 还没有节点。在上面加一个「开始」就开始画了。
            """
        }

        var lines: [String] = ["flowchart \(input.direction.mermaid)"]

        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            lines.append("    %% \(commentSafe(title))")
        }

        // 先集中声明所有节点，再集中声明连线——读起来比混在一起清楚
        for (index, node) in input.nodes.enumerated() {
            lines.append("    \(nodeID(index))\(shapeOf(node))")
        }

        var edges: [String] = []
        for (index, node) in input.nodes.enumerated() {
            let id = nodeID(index)
            // 标了「流程到此结束」的节点不连下一条；最后一位本来也没得连
            let connectsNext = !node.isTerminal && index + 1 < input.nodes.count

            if node.kind == .decision {
                if connectsNext {
                    edges.append("    \(id) -->|是| \(nodeID(index + 1))")
                }
                if let target = node.elseTarget,
                   let targetIndex = input.nodes.firstIndex(where: { $0.id == target }) {
                    edges.append("    \(id) -->|\(labelSafe(node.elseLabel, fallback: "否"))| \(nodeID(targetIndex))")
                }
            } else if connectsNext {
                edges.append("    \(id) --> \(nodeID(index + 1))")
            }
        }

        if !edges.isEmpty {
            lines.append("")
            lines.append(contentsOf: edges)
        }

        return lines.joined(separator: "\n")
    }

    /// 节点在代码里的名字。固定 N1、N2……跟文字脱钩，中文和符号都进不了 id 位置。
    static func nodeID(_ index: Int) -> String { "N\(index + 1)" }

    /// `N1([开始])` 这半截——形状 + 已经转义好的文本
    static func shapeOf(_ node: FlowNode) -> String {
        let (open, close) = node.kind.delimiters
        return "\(open)\(textToken(node))\(close)"
    }

    /// 把节点文字转成能塞进形状里的 token。
    ///
    /// 含 `" [ ] ( ) { } | < > #` 或首尾带空格时必须用引号裹住，
    /// 否则 Mermaid 会把它们当语法。裹之前引号本身要换成 `#quot;`。
    static func textToken(_ node: FlowNode) -> String {
        var value = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { value = node.kind.defaultText }

        value = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "<br/>")

        let specials: Set<Character> = ["\"", "[", "]", "(", ")", "{", "}", "|", "<", ">", "#"]
        let needsQuote = value.contains(where: { specials.contains($0) })

        guard needsQuote else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "#quot;"))\""
    }

    /// 连线标签里的 `|` 会把语法截断，换成全角
    static func labelSafe(_ text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? fallback : trimmed
        return base
            .replacingOccurrences(of: "|", with: "｜")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func commentSafe(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    // MARK: - 校验

    /// 给的是「建议」不是「错误」——图能画出来，但这么画会让看的人犯迷糊。
    static func validate(_ input: ProtoFlowInput) -> [String] {
        guard !input.nodes.isEmpty else { return ["还没有任何节点，先加一个「开始 / 结束」。"] }

        var out: [String] = []

        let blank = input.nodes.enumerated().filter { $0.element.isEmptyText }.map { $0.offset + 1 }
        if !blank.isEmpty {
            out.append("第 \(blank.map(String.init).joined(separator: "、")) 个节点还没填文字，现在用的是默认名，图上会显示成「\(input.nodes[blank[0] - 1].kind.defaultText)」。")
        }

        if input.nodes.count < 2 {
            out.append("只有 1 个节点，连线画不出来。最少要有头和尾两个。")
        }

        if !input.nodes.contains(where: { $0.kind == .start }) {
            out.append("没有「开始 / 结束」节点。流程图习惯上要有明确的起点，看的人一眼能知道从哪进。")
        }

        if let last = input.nodes.last, last.kind == .decision, !last.isTerminal {
            out.append("最后一个节点是判断，它下面没接东西，「是」这一支就断在那儿了。")
        }

        let dangling = input.nodes.filter { $0.kind == .decision && $0.elseTarget == nil }.count
        if dangling > 0 {
            out.append("有 \(dangling) 个判断节点没写明「不成立时去哪」，图上只会画「是」这一支。")
        }

        if input.nodes.contains(where: { $0.elseTarget == $0.id }) {
            out.append("有个判断节点的「否则」指向了自己，会画成一个死循环。")
        }

        // 删节点时可能留下指向已删除节点的分支——图会静默少一条线
        let knownIDs = Set(input.nodes.map(\.id))
        let hasDanglingBranch = input.nodes.contains { node in
            guard let target = node.elseTarget else { return false }
            return !knownIDs.contains(target)
        }
        if hasDanglingBranch {
            out.append("有分支指向了已经被删掉的节点，那条线画不出来，重新选一下目标。")
        }

        for (index, node) in input.nodes.enumerated() where node.kind == .decision {
            guard node.elseTarget != nil else { continue }
            if let target = node.elseTarget,
               let targetIndex = input.nodes.firstIndex(where: { $0.id == target }),
               targetIndex == index + 1, !node.isTerminal {
                out.append("第 \(index + 1) 个判断节点的「是」和「否」都指向同一个节点，这条分支等于没分。")
            }
        }

        if input.nodes.count > 20 {
            out.append("节点有 \(input.nodes.count) 个，一屏已经看不出主线了。超过 20 步建议拆成两张图。")
        }

        return out
    }

    // MARK: - 界面预览

    static func preview(_ input: ProtoFlowInput) -> [FlowPreviewStep] {
        input.nodes.enumerated().map { index, node in
            var elseLine: String?
            if node.kind == .decision, let target = node.elseTarget,
               let targetIndex = input.nodes.firstIndex(where: { $0.id == target }) {
                elseLine = "\(labelSafe(node.elseLabel, fallback: "否")) → \(input.nodes[targetIndex].displayText)"
            }
            return FlowPreviewStep(
                id: node.id,
                index: index,
                kind: node.kind,
                text: node.displayText,
                elseLine: elseLine,
                hasNextEdge: !node.isTerminal && index + 1 < input.nodes.count,
                isTerminal: node.isTerminal
            )
        }
    }

    // MARK: - 导出

    /// 自包含的 HTML 预览页。Mermaid 本体走 CDN，所以断网时图渲染不出来，
    /// 但代码块还在，页面上会如实说明这一点。
    static func htmlPreview(_ input: ProtoFlowInput) -> String {
        let title = escapeHTML(input.effectiveTitle)
        let code = escapeHTML(mermaid(input))

        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(title)</title>
        <style>
          :root { color-scheme: light dark; }
          body {
            margin: 0; padding: 28px 20px 60px;
            font-family: -apple-system, "PingFang SC", "Helvetica Neue", sans-serif;
            background: #ffffff; color: #1c1c1e;
          }
          @media (prefers-color-scheme: dark) {
            body { background: #1c1c1e; color: #f2f2f7; }
            pre { background: #2c2c2e !important; border-color: #3a3a3c !important; }
          }
          h1 { font-size: 18px; font-weight: 600; margin: 0 0 6px; }
          .hint { font-size: 12px; color: #8e8e93; margin-bottom: 22px; line-height: 1.6; }
          .wrap { display: flex; justify-content: center; padding: 12px 0 28px; }
          .mermaid { width: 100%; text-align: center; }
          pre {
            background: #f7f7f9; border: 1px solid #e5e5ea; border-radius: 10px;
            padding: 14px 16px; font-size: 12.5px; line-height: 1.6;
            overflow-x: auto; font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
          }
          details summary { cursor: pointer; font-size: 12px; color: #8e8e93; margin-bottom: 8px; }
        </style>
        </head>
        <body>
          <h1>\(title)</h1>
          <p class="hint">这张图由 mermaid 渲染。如果下面只显示了一堆代码没变成图，说明当前网络加载不到 CDN——代码本身是好的，可以直接粘到 mermaid.live 去看。</p>
          <div class="wrap"><pre class="mermaid">\(code)</pre></div>
          <details>
            <summary>看 Mermaid 源码</summary>
            <pre>\(code)</pre>
          </details>
          <script type="module">
            import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
            mermaid.initialize({ startOnLoad: true, theme: 'neutral', securityLevel: 'loose' });
          </script>
        </body>
        </html>
        """
    }

    static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
