import Combine
import Darwin
import Foundation

/// 一个"够用的" Telnet 客户端。
///
/// - 连接用非阻塞 socket + poll，超时可控（阻塞 connect 等不到可靠超时，那是坑）
/// - 服务端发 IAC 选项协商时按规矩回绝（WILL→DONT、DO→WONT），不装死
/// - 字节流按 UTF-8 解，解不动就退到 GB18030（国内老服务端/交换机的 banner 常是这个）
/// - 屏幕上的 ANSI 颜色之类的控制序列会被清掉，只留人能看的字符
///
/// 状态更新统一走 `onMain`，socket 读写只在 `queue` 上跑，两边不打架。
final class TelnetSession: ObservableObject {

    @Published private(set) var state: TelnetState = .idle
    @Published private(set) var lines: [TelnetLine] = []
    @Published private(set) var bytesIn = 0
    @Published private(set) var bytesOut = 0
    @Published private(set) var handshake: Double?
    @Published private(set) var peer: String = ""

    private var fd: Int32 = -1
    private var readSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.seraphim.tools.telnet")
    private let decoder = TelnetTextDecoder()
    private let negotiator = TelnetNegotiator()
    private var negotiatedCount = 0
    private var pendingTail = ""
    private var hasLiveLine = false
    private let maxLines = 3_000

    var isConnected: Bool { state == .connected }
    var isBusy: Bool { state == .connecting }

    deinit {
        readSource?.cancel()
        if fd >= 0 { close(fd) }
    }

    // MARK: - 连接

    func connect(host: String, port: UInt16, timeout: Double) {
        disconnect(announce: false)
        let target = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            state = .failed("先填一个主机地址")
            return
        }

        reset()
        state = .connecting
        append(.system, "正在连接 \(target):\(port) …")

        queue.async { [weak self] in
            let outcome = TelnetSocket.connect(host: target, port: port, timeout: timeout)
            self?.onMain { [weak self] in
                guard let self else { return }
                switch outcome {
                case .success(let connection):
                    self.fd = connection.fd
                    self.peer = connection.address
                    self.handshake = connection.latency
                    self.state = .connected
                    self.append(.system, String(format: "已连接 %@:%d（握手 %.1f ms）", connection.address, port, connection.latency))
                    self.startReading(fd: connection.fd)
                case .failure(let failure):
                    self.state = .failed(failure.message)
                    self.append(.error, failure.message)
                }
            }
        }
    }

    // MARK: - 发送

    func send(_ text: String, appendNewline: Bool = true) {
        guard state == .connected, fd >= 0 else { return }
        let payload = text + (appendNewline ? "\r\n" : "")
        guard let data = payload.data(using: .utf8) else { return }

        append(.outgoing, text.isEmpty ? "⏎" : text)
        let descriptor = fd

        queue.async { [weak self] in
            var offset = 0
            var idleRounds = 0
            while offset < data.count && idleRounds < 200 {
                let written = data.withUnsafeBytes { raw -> Int in
                    guard let base = raw.baseAddress else { return -1 }
                    return write(descriptor, base.advanced(by: offset), data.count - offset)
                }
                if written > 0 {
                    offset += written
                    idleRounds = 0
                    continue
                }
                if written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    idleRounds += 1
                    usleep(5_000)
                    continue
                }
                let message = String(cString: strerror(errno))
                self?.onMain { [weak self] in
                    self?.append(.error, "发送失败：\(message)")
                }
                return
            }
            let sent = offset
            self?.onMain { [weak self] in
                self?.bytesOut += sent
            }
        }
    }

    func disconnect(announce: Bool = true) {
        readSource?.cancel()
        readSource = nil
        if fd >= 0 {
            close(fd)
            fd = -1
        }
        if announce, state == .connected || state == .connecting {
            append(.system, "已断开连接")
        }
        if state != .idle {
            state = .closed
        }
    }

    func reset() {
        lines.removeAll()
        pendingTail = ""
        hasLiveLine = false
        bytesIn = 0
        bytesOut = 0
        handshake = nil
        peer = ""
        negotiatedCount = 0
        decoder.reset()
        negotiator.reset()
    }

    func clearScreen() {
        lines.removeAll()
        pendingTail = ""
        hasLiveLine = false
        append(.system, "已清屏")
    }

    // MARK: - 读取

    private func startReading(fd descriptor: Int32) {
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in
            self?.pump(descriptor: descriptor)
        }
        source.resume()
        readSource = source
    }

    /// 只在 `queue` 上调用：读字节 → 协商 → 解码 → 回主线程更新界面
    private func pump(descriptor: Int32) {
        var buffer = [UInt8](repeating: 0, count: 32_768)
        let count = read(descriptor, &buffer, buffer.count)

        if count == 0 {
            onMain { [weak self] in self?.handleRemoteClose() }
            return
        }
        if count < 0 {
            if errno == EAGAIN || errno == EWOULDBLOCK { return }
            let message = String(cString: strerror(errno))
            onMain { [weak self] in
                self?.append(.error, "读取出错：\(message)")
                self?.handleRemoteClose()
            }
            return
        }

        let chunk = Data(buffer[0..<count])
        let filtered = negotiator.process(chunk)

        if !filtered.replies.isEmpty {
            let replies = filtered.replies
            replies.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                _ = write(descriptor, base, replies.count)
            }
        }

        let text = TelnetTextSanitizer.clean(decoder.feed(filtered.payload))
        let events = filtered.events
        let received = count

        onMain { [weak self] in
            guard let self else { return }
            self.bytesIn += received
            for event in events where self.negotiatedCount < 40 {
                self.negotiatedCount += 1
                self.append(.system, event)
            }
            self.ingest(text: text)
        }
    }

    private func handleRemoteClose() {
        guard state == .connected || state == .connecting else { return }
        if !pendingTail.isEmpty {
            ingest(text: "\n")
        }
        append(.system, "服务端关闭了连接")
        readSource?.cancel()
        readSource = nil
        if fd >= 0 {
            close(fd)
            fd = -1
        }
        state = .closed
    }

    // MARK: - 行处理

    /// 把新到的文本切成行。最后一段没遇到换行就先当作"正在输入的一行"，
    /// 下批数据到来时替换掉——这样进度条、提示符不会一行行堆满屏幕。
    private func ingest(text: String) {
        guard !text.isEmpty else { return }
        let combined = pendingTail + text

        if hasLiveLine, !lines.isEmpty {
            lines.removeLast()
            hasLiveLine = false
        }

        let endsWithNewline = combined.hasSuffix("\n")
        var components = combined.components(separatedBy: "\n")
        if endsWithNewline, components.last?.isEmpty == true {
            components.removeLast()
        }

        if endsWithNewline {
            pendingTail = ""
        } else {
            pendingTail = components.last ?? ""
            components.removeLast()
        }

        for component in components {
            appendRaw(.incoming, component)
        }

        if !pendingTail.isEmpty {
            lines.append(TelnetLine(kind: .incoming, text: pendingTail, timestamp: Date()))
            hasLiveLine = true
            trimIfNeeded()
        }
    }

    private func append(_ kind: TelnetLine.Kind, _ text: String) {
        appendRaw(kind, text)
    }

    private func appendRaw(_ kind: TelnetLine.Kind, _ text: String) {
        lines.append(TelnetLine(kind: kind, text: text, timestamp: Date()))
        trimIfNeeded()
    }

    private func trimIfNeeded() {
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}

// MARK: - 底层连接

enum TelnetSocket {
    struct Failure: Error {
        let message: String
    }

    struct Connection {
        let fd: Int32
        let address: String
        let latency: Double
    }

    /// 非阻塞 connect + poll 等可写事件
    static func connect(host: String, port: UInt16, timeout: TimeInterval) -> Result<Connection, Failure> {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var info: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &info)
        guard status == 0, let head = info else {
            return .failure(Failure(message: "地址解析失败：\(String(cString: gai_strerror(status)))"))
        }
        defer { freeaddrinfo(head) }

        var lastError = "连接失败"
        var pointer: UnsafeMutablePointer<addrinfo>? = head

        while let current = pointer {
            defer { pointer = current.pointee.ai_next }
            let entry = current.pointee
            let descriptor = socket(entry.ai_family, entry.ai_socktype, entry.ai_protocol)
            if descriptor < 0 {
                lastError = "创建套接字失败：\(String(cString: strerror(errno)))"
                continue
            }

            var on: Int32 = 1
            setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

            let flags = fcntl(descriptor, F_GETFL, 0)
            _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)

            let started = Date()
            let result = Darwin.connect(descriptor, entry.ai_addr, entry.ai_addrlen)
            var connected = result == 0
            var failure: String?

            if !connected {
                if errno == EINPROGRESS {
                    var descriptorPoll = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
                    let milliseconds = Int32(max(100, min(timeout * 1000, 60_000)))
                    let pollResult = poll(&descriptorPoll, 1, milliseconds)
                    if pollResult == 0 {
                        failure = "连接超时（\(Int(timeout * 1000)) ms 内无响应）"
                    } else if pollResult < 0 {
                        failure = "poll 出错：\(String(cString: strerror(errno)))"
                    } else {
                        var socketError: Int32 = 0
                        var length = socklen_t(MemoryLayout<Int32>.size)
                        getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &socketError, &length)
                        if socketError == 0 {
                            connected = true
                        } else if socketError == ECONNREFUSED {
                            failure = "连接被拒绝（端口没开或服务没起）"
                        } else {
                            failure = String(cString: strerror(socketError))
                        }
                    }
                } else if errno == ECONNREFUSED {
                    failure = "连接被拒绝（端口没开或服务没起）"
                } else {
                    failure = String(cString: strerror(errno))
                }
            }

            if connected {
                let latency = max(0.01, Date().timeIntervalSince(started) * 1000)
                return .success(Connection(fd: descriptor, address: numericAddress(entry: entry), latency: latency))
            }

            close(descriptor)
            if let failure { lastError = failure }
        }

        return .failure(Failure(message: lastError))
    }

    private static func numericAddress(entry: addrinfo) -> String {
        guard let address = entry.ai_addr else { return "未知地址" }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let length = entry.ai_family == AF_INET
            ? socklen_t(MemoryLayout<sockaddr_in>.size)
            : socklen_t(MemoryLayout<sockaddr_in6>.size)
        guard getnameinfo(address, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
            return "未知地址"
        }
        return String(cString: host)
    }
}

// MARK: - telnet 选项协商

/// 处理 IAC（0xFF）序列：剥掉协议字节，同时礼貌地回绝服务端的选项请求。
final class TelnetNegotiator {
    private var inSubnegotiation = false
    private var subnegotiationBytes = 0

    struct Result {
        var payload: Data
        var replies: Data
        var events: [String]
    }

    func reset() {
        inSubnegotiation = false
        subnegotiationBytes = 0
    }

    func process(_ input: Data) -> Result {
        var payload = Data()
        var replies = Data()
        var events: [String] = []

        let iac: UInt8 = 255
        let sb: UInt8 = 250
        let se: UInt8 = 240
        let will: UInt8 = 251
        let wont: UInt8 = 252
        let request: UInt8 = 253   // DO
        let dont: UInt8 = 254

        let bytes = [UInt8](input)
        var index = 0

        while index < bytes.count {
            let byte = bytes[index]

            if inSubnegotiation {
                if byte == iac, index + 1 < bytes.count, bytes[index + 1] == se {
                    events.append("子协商结束（\(subnegotiationBytes) 字节，已忽略）")
                    inSubnegotiation = false
                    subnegotiationBytes = 0
                    index += 2
                    continue
                }
                subnegotiationBytes += 1
                index += 1
                continue
            }

            guard byte == iac else {
                payload.append(byte)
                index += 1
                continue
            }

            guard index + 1 < bytes.count else { break }   // 半个 IAC，等下一批

            let command = bytes[index + 1]
            switch command {
            case iac:
                payload.append(iac)
                index += 2
            case sb:
                subnegotiationBytes = 0
                inSubnegotiation = true
                index += 2
            case will, wont, request, dont:
                guard index + 2 < bytes.count else {
                    return Result(payload: payload, replies: replies, events: events)
                }
                let option = bytes[index + 2]
                let name = Self.optionName(option)
                switch command {
                case will:
                    events.append("服务端 WILL \(name) → 回绝（DONT）")
                    replies.append(contentsOf: [iac, dont, option])
                case request:
                    events.append("服务端 DO \(name) → 回绝（WONT）")
                    replies.append(contentsOf: [iac, wont, option])
                case wont:
                    events.append("服务端 WONT \(name)")
                default:
                    events.append("服务端 DONT \(name)")
                }
                index += 3
            default:
                index += 2
            }
        }

        return Result(payload: payload, replies: replies, events: events)
    }

    static func optionName(_ option: UInt8) -> String {
        switch option {
        case 0: return "BINARY"
        case 1: return "ECHO"
        case 3: return "SUPPRESS-GO-AHEAD"
        case 5: return "STATUS"
        case 6: return "TIMING-MARK"
        case 18: return "LOGOUT"
        case 24: return "TERMINAL-TYPE"
        case 31: return "WINDOW-SIZE"
        case 32: return "TERMINAL-SPEED"
        case 33: return "REMOTE-FLOW-CONTROL"
        case 34: return "LINEMODE"
        case 36: return "ENVIRONMENT"
        case 39: return "NEW-ENVIRON"
        default: return "选项 \(option)"
        }
    }
}

// MARK: - 文本解码 / 清洗

/// 字节流 → 文本。留出可能被切断的多字节序列，等下一批数据补齐。
final class TelnetTextDecoder {
    private var buffer = Data()

    private static let gb18030 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
    )

    func reset() {
        buffer.removeAll()
    }

    func feed(_ data: Data) -> String {
        buffer.append(data)
        guard !buffer.isEmpty else { return "" }

        if let text = String(data: buffer, encoding: .utf8) {
            buffer.removeAll()
            return text
        }

        // 末尾可能是被切断的多字节字符，退回最多 3 字节再试
        let trimLimit = min(3, buffer.count)
        if trimLimit > 0 {
            for trim in 1...trimLimit {
                let head = buffer.dropLast(trim)
                if let text = String(data: head, encoding: .utf8) {
                    buffer = Data(buffer.suffix(trim))
                    return text
                }
            }
        }

        // 不是 UTF-8，按 GB18030 解
        for trim in 0...min(3, buffer.count) {
            let head = buffer.dropLast(trim)
            guard !head.isEmpty else { continue }
            if let text = String(data: head, encoding: Self.gb18030) {
                buffer = Data(buffer.suffix(trim))
                return text
            }
        }

        // 实在解不出来就容错解掉，别把数据憋在缓冲区里
        let text = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll()
        return text
    }
}

enum TelnetTextSanitizer {
    private static let ansiPatterns = [
        "\u{1B}\\[[0-9;?]*[ -/]*[@-~]",                    // CSI 序列
        "\u{1B}\\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\\\)",    // OSC 序列
        "\u{1B}[()][A-Za-z0-9]",                           // 字符集选择
        "\u{1B}[=>]",                                      // 单字符转义
    ]

    /// 清掉 ANSI 控制序列与不可见控制字符，统一换行符
    static func clean(_ text: String) -> String {
        var result = text
        for pattern in ansiPatterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")
        result = result.replacingOccurrences(
            of: "[\u{00}-\u{08}\u{0B}\u{0C}\u{0E}-\u{1F}\u{7F}]",
            with: "",
            options: .regularExpression
        )
        return result
    }
}
