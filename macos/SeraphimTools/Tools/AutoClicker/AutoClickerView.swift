import AppKit
import Combine
import SwiftUI

/// 鼠标连点 / 键盘连发。
///
/// 定位：给「要点很多下」和「要按很多次」这两件烦人活一个开关。
/// 事件是 CGEvent 合成的真事件，所以跑起来能切到别的 App，用全局热键启停。
struct AutoClickerView: View {
    @ObservedObject private var store = AutoClickerStore.shared
    @ObservedObject private var engine = AutoClickerEngine.shared

    @State private var permissionGranted = AutoClickerPermission.hasAccessibility
    @State private var toast: String?
    @State private var tick = Date()

    private let heartbeat = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var config: AutoClickerConfig { store.config }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                statusCard
                AutoClickerActionCard(store: store, toast: $toast)
                if config.target == .mouse {
                    AutoClickerPositionCard(store: store, toast: $toast)
                }
                AutoClickerRhythmCard(store: store)
                AutoClickerHotKeyCard(store: store, toast: $toast)
                AutoClickerNotesCard(permissionGranted: $permissionGranted)
            }
            .padding(20)
        }
        .toast($toast)
        .onAppear {
            permissionGranted = AutoClickerPermission.hasAccessibility
            engine.refreshPermissionMessage()
        }
        // 用户可能正开着系统设置授权，这里半秒对一次账，回来就是绿的
        .onReceive(heartbeat) { _ in
            tick = Date()
            let granted = AutoClickerPermission.hasAccessibility
            if granted != permissionGranted {
                permissionGranted = granted
                engine.refreshPermissionMessage()
            }
        }
    }

    // MARK: - 状态与启停

    private var statusCard: some View {
        ToolCard(title: "连点控制", systemImage: "cursorarrow.click.2") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    statusDot

                    VStack(alignment: .leading, spacing: 3) {
                        Text(engine.isRunning ? "正在\(config.target.verb)…" : "空闲")
                            .font(.system(size: 15, weight: .semibold))
                        Text(statusDetail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 12)

                    Button {
                        toggle()
                    } label: {
                        Label(
                            engine.isRunning ? "停止" : "开始",
                            systemImage: engine.isRunning ? "stop.fill" : "play.fill"
                        )
                        .font(.system(size: 13, weight: .semibold))
                        .frame(minWidth: 92)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(engine.isRunning ? Color.red : Color.accentColor)
                    .controlSize(.large)
                }

                if let message = engine.message {
                    ErrorBanner(message: message)
                }

                HStack(spacing: 8) {
                    NoticeTag(
                        text: hotKeyHint,
                        systemImage: config.hotKeyEnabled ? "command" : "command.square",
                        tint: config.hotKeyEnabled ? .blue : .secondary
                    )
                    NoticeTag(
                        text: intervalTag,
                        systemImage: "metronome",
                        tint: .secondary
                    )
                    if config.target == .mouse, config.positionMode == .fixed {
                        NoticeTag(
                            text: "固定坐标 (\(Int(config.fixedX)), \(Int(config.fixedY)))",
                            systemImage: "scope",
                            tint: .secondary
                        )
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var statusDot: some View {
        ZStack {
            Circle()
                .fill((engine.isRunning ? Color.green : Color.secondary).opacity(0.16))
                .frame(width: 44, height: 44)
            Circle()
                .fill(engine.isRunning ? Color.green : Color.secondary.opacity(0.55))
                .frame(width: 12, height: 12)
        }
    }

    private var statusDetail: String {
        if engine.isRunning {
            var parts = ["已\(config.target.verb) \(engine.firedCount) 次"]
            if let started = engine.startedAt {
                parts.append("运行 \(AutoClickerTiming.describe(tick.timeIntervalSince(started)))")
            }
            switch config.target {
            case .mouse:
                parts.append("\(config.clickStyle.title)\(config.button.title)")
            case .keyboard:
                parts.append(config.holdKey ? "按住 \(config.key.fullDisplay)" : "按 \(config.key.fullDisplay)")
            }
            return parts.joined(separator: " · ")
        }

        var parts: [String] = []
        switch config.target {
        case .mouse:
            parts.append("\(config.clickStyle.title)\(config.button.title)")
        case .keyboard:
            parts.append("连发 \(config.key.fullDisplay)")
        }
        if config.repeatMode == .count {
            parts.append("计划 \(config.count) 次")
        } else {
            parts.append("运行到手动停止")
        }
        parts.append("间隔 \(config.intervalDescription)")
        return parts.joined(separator: " · ")
    }

    private var hotKeyHint: String {
        guard config.hotKeyEnabled else { return "全局快捷键已关闭" }
        return "\(config.hotKey.fullDisplay) 开始 / 停止"
    }

    private var intervalTag: String {
        String(format: "约 %.1f 次/秒", config.clicksPerSecond)
    }

    private func toggle() {
        if engine.isRunning {
            engine.stop()
        } else {
            engine.start(config)
            if engine.isRunning {
                toast = "开始了，\(hotKeyHint)"
            }
        }
    }
}
