import AppKit
import SwiftUI

// MARK: - 托盘菜单
//
// 注意：MenuBarExtra 的 label 不能用自定义动态 View——Sonoma 上会渲染成零宽，
// 状态栏图标直接不可见（实测踩过）。所以图标是静态的，运行状态放在菜单第一行汇报。

/// 菜单栏菜单。定位是「不开主窗口也能干的少数几件事」：
/// 看状态、启停代理、开关系统代理、打开主窗口。
/// 用 .menu 风格而不是 .window——这里要的是点开、点一项、走人。
struct TrayMenuContent: View {
    @ObservedObject private var runtime = V2RayRuntime.shared
    @ObservedObject private var store = V2RayStore.shared
    @ObservedObject private var clicker = AutoClickerEngine.shared
    @State private var core: CoreCandidate?
    @State private var scanning = false

    private var proxy: V2RayProxy { runtime.proxy }

    var body: some View {
        // 状态行：不可点，只汇报
        Button(statusText) {}
            .disabled(true)

        if proxy.state.isRunning || proxy.state.isBusy {
            Button(proxy.state.isBusy ? "停止中…" : "停止代理") {
                runtime.stop()
            }
            .disabled(proxy.state.isBusy)
        } else {
            Button(scanning ? "正在准备内核…" : "启动代理") {
                startProxy()
            }
            .disabled(scanning || proxy.state.isBusy)
        }

        // 内核没跑时开系统代理等于亲手断网，Runtime 里会拦；这里索性禁用掉
        Button(systemProxyText) {
            runtime.setSystemProxy(!runtime.useSystemProxy)
        }
        .disabled(!proxy.state.isRunning && !runtime.useSystemProxy)

        Divider()

        // 连点器：不打开主窗口也能启停，权限不够时点一下给出明确指引
        Button(clickerTitle) { toggleClicker() }

        Divider()

        Button("打开工具箱") { openMainWindow() }
        .keyboardShortcut("o", modifiers: [.command])

        Divider()

        Button("退出工具箱") { NSApp.terminate(nil) }
        .keyboardShortcut("q", modifiers: [.command])
    }

    // MARK: 文案

    private var statusText: String {
        if let message = runtime.message { return "⚠️ \(message)" }
        switch proxy.state {
        case .running:
            let node = proxy.nodeName.isEmpty ? "" : " · \(proxy.nodeName)"
            return "代理运行中\(node)"
        case .starting:
            return "代理启动中…"
        case .stopping:
            return "代理停止中…"
        case .failed(let reason):
            return "代理出错：\(reason)"
        case .idle:
            return "代理未运行"
        }
    }

    private var systemProxyText: String {
        runtime.useSystemProxy ? "✓ 系统代理（已开）" : "系统代理（未开）"
    }

    private var clickerTitle: String {
        if clicker.isRunning {
            return "停止连点（已 \(clicker.firedCount) 次）"
        }
        if !AutoClickerPermission.hasAccessibility {
            return "开始连点（需辅助功能权限）"
        }
        let hotKey = AutoClickerStore.shared.config.hotKey.fullDisplay
        return "开始连点（\(hotKey)）"
    }

    // MARK: 动作

    private func toggleClicker() {
        let engine = AutoClickerEngine.shared
        let config = AutoClickerStore.shared.config
        if engine.isRunning {
            engine.stop()
            return
        }

        engine.start(config)
        // 没开起来通常是权限：托盘里看不到页面上的错误条，这里给个明确出口
        guard !engine.isRunning, let message = engine.message else { return }
        let alert = NSAlert()
        alert.messageText = "连点没能开始"
        alert.informativeText = message
        alert.addButton(withTitle: "打开辅助功能设置")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            AutoClickerPermission.openSettings()
        }
    }

    /// 托盘里启动：内核和节点都要自己备齐——主窗口那套「先检测再启动」
    /// 在这儿没人点，就地把流程走完。
    private func startProxy() {
        guard !scanning else { return }
        scanning = true
        Task {
            // 内置内核没释放过就先释放（跟主窗口 refreshCores 同款逻辑）
            if !BundledCore.isInstalled {
                _ = await Task.detached(priority: .userInitiated) { () -> String? in
                    do {
                        try BundledCore.ensureInstalled()
                        return nil
                    } catch {
                        return error.localizedDescription
                    }
                }.value
            }

            let extra = store.manualCorePath.isEmpty ? [] : [store.manualCorePath]
            let list = await CoreLocator.scanAsync(extraPaths: extra)
            await MainActor.run {
                scanning = false
                guard let core = list.first else {
                    runtime.message = "没有可用内核，先在工具箱的 v2ray 页面里下载一个"
                    return
                }
                guard !runtime.start(core: core, node: store.selectedNode) else { return }
                // start 返回 false 且没消息时，多半是节点为空
                if runtime.message == nil {
                    runtime.message = "还没有节点，先在工具箱的 v2ray 页面里导入分享链接"
                }
            }
        }
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // MenuBarExtra 自己的窗口是 NSPanel，跳过它
        for window in NSApp.windows where !window.isKind(of: NSPanel.self) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
