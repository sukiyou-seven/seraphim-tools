import Darwin
import Foundation

/// TCP 端口探测。
///
/// 实现要点：socket 设成非阻塞再 `connect`，未立即成功时用 `poll` 等可写事件。
/// 直接阻塞 connect 是等不到可靠超时的——那是坑，别踩。
enum PortScanner {

    // MARK: - 单个端口

    static func probe(host: String, port: UInt16, timeout: TimeInterval) async -> PortScanResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: blockingProbe(host: host, port: port, timeout: timeout))
            }
        }
    }

    private static func blockingProbe(host: String, port: UInt16, timeout: TimeInterval) -> PortScanResult {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var info: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &info)
        guard status == 0, let address = info else {
            let reason = String(cString: gai_strerror(status))
            return PortScanResult(port: port, state: .failed, latency: nil, note: "地址解析失败：\(reason)")
        }
        defer { freeaddrinfo(address) }

        let entry = address.pointee
        let fd = socket(entry.ai_family, entry.ai_socktype, entry.ai_protocol)
        guard fd >= 0 else {
            return PortScanResult(port: port, state: .failed, latency: nil, note: "创建套接字失败")
        }
        defer { close(fd) }

        // 关掉 SIGPIPE，避免对端半开连接把进程带走
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        let start = Date()
        let connectResult = connect(fd, entry.ai_addr, entry.ai_addrlen)

        if connectResult == 0 {
            return PortScanResult(port: port, state: .open, latency: elapsed(since: start), note: nil)
        }

        if errno != EINPROGRESS {
            if errno == ECONNREFUSED {
                return PortScanResult(port: port, state: .closed, latency: nil, note: "连接被拒绝")
            }
            if errno == EHOSTUNREACH || errno == ENETUNREACH {
                return PortScanResult(port: port, state: .filtered, latency: nil, note: "主机不可达")
            }
            return PortScanResult(port: port, state: .failed, latency: nil, note: errnoText(errno))
        }

        var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let milliseconds = Int32(max(1, min(timeout * 1000, 60_000)))
        let pollResult = poll(&descriptor, 1, milliseconds)

        if pollResult == 0 {
            return PortScanResult(port: port, state: .filtered, latency: nil, note: "\(Int(timeout * 1000))ms 内无响应")
        }
        if pollResult < 0 {
            return PortScanResult(port: port, state: .failed, latency: nil, note: errnoText(errno))
        }

        var socketError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &length)

        if socketError == 0 {
            return PortScanResult(port: port, state: .open, latency: elapsed(since: start), note: nil)
        }
        if socketError == ECONNREFUSED {
            return PortScanResult(port: port, state: .closed, latency: nil, note: "连接被拒绝")
        }
        if socketError == ETIMEDOUT {
            return PortScanResult(port: port, state: .filtered, latency: nil, note: "握手超时")
        }
        return PortScanResult(port: port, state: .failed, latency: nil, note: errnoText(socketError))
    }

    private static func elapsed(since start: Date) -> Double {
        max(0.01, Date().timeIntervalSince(start) * 1000)
    }

    private static func errnoText(_ code: Int32) -> String {
        String(cString: strerror(code))
    }

    // MARK: - 批量扫描

    /// 边扫边出结果。并发上限用 `concurrency` 控制，避免把对方当 DDoS 打。
    static func scan(
        host: String,
        ports: [UInt16],
        timeout: TimeInterval,
        concurrency: Int
    ) -> AsyncStream<PortScanResult> {
        AsyncStream { continuation in
            let worker = Task.detached(priority: .userInitiated) {
                let limit = max(1, min(concurrency, max(1, ports.count)))
                await withTaskGroup(of: PortScanResult.self) { group in
                    var next = 0
                    while next < limit && next < ports.count {
                        let port = ports[next]
                        next += 1
                        group.addTask { await probe(host: host, port: port, timeout: timeout) }
                    }

                    while let result = await group.next() {
                        if Task.isCancelled {
                            group.cancelAll()
                            break
                        }
                        continuation.yield(result)
                        if next < ports.count {
                            let port = ports[next]
                            next += 1
                            group.addTask { await probe(host: host, port: port, timeout: timeout) }
                        }
                    }
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    /// 把 "80,443,8000-8010" 这样的写法展开成端口列表
    static func expand(_ text: String) -> (ports: [UInt16], errors: [String]) {
        var ports: [UInt16] = []
        var errors: [String] = []
        let tokens = text
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "、", with: ",")
            .replacingOccurrences(of: " ", with: ",")
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for token in tokens {
            if token.contains("-") {
                let bounds = token.split(separator: "-", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard bounds.count == 2,
                      let lower = UInt16(bounds[0]),
                      let upper = UInt16(bounds[1]) else {
                    errors.append("「\(token)」不是合法的端口范围")
                    continue
                }
                let low = min(lower, upper)
                let high = max(lower, upper)
                if high - low > 4096 {
                    errors.append("范围「\(token)」太大了，一次最多 4096 个端口")
                    continue
                }
                ports.append(contentsOf: low...high)
            } else if let port = UInt16(token), port > 0 {
                ports.append(port)
            } else {
                errors.append("「\(token)」不是合法的端口号")
            }
        }

        var seen = Set<UInt16>()
        let unique = ports.filter { seen.insert($0).inserted }
        return (unique, errors)
    }

    // MARK: - 本机信息

    struct LocalAddress: Identifiable, Sendable {
        var id: String { "\(interface)-\(address)" }
        let interface: String
        let address: String
        let family: String
    }

    /// 本机网卡地址
    static func localAddresses() -> [LocalAddress] {
        var results: [LocalAddress] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return results }
        defer { freeifaddrs(head) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            guard let addr = current.pointee.ifa_addr else { continue }
            let family = addr.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }

            let name = String(cString: current.pointee.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = family == UInt8(AF_INET)
                ? socklen_t(MemoryLayout<sockaddr_in>.size)
                : socklen_t(MemoryLayout<sockaddr_in6>.size)
            guard getnameinfo(addr, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }

            var address = String(cString: host)
            if let percent = address.firstIndex(of: "%") {
                address = String(address[..<percent])
            }
            if family == UInt8(AF_INET6), address.hasPrefix("fe80") { continue }  // 链路本地没意义

            results.append(LocalAddress(
                interface: name,
                address: address,
                family: family == UInt8(AF_INET) ? "IPv4" : "IPv6"
            ))
        }
        return results
    }

    struct LocalListener: Identifiable, Sendable {
        var id: String { "\(pid)-\(port)-\(address)" }
        let pid: Int
        let command: String
        let address: String
        let port: UInt16
    }

    /// 本机正在 LISTEN 的 TCP 端口。借系统自带的 lsof，解析它的 `-F` 机器可读输出。
    static func localListeners() async -> [LocalListener] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runLsof())
            }
        }
    }

    private static func runLsof() -> [LocalListener] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var listeners: [LocalListener] = []
        var pid = 0
        var command = ""

        for line in output.split(separator: "\n") {
            guard let marker = line.first else { continue }
            let value = String(line.dropFirst())
            switch marker {
            case "p":
                pid = Int(value) ?? 0
                command = ""
            case "c":
                command = value
            case "n":
                // 形如 *:8080 / 127.0.0.1:5432 / [::1]:9000
                guard let colon = value.lastIndex(of: ":") else { continue }
                let portText = String(value[value.index(after: colon)...])
                guard let port = UInt16(portText) else { continue }
                var address = String(value[..<colon])
                if address == "*" { address = "所有网卡" }
                listeners.append(LocalListener(pid: pid, command: command, address: address, port: port))
            default:
                break
            }
        }

        return listeners.sorted { $0.port < $1.port }
    }

    // MARK: - 结束进程

    struct KillOutcome: Sendable {
        let pid: Int
        let command: String
        let ok: Bool
        let message: String
    }

    /// 结束监听端口的进程：先 SIGTERM（留 2 秒善后窗口），不退自动升级 SIGKILL。
    /// 防呆：PID 0 是内核、1 是 launchd，谁杀谁后悔；工具箱自己的进程也不碰。
    static func killProcess(pid: Int, command: String) async -> KillOutcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: performKill(pid: pid, command: command))
            }
        }
    }

    private static func performKill(pid: Int, command: String) -> KillOutcome {
        // kill(pid, 0)：不真发信号，只探进程存不存在、能不能发
        func alive() -> Bool { kill(pid_t(pid), 0) == 0 }

        guard pid > 1 else {
            return KillOutcome(pid: pid, command: command, ok: false,
                               message: "PID \(pid) 不在可杀范围（0 是内核，1 是 launchd）")
        }
        guard pid != ProcessInfo.processInfo.processIdentifier else {
            return KillOutcome(pid: pid, command: command, ok: false,
                               message: "那是工具箱自己的进程，不杀")
        }
        guard alive() else {
            return KillOutcome(pid: pid, command: command, ok: false,
                               message: "进程已经不在了（可能刚好自己退了）")
        }

        guard kill(pid_t(pid), SIGTERM) == 0 else {
            if errno == EPERM {
                return KillOutcome(pid: pid, command: command, ok: false,
                                   message: "没有权限：进程属于其他用户（比如 root），去终端 sudo 处理")
            }
            return KillOutcome(pid: pid, command: command, ok: false,
                               message: "发送 SIGTERM 失败：\(String(cString: strerror(errno)))")
        }

        // 善后窗口 2 秒，每 100ms 探一次，给进程时间保存数据退场
        for _ in 0..<20 {
            usleep(100_000)
            if !alive() {
                return KillOutcome(pid: pid, command: command, ok: true,
                                   message: "已结束「\(command)」（SIGTERM）")
            }
        }

        guard kill(pid_t(pid), SIGKILL) == 0 else {
            return KillOutcome(pid: pid, command: command, ok: false,
                               message: "进程没理 SIGTERM，SIGKILL 也发失败了")
        }
        for _ in 0..<10 {
            usleep(100_000)
            if !alive() {
                return KillOutcome(pid: pid, command: command, ok: true,
                                   message: "已强杀「\(command)」（SIGKILL，它没理 SIGTERM）")
            }
        }
        return KillOutcome(pid: pid, command: command, ok: false,
                           message: "SIGKILL 都发了还活着——多半是僵尸进程，等它父进程收尸")
    }
}
