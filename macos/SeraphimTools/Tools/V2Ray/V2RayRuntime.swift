import AppKit
import Combine
import Foundation

/// 把代理进程和系统代理开关这两件事拢在一起，顺便负责退出时别把用户网络留在半路上。
final class V2RayRuntime: ObservableObject {
    static let shared = V2RayRuntime()

    let proxy = V2RayProxy()
    let store = V2RayStore.shared

    @Published var useSystemProxy = false
    @Published var message: String?

    private var hookInstalled = false
    private var reconciling = false
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        // 内核自己挂掉（不是我们停的）时，系统代理还指着那个死端口，等于断网。
        // 这里兜一把：一见内核意外退出就把系统代理关掉。
        proxy.$state
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                guard case .failed = state, self.useSystemProxy else { return }
                self.setSystemProxy(false, quiet: true)
                self.message = "内核意外退出了，已经顺手关掉系统代理，免得整个网都不通"
            }
            .store(in: &cancellables)
    }

    var isRunning: Bool { proxy.isRunning }

    /// 本机代理的两个端口。系统代理里指向这两个端口的设置都是我们自己写的
    private var ourPorts: Set<Int> { [store.socksPort, store.httpPort] }

    func options() -> XrayConfigBuilder.Options {
        XrayConfigBuilder.Options(
            socksPort: store.socksPort,
            httpPort: store.httpPort,
            bypassChina: store.bypassChina
        )
    }

    // MARK: 启停

    @discardableResult
    func start(core: CoreCandidate?, node: V2RayNode?) -> Bool {
        guard let core else {
            message = "没有可用的内核，先检测或下载一个"
            return false
        }
        guard let node else {
            message = "还没有节点，先导入一条分享链接"
            return false
        }
        guard !proxy.isRunning, !proxy.state.isBusy else { return false }
        proxy.start(node: node, core: core, options: options())
        return true
    }

    func stop() {
        guard useSystemProxy else {
            proxy.stop()
            return
        }
        // 必须先把系统代理还原干净再停内核。反过来的话，中间会有一段时间
        // 系统代理还指着已经死掉的本机端口，整台机器看上去就是断网。
        setSystemProxy(false, quiet: true) { [weak self] in
            self?.proxy.stop()
        }
    }

    /// 换节点后重启
    func restart(core: CoreCandidate?, node: V2RayNode?) {
        guard let core else { return }
        guard let target = node ?? store.selectedNode else { return }

        guard proxy.isRunning || proxy.state.isBusy else {
            start(core: core, node: target)
            return
        }
        let keepSystemProxy = useSystemProxy
        if keepSystemProxy { setSystemProxy(false, quiet: true) }
        proxy.stop()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.4) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.proxy.start(node: target, core: core, options: self.options())
                if keepSystemProxy {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) {
                        DispatchQueue.main.async { self.setSystemProxy(true, quiet: true) }
                    }
                }
            }
        }
    }

    // MARK: 系统代理

    func setSystemProxy(_ on: Bool, quiet: Bool = false, completion: (() -> Void)? = nil) {
        guard on != useSystemProxy || quiet else {
            completion?()
            return
        }

        if on {
            // 内核都没跑就指过去，等于亲手把网掐了。
            // 只有手动开关才拦，程序内部的重启流程（quiet）放行，那时候内核还在启动中
            if !quiet, !proxy.isRunning, !proxy.state.isBusy {
                useSystemProxy = false
                message = "代理还没启动，先把内核跑起来再开系统代理"
                completion?()
                return
            }

            useSystemProxy = true
            let ports = ourPorts
            let httpPort = store.httpPort
            let socksPort = store.socksPort
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                // 存备份前先洗掉指向本机端口的残留，否则会把我们自己上一次留下的状态
                // 当成用户的原始设置存起来，之后"还原"就变成又把代理打开——关不掉就是这么来的
                let snapshot = SystemProxy.snapshot(ourPorts: ports)
                self.store.saveProxyBackup(SystemProxy.encode(snapshot))
                let touched = SystemProxy.enableAll(httpPort: httpPort, socksPort: socksPort)
                DispatchQueue.main.async {
                    if !quiet {
                        self.message = touched.isEmpty
                            ? "没找到能设置的网络服务"
                            : "系统代理已开：\(touched.joined(separator: "、"))"
                    }
                    completion?()
                }
            }
        } else {
            useSystemProxy = false
            let ports = ourPorts
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                let states = SystemProxy.decode(self.store.proxyBackup)
                if states.isEmpty {
                    SystemProxy.disableAll()
                } else {
                    SystemProxy.restore(states, ourPorts: ports)
                }
                DispatchQueue.main.async {
                    if !quiet { self.message = "系统代理已还原" }
                    completion?()
                }
            }
        }
    }

    // MARK: 残留自愈

    /// 跟系统里的实际状态对一次账。
    ///
    /// 系统代理的设置是留在系统里的，而"系统代理开关"只活在内存里。所以只要 App 被强杀、
    /// 崩溃，或者上一次还原失败，就会留下"系统代理还指着本机端口、内核却已经不在了"的
    /// 断网现场。这里负责把它认出来并收拾掉，顺便把开关状态对齐到现实。
    func reconcileSystemProxy() {
        guard !reconciling else { return }
        reconciling = true
        let ports = ourPorts
        let stored = store.proxyBackup

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let stale = SystemProxy.pointingAtUs(ourPorts: ports)
            let clean = SystemProxy.sanitize(SystemProxy.decode(stored), ourPorts: ports)
            let repaired = SystemProxy.encode(clean)

            DispatchQueue.main.async {
                guard let self else { return }
                self.reconciling = false

                // 历史脏备份顺手洗一遍，免得以后"还原"又把它翻出来
                if !stored.isEmpty, repaired != stored {
                    self.store.saveProxyBackup(repaired)
                }

                guard !stale.isEmpty else { return }

                if self.proxy.isRunning {
                    // 内核在跑，那这是本次会话开的，把开关同步成已开
                    self.useSystemProxy = true
                } else {
                    // 内核没了却还指着本机端口 → 上次留下的烂摊子，清掉
                    self.setSystemProxy(false, quiet: true)
                    self.message = "上次退出时系统代理没还原干净，已自动关掉（\(stale.joined(separator: "、"))）"
                }
            }
        }
    }

    // MARK: 退出收尾

    /// 退出前把系统代理还原、内核停掉，免得留下断网现场
    func installShutdownHook() {
        guard !hookInstalled else { return }
        hookInstalled = true
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // 不只看内存里的开关：只要系统里还有指向本机端口的代理设置，就得收拾干净，
            // 否则退出后整台机器就上不了网了
            let ports = self.ourPorts
            let leftover = self.useSystemProxy || !SystemProxy.pointingAtUs(ourPorts: ports).isEmpty
            if leftover {
                let states = SystemProxy.decode(self.store.proxyBackup)
                if states.isEmpty {
                    SystemProxy.disableAll()
                } else {
                    SystemProxy.restore(states, ourPorts: ports)
                }
                self.useSystemProxy = false
            }
            if self.proxy.isRunning {
                self.proxy.stop()
                // 给内核一点退出时间
                usleep(600_000)
            }
        }
    }
}
