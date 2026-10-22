import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

// MARK: - 全局热键中心

/// 基于 Carbon `RegisterEventHotKey` 的全局热键。
///
/// 选 Carbon 而不是 `NSEvent.addGlobalMonitorForEvents`：后者只能"旁听"按键，
/// 按键照样传给前台 App（F6 会同时触发系统功能和连点）；而且监听全局键盘要
/// 辅助功能授权。Carbon 的热键是系统级独占注册，不需要额外权限，按下即拦。
final class GlobalHotKeyCenter {
    static let shared = GlobalHotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private var installed = false

    /// 四字符签名，区分「这条热键是本 App 的」
    private let signature: OSType = 0x5341_5246 // 'SARF'

    private init() {}

    @discardableResult
    func register(_ combo: HotKeyCombo, handler: @escaping () -> Void) -> UInt32? {
        installIfNeeded()

        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var ref: EventHotKeyRef?

        let status = RegisterEventHotKey(
            UInt32(combo.keyCode),
            combo.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else { return nil }
        handlers[id] = handler
        refs[id] = ref
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        handlers.removeValue(forKey: id)
    }

    fileprivate func dispatch(id: UInt32) {
        guard let handler = handlers[id] else { return }
        // Carbon 回调在事件循环里，切回主线程再干活（里面会碰 SwiftUI 状态）
        DispatchQueue.main.async { handler() }
    }

    private func installIfNeeded() {
        guard !installed else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }

                var hotKeyID = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard result == noErr else { return OSStatus(eventNotHandledErr) }

                let center = Unmanaged<GlobalHotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                center.dispatch(id: hotKeyID.id)
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        installed = status == noErr
    }
}

// MARK: - 修饰键的 Carbon 表示

extension KeyModifiers {
    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if contains(.command) { value |= UInt32(cmdKey) }
        if contains(.shift) { value |= UInt32(shiftKey) }
        if contains(.option) { value |= UInt32(optionKey) }
        if contains(.control) { value |= UInt32(controlKey) }
        return value
    }
}

extension HotKeyCombo {
    var carbonModifiers: UInt32 { modifiers.carbonModifiers }
}

// MARK: - 连点器热键

/// 把「配置里的热键」和「Carbon 注册」绑在一起：配置一改就重注册，App 一启动就装好。
///
/// 不挂在工具页面的 onAppear 上——用户没打开过连点页面，热键也得能用。
/// 两条热键各占一个槽位：开始/停止（默认 F6）和拾取指针位置（默认 F7）。
final class AutoClickerHotKey {
    static let shared = AutoClickerHotKey()

    private struct Slot {
        var id: UInt32?
        var combo: HotKeyCombo?
    }

    private var toggleSlot = Slot()
    private var pickSlot = Slot()
    private var cancellable: AnyCancellable?

    private init() {}

    func install() {
        guard cancellable == nil else { return }
        cancellable = AutoClickerStore.shared.$config
            .removeDuplicates()
            .sink { [weak self] config in
                self?.apply(config)
            }
    }

    /// 按键组合或启用开关变了才动注册，其他配置改动不折腾 Carbon
    func apply(_ config: AutoClickerConfig) {
        applyToggle(config)
        applyPick(config)

        let conflict = config.hotKeyEnabled
            && config.pickHotKeyEnabled
            && config.hotKey == config.pickHotKey
        if conflict {
            AutoClickerEngine.shared.message = "「开始 / 停止」和「拾取指针位置」用了同一个键（\(config.hotKey.fullDisplay)），拾取那条不会生效——换一个"
        } else if AutoClickerEngine.shared.message?.contains("拾取那条不会生效") == true {
            AutoClickerEngine.shared.message = nil
        }
    }

    private func applyToggle(_ config: AutoClickerConfig) {
        guard config.hotKeyEnabled else {
            unregister(&toggleSlot)
            return
        }
        if toggleSlot.id != nil, toggleSlot.combo == config.hotKey { return }

        unregister(&toggleSlot)
        toggleSlot.combo = config.hotKey
        toggleSlot.id = GlobalHotKeyCenter.shared.register(config.hotKey) { [weak self] in
            self?.triggerToggle()
        }
        if toggleSlot.id == nil {
            toggleSlot.combo = nil
            AutoClickerEngine.shared.message = "快捷键 \(config.hotKey.fullDisplay) 注册失败——可能被别的 App 占用了，换一个试试"
        }
    }

    private func applyPick(_ config: AutoClickerConfig) {
        guard config.pickHotKeyEnabled else {
            unregister(&pickSlot)
            return
        }
        if pickSlot.id != nil, pickSlot.combo == config.pickHotKey { return }

        unregister(&pickSlot)
        pickSlot.combo = config.pickHotKey
        pickSlot.id = GlobalHotKeyCenter.shared.register(config.pickHotKey) { [weak self] in
            self?.triggerPick()
        }
        if pickSlot.id == nil {
            pickSlot.combo = nil
            AutoClickerEngine.shared.message = "拾取位置的快捷键 \(config.pickHotKey.fullDisplay) 注册失败——可能被占用了，换一个试试"
        }
    }

    private func unregister(_ slot: inout Slot) {
        if let id = slot.id {
            GlobalHotKeyCenter.shared.unregister(id)
        }
        slot.id = nil
        slot.combo = nil
    }

    private func triggerToggle() {
        let config = AutoClickerStore.shared.config
        AutoClickerEngine.shared.toggle(config)
    }

    /// 按一下就把指针当前位置记成固定点击点，并自动切到「固定位置」。
    /// 连点跑着的时候不让拾取：那会儿指针正被连点用着，记下来多半是错的。
    private func triggerPick() {
        let engine = AutoClickerEngine.shared
        let store = AutoClickerStore.shared

        guard !engine.isRunning else {
            engine.message = "连点正在运行，先停下来再按 \(store.config.pickHotKey.fullDisplay) 拾取位置"
            AutoClickerFeedback.playPick(failed: true)
            return
        }

        var config = store.config
        guard AutoClickerPointerPick.apply(point: AutoClickerEventFactory.pointerLocation, to: &config) else {
            engine.message = "拿不到指针位置，稍后再试"
            AutoClickerFeedback.playPick(failed: true)
            return
        }

        store.config = config
        engine.message = nil
        AutoClickerFeedback.playPick(failed: false)
    }
}
