import SwiftUI

/// 单位换算：常规单位一个值进去、一张全单位对照表出来；尺码换算另走一套离散刻度的表。
struct UnitToolView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case convert
        case size

        var id: String { rawValue }

        var title: String {
            switch self {
            case .convert: return "常规单位"
            case .size: return "尺码换算"
            }
        }
    }

    @AppStorage("unitMode") private var mode: Mode = .convert

    var body: some View {
        VStack(spacing: 0) {
            Picker("模式", selection: $mode) {
                ForEach(Mode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            switch mode {
            case .convert:
                UnitConvertPanel()
            case .size:
                SizePanel()
            }
        }
    }
}

/// 线性单位的换算面板：长度、重量、温度这些按倍率走的量。
struct UnitConvertPanel: View {
    @AppStorage("unitCategory") private var categoryID = "data"
    @AppStorage("unitSource") private var sourceUnitID = "byte"
    @AppStorage("unitKeyword") private var keyword = ""

    @State private var inputText = "1"
    @State private var didLoad = false
    @State private var toast: String?

    private var category: UnitCategory {
        UnitEngine.category(id: categoryID) ?? UnitEngine.data
    }

    private var sourceUnit: UnitDef {
        category.unit(id: sourceUnitID) ?? category.base
    }

    /// 输入框里的值。纯数字就用当前单位，带单位就按输入的单位算。
    private var value: Double {
        if let parsed = UnitEngine.parse(inputText), parsed.category.id == categoryID {
            return parsed.value
        }
        return Double(inputText.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private var rows: [UnitConversion] {
        let all = UnitEngine.convertAll(value, from: sourceUnit, in: category)
        return UnitEngine.filter(all, keyword: keyword)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                inputCard
                resultCard
            }
            .padding(20)
        }
        .toast($toast)
        .onChange(of: inputText) { _, newValue in
            absorbUnit(from: newValue)
        }
        .onChange(of: categoryID) { _, _ in
            // 换类别时把源单位落到该类别的基准单位上
            if category.unit(id: sourceUnitID) == nil {
                sourceUnitID = category.baseID
            }
        }
    }

    // MARK: - 输入

    private var inputCard: some View {
        ToolCard(title: "换算", systemImage: "arrow.left.arrow.right") {
            VStack(alignment: .leading, spacing: 14) {
                FlowRow(spacing: 6) {
                    ForEach(UnitEngine.categories) { item in
                        ChipButton(title: item.name, isSelected: item.id == categoryID) {
                            categoryID = item.id
                            sourceUnitID = item.baseID
                        }
                    }
                }

                HStack(alignment: .center, spacing: 10) {
                    TextField("输入数值，也可以直接写「3.5GB」「100 Mbps」", text: $inputText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14, design: .monospaced))
                        .frame(maxWidth: 300)
                        .onSubmit { absorbUnit(from: inputText) }

                    sourceUnitMenu

                    Text("=")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)

                    Text(UnitEngine.format(value) + " " + sourceUnit.symbol)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Text(sourceUnit.name)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    if !sourceUnit.note.isEmpty {
                        Text("· \(sourceUnit.note)")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                    if !inputText.isEmpty, Double(inputText) == nil, UnitEngine.parse(inputText) == nil {
                        NoticeTag(text: "认不出这个写法", systemImage: "exclamationmark.triangle", tint: .orange)
                    }
                }
            }
        }
    }

    private var sourceUnitMenu: some View {
        Menu {
            ForEach(category.units) { unit in
                Button {
                    sourceUnitID = unit.id
                } label: {
                    if unit.id == sourceUnitID {
                        Label("\(unit.name)（\(unit.symbol)）", systemImage: "checkmark")
                    } else {
                        Text("\(unit.name)（\(unit.symbol)）")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(sourceUnit.symbol)
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
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

    /// 用户把单位写进输入框时，自动切到对应的类别和单位
    private func absorbUnit(from text: String) {
        guard let parsed = UnitEngine.parse(text) else { return }
        if parsed.category.id != categoryID {
            categoryID = parsed.category.id
        }
        if parsed.unit.id != sourceUnitID {
            sourceUnitID = parsed.unit.id
        }
    }

    // MARK: - 结果

    private var resultCard: some View {
        ToolCard(title: "换算结果", systemImage: "list.number") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TextField("筛选单位", text: $keyword)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(width: 170)

                    Text("\(UnitEngine.format(value)) \(sourceUnit.symbol) =")
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Button {
                        copyAll()
                    } label: {
                        Label("复制全部", systemImage: "doc.on.doc")
                            .font(.system(size: 11.5))
                    }
                    .controlSize(.small)
                }

                if rows.isEmpty {
                    Text("没有匹配的单位")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            rowView(row)
                            if index < rows.count - 1 {
                                Divider().opacity(0.35)
                            }
                        }
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
    }

    private func rowView(_ row: UnitConversion) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.unit.name)
                    .font(.system(size: 12, weight: row.isSource ? .semibold : .regular))
                Text(row.unit.symbol)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 150, alignment: .leading)

            Text(row.formatted)
                .font(.system(size: 12.5, weight: row.isSource ? .semibold : .regular, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 6)

            if row.isSource {
                NoticeTag(text: "源", systemImage: "arrow.right.circle", tint: .accentColor)
            } else if row.isBase {
                NoticeTag(text: "基准", systemImage: "dial.low", tint: .secondary)
            }

            CopyIconButton(text: row.formatted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func copyAll() {
        guard !rows.isEmpty else { return }
        let header = "\(UnitEngine.format(value)) \(sourceUnit.symbol)"
        let body = rows
            .filter { !$0.isSource }
            .map { "\($0.unit.name)（\($0.unit.symbol)）: \($0.formatted)" }
            .joined(separator: "\n")
        NSPasteboard.copyString(header + "\n" + body)
        toast = "已复制 \(rows.count) 条"
    }
}
