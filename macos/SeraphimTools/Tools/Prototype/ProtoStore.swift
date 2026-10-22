import Combine
import Foundation

/// 四段表单的存放处。做成单例：切走工具页再回来，填了一半的东西还在。
///
/// 走 UserDefaults 存 JSON Data，理由跟提示词模板那边一样——
/// 纯文本、量级小，不值得单开文件，而且省掉了逐个字段铺 @AppStorage 的噪音
/// （光「需求转提示词」就有 9 个字段，四个面板加起来三十多个）。
final class ProtoStore: ObservableObject {
    static let shared = ProtoStore()

    @Published var requirement = ProtoRequirementInput() {
        didSet { persistIfReady() }
    }
    @Published var page = ProtoPageInput() {
        didSet { persistIfReady() }
    }
    @Published var component = ProtoComponentInput() {
        didSet { persistIfReady() }
    }
    @Published var flow = ProtoFlowInput() {
        didSet { persistIfReady() }
    }

    /// 最近点过的预设（新的在前），预设区会先把它挑出来
    @Published private(set) var recentPresets: [String] = []

    private let defaults = UserDefaults.standard

    private enum Key {
        static let requirement = "protoRequirementInput"
        static let page = "protoPageInput"
        static let component = "protoComponentInput"
        static let flow = "protoFlowInput"
        static let recent = "protoRecentPresets"
        static let seeded = "protoSeeded"
    }

    /// 装载期间挡一下 didSet——init 里赋值本来就不触发观察器，
    /// 但显式加个闸更稳，省得以后有人在 init 之外做批量赋值时被写穿。
    private var isLoading = false

    private init() {
        isLoading = true
        requirement = Self.load(ProtoRequirementInput.self, key: Key.requirement, from: defaults) ?? ProtoRequirementInput()
        page = Self.load(ProtoPageInput.self, key: Key.page, from: defaults) ?? ProtoPageInput()
        component = Self.load(ProtoComponentInput.self, key: Key.component, from: defaults) ?? ProtoComponentInput()
        flow = Self.load(ProtoFlowInput.self, key: Key.flow, from: defaults) ?? ProtoFlowInput()
        recentPresets = defaults.stringArray(forKey: Key.recent) ?? []

        // 首次打开塞一张流程图当例子——空白的节点列表没人知道该怎么下手
        if !defaults.bool(forKey: Key.seeded) {
            if flow.nodes.isEmpty, let sample = ProtoPresets.firstFlowPreset() {
                flow = sample
            }
            defaults.set(true, forKey: Key.seeded)
        }

        isLoading = false
        persistAll()
    }

    // MARK: - 读写

    private static func load<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func persistIfReady() {
        guard !isLoading else { return }
        persistAll()
    }

    private func persistAll() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(requirement) { defaults.set(data, forKey: Key.requirement) }
        if let data = try? encoder.encode(page) { defaults.set(data, forKey: Key.page) }
        if let data = try? encoder.encode(component) { defaults.set(data, forKey: Key.component) }
        if let data = try? encoder.encode(flow) { defaults.set(data, forKey: Key.flow) }
        defaults.set(recentPresets, forKey: Key.recent)
    }

    // MARK: - 预设使用记录

    func markPresetUsed(_ id: String) {
        var next = recentPresets.filter { $0 != id }
        next.insert(id, at: 0)
        recentPresets = Array(next.prefix(6))
        persistAll()
    }

    func clearPresetHistory() {
        recentPresets = []
        persistAll()
    }

    // MARK: - 复位

    /// 只清当前这一段，别的段留着
    func reset(_ kind: ProtoPresetKind) {
        isLoading = true
        switch kind {
        case .requirement: requirement = ProtoRequirementInput()
        case .page: page = ProtoPageInput()
        case .component: component = ProtoComponentInput()
        case .flow: flow = ProtoFlowInput()
        }
        isLoading = false
        persistAll()
    }

    /// 应用一个预设
    func apply(_ preset: ProtoPreset) {
        isLoading = true
        switch preset.payload {
        case .requirement(let value): requirement = value
        case .page(let value): page = value
        case .component(let value): component = value
        case .flow(let value): flow = value
        }
        isLoading = false
        markPresetUsed(preset.id)
    }
}
