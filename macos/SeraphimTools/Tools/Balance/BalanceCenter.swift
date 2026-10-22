import Foundation

/// 余额工具的运行时状态。
///
/// 两件事特别值得注意：
/// 1. **key 只进钥匙串**，一个字节都不写 UserDefaults。界面上只显示掩码，
///    连日志和错误文案里都不带 key（错误文案只来自响应体，跟 key 无关）。
/// 2. 读写钥匙串是**起子进程**（`/usr/bin/security`），会阻塞。全部丢到后台队列，
///    主线程一次都不碰——这个项目上吃过「主线程被卡住 → 界面黑屏但没崩溃报告」的亏。
@MainActor
final class BalanceCenter: ObservableObject {
    static let shared = BalanceCenter()

    /// 每家最近一次的检测结果
    @Published private(set) var reports: [String: BalanceReport] = [:]
    /// 已经填过 key 的厂商 id
    @Published private(set) var configured: Set<String> = []
    /// 正在检测的厂商 id
    @Published private(set) var running: Set<String> = []
    /// 用户自己加的厂商
    @Published private(set) var customs: [CustomProvider] = []

    private var keys: [String: String] = [:]
    private var bootstrapped = false

    private let service = "SeraphimTools.balance"
    private let customsKey = "balanceCustomProviders"

    private init() {}

    // MARK: - 启动

    var allProviders: [BalanceProvider] {
        BalanceProviders.builtins + customs.map(\.asProvider)
    }

    var configuredProviders: [BalanceProvider] {
        allProviders.filter { configured.contains($0.id) }
    }

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        loadCustoms()
        await reloadKeys()
    }

    private func reloadKeys() async {
        let ids = allProviders.map(\.id)
        let service = self.service
        let found: [String: String] = await Task.detached(priority: .userInitiated) {
            var result: [String: String] = [:]
            for id in ids {
                if let value = Keychain.value(service: service, account: id), !value.isEmpty {
                    result[id] = value
                }
            }
            return result
        }.value
        keys = found
        configured = Set(found.keys)
    }

    // MARK: - Key

    func key(for id: String) -> String? { keys[id] }

    func maskedKey(for id: String) -> String? {
        keys[id].map(BalanceEngine.mask)
    }

    @discardableResult
    func saveKey(_ key: String, for id: String) async -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let service = self.service
        let ok = await Task.detached(priority: .userInitiated) {
            Keychain.set(trimmed, service: service, account: id)
        }.value
        if ok {
            keys[id] = trimmed
            configured.insert(id)
        }
        return ok
    }

    func deleteKey(for id: String) async {
        let service = self.service
        _ = await Task.detached(priority: .userInitiated) {
            Keychain.remove(service: service, account: id)
        }.value
        keys[id] = nil
        configured.remove(id)
        reports[id] = nil
    }

    func deleteAllKeys() async {
        let ids = Array(configured)
        let service = self.service
        await Task.detached(priority: .userInitiated) {
            for id in ids {
                _ = Keychain.remove(service: service, account: id)
            }
        }.value
        keys.removeAll()
        configured.removeAll()
        reports.removeAll()
    }

    // MARK: - 检测

    func detect(_ provider: BalanceProvider) async {
        guard !running.contains(provider.id) else { return }

        guard let key = keys[provider.id], !key.isEmpty else {
            reports[provider.id] = BalanceReport(
                providerID: provider.id,
                status: .unconfigured,
                httpStatus: 0,
                latencyMS: 0,
                headline: "还没填 Key",
                detail: "填上这个平台的 API Key 才能检测。",
                amounts: [], fields: [], rawBody: "",
                queriedAt: Date(),
                usedProbe: provider.capability == .probe
            )
            return
        }

        guard provider.effectiveEndpoint != nil else {
            reports[provider.id] = BalanceReport(
                providerID: provider.id,
                status: .malformed,
                httpStatus: 0, latencyMS: 0,
                headline: "接口地址没填",
                detail: "这个自定义厂商还没有配置查询地址。",
                amounts: [], fields: [], rawBody: "",
                queriedAt: Date(), usedProbe: false
            )
            return
        }

        running.insert(provider.id)
        let usedProbe = provider.capability == .probe
        let response = await BalanceHTTP.fetch(provider: provider, key: key)

        let report: BalanceReport
        if let error = response.error {
            report = BalanceReport(
                providerID: provider.id,
                status: .networkError,
                httpStatus: 0,
                latencyMS: response.latencyMS,
                headline: "连不上",
                detail: error,
                amounts: [], fields: [], rawBody: "",
                queriedAt: Date(),
                usedProbe: usedProbe
            )
        } else {
            let interpretation = BalanceEngine.interpret(
                provider: provider,
                body: response.body,
                httpStatus: response.httpStatus,
                usedProbe: usedProbe
            )
            report = BalanceReport(
                providerID: provider.id,
                status: interpretation.status,
                httpStatus: response.httpStatus,
                latencyMS: response.latencyMS,
                headline: interpretation.headline,
                detail: interpretation.detail,
                amounts: interpretation.amounts,
                fields: interpretation.fields,
                rawBody: response.body,
                queriedAt: Date(),
                usedProbe: usedProbe
            )
        }

        reports[provider.id] = report
        running.remove(provider.id)
    }

    /// 批量检测。只跑填了 key 的，限制并发 4 条——一口气打几十个接口没必要，
    /// 还容易被对方按速率拦。
    func detectAll(_ providers: [BalanceProvider]) async {
        let pending = providers.filter { configured.contains($0.id) && !running.contains($0.id) }
        guard !pending.isEmpty else { return }

        let limit = 4
        await withTaskGroup(of: Void.self) { group in
            var index = 0
            var active = 0
            while active < limit, index < pending.count {
                let provider = pending[index]
                index += 1
                active += 1
                group.addTask { @MainActor in await self.detect(provider) }
            }
            for await _ in group {
                if index < pending.count {
                    let provider = pending[index]
                    index += 1
                    group.addTask { @MainActor in await self.detect(provider) }
                }
            }
        }
    }

    func clearReport(for id: String) {
        reports[id] = nil
    }

    // MARK: - 自定义厂商

    private func loadCustoms() {
        guard let data = UserDefaults.standard.data(forKey: customsKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        customs = (try? decoder.decode([CustomProvider].self, from: data)) ?? []
    }

    private func persistCustoms() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(customs) else { return }
        UserDefaults.standard.set(data, forKey: customsKey)
    }

    @discardableResult
    func addCustom(_ provider: CustomProvider) -> Bool {
        let trimmed = provider.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var item = provider
        item.name = trimmed
        customs.append(item)
        persistCustoms()
        return true
    }

    func updateCustom(_ provider: CustomProvider) {
        guard let index = customs.firstIndex(where: { $0.id == provider.id }) else { return }
        customs[index] = provider
        persistCustoms()
    }

    func removeCustom(id: String) async {
        customs.removeAll { $0.id == id }
        persistCustoms()
        await deleteKey(for: "custom:" + id)
    }

    // MARK: - 汇总

    /// 按币种把已知余额加起来。不同币种不能混着加，分开算。
    func totals(providers: [BalanceProvider]) -> [(currency: String, value: Double)] {
        var buckets: [String: Double] = [:]
        for provider in providers {
            guard let report = reports[provider.id], report.status == .ok,
                  let primary = report.primaryAmount, !primary.kind.isSpending else { continue }
            let currency = primary.currency.uppercased()
            buckets[currency, default: 0] += primary.value
        }
        return buckets
            .map { (currency: $0.key, value: $0.value) }
            .sorted { $0.currency < $1.currency }
    }

    func attentionCount(providers: [BalanceProvider]) -> Int {
        providers.filter { reports[$0.id]?.status.needsAttention == true }.count
    }
}
