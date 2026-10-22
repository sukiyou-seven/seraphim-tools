import Foundation

/// DNS 查询。
///
/// 底层用系统的 dig：它把递归、超时、EDNS、DNSSEC、TCP 回退这些细节都处理干净了，
/// 自己从零写 resolver 只会更脆。这里负责拼参数 + 把 dig 的结构化输出解析成表格数据。
enum DNSEngine {

    struct Query: Sendable {
        var name: String = ""
        var type: DNSRecordType = .a
        var server: String = ""        // 空 = 用系统默认
        var trace = false
        var useTCP = false
        var checkDNSSEC = false
        var timeout: Double = 5

        static let initial = Query()
    }

    // MARK: - 执行

    static func lookup(_ query: Query) async -> DNSResult {
        let started = Date()
        let target = query.name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !target.isEmpty else {
            return emptyResult(query: query, failure: "先填一个域名或 IP")
        }

        let arguments = makeArguments(query)
        let outcome = await runDig(arguments: arguments)
        let elapsed = Date().timeIntervalSince(started) * 1000

        if let failure = outcome.launchError {
            return emptyResult(query: query, failure: "起不了 dig 进程：\(failure)", elapsed: elapsed)
        }
        return parse(output: outcome.output, query: query, elapsed: elapsed)
    }

    static func makeArguments(_ query: Query) -> [String] {
        let target = query.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var arguments = ["+time=\(max(1, Int(query.timeout.rounded())))", "+tries=1"]

        if !query.server.trimmingCharacters(in: .whitespaces).isEmpty {
            var server = query.server.trimmingCharacters(in: .whitespaces)
            if !server.hasPrefix("@") { server = "@" + server }
            arguments.append(server)
        }
        if query.trace {
            arguments.append("+trace")
        }
        if query.useTCP {
            arguments.append("+tcp")
        }
        if query.checkDNSSEC {
            arguments.append("+dnssec")
        }

        // 反向解析走 dig -x
        if query.type == .ptr, isIPAddress(target) {
            arguments.append("-x")
            arguments.append(target)
        } else {
            arguments.append(target)
            arguments.append(query.type.rawValue)
        }
        return arguments
    }

    private struct DigOutcome {
        var output: String = ""
        var launchError: String?
    }

    private static func runDig(arguments: [String]) async -> DigOutcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/dig")
                process.arguments = arguments

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: DigOutcome(launchError: error.localizedDescription))
                    return
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                continuation.resume(returning: DigOutcome(output: text))
            }
        }
    }

    // MARK: - 解析

    static func parse(output: String, query: Query, elapsed: Double) -> DNSResult {
        let lines = output.components(separatedBy: "\n")

        var status = "UNKNOWN"
        var flags = ""
        var server = ""
        var queryTime: Int?
        var answers: [DNSRecord] = []
        var authority: [DNSRecord] = []
        var additional: [DNSRecord] = []
        var failure: String?
        var nextID = 0

        enum Section {
            case none
            case answer
            case authority
            case additional
        }
        var section: Section = .none
        var lastRecordName: String?

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty { continue }

            if line.contains("->>HEADER<<-") {
                if let found = capture(#"status:\s*([A-Z]+)"#, in: line) { status = found }
                continue
            }
            // dig 把 flags 单独放在 header 的下一行
            if line.hasPrefix(";; flags:") {
                if let found = capture(#"flags:\s*([^;]+)"#, in: line) {
                    flags = found.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ",")))
                }
                continue
            }
            if line.hasPrefix(";; SERVER:") {
                var text = line.replacingOccurrences(of: ";; SERVER:", with: "")
                    .trimmingCharacters(in: .whitespaces)

                // 末尾的 (UDP) / (TCP) 是传输方式，单独摘出来显示
                var transport = ""
                if let open = text.lastIndex(of: "("), let close = text.lastIndex(of: ")"), open < close {
                    let inside = String(text[text.index(after: open)..<close])
                    if ["UDP", "TCP", "udp", "tcp"].contains(inside) {
                        transport = inside
                        text = String(text[text.startIndex..<open]).trimmingCharacters(in: .whitespaces)
                    }
                }

                // dig 会写成 8.8.8.8#53(8.8.8.8)，括号里跟前面重复，去掉让界面干净点
                if let hash = text.firstIndex(of: "#") {
                    let host = String(text[text.startIndex..<hash])
                    var port = String(text[text.index(after: hash)...])
                    if let open = port.firstIndex(of: "("), let close = port.lastIndex(of: ")"), open < close {
                        let inside = String(port[port.index(after: open)..<close])
                        if inside == host {
                            port = String(port[port.startIndex..<open])
                        }
                    }
                    text = "\(host)#\(port)"
                }

                server = transport.isEmpty ? text : "\(text) (\(transport))"
                continue
            }
            if line.hasPrefix(";; Query time:") {
                queryTime = capture(#"(\d+)\s*msec"#, in: line).flatMap(Int.init)
                continue
            }
            if line.hasPrefix(";; ANSWER SECTION") { section = .answer; lastRecordName = nil; continue }
            if line.hasPrefix(";; AUTHORITY SECTION") { section = .authority; lastRecordName = nil; continue }
            if line.hasPrefix(";; ADDITIONAL SECTION") { section = .additional; lastRecordName = nil; continue }
            if line.hasPrefix(";; OPT PSEUDOSECTION") { section = .none; continue }
            if line.hasPrefix(";; QUESTION SECTION") { section = .none; continue }

            if line.contains("connection timed out") || line.contains("no servers could be reached") {
                failure = "连不上 DNS 服务器：\(query.server.isEmpty ? "系统默认" : query.server) 没响应"
                continue
            }
            if line.contains("communications error to") {
                failure = line.replacingOccurrences(of: ";; ", with: "")
                continue
            }
            if line.hasPrefix(";; Warning:") {
                if failure == nil { failure = line.replacingOccurrences(of: ";; Warning: ", with: "") }
                continue
            }

            if line.hasPrefix(";") || line.hasPrefix(";;") {
                continue
            }

            guard section != .none else { continue }

            guard let record = parseRecord(line, id: nextID, fallbackName: lastRecordName) else { continue }
            nextID += 1
            lastRecordName = record.name
            switch section {
            case .answer: answers.append(record)
            case .authority: authority.append(record)
            case .additional: additional.append(record)
            case .none: break
            }
        }

        if answers.isEmpty, authority.isEmpty, additional.isEmpty, failure == nil {
            if status.uppercased() == "NXDOMAIN" {
                failure = nil   // NXDOMAIN 是有效答案：域名不存在
            } else if status.uppercased() == "SERVFAIL" {
                failure = "服务器返回 SERVFAIL：上游解析失败，或者被 DNSSEC 拦了"
            } else if status.uppercased() == "REFUSED" {
                failure = "服务器 REFUSED：它拒绝为这个查询服务（很多公共 DNS 不接受 ANY 查询）"
            } else {
                failure = "没有解析到任何记录"
            }
        }

        return DNSResult(
            query: query.name.trimmingCharacters(in: .whitespacesAndNewlines),
            type: query.type,
            server: server.isEmpty ? (query.server.isEmpty ? "系统默认" : query.server) : server,
            status: status,
            flags: flags,
            queryTime: queryTime,
            answers: answers,
            authority: authority,
            additional: additional,
            raw: output,
            elapsed: elapsed,
            failure: failure,
            isTrace: query.trace
        )
    }

    private static func parseRecord(_ line: String, id: Int, fallbackName: String?) -> DNSRecord? {
        // 形如：example.com.  3600  IN  A  93.184.216.34
        let pattern = #"^(\S+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(.+)$"#
        if let groups = captures(pattern, in: line), groups.count == 5 {
            let name = groups[0]
            let ttl = Int(groups[1])
            let recordClass = groups[2]
            let type = groups[3]
            var value = groups[4].trimmingCharacters(in: .whitespaces)

            // DNSSEC 的 RRSIG 之类太长，压一压
            if type == "RRSIG", value.count > 120 {
                value = String(value.prefix(120)) + " …"
            }
            return DNSRecord(id: id, name: name, ttl: ttl, recordClass: recordClass, type: type, value: value)
        }

        // 续行（TXT 长记录被 dig 折行时没有名字和 TTL）
        if let fallbackName, !line.hasPrefix(";") {
            return DNSRecord(id: id, name: fallbackName, ttl: nil, recordClass: "IN", type: "TXT", value: line)
        }
        return nil
    }

    private static func emptyResult(query: Query, failure: String, elapsed: Double = 0) -> DNSResult {
        DNSResult(
            query: query.name,
            type: query.type,
            server: query.server.isEmpty ? "系统默认" : query.server,
            status: "—",
            flags: "",
            queryTime: nil,
            answers: [],
            authority: [],
            additional: [],
            raw: "",
            elapsed: elapsed,
            failure: failure,
            isTrace: query.trace
        )
    }

    // MARK: - 本机 DNS 配置

    static func localConfig() -> LocalDNSConfig {
        var resolvers: [DNSResolverInfo] = []
        var searchDomains: [String] = []

        if let text = runAndCapture("/usr/sbin/scutil", ["--dns"]) {
            var current: DNSResolverInfo?
            for rawLine in text.components(separatedBy: "\n") {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("resolver #") {
                    if let current { resolvers.append(current) }
                    let number = Int(line.replacingOccurrences(of: "resolver #", with: "")) ?? (resolvers.count + 1)
                    current = DNSResolverInfo(id: number, servers: [], domains: [], interface: nil, flags: nil)
                    continue
                }
                guard current != nil else { continue }
                if line.hasPrefix("nameserver["), let value = value(after: ":", in: line) {
                    current?.servers.append(value)
                } else if line.hasPrefix("domain ") || line.hasPrefix("domain:"), let value = value(after: ":", in: line) {
                    current?.domains.append(value)
                } else if line.hasPrefix("search domain["), let value = value(after: ":", in: line) {
                    if !searchDomains.contains(value) { searchDomains.append(value) }
                } else if line.hasPrefix("if_index") {
                    if let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")"), open < close {
                        current?.interface = String(line[line.index(after: open)..<close])
                    }
                } else if line.hasPrefix("flags") , current?.flags == nil {
                    current?.flags = value(after: ":", in: line)
                }
            }
            if let current { resolvers.append(current) }
        }

        // /etc/hosts：调本地开发环境时最常踩的就是它
        var hosts: [DNSHostEntry] = []
        if let text = try? String(contentsOfFile: "/etc/hosts", encoding: .utf8) {
            for rawLine in text.components(separatedBy: "\n") {
                var line = rawLine
                if let hash = line.firstIndex(of: "#") { line = String(line[..<hash]) }
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
                guard parts.count >= 2, isIPAddress(parts[0]) else { continue }
                hosts.append(DNSHostEntry(ip: parts[0], names: Array(parts.dropFirst())))
            }
        }

        return LocalDNSConfig(resolvers: resolvers, searchDomains: searchDomains, hosts: hosts)
    }

    private static func runAndCapture(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    private static func value(after marker: String, in line: String) -> String? {
        guard let range = line.range(of: marker, options: .backwards) else { return nil }
        let value = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    // MARK: - 小工具

    static func isIPAddress(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.contains(":") {
            return trimmed.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF:.").contains($0) }
        }
        let parts = trimmed.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let value = Int(part), (0...255).contains(value) else { return false }
            return String(value) == part || part.count > 1
        }
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        captures(pattern, in: text)?.first
    }

    private static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        var results: [String] = []
        for index in 1..<match.numberOfRanges {
            guard let captureRange = Range(match.range(at: index), in: text) else {
                results.append("")
                continue
            }
            results.append(String(text[captureRange]))
        }
        return results.isEmpty ? nil : results
    }
}
