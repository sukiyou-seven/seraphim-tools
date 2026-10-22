import AppKit
import SwiftUI

// MARK: - 配置字段的 Binding

extension AutoClickerStore {
    /// @Published 的 projectedValue 只能拿到整份 config，这里把单个字段包成 Binding
    func binding<T>(_ keyPath: WritableKeyPath<AutoClickerConfig, T>) -> Binding<T> {
        Binding(
            get: { self.config[keyPath: keyPath] },
            set: { self.config[keyPath: keyPath] = $0 }
        )
    }
}

// MARK: - 行内小工具

/// 「标签 + 控件」的固定行，各卡片共用，省得每处都手写宽度
private struct FieldRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
    }
}

/// 带单位后缀的整数输入 + 步进器
private struct NumberField: View {
    var suffix: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int
    var width: CGFloat = 78

    var body: some View {
        HStack(spacing: 6) {
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 12.5, design: .monospaced))
                .frame(width: width)

            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()

            if !suffix.isEmpty {
                Text(suffix)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 说明文字
private struct HintText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 连点目标

struct AutoClickerActionCard: View {
    @ObservedObject var store: AutoClickerStore
    @Binding var toast: String?

    @State private var recording = false
    @State private var monitor: Any?

    private var config: AutoClickerConfig { store.config }

    var body: some View {
        ToolCard(title: "连点目标", systemImage: "cursorarrow.click") {
            VStack(alignment: .leading, spacing: 14) {
                Picker("", selection: store.binding(\.target)) {
                    ForEach(ClickTarget.allCases) { item in
                        Label(item.title, systemImage: item.systemImage).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if config.target == .mouse {
                    mouseControls
                } else {
                    keyboardControls
                }
            }
        }
        .toast($toast)
        .onDisappear { endRecording() }
    }

    // MARK: 鼠标

    private var mouseControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldRow(title: "按键") {
                HStack(spacing: 6) {
                    ForEach(ClickButton.allCases) { item in
                        ChipButton(title: item.title, isSelected: config.button == item) {
                            store.config.button = item
                        }
                    }
                }
            }

            FieldRow(title: "点击方式") {
                HStack(spacing: 6) {
                    ForEach(ClickStyle.allCases) { item in
                        ChipButton(title: item.title, isSelected: config.clickStyle == item) {
                            store.config.clickStyle = item
                        }
                    }
                }
            }

            FieldRow(title: "按下到松开") {
                NumberField(
                    suffix: "毫秒",
                    value: store.binding(\.pressMs),
                    range: AutoClickerTiming.minPressMs...AutoClickerTiming.maxPressMs,
                    step: 5
                )
            }

            HintText("按下时长就是按住多久才松手。老式 App 和游戏对过短的点击可能不认账，20–50 毫秒最稳；双击模式下每轮发两下 down/up，第二下带 clickState = 2。")
        }
    }

    // MARK: 键盘

    private var keyboardControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldRow(title: "要连发的键") {
                Button {
                    recording ? endRecording() : beginRecording()
                } label: {
                    Text(recording ? "请按键…（Esc 取消）" : config.key.fullDisplay)
                        .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                        .frame(minWidth: 132)
                }
                .buttonStyle(.bordered)
                .tint(recording ? Color.orange : Color.accentColor)

                Toggle("按住不放（不自动松开）", isOn: store.binding(\.holdKey))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
            }

            FieldRow(title: "按下到松开") {
                NumberField(
                    suffix: "毫秒",
                    value: store.binding(\.pressMs),
                    range: AutoClickerTiming.minPressMs...AutoClickerTiming.maxPressMs,
                    step: 5
                )
                .disabled(config.holdKey)
            }

            HintText(config.holdKey
                ? "按住不放：按下后一直保持，直到你按快捷键/点停止才松开——适合持续移动、持续施法这类场景。"
                : "每轮发一次完整的 键按下 → 键松开；带修饰键时（比如 ⌘A）修饰键会一起按下并按相反顺序松开。")
        }
    }

    // MARK: 录制按键

    private func beginRecording() {
        endRecording()
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // 纯修饰键的按下不算一个目标键，放过去等真正的键
            if event.type == .flagsChanged {
                return event
            }
            if event.keyCode == 53 { // Esc 取消
                endRecording()
                return nil
            }

            let chord = KeyChord(
                keyCode: event.keyCode,
                display: KeyCodeNames.name(for: event.keyCode) ?? Self.characterName(for: event),
                modifiers: KeyModifiers(event.modifierFlags)
            )
            store.config.key = chord
            endRecording()
            toast = "连发键设成 \(chord.fullDisplay)"
            return nil
        }
    }

    private func endRecording() {
        guard recording || monitor != nil else { return }
        recording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    static func characterName(for event: NSEvent) -> String {
        guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else {
            return "Key \(event.keyCode)"
        }
        return characters.uppercased()
    }
}

// MARK: - 点击位置

struct AutoClickerPositionCard: View {
    @ObservedObject var store: AutoClickerStore
    @Binding var toast: String?

    @State private var countdown: Int?
    @State private var pickTask: Task<Void, Never>?

    private var config: AutoClickerConfig { store.config }

    var body: some View {
        ToolCard(title: "点击位置", systemImage: "scope") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: store.binding(\.positionMode)) {
                    ForEach(PositionMode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if config.positionMode == .fixed {
                    HStack(spacing: 8) {
                        coordinateField("X", value: store.binding(\.fixedX))
                        coordinateField("Y", value: store.binding(\.fixedY))

                        if let countdown {
                            Button {
                                cancelCountdown()
                            } label: {
                                Label("\(countdown) 秒后取指针位置 · 取消", systemImage: "timer")
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                        } else {
                            Button {
                                beginCountdown()
                            } label: {
                                Label("取指针位置", systemImage: "location.circle")
                                    .font(.system(size: 11.5))
                            }
                            .buttonStyle(.bordered)
                        }

                        Spacer(minLength: 0)
                    }

                    Toggle("每次点击前把指针移到这个位置", isOn: store.binding(\.movePointer))
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11.5))

                    HintText("取位置别用「把鼠标移回按钮再点」——那样记到的是按钮的位置。两种办法：① 点上面的按钮后有 3 秒倒计时，把指针移到目标点等它自己记；② 直接按 \(pickKeyName ?? "拾取快捷键")（全局生效，在下面「全局快捷键」里可改），按一下记当前位置。固定位置用全局屏幕坐标：左上角是 (0, 0)，往右下递增，多显示器时副屏可能是负数。")
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HintText("每次点击落在指针当前所在的位置——把指针停在要点的按钮上就行。连点过程中你把指针挪走，点击也跟着挪。")
                }
            }
        }
        .onDisappear { cancelCountdown() }
    }

    private var pickKeyName: String? {
        config.pickHotKeyEnabled ? config.pickHotKey.fullDisplay : nil
    }

    private func coordinateField(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("", value: value, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 12.5, design: .monospaced))
                .frame(width: 80)
        }
    }

    /// 点按钮时指针就在按钮上，所以不能立刻取——给 3 秒让人把指针挪到目标点
    private func beginCountdown() {
        pickTask?.cancel()
        countdown = 3
        pickTask = Task { @MainActor in
            for remaining in stride(from: 2, through: 1, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                countdown = remaining
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
            capturePointer()
            countdown = nil
        }
    }

    private func cancelCountdown() {
        pickTask?.cancel()
        pickTask = nil
        countdown = nil
    }

    private func capturePointer() {
        var updated = store.config
        guard AutoClickerPointerPick.apply(point: AutoClickerEventFactory.pointerLocation, to: &updated) else {
            toast = "拿不到指针位置，稍后再试"
            return
        }
        store.config = updated
        toast = "已记录坐标 (\(Int(updated.fixedX)), \(Int(updated.fixedY)))"
    }
}

// MARK: - 节奏

struct AutoClickerRhythmCard: View {
    @ObservedObject var store: AutoClickerStore

    private var config: AutoClickerConfig { store.config }

    var body: some View {
        ToolCard(title: "节奏", systemImage: "metronome") {
            VStack(alignment: .leading, spacing: 12) {
                FieldRow(title: "间隔") {
                    NumberField(
                        suffix: "毫秒",
                        value: store.binding(\.intervalMs),
                        range: AutoClickerTiming.minIntervalMs...60_000,
                        step: 10
                    )
                    Text(String(format: "≈ %.1f 次/秒", config.clicksPerSecond))
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                FieldRow(title: "随机抖动") {
                    Toggle("间隔在区间里随机", isOn: store.binding(\.randomize))
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11.5))
                }

                if config.randomize {
                    FieldRow(title: "") {
                        HStack(spacing: 6) {
                            TextField("", value: store.binding(\.randomMinMs), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 12.5, design: .monospaced))
                                .frame(width: 70)
                            Text("到")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                            TextField("", value: store.binding(\.randomMaxMs), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 12.5, design: .monospaced))
                                .frame(width: 70)
                            Text("毫秒之间随机")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                FieldRow(title: "运行方式") {
                    HStack(spacing: 6) {
                        ForEach(RepeatMode.allCases) { item in
                            ChipButton(title: item.title, isSelected: config.repeatMode == item) {
                                store.config.repeatMode = item
                            }
                        }
                        if config.repeatMode == .count {
                            TextField("", value: store.binding(\.count), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 12.5, design: .monospaced))
                                .frame(width: 80)
                            Text("次")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HintText(durationHint)
            }
        }
    }

    private var durationHint: String {
        if let seconds = AutoClickerTiming.estimatedDuration(for: config) {
            let interval = config.intervalDescription
            let perSecond = String(format: "%.1f", config.clicksPerSecond)
            return "间隔 \(interval)，每秒约 \(perSecond) 次，\(config.count) 次跑完大约 \(AutoClickerTiming.describe(seconds))。"
        }
        return "间隔 \(config.intervalDescription)，一直运行到你按快捷键或点停止。"
    }
}

// MARK: - 全局快捷键

struct AutoClickerHotKeyCard: View {
    @ObservedObject var store: AutoClickerStore
    @Binding var toast: String?

    private enum RecordTarget: Equatable {
        case toggle
        case pick

        var title: String {
            switch self {
            case .toggle: return "开始 / 停止"
            case .pick: return "拾取位置"
            }
        }
    }

    @State private var recordingTarget: RecordTarget?
    @State private var monitor: Any?

    private var config: AutoClickerConfig { store.config }

    var body: some View {
        ToolCard(title: "全局快捷键", systemImage: "command") {
            VStack(alignment: .leading, spacing: 12) {
                hotKeyRow(
                    title: "开始 / 停止",
                    combo: config.hotKey,
                    enabled: store.binding(\.hotKeyEnabled),
                    target: .toggle
                )
                hotKeyRow(
                    title: "拾取指针位置",
                    combo: config.pickHotKey,
                    enabled: store.binding(\.pickHotKeyEnabled),
                    target: .pick
                )

                Toggle("启停和拾取时给个提示音", isOn: store.binding(\.soundFeedback))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))

                HintText("两条都全局生效：切到别的 App 也能用，按下后不会再传给前台程序。拾取那条按一下就把指针当前位置填进「固定位置」——不用再把鼠标挪回按钮上；连点运行中不让拾取，先停。默认 F6 / F7，有些键盘把 F 键当媒体键（F6 是「勿扰」），按不出来就在系统设置里勾「将 F1、F2 等键用作标准功能键」，或者改成 ⌃⌥ + 字母这种组合。")
            }
        }
        .toast($toast)
        .onDisappear { endRecording() }
    }

    private func hotKeyRow(
        title: String,
        combo: HotKeyCombo,
        enabled: Binding<Bool>,
        target: RecordTarget
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            Button {
                recordingTarget == target ? endRecording() : beginRecording(target)
            } label: {
                Text(recordingTarget == target ? "请按组合键…（Esc 取消）" : combo.fullDisplay)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .frame(minWidth: 140)
            }
            .buttonStyle(.bordered)
            .tint(recordingTarget == target ? Color.orange : Color.accentColor)

            Toggle("启用", isOn: enabled)
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5))

            Spacer(minLength: 0)
        }
    }

    private func beginRecording(_ target: RecordTarget) {
        endRecording()
        recordingTarget = target
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                return event
            }
            if event.keyCode == 53 { // Esc 取消
                endRecording()
                return nil
            }

            let modifiers = KeyModifiers(event.modifierFlags)
            guard !modifiers.isEmpty || KeyCodeNames.isFunctionKey(event.keyCode) else {
                toast = "全局快捷键要带 ⌘⌃⌥⇧，或者用 F1–F20 / 方向键——不然会把你正常打字吃掉"
                return nil
            }

            let combo = HotKeyCombo(
                keyCode: event.keyCode,
                display: KeyCodeNames.name(for: event.keyCode) ?? AutoClickerActionCard.characterName(for: event),
                modifiers: modifiers
            )
            switch target {
            case .toggle:
                store.config.hotKey = combo
            case .pick:
                store.config.pickHotKey = combo
            }
            endRecording()
            toast = "「\(target.title)」的快捷键改成 \(combo.fullDisplay)"
            return nil
        }
    }

    private func endRecording() {
        guard recordingTarget != nil || monitor != nil else { return }
        recordingTarget = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

// MARK: - 权限与说明

struct AutoClickerNotesCard: View {
    @Binding var permissionGranted: Bool

    @State private var resetMessage: String?

    var body: some View {
        ToolCard(title: "权限与说明", systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 12) {
                if permissionGranted {
                    Label("已获得辅助功能权限", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                } else {
                    ErrorBanner(message: "还差「辅助功能」权限：向别的 App 发点击和按键必须有它。勾上之后回来点「重新检查」，或者重新按一次开始。")

                    HStack(spacing: 8) {
                        Button("请求授权") {
                            permissionGranted = AutoClickerPermission.requestAccessibility()
                        }
                        Button("打开系统设置") {
                            AutoClickerPermission.openSettings()
                        }
                        Button("重置授权记录") {
                            resetMessage = AutoClickerPermission.resetAccessibilityRecord()
                        }
                        Button("重新检查") {
                            permissionGranted = AutoClickerPermission.hasAccessibility
                        }
                    }
                    .controlSize(.regular)

                    if let resetMessage {
                        Text(resetMessage)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("当前运行：\(Bundle.main.bundlePath)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        if let hash = AutoClickerPermission.signatureHash {
                            Text("签名哈希：\(hash.prefix(16))…")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                        }
                        Text("事件投递：\(AutoClickerPermission.canPostEvents ? "允许" : "未允许")")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }

                    HintText("系统设置里明明勾着却还说没权限？那是这个 App 被重新构建过——它用 ad-hoc 签名，系统授权绑在这份二进制的哈希上，一重建旧勾选就失效。点「重置授权记录」，重启 App，再点「请求授权」勾一次；之后只要不重新构建就一直有效。")
                }

                VStack(alignment: .leading, spacing: 6) {
                    bullet("原理：用 CGEvent 合成真实的鼠标 / 键盘事件投递给系统，不是模拟 UI 点击，所以对几乎所有 App 都有效——代价是必须拿到系统级授权。")
                    bullet("连点跑起来后工具箱窗口不用留在前台，切走也照点；用快捷键随时能停。")
                    bullet("系统安全输入框、锁屏、部分全屏游戏的独占输入会忽略合成事件，这是系统限制，不是工具失效。")
                    bullet("「一直运行」模式没有自动刹车，确认目标位置承受得住连续点击再开。")
                }
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("·")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
