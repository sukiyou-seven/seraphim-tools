import AppKit
import SwiftUI

/// 尺码换算：鞋码、衣服尺码，欧码 / 美码 / 国内码互相对照。
///
/// 这一页的立场是「先量身体，再对表」——标号是各家自己定的约定，
/// 净尺寸才是跨体系唯一能对齐的东西。所以每张表都以净尺寸当轴心列，
/// 表头里蓝色的那几列就是它。
struct SizePanel: View {
    @AppStorage("sizeChartID") private var chartID = "adultShoe"
    @AppStorage("sizeQuery") private var query = ""
    @AppStorage("sizeQueryColumn") private var queryColumnID = ""
    @AppStorage("sizeShowAllColumns") private var showAllColumns = false

    @State private var toast: String?

    private var chart: SizeChart {
        SizeEngine.chart(id: chartID) ?? SizeEngine.adultShoes
    }

    private var columns: [SizeColumn] {
        showAllColumns ? chart.columns : chart.defaultColumns
    }

    private var queryColumn: SizeColumn? {
        chart.columns.first { $0.id == queryColumnID }
    }

    private var matched: SizeMatch? {
        SizeEngine.locate(query, in: chart, column: queryColumn)
    }

    /// 换了表，之前选的体系可能不存在了，落回自动识别
    private func dropStaleColumn() {
        if queryColumn == nil { queryColumnID = "" }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    chartCard
                    queryCard
                    tableCard
                    referenceCards
                }
                .padding(20)
            }
            .onChange(of: matched?.row.id) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .toast($toast)
        .onChange(of: chartID) { _, _ in dropStaleColumn() }
        .onAppear { dropStaleColumn() }
    }

    // MARK: - 选表

    private var chartCard: some View {
        ToolCard(title: "对照表", systemImage: "tablecells") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(SizeGroup.allCases) { group in
                    groupPicker(group)
                }

                HStack(spacing: 8) {
                    Text("表里蓝色的列是量出来的净尺寸，其余是各家自己定的标号。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func groupPicker(_ group: SizeGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(group.rawValue, systemImage: group.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)

            FlowRow(spacing: 6) {
                ForEach(SizeEngine.charts(in: group)) { item in
                    ChipButton(title: item.title, isSelected: item.id == chart.id) {
                        chartID = item.id
                    }
                }
            }
        }
    }

    // MARK: - 查码

    private var queryCard: some View {
        ToolCard(title: "我拿的是哪个码", systemImage: "magnifyingglass") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    columnMenu

                    TextField(inputHint, text: $query)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(maxWidth: 320)

                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Text("清空").font(.system(size: 11.5))
                        }
                        .controlSize(.small)
                    }

                    Spacer(minLength: 0)
                }

                queryResult
            }
        }
    }

    private var columnMenu: some View {
        Menu {
            Button {
                queryColumnID = ""
            } label: {
                if queryColumnID.isEmpty {
                    Label("自动识别", systemImage: "checkmark")
                } else {
                    Text("自动识别")
                }
            }

            Divider()

            ForEach(chart.columns) { column in
                Button {
                    queryColumnID = column.id
                } label: {
                    if column.id == queryColumnID {
                        Label(column.title, systemImage: "checkmark")
                    } else {
                        Text(column.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(queryColumn?.title ?? "自动识别")
                    .font(.system(size: 12.5, weight: .medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.07), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder
    private var queryResult: some View {
        if let matched {
            matchedView(matched)
        } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("填哪个体系的码都行，也可以直接填量出来的净尺寸（写清楚 cm / mm）。带「码」字、带体系前缀（EU42、欧码42）都认。")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ErrorBanner(message: "认不出「\(query)」。试试 42 / EU42 / 265mm / 26.5cm 这样的写法，或者把左边的体系换成你手上那个码的体系。")
        }
    }

    private func matchedView(_ found: SizeMatch) -> some View {
        let text = SizeEngine.summary(found.row, in: chart, columns: columns)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                NoticeTag(
                    text: found.byMeasurement ? "按 \(found.column.title) 就近落档" : "命中 \(found.column.title)",
                    systemImage: found.byMeasurement ? "ruler" : "target",
                    tint: .accentColor
                )
                if found.byMeasurement {
                    NoticeTag(
                        text: "净尺寸 \(SizeEngine.sizeText(found.row.pivot))",
                        systemImage: "arrow.left.arrow.right",
                        tint: .secondary
                    )
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 10) {
                Text(text)
                    .font(.system(size: 12.5, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                CopyIconButton(text: text)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.22))
        )
    }

    private var inputHint: String {
        switch chart.id {
        case "adultShoe": return "42 · EU 42 · 265mm · 26.5cm"
        case "kidsShoe": return "28 · EU 28 · 175mm · 17.5cm"
        case "womenBottom": return "M · 165/72A · 38 · 72cm"
        case "menTop": return "175/92A · L · 48 · 92cm"
        case "menBottom": return "L · 180/80A · W31 · 80cm"
        case "kidsCloth": return "120 · 身高 120cm"
        default: return "M · 165/88A · 38 · 88cm"
        }
    }

    // MARK: - 对照表

    private var tableCard: some View {
        ToolCard(title: chart.title, systemImage: chart.systemImage) {
            VStack(alignment: .leading, spacing: 10) {
                tableToolbar

                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        tableHeader
                        Divider()
                        ForEach(chart.rows) { row in
                            SizeTableRow(
                                row: row,
                                chart: chart,
                                columns: columns,
                                isMatched: row.id == matched?.row.id
                            )
                            if row.id != chart.rows.last?.id {
                                Divider().opacity(0.25)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.025))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07))
                )
            }
        }
    }

    private var tableToolbar: some View {
        HStack(spacing: 10) {
            Text("\(chart.rows.count) 行")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Toggle("显示全部列", isOn: $showAllColumns)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11.5))

            Spacer(minLength: 0)

            Button {
                copyTable()
            } label: {
                Label("复制表格", systemImage: "doc.on.doc")
                    .font(.system(size: 11.5))
            }
            .controlSize(.small)
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 6) {
            ForEach(columns) { column in
                Text(column.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(column.isMeasurement ? Color.accentColor : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: column.width)
            }
            Color.clear.frame(width: 24)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func copyTable() {
        let header = columns.map(\.title).joined(separator: "\t")
        let body = chart.rows
            .map { row in columns.map { row.value($0.id) }.joined(separator: "\t") }
            .joined(separator: "\n")
        NSPasteboard.copyString([header, body].joined(separator: "\n"))
        toast = "已复制 \(chart.title)（制表符分隔，可直接贴进表格）"
    }

    // MARK: - 量体与注意事项

    private var referenceCards: some View {
        VStack(spacing: 14) {
            ToolCard(title: "怎么量（\(chart.pivotColumn.title)）", systemImage: "ruler") {
                bulletList(chart.measure, numbered: true)
            }
            ToolCard(title: "注意事项", systemImage: "info.circle") {
                bulletList(chart.notes, numbered: false)
            }
        }
    }

    private func bulletList(_ items: [String], numbered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text(numbered ? "\(index + 1)" : "·")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: numbered ? 14 : 10, alignment: .trailing)
                        .padding(.top, 1)
                    Text(SizePanel.rich(item))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// 备注里用 `**…**` 标重点，走一遍 markdown 渲染成粗体
    static func rich(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

// MARK: - 表格行

private struct SizeTableRow: View {
    let row: SizeRow
    let chart: SizeChart
    let columns: [SizeColumn]
    let isMatched: Bool

    private var summary: String {
        SizeEngine.summary(row, in: chart, columns: columns)
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(columns) { column in
                cell(column)
            }
            CopyIconButton(text: summary)
                .frame(width: 24)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isMatched ? Color.accentColor.opacity(0.16) : Color.clear)
        .overlay(alignment: .leading) {
            if isMatched {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
            }
        }
    }

    private func cell(_ column: SizeColumn) -> some View {
        let isPivot = column.id == chart.pivotColumnID
        return Text(row.value(column.id))
            .font(.system(size: 12, weight: isPivot ? .semibold : .regular, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: column.width)
    }
}
