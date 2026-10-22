import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Security

// MARK: - 辅助功能权限

/// 合成事件要投递到别的 App，必须拿到系统「辅助功能」授权。
///
/// 没有它 `CGEvent.post` 是静默失败——界面看着在跑，实际一下都没点出去。
/// 所以启动前一定先查，别让用户对着一个空转的界面猜。
///
/// 另一个坑：这个 App 是 ad-hoc 签名（CODE_SIGN_IDENTITY = "-"），系统记录授权时
/// 会把凭据绑在这份二进制的哈希上。重新构建一次哈希就变，系统设置里那条勾选还在，
/// 但对新二进制已经对不上了——表现为「明明勾了还是一直要授权」。这种情况下要靠
/// `resetAccessibilityRecord()` 清掉旧条目，重启后重新授权一次。
enum AutoClickerPermission {
    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// 「发送事件」这一项的实际状态。和 AXIsProcessTrusted 分开看，能区分是整项没给，
    /// 还是给了但事件投递被单独拒绝。
    static var canPostEvents: Bool {
        CGPreflightPostEventAccess()
    }

    /// 弹一次系统授权提示（会把这个 App 加进「辅助功能」列表）
    @discardableResult
    static func requestAccessibility() -> Bool {
        // 用字面量键名，省掉 kAXTrustedCheckOptionPrompt 的 CFString 桥接
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// 清掉这个 bundle id 在「辅助功能」里的全部记录（含对不上的旧条目）
    static func resetAccessibilityRecord() -> String {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            return "拿不到 bundle id"
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
                ? "旧授权记录已清掉。重启 App，再点「请求授权」重新勾一次。"
                : "重置失败（tccutil 退出码 \(process.terminationStatus)）"
        } catch {
            return "重置失败：\(error.localizedDescription)"
        }
    }

    /// 当前可执行文件的签名哈希（前 16 位够核对了），用来确认系统设置里勾的是不是这一份
    static var signatureHash: String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
              let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let unique = dict[kSecCodeInfoUnique as String] as? Data else { return nil }
        return unique.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - 修饰键的 CoreGraphics 表示

extension KeyModifiers {
    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.control) { flags.insert(.maskControl) }
        return flags
    }

    /// 修饰键本身的虚拟键码（用来发真实的 modifier down / up）
    var virtualKeyCode: CGKeyCode? {
        switch self {
        case .command: return 55
        case .shift: return 56
        case .option: return 58
        case .control: return 59
        default: return nil
        }
    }

    /// 从 NSEvent 的修饰键标志转过来（录制快捷键 / 连发键时用）
    init(_ flags: NSEvent.ModifierFlags) {
        var value = KeyModifiers()
        if flags.contains(.command) { value.insert(.command) }
        if flags.contains(.shift) { value.insert(.shift) }
        if flags.contains(.option) { value.insert(.option) }
        if flags.contains(.control) { value.insert(.control) }
        self = value
    }
}

// MARK: - 事件工厂

/// 只负责把「一次点击 / 一次按键」构造出来，不负责投递。
/// 拆出来是为了能脱离权限单测：CGEvent 可以在没有授权的情况下创建和读字段。
enum AutoClickerEventFactory {
    /// 指针当前所在的全局屏幕坐标（左上角原点，和 CGEvent 一个坐标系）
    static var pointerLocation: CGPoint? {
        CGEvent(source: nil)?.location
    }

    static func mouseEvent(
        button: ClickButton,
        down: Bool,
        at point: CGPoint,
        clickState: Int,
        source: CGEventSource?
    ) -> CGEvent? {
        let type: CGEventType
        let cgButton: CGMouseButton
        switch button {
        case .left:
            type = down ? .leftMouseDown : .leftMouseUp
            cgButton = .left
        case .right:
            type = down ? .rightMouseDown : .rightMouseUp
            cgButton = .right
        case .middle:
            type = down ? .otherMouseDown : .otherMouseUp
            cgButton = .center
        }

        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: cgButton
        ) else { return nil }

        // 双击的第二下要带 clickState = 2，否则 App 认成一快速两下单击
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
        return event
    }

    static func keyEvent(
        keyCode: CGKeyCode,
        down: Bool,
        flags: CGEventFlags,
        source: CGEventSource?
    ) -> CGEvent? {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else {
            return nil
        }
        event.flags = flags
        return event
    }

    static func modifierEvent(_ modifier: KeyModifiers, down: Bool, source: CGEventSource?) -> CGEvent? {
        guard let keyCode = modifier.virtualKeyCode else { return nil }
        return keyEvent(keyCode: keyCode, down: down, flags: modifier.cgEventFlags, source: source)
    }
}

// MARK: - 拾取指针位置

/// 把指针当前位置记成固定点击点。界面按钮和全局热键都走这条路，
/// 顺便让「取不到指针时不要改配置」这条能单测。
enum AutoClickerPointerPick {
    @discardableResult
    static func apply(point: CGPoint?, to config: inout AutoClickerConfig) -> Bool {
        guard let point else { return false }
        config.fixedX = point.x.rounded()
        config.fixedY = point.y.rounded()
        config.positionMode = .fixed
        return true
    }
}

// MARK: - 运行器

/// 后台线程上的连点循环。
///
/// 不复用 `Timer.scheduledTimer`：主线程被 UI 占着时它会被拖慢，间隔直接糊掉。
/// 这里用独立的高优先级队列 + DispatchSourceTimer，每次手动排下一次的时间点。
final class AutoClickerRunner {
    private let queue = DispatchQueue(label: "com.seraphim.tools.autoclicker.runner", qos: .userInteractive)

    private var timer: DispatchSourceTimer?
    private var generation = 0
    private var config: AutoClickerConfig?
    private var fired = 0
    private var rng = SystemRandomNumberGenerator()
    private var source: CGEventSource?

    private var onProgress: ((Int) -> Void)?
    private var onFinish: ((Int) -> Void)?
    private var lastReport = Date.distantPast

    /// 「按住不放」模式下已经按下去了、等 stop 时再松开
    private var holdsKey = false
    private var heldKeyCode: CGKeyCode?
    private var heldModifiers: KeyModifiers = []

    /// 事件投递和指针移动做成可注入：台本（swiftc 出的 CLI）里换成收集器，
    /// 就能在没有辅助功能权限、也不真的动鼠标的情况下测状态机。
    private let deliverEvent: (CGEvent) -> Void
    private let movePointer: (CGPoint) -> Void

    init(
        deliverEvent: @escaping (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) },
        movePointer: @escaping (CGPoint) -> Void = { point in
            CGWarpMouseCursorPosition(point)
            // warp 之后指针会和硬件短暂「脱钩」，立刻重新关联回来
            CGAssociateMouseAndMouseCursorPosition(1)
        }
    ) {
        self.deliverEvent = deliverEvent
        self.movePointer = movePointer
    }

    private func post(_ event: CGEvent?) {
        guard let event else { return }
        deliverEvent(event)
    }

    // MARK: 生命周期

    func start(
        config: AutoClickerConfig,
        onProgress: @escaping (Int) -> Void,
        onFinish: @escaping (Int) -> Void
    ) {
        let normalized = config.normalized()
        queue.async { [weak self] in
            guard let self else { return }
            self.teardown(releaseHold: true)
            self.generation += 1
            let generation = self.generation

            self.config = normalized
            self.fired = 0
            self.rng = SystemRandomNumberGenerator()
            self.source = CGEventSource(stateID: .hidSystemState)
            self.onProgress = onProgress
            self.onFinish = onFinish
            self.lastReport = .distantPast
            self.holdsKey = normalized.target == .keyboard && normalized.holdKey

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.setEventHandler { [weak self] in self?.tick(generation: generation) }
            self.timer = timer
            timer.resume()
            // 第一下立刻来，不要先等一个间隔
            self.schedule(generation: generation, deadline: .now())
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.generation += 1
            self.teardown(releaseHold: true)
        }
    }

    /// 退出 App / 关窗口这类必须当场松手的场合
    func stopSynchronously() {
        queue.sync {
            generation += 1
            teardown(releaseHold: true)
        }
    }

    // MARK: 循环

    private func tick(generation gen: Int) {
        guard gen == generation, let config else { return }
        let started = DispatchTime.now()

        fire(config)
        fired += 1
        report(force: false)

        if config.repeatMode == .count, fired >= max(1, config.count) {
            generation += 1
            teardown(releaseHold: true)
            report(force: true)
            let finish = onFinish
            let total = fired
            onProgress = nil
            onFinish = nil
            DispatchQueue.main.async { finish?(total) }
            return
        }

        if holdsKey {
            // 已经按下去了，不再发事件；停表，等用户手动停止
            timer?.cancel()
            timer = nil
            return
        }

        let intervalMs = AutoClickerTiming.nextIntervalMs(for: config, using: &rng)
        schedule(generation: gen, deadline: started + .milliseconds(intervalMs))
    }

    private func schedule(generation gen: Int, deadline: DispatchTime) {
        guard gen == generation, let timer else { return }
        let now = DispatchTime.now()
        timer.schedule(deadline: deadline > now ? deadline : now)
    }

    // MARK: 发一次

    private func fire(_ config: AutoClickerConfig) {
        switch config.target {
        case .mouse:
            fireMouse(config)
        case .keyboard:
            fireKey(config)
        }
    }

    private func fireMouse(_ config: AutoClickerConfig) {
        let point: CGPoint
        if config.positionMode == .fixed {
            point = CGPoint(x: config.fixedX, y: config.fixedY)
            if config.movePointer {
                // 先把指针挪过去，再发事件：很多游戏只认指针位置的点击
                movePointer(point)
            }
        } else {
            point = AutoClickerEventFactory.pointerLocation ?? .zero
        }

        let pressSeconds = Double(config.pressMs) / 1000
        let rounds = config.clickStyle.clickCount

        for round in 1...rounds {
            post(AutoClickerEventFactory.mouseEvent(
                button: config.button,
                down: true,
                at: point,
                clickState: round,
                source: source
            ))

            if pressSeconds > 0 {
                Thread.sleep(forTimeInterval: pressSeconds)
            }

            post(AutoClickerEventFactory.mouseEvent(
                button: config.button,
                down: false,
                at: point,
                clickState: round,
                source: source
            ))

            // 双击的两下之间留一点缝，太紧会被系统合并成一下
            if round < rounds {
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }

    private func fireKey(_ config: AutoClickerConfig) {
        postChord(config.key, down: true)

        if holdsKey {
            heldKeyCode = config.key.keyCode
            heldModifiers = config.key.modifiers
            return
        }

        let pressSeconds = Double(config.pressMs) / 1000
        if pressSeconds > 0 {
            Thread.sleep(forTimeInterval: pressSeconds)
        }

        postChord(config.key, down: false)
    }

    /// 修饰键按住 → 主键按下 → 主键松开 → 修饰键逆序松开。
    /// 连着发真实的 modifier 事件，比只给主键挂 flags 更像人手（部分 App 只认前者）。
    private func postChord(_ chord: KeyChord, down: Bool) {
        let active = KeyModifiers.pressOrder.filter { chord.modifiers.contains($0) }
        let flags = chord.modifiers.cgEventFlags

        if down {
            for modifier in active {
                post(AutoClickerEventFactory.modifierEvent(modifier, down: true, source: source))
            }
            post(AutoClickerEventFactory.keyEvent(
                keyCode: chord.keyCode,
                down: true,
                flags: flags,
                source: source
            ))
        } else {
            post(AutoClickerEventFactory.keyEvent(
                keyCode: chord.keyCode,
                down: false,
                flags: flags,
                source: source
            ))
            for modifier in active.reversed() {
                post(AutoClickerEventFactory.modifierEvent(modifier, down: false, source: source))
            }
        }
    }

    // MARK: 收尾

    /// 停表 + 把还按着的键松开。按住的键不松开，用户会卡住一个键。
    private func teardown(releaseHold: Bool) {
        timer?.cancel()
        timer = nil
        config = nil

        if releaseHold, let keyCode = heldKeyCode {
            post(AutoClickerEventFactory.keyEvent(
                keyCode: keyCode,
                down: false,
                flags: heldModifiers.cgEventFlags,
                source: source
            ))
            let active = KeyModifiers.pressOrder.filter { heldModifiers.contains($0) }
            for modifier in active.reversed() {
                post(AutoClickerEventFactory.modifierEvent(modifier, down: false, source: source))
            }
        }
        heldKeyCode = nil
        heldModifiers = []
        holdsKey = false
    }

    /// 主线程更新 @Published 太快会把 SwiftUI 拖死（10ms 间隔 = 每秒 100 次），
    /// 这里压到 10 Hz；最后一次一定送出去。
    private func report(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastReport) >= 0.1 else { return }
        lastReport = now
        let count = fired
        let progress = onProgress
        DispatchQueue.main.async { progress?(count) }
    }
}

// MARK: - 引擎（对外的状态门面）

/// 界面、托盘、热键共用的一份运行状态。
/// 所有 @Published 都只在主线程改——后台队列通过 DispatchQueue.main.async 回推。
final class AutoClickerEngine: ObservableObject {
    static let shared = AutoClickerEngine()

    @Published private(set) var isRunning = false
    @Published private(set) var firedCount = 0
    @Published private(set) var startedAt: Date?
    @Published var message: String?

    private let runner = AutoClickerRunner()
    private var terminationObserver: NSObjectProtocol?

    private init() {}

    /// App 退出时把还按着的键松开——进程没了系统不会替你松手
    func installTerminationHook() {
        guard terminationObserver == nil else { return }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopImmediately()
        }
    }

    func start(_ config: AutoClickerConfig) {
        guard !isRunning else { return }

        guard AutoClickerPermission.hasAccessibility else {
            // 不在这里自动弹系统授权框：没权限时点一次「开始」就弹一次，非常烦。
            // 授权入口集中在页面上的「请求授权」按钮，这里只把原因说清楚。
            message = "需要「辅助功能」权限才能向别的 App 发点击和按键。到下面「权限与说明」里点「请求授权」，勾上后回来再开始。"
            return
        }

        let normalized = config.normalized()
        message = nil
        firedCount = 0
        startedAt = Date()
        isRunning = true
        AutoClickerFeedback.play(started: true)

        runner.start(
            config: normalized,
            onProgress: { [weak self] count in
                DispatchQueue.main.async { self?.firedCount = count }
            },
            onFinish: { [weak self] count in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.firedCount = count
                    self.isRunning = false
                    self.startedAt = nil
                    AutoClickerFeedback.play(started: false)
                }
            }
        )
    }

    func stop() {
        guard isRunning else { return }
        runner.stop()
        isRunning = false
        startedAt = nil
        AutoClickerFeedback.play(started: false)
    }

    /// 同步版：退出前用，来不及等队列
    func stopImmediately() {
        runner.stopSynchronously()
        isRunning = false
        startedAt = nil
    }

    func toggle(_ config: AutoClickerConfig) {
        isRunning ? stop() : start(config)
    }

    /// 用户去系统设置里勾上权限后，把那条拦路提示撤掉
    func refreshPermissionMessage() {
        if AutoClickerPermission.hasAccessibility, message?.contains("辅助功能") == true {
            message = nil
        }
    }
}

// MARK: - 提示音

enum AutoClickerFeedback {
    /// 全局快捷键触发时看不到界面，声音是唯一的状态反馈
    static func play(started: Bool) {
        guard AutoClickerStore.shared.config.soundFeedback else { return }
        NSSound(named: started ? "Tink" : "Pop")?.play()
    }

    /// 拾取坐标的反馈：成功一声轻响，失败用系统警告音
    static func playPick(failed: Bool) {
        guard AutoClickerStore.shared.config.soundFeedback else { return }
        NSSound(named: failed ? "Basso" : "Morse")?.play()
    }
}
