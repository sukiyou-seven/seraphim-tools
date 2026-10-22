import Foundation
import CoreGraphics

// MARK: - 列

/// 尺码表里的一列。
///
/// 同一个「码」在不同体系里是完全不同的数，所以列由每张表自己声明——
/// 鞋码表里的「中国码」是脚长毫米数，衣服表里的「中国码」是 S / M / L，
/// 硬塞进一个全局枚举只会越写越乱。
struct SizeColumn: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// 用户输入时可能用到的写法（"欧码" / "欧洲" / "EU"…）
    var aliases: [String]
    /// 显示宽度
    var width: CGFloat
    /// 是不是「量出来的净尺寸」而不是标号
    var isMeasurement: Bool
    /// 列多的时候默认收起几列，免得表格挤成一团
    var visibleByDefault: Bool

    init(
        id: String,
        title: String,
        aliases: [String] = [],
        width: CGFloat = 62,
        isMeasurement: Bool = false,
        visibleByDefault: Bool = true
    ) {
        self.id = id
        self.title = title
        self.aliases = aliases
        self.width = width
        self.isMeasurement = isMeasurement
        self.visibleByDefault = visibleByDefault
    }

    /// 匹配用户输入时用的全部候选写法
    var searchKeys: [String] { [id, title] + aliases }
}

// MARK: - 行

/// 尺码表里的一行。
struct SizeRow: Identifiable, Sendable {
    let id: String
    /// 列 id → 该列在这一行的取值
    let values: [String: String]
    /// 轴心测量值（脚长 cm / 净胸围 cm / 净腰围 cm / 身高 cm）。
    /// 所有换算都围着它转——标号是约定，净尺寸才是事实。
    let pivot: Double
    /// 补充说明
    var note: String = ""

    func value(_ columnID: String) -> String { values[columnID] ?? "—" }
}

enum SizeGroup: String, CaseIterable, Identifiable, Sendable {
    case shoe = "鞋码"
    case clothing = "衣服"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .shoe: return "shoe"
        case .clothing: return "tshirt"
        }
    }
}

// MARK: - 表

struct SizeChart: Identifiable, Sendable {
    let id: String
    let title: String
    let group: SizeGroup
    let systemImage: String
    /// 轴心列，同时也是「按净尺寸找」时用的那一列
    let pivotColumnID: String
    let columns: [SizeColumn]
    let rows: [SizeRow]
    /// 怎么量
    let measure: [String]
    /// 表下面的注意事项
    let notes: [String]

    func column(_ id: String) -> SizeColumn? { columns.first { $0.id == id } }

    var pivotColumn: SizeColumn { column(pivotColumnID) ?? columns[0] }

    var defaultColumns: [SizeColumn] { columns.filter(\.visibleByDefault) }

    /// 轴心列的标题里已经带单位了，这里给输入框一个像样的占位提示
    var inputHint: String { "比如 \(pivotColumn.title)" }
}

/// 一次命中的结果
struct SizeMatch: Sendable {
    let row: SizeRow
    let column: SizeColumn
    /// 是不是按净尺寸（脚长 / 胸围 / 腰围 / 身高）命中的
    let byMeasurement: Bool
}

// MARK: - 引擎

enum SizeEngine {

    // MARK: 取值

    static func chart(id: String) -> SizeChart? { charts.first { $0.id == id } }

    static func charts(in group: SizeGroup) -> [SizeChart] {
        charts.filter { $0.group == group }
    }

    // MARK: 数值格式化

    /// 42.0 → "42"，42.5 → "42.5"
    static func sizeText(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.001 { return String(Int(value.rounded())) }
        return String(format: "%.1f", value)
    }

    /// 半码取整：鞋码都是 1/2 码为最小刻度，算出 41.7 得说 41.5 或 42
    static func roundHalf(_ value: Double) -> Double {
        (value * 2).rounded() / 2
    }

    // MARK: 输入规整

    /// 去空白、转小写、切掉「码 / 号」这类尾巴
    static func normalized(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        value = value.replacingOccurrences(of: " ", with: "")
        value = value.replacingOccurrences(of: "\u{3000}", with: "")
        for suffix in ["码", "号"] where value.hasSuffix(suffix) {
            value.removeLast()
        }
        return value
    }

    // MARK: 查询

    /// 在一列里找匹配的行。先精确对字符串，再按数值比（容忍 42 与 42.0）。
    static func match(_ text: String, column: SizeColumn, in chart: SizeChart) -> SizeRow? {
        let needle = normalized(text)
        guard !needle.isEmpty else { return nil }

        // 用户可能把体系也写进来了："EU42" / "欧码42"。
        // 这里不能拿归一化后的别名去比前缀——「欧码」会被归一化削成「欧」，
        // 削完再去前缀就错位了。要拿原样的别名去比原文，比中了再单独归一化剩下的部分。
        let lowered = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var candidates: Set<String> = [needle]
        for key in column.searchKeys where !key.isEmpty {
            let alias = key.lowercased()
            if lowered.hasPrefix(alias) {
                candidates.insert(normalized(String(lowered.dropFirst(alias.count))))
            }
        }
        candidates.remove("")

        for row in chart.rows where candidates.contains(normalized(row.value(column.id))) {
            return row
        }

        for row in chart.rows {
            guard let rowValue = Double(normalized(row.value(column.id))) else { continue }
            for candidate in candidates {
                if let value = Double(candidate), abs(rowValue - value) < 0.001 { return row }
            }
        }
        return nil
    }

    /// 从输入里读出一个「净尺寸」。只在明确写了单位时才认，
    /// 免得把欧码 42 当成 42cm 的胸围。
    static func measurement(from text: String) -> Double? {
        let value = normalized(text)
        for suffix in ["mm", "毫米"] where value.hasSuffix(suffix) {
            if let number = Double(value.dropLast(suffix.count)) { return number / 10 }
        }
        for suffix in ["cm", "厘米", "公分"] where value.hasSuffix(suffix) {
            if let number = Double(value.dropLast(suffix.count)) { return number }
        }
        return nil
    }

    /// 按净尺寸找最接近的一行。量出来的数字不可能正好压在标准值上，
    /// 比如脚长 26.3 得落到 26.5 那一行。
    static func nearestRow(to centimeters: Double, in chart: SizeChart) -> SizeRow? {
        chart.rows.min { abs($0.pivot - centimeters) < abs($1.pivot - centimeters) }
    }

    /// 统一入口：输入既可能是标号也可能是净尺寸，这里自动判断。
    ///
    /// - `column` 是用户指定的「我手上这个是什么码」。指定了就优先按它找；
    ///   找不到再退到全表扫一遍（用户选错体系时仍然能救回来）。
    static func locate(_ text: String, in chart: SizeChart, column: SizeColumn?) -> SizeMatch? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. 指定的体系里有，就信它。能走进这一步说明是精确对上的标号，
        //    不算「按净尺寸就近落档」，界面上的措辞也因此不同。
        if let column, let row = match(trimmed, column: column, in: chart) {
            return SizeMatch(row: row, column: column, byMeasurement: false)
        }

        // 2. 明确写了 cm / mm，按净尺寸定位
        if let centimeters = measurement(from: trimmed), let row = nearestRow(to: centimeters, in: chart) {
            let pivot = chart.pivotColumn
            return SizeMatch(row: row, column: pivot, byMeasurement: pivot.isMeasurement)
        }

        // 3. 指定的是轴心列，但数字不是标准值 —— 就近落档
        if let column, column.id == chart.pivotColumnID, let value = Double(normalized(trimmed)),
           let row = nearestRow(to: value, in: chart) {
            return SizeMatch(row: row, column: column, byMeasurement: true)
        }

        // 4. 全表扫一遍（同样是对上了标号）
        for candidate in chart.columns where candidate.id != column?.id {
            if let row = match(trimmed, column: candidate, in: chart) {
                return SizeMatch(row: row, column: candidate, byMeasurement: false)
            }
        }

        // 5. 纯数字又不像标号，就拿去当净尺寸试
        if let value = Double(normalized(trimmed)), let row = nearestRow(to: value, in: chart) {
            let pivot = chart.pivotColumn
            return SizeMatch(row: row, column: pivot, byMeasurement: true)
        }
        return nil
    }

    /// 把一行拼成一段可直接粘贴的文字
    static func summary(_ row: SizeRow, in chart: SizeChart, columns: [SizeColumn]) -> String {
        columns
            .map { "\($0.title) \(row.value($0.id))" }
            .joined(separator: " · ")
    }
}
