import Combine
import Foundation

/// 节点列表与设置的存放处。做成单例，切走工具页再回来状态还在。
final class V2RayStore: ObservableObject {
    static let shared = V2RayStore()

    @Published var nodes: [V2RayNode] = []
    @Published var selectedID: UUID?
    @Published var latency: [UUID: Int] = [:]
    @Published var testing = false
    @Published var manualCorePath = ""
    @Published var socksPort = 10808
    @Published var httpPort = 10809
    @Published var bypassChina = true
    @Published var proxyBackup = ""

    private let defaults = UserDefaults.standard
    private var testingTask: Task<Void, Never>?

    private init() {
        load()
    }

    var selectedNode: V2RayNode? {
        nodes.first { $0.id == selectedID }
    }

    // MARK: 读写

    func load() {
        if let data = defaults.data(forKey: "v2rayNodes"),
           let list = try? JSONDecoder().decode([V2RayNode].self, from: data) {
            nodes = list
        }
        if let text = defaults.string(forKey: "v2raySelected"), let uuid = UUID(uuidString: text),
           nodes.contains(where: { $0.id == uuid }) {
            selectedID = uuid
        } else {
            selectedID = nodes.first?.id
        }
        manualCorePath = defaults.string(forKey: "v2rayCorePath") ?? ""
        proxyBackup = defaults.string(forKey: "v2rayProxyBackup") ?? ""

        let socks = defaults.integer(forKey: "v2raySocksPort")
        if socks > 0 { socksPort = socks }
        let http = defaults.integer(forKey: "v2rayHTTPPort")
        if http > 0 { httpPort = http }
        if defaults.object(forKey: "v2rayBypassChina") != nil {
            bypassChina = defaults.bool(forKey: "v2rayBypassChina")
        }
    }

    func persist() {
        if let data = try? JSONEncoder().encode(nodes) {
            defaults.set(data, forKey: "v2rayNodes")
        }
        defaults.set(selectedID?.uuidString ?? "", forKey: "v2raySelected")
        defaults.set(manualCorePath, forKey: "v2rayCorePath")
        defaults.set(socksPort, forKey: "v2raySocksPort")
        defaults.set(httpPort, forKey: "v2rayHTTPPort")
        defaults.set(bypassChina, forKey: "v2rayBypassChina")
        defaults.set(proxyBackup, forKey: "v2rayProxyBackup")
    }

    func saveProxyBackup(_ text: String) {
        proxyBackup = text
        defaults.set(text, forKey: "v2rayProxyBackup")
    }

    // MARK: 节点增删

    /// 去重后加入，返回真正新增的数量
    @discardableResult
    func add(_ incoming: [V2RayNode]) -> Int {
        var added = 0
        for node in incoming {
            if let index = nodes.firstIndex(where: { $0.fingerprintKey == node.fingerprintKey }) {
                // 已存在就更新备注
                if !node.remark.isEmpty { nodes[index].remark = node.remark }
                continue
            }
            nodes.append(node)
            added += 1
        }
        if selectedID == nil { selectedID = nodes.first?.id }
        persist()
        return added
    }

    func remove(_ node: V2RayNode) {
        nodes.removeAll { $0.id == node.id }
        latency[node.id] = nil
        if selectedID == node.id { selectedID = nodes.first?.id }
        persist()
    }

    func update(_ node: V2RayNode) {
        guard let index = nodes.firstIndex(where: { $0.id == node.id }) else { return }
        nodes[index] = node
        persist()
    }

    func select(_ node: V2RayNode) {
        selectedID = node.id
        persist()
    }

    // MARK: 测速

    func testLatency(for node: V2RayNode) {
        guard let port = UInt16(exactly: node.port) else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let value = TCPPing.measure(host: node.address, port: port, timeout: 3)
            DispatchQueue.main.async {
                self?.latency[node.id] = value ?? -1
            }
        }
    }

    func testAll() {
        let list = nodes
        guard !list.isEmpty else { return }
        testingTask?.cancel()
        testing = true
        testingTask = Task { [weak self] in
            await withTaskGroup(of: (UUID, Int).self) { group in
                for node in list {
                    group.addTask {
                        guard let port = UInt16(exactly: node.port) else { return (node.id, -1) }
                        let value = await withCheckedContinuation { continuation in
                            DispatchQueue.global(qos: .userInitiated).async {
                                continuation.resume(returning: TCPPing.measure(host: node.address, port: port, timeout: 3))
                            }
                        }
                        return (node.id, value ?? -1)
                    }
                }
                for await (id, value) in group {
                    if Task.isCancelled { break }
                    await MainActor.run { self?.latency[id] = value }
                }
            }
            await MainActor.run { self?.testing = false }
        }
    }

    func latencyText(_ node: V2RayNode) -> String {
        guard let value = latency[node.id] else { return "—" }
        return value < 0 ? "超时" : "\(value) ms"
    }
}
