import Foundation

// MARK: - 模型

struct ProxyEndpoint: Codable, Hashable, Sendable {
    var enabled: Bool = false
    var server: String = ""
    var port: Int = 0

    var description: String {
        enabled ? "\(server):\(port)" : "关闭"
    }
}

struct ServiceProxyState: Codable, Hashable, Identifiable, Sendable {
    var service: String
    var http: ProxyEndpoint = ProxyEndpoint()
    var https: ProxyEndpoint = ProxyEndpoint()
    var socks: ProxyEndpoint = ProxyEndpoint()
    var bypass: [String] = []

    var id: String { service }

    var anyEnabled: Bool { http.enabled || https.enabled || socks.enabled }
}

// MARK: - 系统代理

enum SystemProxy {
    private static let tool = "/usr/sbin/networksetup"

    /// 本机回环地址。某个代理设置只要是指向这里的端口，基本可以断定是我们自己写进去的
    private static let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1", "0.0.0.0", "localhost.localdomain"]

    /// 当前可用（未被禁用）的网络服务名
    static func services() -> [String] {
        let result = Shell.run(tool, ["-listallnetworkservices"], timeout: 10)
        guard result.ok else { return [] }
        return result.out
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") && !$0.hasPrefix("*") }
    }

    /// 读某个服务的代理配置
    static func read(service: String) -> ServiceProxyState {
        var state = ServiceProxyState(service: service)
        state.http = endpoint(service: service, flag: "-getwebproxy")
        state.https = endpoint(service: service, flag: "-getsecurewebproxy")
        state.socks = endpoint(service: service, flag: "-getsocksfirewallproxy")

        let bypass = Shell.run(tool, ["-getproxybypassdomains", service], timeout: 8)
        if bypass.ok {
            state.bypass = bypass.out
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("There aren't any") }
        }
        return state
    }

    private static func endpoint(service: String, flag: String) -> ProxyEndpoint {
        let result = Shell.run(tool, [flag, service], timeout: 8)
        var endpoint = ProxyEndpoint()
        guard result.ok else { return endpoint }
        for line in result.out.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "Enabled": endpoint.enabled = parts[1].lowercased() == "yes"
            case "Server": endpoint.server = parts[1]
            case "Port": endpoint.port = Int(parts[1]) ?? 0
            default: break
            }
        }
        return endpoint
    }

    // MARK: 区分"我们的代理"和用户自己的代理

    /// 这个端点是不是工具箱自己设的（开着，并且指向本机的代理端口）
    static func isOurs(_ endpoint: ProxyEndpoint, ourPorts: Set<Int>) -> Bool {
        guard endpoint.enabled, endpoint.port > 0 else { return false }
        return loopbackHosts.contains(endpoint.server.lowercased()) && ourPorts.contains(endpoint.port)
    }

    /// 把一个服务的状态里"我们自己的痕迹"抹掉，当作没开代理
    static func sanitize(_ state: ServiceProxyState, ourPorts: Set<Int>) -> ServiceProxyState {
        var clean = state
        if isOurs(clean.http, ourPorts: ourPorts) { clean.http = ProxyEndpoint() }
        if isOurs(clean.https, ourPorts: ourPorts) { clean.https = ProxyEndpoint() }
        if isOurs(clean.socks, ourPorts: ourPorts) { clean.socks = ProxyEndpoint() }
        return clean
    }

    static func sanitize(_ states: [ServiceProxyState], ourPorts: Set<Int>) -> [ServiceProxyState] {
        states.map { sanitize($0, ourPorts: ourPorts) }
    }

    /// 备份所有服务的当前代理设置，关闭时按这个还原。
    ///
    /// 快照前必须先把"指向本机端口"的残留抹掉，否则会把我们自己上一次留下的状态
    /// 误当成用户的原始设置存起来——之后"还原"就变成又把代理打开，表现出来就是
    /// 停止后系统代理关不掉。
    static func snapshot(ourPorts: Set<Int>) -> [ServiceProxyState] {
        services().map { sanitize(read(service: $0), ourPorts: ourPorts) }
    }

    /// 现在有哪些服务的代理是开着的、并且指向本机端口（= 上次没收拾干净）
    static func pointingAtUs(ourPorts: Set<Int>) -> [String] {
        services().filter { service in
            let state = read(service: service)
            return isOurs(state.http, ourPorts: ourPorts)
                || isOurs(state.https, ourPorts: ourPorts)
                || isOurs(state.socks, ourPorts: ourPorts)
        }
    }

    static func encode(_ states: [ServiceProxyState]) -> String {
        guard let data = try? JSONEncoder().encode(states) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func decode(_ text: String) -> [ServiceProxyState] {
        guard let data = text.data(using: .utf8),
              let states = try? JSONDecoder().decode([ServiceProxyState].self, from: data) else { return [] }
        return states
    }

    /// 把所有服务都指到本地代理
    @discardableResult
    static func enableAll(host: String = "127.0.0.1", httpPort: Int, socksPort: Int) -> [String] {
        var touched: [String] = []
        for service in services() {
            let ok = enable(service: service, host: host, httpPort: httpPort, socksPort: socksPort)
            if ok { touched.append(service) }
        }
        return touched
    }

    @discardableResult
    static func enable(service: String, host: String = "127.0.0.1", httpPort: Int, socksPort: Int) -> Bool {
        var ok = true

        ok = Shell.run(tool, ["-setwebproxy", service, host, "\(httpPort)"]).ok && ok
        ok = Shell.run(tool, ["-setwebproxystate", service, "on"]).ok && ok
        ok = Shell.run(tool, ["-setsecurewebproxy", service, host, "\(httpPort)"]).ok && ok
        ok = Shell.run(tool, ["-setsecurewebproxystate", service, "on"]).ok && ok
        ok = Shell.run(tool, ["-setsocksfirewallproxy", service, host, "\(socksPort)"]).ok && ok
        ok = Shell.run(tool, ["-setsocksfirewallproxystate", service, "on"]).ok && ok

        // 本地地址别绕进代理，否则本地服务会连不上
        var bypass = ["127.0.0.1", "localhost", "*.local", "169.254/16"]
        let existing = Shell.run(tool, ["-getproxybypassdomains", service], timeout: 8)
        if existing.ok {
            for line in existing.out.components(separatedBy: .newlines) {
                let item = line.trimmingCharacters(in: .whitespaces)
                if !item.isEmpty, !item.hasPrefix("There aren't any"), !bypass.contains(item) {
                    bypass.append(item)
                }
            }
        }
        Shell.run(tool, ["-setproxybypassdomains", service] + bypass)

        return ok
    }

    /// 关掉所有服务的代理
    @discardableResult
    static func disableAll() -> [String] {
        var touched: [String] = []
        for service in services() {
            if disable(service: service) { touched.append(service) }
        }
        return touched
    }

    @discardableResult
    static func disable(service: String) -> Bool {
        var ok = true
        ok = Shell.run(tool, ["-setwebproxystate", service, "off"]).ok && ok
        ok = Shell.run(tool, ["-setsecurewebproxystate", service, "off"]).ok && ok
        ok = Shell.run(tool, ["-setsocksfirewallproxystate", service, "off"]).ok && ok
        return ok
    }

    /// 按备份还原。
    ///
    /// 还原前先洗掉备份里"指向本机端口"的项（历史脏备份也一并兜住），
    /// 最后再扫一遍：还有哪个服务指着我们自己的端口，一律关掉——保证"停"是真的停。
    @discardableResult
    static func restore(_ states: [ServiceProxyState], ourPorts: Set<Int> = []) -> Bool {
        let targets = ourPorts.isEmpty ? states : sanitize(states, ourPorts: ourPorts)
        var ok = true
        guard !targets.isEmpty else {
            disableAll()
            return true
        }
        for state in targets {
            ok = restore(service: state.service, http: state.http, https: state.https, socks: state.socks, bypass: state.bypass) && ok
        }

        // 收尾扫一遍，兜住备份没覆盖到的服务
        if !ourPorts.isEmpty {
            for service in pointingAtUs(ourPorts: ourPorts) {
                ok = disable(service: service) && ok
            }
        }
        return ok
    }

    @discardableResult
    static func restore(service: String, http: ProxyEndpoint, https: ProxyEndpoint, socks: ProxyEndpoint, bypass: [String]) -> Bool {
        var ok = true

        if http.enabled, !http.server.isEmpty, http.port > 0 {
            ok = Shell.run(tool, ["-setwebproxy", service, http.server, "\(http.port)"]).ok && ok
            ok = Shell.run(tool, ["-setwebproxystate", service, "on"]).ok && ok
        } else {
            ok = Shell.run(tool, ["-setwebproxystate", service, "off"]).ok && ok
        }

        if https.enabled, !https.server.isEmpty, https.port > 0 {
            ok = Shell.run(tool, ["-setsecurewebproxy", service, https.server, "\(https.port)"]).ok && ok
            ok = Shell.run(tool, ["-setsecurewebproxystate", service, "on"]).ok && ok
        } else {
            ok = Shell.run(tool, ["-setsecurewebproxystate", service, "off"]).ok && ok
        }

        if socks.enabled, !socks.server.isEmpty, socks.port > 0 {
            ok = Shell.run(tool, ["-setsocksfirewallproxy", service, socks.server, "\(socks.port)"]).ok && ok
            ok = Shell.run(tool, ["-setsocksfirewallproxystate", service, "on"]).ok && ok
        } else {
            ok = Shell.run(tool, ["-setsocksfirewallproxystate", service, "off"]).ok && ok
        }

        if !bypass.isEmpty {
            Shell.run(tool, ["-setproxybypassdomains", service] + bypass)
        }

        return ok
    }

    /// 现在有没有代理是开着的
    static func currentSummary() -> (anyEnabled: Bool, text: String) {
        var lines: [String] = []
        var any = false
        for service in services() {
            let state = read(service: service)
            guard state.anyEnabled else { continue }
            any = true
            var parts: [String] = []
            if state.http.enabled { parts.append("HTTP \(state.http.description)") }
            if state.https.enabled { parts.append("HTTPS \(state.https.description)") }
            if state.socks.enabled { parts.append("SOCKS \(state.socks.description)") }
            lines.append("\(service)：\(parts.joined(separator: " · "))")
        }
        return (any, lines.joined(separator: "\n"))
    }
}
