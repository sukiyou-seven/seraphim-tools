import SwiftUI

@main
struct SeraphimToolsApp: App {
    init() {
        // 退出收尾（还原系统代理 + 停内核）以前装在 v2ray 页面的 onAppear 里——
        // 用户没打开过那个页面，钩子就没装，退出可能留下「系统代理指死端口」的断网现场。
        // App 一启动就装好，跟页面无关。
        V2RayRuntime.shared.installShutdownHook()
        // 顺手对账：上次强杀/崩溃留下的系统代理残留，启动时就收拾掉
        V2RayRuntime.shared.reconcileSystemProxy()

        // 连点器的全局热键和退出松手也跟页面无关：开箱即可用，退出不留按住不放的键
        AutoClickerHotKey.shared.install()
        AutoClickerEngine.shared.installTerminationHook()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 940, minHeight: 620)
                .onOpenURL { url in
                    guard url.isFileURL else { return }
                    AppState.shared.enqueue(imageURL: url)
                }
        }
        .defaultSize(width: 1160, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Divider()
                Button("重新载入工具箱") {
                    NotificationCenter.default.post(name: .reloadToolbox, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
            }
        }

        // 菜单栏（托盘）：看代理状态、启停代理、开系统代理、唤起主窗口
        MenuBarExtra {
            TrayMenuContent()
        } label: {
            Label("工具箱", systemImage: "wrench.and.screwdriver")
        }
        .menuBarExtraStyle(.menu)
    }
}

extension Notification.Name {
    static let reloadToolbox = Notification.Name("SeraphimTools.reloadToolbox")
}
