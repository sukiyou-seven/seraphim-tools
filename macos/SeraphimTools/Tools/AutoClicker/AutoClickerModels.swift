import Foundation

// MARK: - 连点目标

/// 连点器发的是什么：鼠标点击还是键盘按键。
///
/// 枚举 rawValue 一律英文（存储键），中文只放 title——项目的硬规则。
enum ClickTarget: String, CaseIterable, Identifiable, Codable {
    case mouse
    case keyboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mouse: return "鼠标连点"
        case .keyboard: return "键盘连发"
        }
    }

    var systemImage: String {
        switch self {
        case .mouse: return "cursorarrow.click"
        case .keyboard: return "keyboard"
        }
    }

    /// 「正在连点」「连点 N 次」里的那个动词
    var verb: String {
        switch self {
        case .mouse: return "连点"
        case .keyboard: return "连发"
        }
    }
}

// MARK: - 鼠标按键

enum ClickButton: String, CaseIterable, Identifiable, Codable {
    case left
    case right
    case middle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return "左键"
        case .right: return "右键"
        case .middle: return "中键"
        }
    }
}

// MARK: - 单击 / 双击

enum ClickStyle: String, CaseIterable, Identifiable, Codable {
    case single
    case double

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: return "单击"
        case .double: return "双击"
        }
    }

    /// 每次触发发几轮 down / up
    var clickCount: Int {
        switch self {
        case .single: return 1
        case .double: return 2
        }
    }
}

// MARK: - 点击位置

enum PositionMode: String, CaseIterable, Identifiable, Codable {
    case cursor
    case fixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cursor: return "跟随指针"
        case .fixed: return "固定位置"
        }
    }
}

// MARK: - 重复方式

enum RepeatMode: String, CaseIterable, Identifiable, Codable {
    case infinite
    case count

    var id: String { rawValue }

    var title: String {
        switch self {
        case .infinite: return "一直运行"
        case .count: return "点 N 次"
        }
    }
}

// MARK: - 修饰键

/// 自己的一套修饰键表示。
///
/// 刻意不直接用 `NSEvent.ModifierFlags` / Carbon 常量：这一层是纯 Foundation，
/// 台本（swiftc 直接编 Models 出 CLI）不牵 AppKit 也能测。
struct KeyModifiers: OptionSet, Hashable {
    let rawValue: UInt

    init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    static let command = KeyModifiers(rawValue: 1 << 0)
    static let shift = KeyModifiers(rawValue: 1 << 1)
    static let option = KeyModifiers(rawValue: 1 << 2)
    static let control = KeyModifiers(rawValue: 1 << 3)

    /// 按下修饰键的顺序（松开时逆序）
    static let pressOrder: [KeyModifiers] = [.control, .option, .shift, .command]

    /// 界面显示：⌃⌥⇧⌘
    var display: String {
        var text = ""
        if contains(.control) { text += "⌃" }
        if contains(.option) { text += "⌥" }
        if contains(.shift) { text += "⇧" }
        if contains(.command) { text += "⌘" }
        return text
    }
}

extension KeyModifiers: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(UInt.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - 按键组合

/// 键盘连发的目标键：keyCode + 显示的字符 + 一起按住的修饰键。
///
/// display 在捕获那一刻由当前键盘布局算出来存着——不同布局下同一个 keyCode
/// 的字符不一样，但重放时只认 keyCode，所以显示串只是给人看的。
struct KeyChord: Codable, Equatable, Hashable {
    var keyCode: UInt16
    var display: String
    var modifiers: KeyModifiers

    /// 没设过键时的兜底：A
    static let fallback = KeyChord(keyCode: 0, display: "A", modifiers: [])

    var fullDisplay: String { modifiers.display + display }
}

/// 全局快捷键。
struct HotKeyCombo: Codable, Equatable, Hashable {
    var keyCode: UInt16
    var display: String
    var modifiers: KeyModifiers

    /// 默认 F6（kVK_F6 = 0x61 = 97）
    static let defaultF6 = HotKeyCombo(keyCode: 97, display: "F6", modifiers: [])

    /// 默认 F7（kVK_F7 = 0x62 = 98），给「拾取指针位置」用
    static let defaultF7 = HotKeyCombo(keyCode: 98, display: "F7", modifiers: [])

    var fullDisplay: String { modifiers.display + display }
}

// MARK: - 键名

/// 虚拟键码 → 好认的名字。只收特殊键，普通字符由捕获时的 NSEvent 给出。
enum KeyCodeNames {
    static let special: [UInt16: String] = [
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc",
        54: "右 ⌘", 55: "⌘", 56: "⇧", 57: "Caps Lock", 58: "⌥", 59: "⌃",
        60: "右 ⇧", 61: "右 ⌥", 62: "右 ⌃", 63: "Fn",
        64: "F17", 65: "小键盘 .", 67: "小键盘 *", 69: "小键盘 +", 71: "小键盘 Clear",
        75: "小键盘 /", 76: "小键盘 Enter", 78: "小键盘 -", 79: "F18", 80: "F19",
        81: "小键盘 =", 82: "小键盘 0", 83: "小键盘 1", 84: "小键盘 2", 85: "小键盘 3",
        86: "小键盘 4", 87: "小键盘 5", 88: "小键盘 6", 89: "小键盘 7", 91: "小键盘 8",
        92: "小键盘 9", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
        101: "F9", 103: "F11", 105: "F13", 106: "F16", 107: "F14",
        109: "F10", 111: "F12", 113: "F15", 115: "Home", 116: "Page Up",
        117: "向前删除", 118: "F4", 119: "End", 120: "F2", 121: "Page Down",
        122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    /// 功能键、方向键、Home/End 这类不带修饰键也能当全局热键
    static let functionKeys: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,     // F1–F12
        105, 107, 113, 106, 64, 79, 80, 90,                          // F13–F20
        115, 116, 117, 119, 121, 123, 124, 125, 126,                 // Home / Page / 方向键
    ]

    static func name(for keyCode: UInt16) -> String? {
        special[keyCode]
    }

    static func isFunctionKey(_ keyCode: UInt16) -> Bool {
        functionKeys.contains(keyCode)
    }
}

// MARK: - 配置

/// 连点器的全部设置。整体存成一段 JSON Data（跟原型助手那套一个路子），
/// 不给二十来个字段逐个铺 @AppStorage。
struct AutoClickerConfig: Equatable {
    // 动作
    var target: ClickTarget = .mouse
    var button: ClickButton = .left
    var clickStyle: ClickStyle = .single
    var pressMs: Int = 30
    var positionMode: PositionMode = .cursor
    var fixedX: Double = 0
    var fixedY: Double = 0
    var movePointer: Bool = true

    // 键盘
    var key: KeyChord = .fallback
    var holdKey: Bool = false

    // 节奏
    var intervalMs: Int = 100
    var randomize: Bool = false
    var randomMinMs: Int = 80
    var randomMaxMs: Int = 120
    var repeatMode: RepeatMode = .infinite
    var count: Int = 100

    // 热键与反馈
    var hotKey: HotKeyCombo = .defaultF6
    var hotKeyEnabled: Bool = true
    /// 按一下就记录指针当前位置（固定坐标模式下不用把鼠标挪回按钮上）
    var pickHotKey: HotKeyCombo = .defaultF7
    var pickHotKeyEnabled: Bool = true
    var soundFeedback: Bool = true
}

extension AutoClickerConfig {
    /// 把用户可能填出格的值收回到能用范围。引擎启动前一定先过一遍。
    func normalized() -> AutoClickerConfig {
        var copy = self
        copy.pressMs = AutoClickerTiming.clamp(pressMs, AutoClickerTiming.minPressMs, AutoClickerTiming.maxPressMs)
        copy.intervalMs = AutoClickerTiming.clamp(intervalMs, AutoClickerTiming.minIntervalMs, AutoClickerTiming.maxIntervalMs)
        copy.randomMinMs = AutoClickerTiming.clamp(randomMinMs, AutoClickerTiming.minIntervalMs, AutoClickerTiming.maxIntervalMs)
        copy.randomMaxMs = AutoClickerTiming.clamp(randomMaxMs, AutoClickerTiming.minIntervalMs, AutoClickerTiming.maxIntervalMs)
        if copy.randomMinMs > copy.randomMaxMs {
            swap(&copy.randomMinMs, &copy.randomMaxMs)
        }
        copy.count = AutoClickerTiming.clamp(count, 1, AutoClickerTiming.maxCount)
        if copy.key.display.isEmpty {
            copy.key.display = KeyCodeNames.name(for: copy.key.keyCode) ?? "Key \(copy.key.keyCode)"
        }
        if copy.hotKey.display.isEmpty {
            copy.hotKey.display = KeyCodeNames.name(for: copy.hotKey.keyCode) ?? "Key \(copy.hotKey.keyCode)"
        }
        return copy
    }

    /// 每秒大概几次（随机抖动时取区间中值）
    var clicksPerSecond: Double {
        let range = AutoClickerTiming.intervalRange(for: self)
        let average = Double(range.lowerBound + range.upperBound) / 2
        return average > 0 ? 1000.0 / average : 0
    }

    /// 间隔的人话描述：「100 毫秒」/「80–120 毫秒」
    var intervalDescription: String {
        let range = AutoClickerTiming.intervalRange(for: self)
        if range.lowerBound == range.upperBound {
            return "\(range.lowerBound) 毫秒"
        }
        return "\(range.lowerBound)–\(range.upperBound) 毫秒"
    }
}

// MARK: - Codable（缺失字段回落默认值）

extension AutoClickerConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case target, button, clickStyle, pressMs
        case positionMode, fixedX, fixedY, movePointer
        case key, holdKey
        case intervalMs, randomize, randomMinMs, randomMaxMs, repeatMode, count
        case hotKey, hotKeyEnabled, pickHotKey, pickHotKeyEnabled, soundFeedback
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AutoClickerConfig()
        target = container.value(ClickTarget.self, for: .target, default: defaults.target)
        button = container.value(ClickButton.self, for: .button, default: defaults.button)
        clickStyle = container.value(ClickStyle.self, for: .clickStyle, default: defaults.clickStyle)
        pressMs = container.value(Int.self, for: .pressMs, default: defaults.pressMs)
        positionMode = container.value(PositionMode.self, for: .positionMode, default: defaults.positionMode)
        fixedX = container.value(Double.self, for: .fixedX, default: defaults.fixedX)
        fixedY = container.value(Double.self, for: .fixedY, default: defaults.fixedY)
        movePointer = container.value(Bool.self, for: .movePointer, default: defaults.movePointer)
        key = container.value(KeyChord.self, for: .key, default: defaults.key)
        holdKey = container.value(Bool.self, for: .holdKey, default: defaults.holdKey)
        intervalMs = container.value(Int.self, for: .intervalMs, default: defaults.intervalMs)
        randomize = container.value(Bool.self, for: .randomize, default: defaults.randomize)
        randomMinMs = container.value(Int.self, for: .randomMinMs, default: defaults.randomMinMs)
        randomMaxMs = container.value(Int.self, for: .randomMaxMs, default: defaults.randomMaxMs)
        repeatMode = container.value(RepeatMode.self, for: .repeatMode, default: defaults.repeatMode)
        count = container.value(Int.self, for: .count, default: defaults.count)
        hotKey = container.value(HotKeyCombo.self, for: .hotKey, default: defaults.hotKey)
        hotKeyEnabled = container.value(Bool.self, for: .hotKeyEnabled, default: defaults.hotKeyEnabled)
        pickHotKey = container.value(HotKeyCombo.self, for: .pickHotKey, default: defaults.pickHotKey)
        pickHotKeyEnabled = container.value(Bool.self, for: .pickHotKeyEnabled, default: defaults.pickHotKeyEnabled)
        soundFeedback = container.value(Bool.self, for: .soundFeedback, default: defaults.soundFeedback)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(button, forKey: .button)
        try container.encode(clickStyle, forKey: .clickStyle)
        try container.encode(pressMs, forKey: .pressMs)
        try container.encode(positionMode, forKey: .positionMode)
        try container.encode(fixedX, forKey: .fixedX)
        try container.encode(fixedY, forKey: .fixedY)
        try container.encode(movePointer, forKey: .movePointer)
        try container.encode(key, forKey: .key)
        try container.encode(holdKey, forKey: .holdKey)
        try container.encode(intervalMs, forKey: .intervalMs)
        try container.encode(randomize, forKey: .randomize)
        try container.encode(randomMinMs, forKey: .randomMinMs)
        try container.encode(randomMaxMs, forKey: .randomMaxMs)
        try container.encode(repeatMode, forKey: .repeatMode)
        try container.encode(count, forKey: .count)
        try container.encode(hotKey, forKey: .hotKey)
        try container.encode(hotKeyEnabled, forKey: .hotKeyEnabled)
        try container.encode(pickHotKey, forKey: .pickHotKey)
        try container.encode(pickHotKeyEnabled, forKey: .pickHotKeyEnabled)
        try container.encode(soundFeedback, forKey: .soundFeedback)
    }
}

private extension KeyedDecodingContainer {
    /// 缺字段 / 解不动都回落默认值：以后加字段不会把老配置整段读废
    func value<T: Decodable>(_ type: T.Type, for key: Key, default fallback: T) -> T {
        do {
            if let value = try decodeIfPresent(type, forKey: key) {
                return value
            }
        } catch {}
        return fallback
    }
}

// MARK: - 节奏计算

enum AutoClickerTiming {
    static let minIntervalMs = 10
    static let maxIntervalMs = 3_600_000
    static let minPressMs = 0
    static let maxPressMs = 2_000
    static let maxCount = 10_000_000

    static func clamp(_ value: Int, _ lower: Int, _ upper: Int) -> Int {
        min(max(value, lower), upper)
    }

    /// 实际使用的间隔区间：随机抖动时是 min...max，否则固定值
    static func intervalRange(for config: AutoClickerConfig) -> ClosedRange<Int> {
        guard config.randomize else {
            let value = clamp(config.intervalMs, minIntervalMs, maxIntervalMs)
            return value...value
        }
        let lower = clamp(config.randomMinMs, minIntervalMs, maxIntervalMs)
        let upper = clamp(config.randomMaxMs, minIntervalMs, maxIntervalMs)
        return min(lower, upper)...max(lower, upper)
    }

    static func nextIntervalMs<R: RandomNumberGenerator>(for config: AutoClickerConfig, using rng: inout R) -> Int {
        Int.random(in: intervalRange(for: config), using: &rng)
    }

    /// 预计总耗时；「一直运行」返回 nil
    static func estimatedDuration(for config: AutoClickerConfig) -> TimeInterval? {
        guard config.repeatMode == .count else { return nil }
        let range = intervalRange(for: config)
        let average = Double(range.lowerBound + range.upperBound) / 2
        return Double(max(1, config.count)) * average / 1000
    }

    /// 时长说成人话
    static func describe(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        if seconds < 1 {
            return String(format: "%.0f 毫秒", seconds * 1000)
        }
        if seconds < 60 {
            return String(format: "%.1f 秒", seconds)
        }
        if seconds < 3600 {
            let minutes = Int(seconds) / 60
            let rest = Int(seconds) % 60
            return rest == 0 ? "\(minutes) 分钟" : "\(minutes) 分 \(rest) 秒"
        }
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return minutes == 0 ? "\(hours) 小时" : "\(hours) 小时 \(minutes) 分"
    }
}
