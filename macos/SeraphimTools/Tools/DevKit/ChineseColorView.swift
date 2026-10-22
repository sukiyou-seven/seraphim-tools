import AppKit
import SwiftUI

/// 中国传统色：526 个老色名的色卡册。
///
/// 用法就是"找一个好看的颜色然后把它抄走"——所以点击色卡即复制，
/// 另外留了个反查：手里已经有颜色了，想知道它像哪个传统色。
struct ChineseColorView: View {

    @AppStorage("chineseColorFamily") private var familyRaw = "all"
    @AppStorage("chineseColorPicked") private var pickedHex = "#863020"
    @AppStorage("chineseColorKeyword") private var keyword = ""
    @State private var picked: ChineseColorTable.Entry?
    @State private var toast: String?
    @State private var didLoad = false

    // MARK: - 派生数据

    private var selectedFamily: ChineseColorTable.Family? {
        ChineseColorTable.Family(rawValue: familyRaw)
    }

    private var sourceEntries: [ChineseColorTable.Entry] {
        guard let family = selectedFamily else { return ChineseColorTable.all }
        return ChineseColorTable.grouped.first { $0.family == family }?.entries ?? []
    }

    private var results: [ChineseColorTable.Entry] {
        ChineseColorTable.search(keyword, in: sourceEntries)
    }

    /// 搜索框里敲的是色值（而不是色名）时，顺手算一下最接近的传统色
    private var probeColor: RGBAColor? {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("#") || text.hasPrefix("0x") || text.contains("(") {
            return ColorEngine.parse(text)
        }
        guard text.count == 6, text.allSatisfy({ $0.isHexDigit }) else { return nil }
        return ColorEngine.parse("#" + text)
    }

    private static let familyCounts: [ChineseColorTable.Family: Int] = {
        var counts: [ChineseColorTable.Family: Int] = [:]
        for group in ChineseColorTable.grouped { counts[group.family] = group.entries.count }
        return counts
    }()

    // MARK: - 界面

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                libraryCard
                if let picked {
                    detailCard(picked)
                }
                gridCard
            }
            .padding(20)
        }
        .toast($toast)
        .onAppear(perform: restorePicked)
    }

    // MARK: 检索

    private var libraryCard: some View {
        ToolCard(title: "中国传统色", systemImage: "circle.grid.3x3") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TextField("搜色名 / 拼音 / 色值：月白、yuebai、#863020", text: $keyword)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5))
                        .onSubmit { pickFirstResult() }

                    Button("随机一色") { pickRandom() }
                        .controlSize(.small)

                    if !keyword.isEmpty {
                        Button("清空") { keyword = "" }
                            .controlSize(.small)
                    }
                }

                if let probeColor {
                    nearestRow(for: probeColor)
                }

                FlowRow(spacing: 6) {
                    ChipButton(title: "全部 \(ChineseColorTable.count)", isSelected: selectedFamily == nil) {
                        familyRaw = "all"
                    }
                    ForEach(ChineseColorTable.Family.allCases) { family in
                        ChipButton(
                            title: "\(family.title) \(Self.familyCounts[family] ?? 0)",
                            isSelected: selectedFamily == family
                        ) {
                            familyRaw = family.rawValue
                        }
                    }
                }

                HStack(spacing: 8) {
                    Text(selectedFamily?.note ?? "赤橙黄绿青蓝紫，还有褐色与灰调")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    if results.isEmpty && probeColor != nil {
                        Text("按色值反查")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(results.count) / \(sourceEntries.count) 色")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// 输入了色值：直接给出最像的几个传统色
    private func nearestRow(for color: RGBAColor) -> some View {
        let matches = ChineseColorTable.nearest(to: color, limit: 4)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 10))
                Text("最接近的传统色")
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
            }
            .foregroundStyle(.tertiary)

            FlowRow(spacing: 6) {
                ForEach(matches, id: \.entry.id) { match in
                    Button {
                        select(match.entry, copy: false)
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(swiftUIColor(match.entry.color))
                                .frame(width: 11, height: 11)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.18)))
                            Text(match.entry.name)
                                .font(.system(size: 11))
                            Text(match.entry.hex.uppercased())
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 当前色

    private func detailCard(_ entry: ChineseColorTable.Entry) -> some View {
        ToolCard(title: "当前色", systemImage: "paintbrush.pointed") {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(swiftUIColor(entry.color))
                        .frame(width: 96, height: 96)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12))
                        )
                        .overlay(
                            Text(entry.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ColorEngine.isDark(entry.color) ? Color.white : Color.black)
                                .padding(4)
                        )

                    Text(entry.pinyin)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(entry.name)
                            .font(.system(size: 19, weight: .semibold))
                            .textSelection(.enabled)
                        NoticeTag(text: entry.family.title, systemImage: "circle.lefthalf.filled", tint: .accentColor)
                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(displayFormats, id: \.self) { format in
                            let value = ColorEngine.string(for: entry.color, format: format)
                            HStack(spacing: 10) {
                                Text(format.title)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 104, alignment: .leading)
                                Text(value)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .textSelection(.enabled)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 6)
                                CopyIconButton(text: value)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                            )
                        }
                    }
                }
            }
        }
    }

    private var displayFormats: [ColorOutputFormat] {
        [.hex, .rgb, .hsl, .cmyk]
    }

    // MARK: 色卡

    private var gridCard: some View {
        ToolCard(title: gridTitle, systemImage: "square.grid.3x3") {
            if !results.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 84, maximum: 118), spacing: 8)],
                    spacing: 10
                ) {
                    ForEach(results) { entry in
                        swatchButton(entry)
                    }
                }
            } else if let probeColor {
                // 敲的是色值而不是色名：把最像的十六个直接摆出来
                let matches = ChineseColorTable.nearest(to: probeColor, limit: 16).map(\.entry)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 84, maximum: 118), spacing: 8)],
                    spacing: 10
                ) {
                    ForEach(matches) { entry in
                        swatchButton(entry)
                    }
                }
            } else {
                Text("没有匹配的色名，换个词试试")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            }
        }
    }

    private var gridTitle: String {
        if !keyword.isEmpty {
            return results.isEmpty && probeColor != nil ? "最接近的传统色" : "搜索结果"
        }
        return (selectedFamily?.title ?? "全部") + "色卡"
    }

    private func swatchButton(_ entry: ChineseColorTable.Entry) -> some View {
        let isPicked = picked?.id == entry.id
        return Button {
            select(entry, copy: true)
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(swiftUIColor(entry.color))
                    Text(entry.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ColorEngine.isDark(entry.color) ? Color.white : Color.black)
                        .padding(.horizontal, 3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(height: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.primary.opacity(isPicked ? 0 : 0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: isPicked ? 2 : 0)
                )

                Text(entry.hex.uppercased())
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(isPicked ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .help("\(entry.name)　\(entry.hex.uppercased())　点击复制")
        .contextMenu {
            Button("复制色名 \(entry.name)") { copy(entry.name, message: "已复制 \(entry.name)") }
            Button("复制 HEX") { copy(entry.hex.uppercased(), message: "已复制 \(entry.hex.uppercased())") }
            Button("复制 RGB") {
                copy(ColorEngine.string(for: entry.color, format: .rgb), message: "已复制 RGB")
            }
            Button("复制 CMYK") {
                copy(ColorEngine.string(for: entry.color, format: .cmyk), message: "已复制 CMYK")
            }
        }
    }

    // MARK: - 动作

    private func select(_ entry: ChineseColorTable.Entry, copy shouldCopy: Bool) {
        picked = entry
        pickedHex = entry.hex
        if shouldCopy {
            copy(entry.hex.uppercased(), message: "\(entry.name)　\(entry.hex.uppercased())")
        }
    }

    private func copy(_ text: String, message: String) {
        NSPasteboard.copyString(text)
        toast = message
    }

    private func pickFirstResult() {
        guard let first = results.first else {
            NSSound.beep()
            toast = "没有匹配的色名"
            return
        }
        select(first, copy: true)
    }

    private func pickRandom() {
        let pool = results.isEmpty ? ChineseColorTable.all : results
        guard let entry = pool.randomElement() else { return }
        select(entry, copy: true)
        keyword = ""
    }

    private func restorePicked() {
        guard !didLoad else { return }
        didLoad = true
        let saved = ChineseColorTable.all.first { $0.hex.caseInsensitiveCompare(pickedHex) == .orderedSame }
        picked = saved ?? ChineseColorTable.all.first { $0.name == "火岩棕" } ?? ChineseColorTable.all.first
    }
}
