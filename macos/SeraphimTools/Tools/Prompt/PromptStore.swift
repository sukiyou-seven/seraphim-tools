import Combine
import Foundation

/// 模板库的存放处。做成单例，切走工具页再回来内容还在。
///
/// 存 UserDefaults 里的 JSON Data——模板是纯文本，量级在几百 KB 以下，
/// 不值得为它单开一个文件，而且这样导入导出跟持久化共用同一套编码。
final class PromptStore: ObservableObject {
    static let shared = PromptStore()

    @Published private(set) var templates: [PromptTemplate] = []

    private let defaults = UserDefaults.standard
    private let storageKey = "promptTemplates"
    private let seedKey = "promptSeeded"

    private init() {
        load()
    }

    // MARK: - 读写

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = defaults.data(forKey: storageKey),
           let list = try? decoder.decode([PromptTemplate].self, from: data) {
            templates = list
        } else {
            templates = []
        }
        // 内置示例只在第一次塞进来。用户删光了就是删光了，不强行还给他。
        if !defaults.bool(forKey: seedKey) {
            templates = PromptLibrary.builtins
            defaults.set(true, forKey: seedKey)
            persist()
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(templates) {
            defaults.set(data, forKey: storageKey)
        }
    }

    // MARK: - 增删改

    func insert(_ template: PromptTemplate) {
        templates.append(template)
        persist()
    }

    func update(_ template: PromptTemplate) {
        guard let index = templates.firstIndex(where: { $0.id == template.id }) else { return }
        var next = template
        next.updatedAt = Date()
        templates[index] = next
        persist()
    }

    func remove(id: UUID) {
        templates.removeAll { $0.id == id }
        persist()
    }

    /// 复刻一份放旁边，改起来不怕毁掉原来的
    func duplicate(id: UUID) {
        guard let source = templates.first(where: { $0.id == id }) else { return }
        var copy = source
        copy.id = UUID()
        copy.title = source.title + " 副本"
        copy.isBuiltin = false
        copy.useCount = 0
        copy.createdAt = Date()
        copy.updatedAt = Date()
        templates.append(copy)
        persist()
    }

    /// 记一次使用（用过的会排到前面）
    func markUsed(id: UUID) {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[index].useCount += 1
        persist()
    }

    /// 清空使用计数，把排序还原成"最近改过的在前"
    func resetUsage() {
        for index in templates.indices {
            templates[index].useCount = 0
        }
        persist()
    }

    @discardableResult
    func importTemplates(_ incoming: [PromptTemplate]) -> PromptImportSummary {
        let result = PromptEngine.merge(incoming, into: templates)
        templates = result.list
        persist()
        return result.summary
    }

    /// 内置模板被改乱或删掉后一键补回来（已存在的同标题同分类不重复加）
    @discardableResult
    func restoreBuiltins() -> PromptImportSummary {
        importTemplates(PromptLibrary.builtins)
    }

    var isEmpty: Bool { templates.isEmpty }

    func contains(id: UUID) -> Bool { templates.contains { $0.id == id } }
}
