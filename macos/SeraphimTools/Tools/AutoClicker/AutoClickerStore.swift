import Combine
import Foundation

/// 连点器配置的存放处。
///
/// 做成单例而不是在视图里铺二十个 @AppStorage：热键注册和托盘菜单都要读同一份，
/// 而且改一个字段要能立刻让 Carbon 重注册。整体存 JSON Data，
/// 加字段时靠 `AutoClickerConfig` 的自定义解码回落默认值兜住。
final class AutoClickerStore: ObservableObject {
    static let shared = AutoClickerStore()

    @Published var config: AutoClickerConfig {
        didSet {
            guard !isLoading else { return }
            persist()
        }
    }

    private let defaults = UserDefaults.standard
    private var isLoading = true

    private enum Key {
        static let config = "autoClickerConfig"
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Key.config),
           let decoded = try? JSONDecoder().decode(AutoClickerConfig.self, from: data) {
            config = decoded
        } else {
            config = AutoClickerConfig()
        }
        isLoading = false
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: Key.config)
    }
}
