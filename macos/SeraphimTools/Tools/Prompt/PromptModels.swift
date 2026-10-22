import Foundation

// MARK: - 分类
//
// AI 绘图、代码、文案这三种用例的写法差得很远：绘图要的是"能看见的东西"，
// 代码要的是"输入输出和边界"，文案要的是"给谁看、想让人干什么"。
// 所以模板先按用途分，每类在界面上给一句怎么写才管用的提示。

enum PromptCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case image = "AI 绘图"
    case copywriting = "文案"
    case code = "代码"
    case slides = "PPT"
    case video = "短视频脚本"
    case custom = "其他"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .image: return "photo.artframe"
        case .copywriting: return "text.quote"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .slides: return "rectangle.on.rectangle"
        case .video: return "video"
        case .custom: return "tray.full"
        }
    }

    var hint: String {
        switch self {
        case .image: return "画面描述越具体越稳；主体、风格、光线、构图分开写"
        case .copywriting: return "「给谁看、想让人做什么」比堆形容词管用"
        case .code: return "说清语言、输入输出、边界条件和验收标准"
        case .slides: return "受众和时长决定页数与深浅"
        case .video: return "前 3 秒决定完播率，结尾要有明确动作"
        case .custom: return "自己攒的模板放这里"
        }
    }

    /// 内置模板里用得多的几个排在前面
    static var ordered: [PromptCategory] { allCases }
}

// MARK: - 模板

struct PromptTemplate: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var category: PromptCategory
    var tags: [String]
    /// 正文，里面可以写 {{变量}}
    var body: String
    /// 用法说明 / 注意事项
    var note: String
    /// 是不是内置示例（内置的可以编辑删除，也能一键恢复）
    var isBuiltin: Bool
    var createdAt: Date
    var updatedAt: Date
    /// 用过几次，用来把常用的顶到前面
    var useCount: Int

    init(
        id: UUID = UUID(),
        title: String,
        category: PromptCategory,
        tags: [String] = [],
        body: String,
        note: String = "",
        isBuiltin: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        useCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.tags = tags
        self.body = body
        self.note = note
        self.isBuiltin = isBuiltin
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.useCount = useCount
    }

    /// 变量个数（界面上给个角标）
    var variableCount: Int { PromptEngine.variables(in: body).count }

    /// 检索用的索引文本
    var searchIndex: String {
        ([title, note, body] + tags).joined(separator: " ").lowercased()
    }

    /// 去重用的键：标题 + 分类
    var dedupeKey: String { (title.trimmingCharacters(in: .whitespaces) + "\u{1}" + category.rawValue).lowercased() }

    var displayTags: [String] { tags.filter { !$0.isEmpty } }
}

// MARK: - 导入导出

/// 导出文件的结构。带上版本号，以后加字段还能认老文件。
struct PromptExportFile: Codable, Sendable {
    var version: Int
    var exportedAt: Date
    var templates: [PromptTemplate]

    init(templates: [PromptTemplate], exportedAt: Date = Date(), version: Int = 1) {
        self.version = version
        self.exportedAt = exportedAt
        self.templates = templates
    }
}

/// 导入结果，界面直接拿来汇报
struct PromptImportSummary: Sendable {
    var added = 0
    var skipped = 0
    var total = 0

    var text: String {
        if added == 0 && skipped == 0 { return "文件里没有模板" }
        if skipped == 0 { return "导入 \(added) 个模板" }
        if added == 0 { return "\(skipped) 个模板已存在，没有新增" }
        return "导入 \(added) 个，跳过重复 \(skipped) 个"
    }
}

// MARK: - 估算

/// 字符与 token 的粗略统计。token 数只能估——各家分词器不一样，
/// 中文大约 1 字 1 token 上下、英文大约 4 字符 1 token，这里取折中值给个量级。
struct PromptStats: Sendable {
    var characters = 0
    var cjkCharacters = 0
    var words = 0
    var lines = 0
    var estimatedTokens = 0

    static func measure(_ text: String) -> PromptStats {
        var stats = PromptStats()
        stats.characters = text.count
        stats.lines = text.isEmpty ? 0 : text.components(separatedBy: "\n").count

        var cjk = 0
        var other = 0
        var words = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            if PromptEngine.isCJK(scalar) {
                cjk += 1
                inWord = false
            } else if CharacterSet.alphanumerics.contains(scalar) {
                other += 1
                if !inWord { words += 1 }
                inWord = true
            } else {
                other += 1
                inWord = false
            }
        }
        stats.cjkCharacters = cjk
        stats.words = words
        stats.estimatedTokens = max(text.isEmpty ? 0 : 1, Int((Double(cjk) * 0.75 + Double(other) / 4.0).rounded(.up)))
        return stats
    }

    /// "12 字 ≈ 9 token"
    var brief: String { "\(characters) 字符 ≈ \(estimatedTokens) token" }
}
