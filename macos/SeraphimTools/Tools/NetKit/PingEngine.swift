import Foundation

/// ping / ping6 的封装。
///
/// 为什么直接调系统的 ping：macOS 上自己造 ICMP 要跟 socket 权限纠缠，而系统自带的 ping
/// 非 root 就能跑（用的是 datagram ICMP），稳定性、超时语义都是现成的。这里只负责拼参数、
/// 流式解析它的输出。
enum PingEngine {

    struct Launch {
        let executable: String
        let arguments: [String]

        var commandLine: String {
            ([executable] + arguments).map { argument in
                argument.contains(" ") ? "'\(argument)'" : argument
            }.joined(separator: " ")
        }
    }

    /// 非 root 跑 ping 时系统限制的最小发包间隔
    static let minimumInterval: Double = 0.2

    static func makeLaunch(_ options: PingOptions) -> Launch {
        let host = options.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let isV6 = options.family == .v6
        let executable = isV6 ? "/sbin/ping6" : "/sbin/ping"

        var arguments: [String] = ["-n"]
        if options.count > 0 {
            arguments += ["-c", String(max(1, min(options.count, 999)))]
        }
        arguments += ["-i", String(format: "%.2f", max(minimumInterval, min(options.interval, 30)))]
        arguments += ["-s", String(max(8, min(options.packetSize, 65_507)))]
        // ping6 没有 -W 这个开关，超时交给系统默认
        if !isV6 {
            arguments += ["-W", String(Int(max(0.1, min(options.waitTimeout, 30)) * 1000))]
        }
        arguments.append(host)

        return Launch(executable: executable, arguments: arguments)
    }

    /// 边 ping 边吐事件。持续模式（count = 0）就一直跑，直到调用方取消。
    static func run(_ options: PingOptions) -> AsyncStream<PingEvent> {
        AsyncStream { continuation in
            let launch = makeLaunch(options)
            let box = ProcessBox()

            let worker = Thread {
                guard !options.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continuation.yield(.failure("先填一个主机地址"))
                    continuation.finish()
                    return
                }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: launch.executable)
                process.arguments = launch.arguments

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                let parser = PingOutputParser()
                let lock = NSLock()
                var buffer = ""

                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    let text = String(decoding: data, as: UTF8.self)

                    lock.lock()
                    buffer += text
                    var lines: [String] = []
                    while let index = buffer.firstIndex(of: "\n") {
                        lines.append(String(buffer[buffer.startIndex..<index]))
                        buffer.removeSubrange(buffer.startIndex...index)
                    }
                    lock.unlock()

                    for line in lines {
                        for event in parser.consume(line: line) {
                            continuation.yield(event)
                        }
                    }
                }

                process.terminationHandler = { finished in
                    pipe.fileHandleForReading.readabilityHandler = nil

                    lock.lock()
                    let remainder = buffer
                    buffer = ""
                    lock.unlock()

                    if !remainder.isEmpty {
                        for event in parser.consume(line: remainder) {
                            continuation.yield(event)
                        }
                    }
                    if let final = parser.finish() {
                        continuation.yield(final)
                    }

                    if finished.terminationReason == .uncaughtSignal {
                        continuation.yield(.notice("已手动停止"))
                    }
                    continuation.finish()
                }

                continuation.yield(.started(command: launch.commandLine))

                do {
                    try process.run()
                    box.attach(process)
                } catch {
                    continuation.yield(.failure("起不了 ping 进程：\(error.localizedDescription)"))
                    continuation.finish()
                }
            }
            worker.stackSize = 512 * 1024
            worker.start()

            continuation.onTermination = { _ in box.terminate() }
        }
    }

    /// 让 AsyncStream 的终止回调能杀掉进程
    private final class ProcessBox: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?

        func attach(_ process: Process) {
            lock.lock()
            let alreadyCancelled = cancelled
            self.process = process
            lock.unlock()
            if alreadyCancelled { process.terminate() }
        }

        private var cancelled = false

        func terminate() {
            lock.lock()
            cancelled = true
            let running = process
            lock.unlock()
            if let running, running.isRunning {
                running.terminate()
            }
        }
    }
}

/// 逐行解析 ping 的输出。
///
/// 两个平台的输出格式不太一样（`ttl=` / `hlim=`、`time=x ms` 前面是冒号还是逗号），
/// 所以这里全用宽容匹配，能认出来就行。
final class PingOutputParser {
    private var summary: PingSummary?
    private var pendingLoss: (transmitted: Int, received: Int)?

    func consume(line rawLine: String) -> [PingEvent] {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return [] }

        if line.hasPrefix("PING6(") {
            // PING6(104=40+8+56 bytes) ::1 --> ::1
            guard let arrow = line.range(of: "-->") else { return [.notice(line)] }
            var source = String(line[line.startIndex..<arrow.lowerBound])
            if let close = source.firstIndex(of: ")") {
                source = String(source[source.index(after: close)...])
            }
            let sourceText = source.trimmingCharacters(in: .whitespaces)
            let destination = line[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
            return [.resolved(host: sourceText.isEmpty ? destination : sourceText, address: destination)]
        }

        if line.hasPrefix("PING ") {
            // PING example.com (93.184.216.34): 56 data bytes
            let body = line.dropFirst(5)
            var address: String?
            var host = String(body)
            if let open = body.firstIndex(of: "(") {
                host = String(body[body.startIndex..<open])
                if let close = body[open...].firstIndex(of: ")") {
                    let inside = String(body[body.index(after: open)..<close])
                    if !inside.contains("=") { address = inside }
                }
            } else if let colon = body.firstIndex(of: ":") {
                host = String(body[body.startIndex..<colon])
            }
            let hostText = host.trimmingCharacters(in: .whitespaces)
            guard !hostText.isEmpty else { return [.notice(line)] }
            return [.resolved(host: hostText, address: address ?? hostText)]
        }

        if line.contains("packets transmitted") {
            let numbers = matches(pattern: #"(\d+)\s+packets transmitted,\s+(\d+)\s+(?:packets )?received"#, in: line)
            if numbers.count >= 2, let sent = Int(numbers[0]), let got = Int(numbers[1]) {
                pendingLoss = (sent, got)
            }
            let loss = matches(pattern: #"([\d.]+)%\s+packet loss"#, in: line).first.flatMap(Double.init) ?? 0
            var current = summary ?? PingSummary()
            current.transmitted = pendingLoss?.transmitted ?? current.transmitted
            current.received = pendingLoss?.received ?? current.received
            current.lossPercent = loss
            summary = current
            return [.notice(line)]
        }

        if line.contains("round-trip") {
            // round-trip min/avg/max/stddev = 0.064/0.098/0.131/0.034 ms
            var current = summary ?? PingSummary()
            let values = matches(pattern: #"=\s*([\d.]+)/([\d.]+)/([\d.]+)/([\d.]+)"#, in: line)
            if values.count == 4 {
                current.minRTT = Double(values[0])
                current.avgRTT = Double(values[1])
                current.maxRTT = Double(values[2])
                current.stddev = Double(values[3])
            }
            summary = current
            return [.notice(line)]
        }

        if line.hasPrefix("---") && line.hasSuffix("---") {
            return []
        }

        if line.hasPrefix("ping:") || line.hasPrefix("ping6:") {
            let message = line.replacingOccurrences(of: #"^ping6?:\s*"#, with: "", options: .regularExpression)
            return [.failure(message)]
        }

        if line.contains("Request timeout for icmp_seq") {
            let sequence = matches(pattern: #"icmp_seq[= ](\d+)"#, in: line).first.flatMap(Int.init) ?? 0
            return [.sample(PingSample(sequence: sequence, bytes: 0, time: 0, ttl: nil, timeout: true))]
        }

        if line.contains("icmp_seq"), line.contains("time=") {
            let sequence = matches(pattern: #"icmp_seq[= ](\d+)"#, in: line).first.flatMap(Int.init) ?? 0
            let bytes = matches(pattern: #"^(\d+)\s+bytes from"#, in: line).first.flatMap(Int.init) ?? 0
            let time = matches(pattern: #"time[=]([\d.]+)"#, in: line).first.flatMap(Double.init) ?? 0
            let ttl = matches(pattern: #"(?:ttl|hlim)[=](\d+)"#, in: line).first.flatMap(Int.init)
            return [.sample(PingSample(sequence: sequence, bytes: bytes, time: time, ttl: ttl, timeout: false))]
        }

        return [.notice(line)]
    }

    /// 进程结束时兜底吐出汇总
    func finish() -> PingEvent? {
        guard let summary else { return nil }
        return .summary(summary)
    }

    private func matches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return [] }
        var results: [String] = []
        for index in 1..<match.numberOfRanges {
            guard let capture = Range(match.range(at: index), in: text) else {
                results.append("")
                continue
            }
            results.append(String(text[capture]))
        }
        return results
    }
}
