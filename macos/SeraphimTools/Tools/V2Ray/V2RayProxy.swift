import Combine
import Foundation
import Darwin

// MARK: - 日志

struct ProxyLogLine: Identifiable, Hashable, Sendable {
    let id = UUID()
    let date: Date
    let text: String
    let isError: Bool
}

// MARK: - 会话日志落盘

/// 代理会话日志落盘。内核异常退出、App 被强杀这类「当时看见了、事后说不清」的事，
/// 只存内存等于没记——下次打开日志面板是空的，谁也说不清上次为什么断。
/// 文件在 runtime 目录（proxy-session.log），出问题把整个文件拷走就行。
enum ProxySessionLog {
    /// 会话分隔符前缀。按它把文件切成一段一段的「上次会话」
    static let separatorPrefix = "── 会话"

    static var fileURL: URL {
        CoreLocator.runtimeDirectory().appendingPathComponent("proxy-session.log")
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    static func append(_ text: String, isError: Bool) {
        let stamp = stampFormatter.string(from: Date())
        let mark = isError ? "!! " : ""
        let line = "[\(stamp)] \(mark)\(text)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = fileURL
        // 必须串行：并发队列会把「会话分隔符」插到前一个会话的日志中间，
        // 按分隔符切段就全乱了
        writeQueue.async {
            write(data, to: url)
        }
    }

    private static let writeQueue = DispatchQueue(label: "SeraphimTools.proxySessionLog")

    /// 开始新会话时补一行分隔符，事后才能区分「上次会话」和「这次会话」
    static func beginSession(node: String, core: String) {
        append("\(separatorPrefix)：\(node) · \(core) ──", isError: false)
    }

    /// 上一次会话（最近一条分隔符之前那段）的错误行。
    /// App 重启时拿来提醒「上次为什么断」；还没用过（没有分隔符）时返回空。
    static func previousSessionErrorLines() -> [String] {
        guard let all = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let segments = all.components(separatedBy: separatorPrefix)
        // 最后一段是「当前/最近」会话；提醒针对它前面那一段
        guard segments.count >= 2 else { return [] }
        let previous = segments[segments.count - 2]
        return previous
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("[") && $0.contains("!! ") }
    }

    private static func write(_ data: Data, to url: URL) {
        let path = url.path
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        } else if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let size = attrs[.size] as? UInt64, size > 512 * 1024 {
            // 超过 512 KB 就轮转：只留最后 300 行，文件别无限长
            rotate(path: path)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    private static func rotate(path: String) {
        guard let all = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let lines = all.components(separatedBy: "\n")
        let kept = lines.suffix(300).joined(separator: "\n")
        try? kept.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

enum ProxyState: Equatable, Sendable {
    case idle
    case starting
    case running
    case stopping
    case failed(String)

    var isBusy: Bool {
        self == .starting || self == .stopping
    }

    var isRunning: Bool {
        self == .running
    }

    var title: String {
        switch self {
        case .idle: return "未运行"
        case .starting: return "启动中…"
        case .running: return "运行中"
        case .stopping: return "停止中…"
        case .failed(let message): return message
        }
    }
}

// MARK: - 端口

enum PortProbe {
    /// 本地端口有没有人在听
    static func isListening(_ port: UInt16, host: String = "127.0.0.1") -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr(host)

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    /// 谁占着这个端口（lsof），拿不到就返回 nil
    static func occupant(of port: UInt16) -> String? {
        let result = Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-F", "cn"], timeout: 6)
        guard result.ok else { return nil }
        var command = ""
        for line in result.out.components(separatedBy: .newlines) {
            if line.hasPrefix("c") { command = String(line.dropFirst()) }
        }
        return command.isEmpty ? nil : command
    }

    /// 占着这个端口的进程 PID 列表（拿不到就是空）
    static func listenerPIDs(of port: UInt16) -> [pid_t] {
        let result = Shell.run("/usr/sbin/lsof", ["-nP", "-t", "-iTCP:\(port)", "-sTCP:LISTEN"], timeout: 5)
        guard result.ok else { return [] }
        return result.out
            .components(separatedBy: .newlines)
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .map { pid_t($0) }
    }

    /// 进程主可执行文件的路径（lsof 的 txt 段）。拿不到返回 nil。
    /// 不用 ps：全路径比命令行可靠，而且 ps 在某些受限环境里跑不了。
    static func executablePath(of pid: pid_t) -> String? {
        let result = Shell.run("/usr/sbin/lsof", ["-a", "-nP", "-p", "\(pid)", "-d", "txt", "-Fn"], timeout: 5)
        guard result.ok else { return nil }
        for line in result.out.components(separatedBy: .newlines) where line.hasPrefix("n") {
            let path = String(line.dropFirst())
            if path.hasPrefix("/") { return path }
        }
        return nil
    }
}

// MARK: - 延迟测速

/// 量一下到远端地址的 TCP 握手耗时，够用了（不带 payload，不碰协议）
enum TCPPing {
    static func measure(host: String, port: UInt16, timeout: TimeInterval = 3) -> Int? {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &list) == 0, let head = list else { return nil }
        defer { freeaddrinfo(list) }

        var pointer: UnsafeMutablePointer<addrinfo>? = head
        while let info = pointer {
            if let value = attempt(info.pointee, timeout: timeout) { return value }
            pointer = info.pointee.ai_next
        }
        return nil
    }

    private static func attempt(_ info: addrinfo, timeout: TimeInterval) -> Int? {
        let descriptor = socket(info.ai_family, info.ai_socktype, info.ai_protocol)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        // 非阻塞 connect + poll，才好精确控超时
        let flags = fcntl(descriptor, F_GETFL, 0)
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
        var one: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

        let start = DispatchTime.now().uptimeNanoseconds
        let result = connect(descriptor, info.ai_addr, info.ai_addrlen)
        if result == 0 {
            return Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        guard errno == EINPROGRESS else { return nil }

        var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        let milliseconds = Int32(max(1, timeout * 1000))
        guard poll(&pollDescriptor, 1, milliseconds) > 0 else { return nil }

        var error: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &length) == 0, error == 0 else { return nil }
        return Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }
}

// MARK: - 连通性自检

/// 端口在监听 ≠ 真的能出去。
///
/// 内核可能起来了、端口也听着，但出站压根连不上节点（节点挂了、参数错了、路由把流量
/// 放给了直连），这时候界面显示"运行中"纯属骗自己。所以起完内核就拿本地代理去
/// 请求一个测试地址，把结果摆给用户看。
enum ProxyHealth: Equatable, Sendable {
    case unknown
    case testing
    case ok(socksMs: Int, httpMs: Int)
    case partial(String)
    case failed(String)

    var isGood: Bool {
        if case .ok = self { return true }
        return false
    }

    var isBusy: Bool { self == .testing }

    var title: String {
        switch self {
        case .unknown: return "还没测过"
        case .testing: return "正在检测…"
        case .ok(let socksMs, let httpMs):
            return "已连通 · SOCKS \(socksMs) ms · HTTP \(httpMs) ms"
        case .partial(let detail): return "部分不通：\(detail)"
        case .failed(let reason): return "连不出去：\(reason)"
        }
    }
}

/// 借系统自带的 curl 做一次真实请求——它能用 `--socks5-hostname` 把域名交给代理解析，
/// 正好避开本机 DNS 被污染这档子事。
enum ProxyProbe {

    private static let targets = [
        "https://www.gstatic.com/generate_204",
        "https://cp.cloudflare.com/generate_204"
    ]

    /// 环境里可能被塞了代理变量，命令行参数优先，但清干净更保险
    private static let cleanEnvironment: [String: String] = [
        "http_proxy": "", "https_proxy": "", "all_proxy": "",
        "HTTP_PROXY": "", "HTTPS_PROXY": "", "ALL_PROXY": ""
    ]

    static func measure(viaSOCKS port: Int) -> Int? {
        firstSuccess(extraArguments: ["--socks5-hostname", "127.0.0.1:\(port)"])
    }

    static func measure(viaHTTP port: Int) -> Int? {
        firstSuccess(extraArguments: ["-x", "http://127.0.0.1:\(port)"])
    }

    private static func firstSuccess(extraArguments: [String]) -> Int? {
        for target in targets {
            if let milliseconds = request(target, extraArguments: extraArguments) {
                return milliseconds
            }
        }
        return nil
    }

    private static func request(_ url: String, extraArguments: [String]) -> Int? {
        let result = Shell.run(
            "/usr/bin/curl",
            ["-s", "-o", "/dev/null", "-w", "%{http_code} %{time_total}",
             "--max-time", "8", "--connect-timeout", "6"] + extraArguments + [url],
            timeout: 14,
            environment: cleanEnvironment
        )
        let parts = result.out
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map(String.init)
        guard parts.count >= 2,
              let code = Int(parts[0]), (200..<400).contains(code),
              let seconds = Double(parts[1]) else { return nil }
        return Int((seconds * 1000).rounded())
    }
}

// MARK: - 代理会话

/// 管一个内核进程：写配置、启停、收日志
final class V2RayProxy: ObservableObject {
    @Published private(set) var state: ProxyState = .idle
    @Published private(set) var logs: [ProxyLogLine] = []
    @Published private(set) var startedAt: Date?
    @Published private(set) var nodeName = ""
    @Published private(set) var coreDescription = ""
    @Published private(set) var configPath = ""
    @Published private(set) var health: ProxyHealth = .unknown
    @Published var systemProxyOn = false

    private var process: Process?
    private var configURL: URL?
    private var activePorts: (socks: Int, http: Int)?
    private let maxLogLines = 600

    var isRunning: Bool { state.isRunning }

    var uptimeText: String? {
        guard let startedAt else { return nil }
        let seconds = Int(Date().timeIntervalSince(startedAt))
        if seconds < 60 { return "\(seconds) 秒" }
        if seconds < 3600 { return "\(seconds / 60) 分 \(seconds % 60) 秒" }
        return "\(seconds / 3600) 时 \((seconds % 3600) / 60) 分"
    }

    // MARK: 启动

    func start(node: V2RayNode, core: CoreCandidate, options: XrayConfigBuilder.Options) {
        guard !state.isBusy, !state.isRunning else { return }

        // geo 数据在不在，直接决定能不能写 geosite:cn（缺文件内核会拒绝启动）
        let geoDirectory = CoreLocator.geoAssetDirectory(near: core.path)
        var effective = options
        effective.geoAvailable = geoDirectory != nil

        let config = XrayConfigBuilder.build(node: node, options: effective)
        let runtime = CoreLocator.runtimeDirectory()
        let url = runtime.appendingPathComponent("config.json")
        do {
            try config.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            appendLog("配置写入失败：\(error.localizedDescription)", isError: true)
            state = .failed("配置写入失败")
            return
        }
        configPath = url.path

        // 两个入站撞同一个端口的话内核会直接起不来，先拦下来
        guard options.socksPort != options.httpPort else {
            appendLog("SOCKS 和 HTTP 不能是同一个端口（现在都是 \(options.socksPort)），改一个再启", isError: true)
            state = .failed("本地端口重复")
            return
        }

        // 端口先看有没有被占。占着的若是上次强杀 App 留下的孤儿内核，替用户收掉再走；
        // 是别人的进程就照旧报错，不动它。
        for (label, port) in [("SOCKS", options.socksPort), ("HTTP", options.httpPort)] {
            if PortProbe.isListening(UInt16(port)) {
                if reclaimOurLeftoverCore(port: port) { continue }
                let who = PortProbe.occupant(of: UInt16(port)).map { "（\($0) 占着）" } ?? ""
                appendLog("\(label) 端口 \(port) 已被占用\(who)，换个端口或用 v2rayN 的面板先停掉它", isError: true)
                state = .failed("\(label) 端口 \(port) 被占用")
                return
            }
        }

        state = .starting
        health = .unknown
        activePorts = (options.socksPort, options.httpPort)
        nodeName = node.displayName
        coreDescription = "\(core.kind.title) \(core.version)（\(core.source)）"
        logs.removeAll()
        ProxySessionLog.beginSession(node: node.displayName, core: coreDescription)
        appendLog("使用内核：\(core.path)")
        appendLog("配置文件：\(url.path)")
        appendLog("本地端口：SOCKS 127.0.0.1:\(options.socksPort) · HTTP 127.0.0.1:\(options.httpPort)")
        if options.bypassChina {
            if let geoDirectory {
                appendLog("大陆分流：开（geo 数据在 \(geoDirectory)）")
            } else {
                appendLog("没找到 geosite.dat，已自动降级为全局走代理（内核会因为缺这个文件起不来）", isError: true)
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: core.path)
        process.arguments = ["run", "-c", url.path]

        var environment = ProcessInfo.processInfo.environment
        if let geoDirectory {
            environment[core.kind.geoEnvironmentKey] = geoDirectory
            environment["XRAY_LOCATION_ASSET"] = geoDirectory
            environment["V2RAY_LOCATION_ASSET"] = geoDirectory
        }
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.ingest(data, isError: false)
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.ingest(data, isError: true)
        }

        process.terminationHandler = { [weak self] finished in
            guard let self else { return }
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            let status = finished.terminationStatus
            DispatchQueue.main.async {
                self.process = nil
                if self.state == .stopping {
                    self.state = .idle
                    self.startedAt = nil
                    self.appendLog("已停止")
                } else if self.state.isRunning || self.state == .starting {
                    self.state = .failed("内核退出了（代码 \(status)）")
                    self.startedAt = nil
                    self.health = .unknown
                    self.activePorts = nil
                    self.appendLog("内核异常退出，代码 \(status)，看上面的日志找原因", isError: true)
                }
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            appendLog("启动失败：\(error.localizedDescription)", isError: true)
            state = .failed("启动失败")
            return
        }

        waitForReady(socksPort: options.socksPort, httpPort: options.httpPort)
    }

    /// 端口被占时，看看占着的是不是我们自己的孤儿内核（App 被强杀时 xray 不会被
    /// 一起带走，下次启动就撞上「端口被占用」）。是就替用户收掉；不是别人的不动。
    private func reclaimOurLeftoverCore(port: Int) -> Bool {
        for pid in PortProbe.listenerPIDs(of: UInt16(port)) {
            guard let path = PortProbe.executablePath(of: pid) else { continue }
            let lower = path.lowercased()
            let isOurs = lower.contains("/seraphimtools/") && (lower.contains("xray") || lower.contains("v2ray"))
            guard isOurs else { continue }

            appendLog("端口 \(port) 被上次留下的内核进程占着（pid \(pid)，\(path)），先收掉再启动")
            kill(pid, SIGTERM)
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline, PortProbe.isListening(UInt16(port)) {
                usleep(100_000)
            }
            if PortProbe.isListening(UInt16(port)) {
                kill(pid, SIGKILL)
                usleep(300_000)
            }
            return !PortProbe.isListening(UInt16(port))
        }
        return false
    }

    /// 轮询端口，最多等 6 秒
    private func waitForReady(socksPort: Int, httpPort: Int) {
        let deadline = Date().addingTimeInterval(6)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while Date() < deadline {
                guard let self else { return }
                if self.process == nil {
                    DispatchQueue.main.async {
                        if self.state == .starting {
                            self.state = .failed("内核没起来")
                        }
                    }
                    return
                }
                let listening = PortProbe.isListening(UInt16(socksPort)) || PortProbe.isListening(UInt16(httpPort))
                if listening {
                    DispatchQueue.main.async {
                        guard self.state == .starting else { return }
                        self.state = .running
                        self.startedAt = Date()
                        self.appendLog("启动完成，本地端口已就绪：SOCKS \(socksPort) · HTTP \(httpPort)")
                        self.verifyConnectivity()
                    }
                    return
                }
                usleep(220_000)
            }
            DispatchQueue.main.async {
                guard let self, self.state == .starting else { return }
                self.state = .failed("等超时了，端口没起来")
                self.appendLog("等了 6 秒端口还没监听，看内核日志", isError: true)
                self.terminateProcess()
            }
        }
    }

    // MARK: 连通性自检

    /// 拿本地端口真发一次请求，确认流量确实能从节点出去
    func verifyConnectivity() {
        guard let ports = activePorts, isRunning else {
            health = .unknown
            return
        }
        guard !health.isBusy else { return }
        health = .testing

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let box = ProbeBox()
            let group = DispatchGroup()

            group.enter()
            DispatchQueue.global(qos: .utility).async {
                box.socks = ProxyProbe.measure(viaSOCKS: ports.socks)
                group.leave()
            }
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                box.http = ProxyProbe.measure(viaHTTP: ports.http)
                group.leave()
            }
            group.wait()

            DispatchQueue.main.async {
                guard let self else { return }
                switch (box.socks, box.http) {
                case let (socksMs?, httpMs?):
                    self.health = .ok(socksMs: socksMs, httpMs: httpMs)
                    self.appendLog("自检通过：SOCKS \(socksMs) ms · HTTP \(httpMs) ms")

                case let (socksMs?, nil):
                    self.health = .partial("HTTP 端口 \(ports.http) 没响应")
                    self.appendLog("SOCKS 能出去（\(socksMs) ms），但 HTTP 端口 \(ports.http) 没反应", isError: true)

                case let (nil, httpMs?):
                    self.health = .partial("SOCKS 端口 \(ports.socks) 没响应")
                    self.appendLog("HTTP 能出去（\(httpMs) ms），但 SOCKS 端口 \(ports.socks) 没反应", isError: true)

                case (nil, nil):
                    self.health = .failed("流量没能从节点出去")
                    self.appendLog("自检失败：两个本地端口都出不去。多半是节点已失效，或者链接参数不对。", isError: true)
                }
            }
        }
    }

    // MARK: 停止

    func stop() {
        health = .unknown
        activePorts = nil
        guard process != nil else {
            state = .idle
            startedAt = nil
            return
        }
        state = .stopping
        terminateProcess()
    }

    private func terminateProcess() {
        guard let process else { return }
        if process.isRunning {
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.6) {
                if process.isRunning {
                    kill(pid, SIGKILL)
                }
            }
        }
    }

    // MARK: 日志

    private func ingest(_ data: Data, isError: Bool) {
        var text = String(data: data, encoding: .utf8)
        if text == nil {
            text = String(data: data, encoding: .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))))
        }
        guard let text, !text.isEmpty else { return }
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for line in lines {
                self.appendLog(line.trimmingCharacters(in: .whitespaces), isError: isError)
            }
        }
    }

    func appendLog(_ text: String, isError: Bool = false) {
        logs.append(ProxyLogLine(date: Date(), text: text, isError: isError))
        if logs.count > maxLogLines {
            logs.removeFirst(logs.count - maxLogLines)
        }
        ProxySessionLog.append(text, isError: isError)
    }

    func clearLogs() {
        logs.removeAll()
    }
}

/// 两个探测线程各写各的字段，用个盒子避开并发写 var 的告警
private final class ProbeBox: @unchecked Sendable {
    var socks: Int?
    var http: Int?
}
