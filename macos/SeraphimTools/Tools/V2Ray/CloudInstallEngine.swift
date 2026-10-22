import Combine
import Foundation

// MARK: - SSH 主机

enum SSHAuthMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case password
    case key

    var id: String { rawValue }

    var title: String {
        switch self {
        case .password: return "密码"
        case .key: return "私钥"
        }
    }
}

struct SSHHostConfig: Codable, Hashable, Sendable {
    var host: String = ""
    var port: Int = 22
    var user: String = "root"
    var authMode: SSHAuthMode = .key
    var password: String = ""
    var keyPath: String = "~/.ssh/id_rsa"
}

// MARK: - 装什么

enum ServerMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case vlessReality
    case vlessWebSocket
    case vmessWebSocket

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vlessReality: return "VLESS + REALITY"
        case .vlessWebSocket: return "VLESS + WebSocket"
        case .vmessWebSocket: return "VMess + WebSocket"
        }
    }

    var detail: String {
        switch self {
        case .vlessReality:
            return "现在最抗封锁的搭配，不需要域名和证书，直接借用大站的 TLS 指纹。默认端口 443。"
        case .vlessWebSocket:
            return "走 WebSocket，方便以后套 CDN。没加 TLS，裸跑或者自己在前面挂 nginx。"
        case .vmessWebSocket:
            return "老牌搭配，兼容性最好，客户端最老的内核也认。"
        }
    }

    var needsRealityKeys: Bool { self == .vlessReality }
    var defaultPort: Int { self == .vlessReality ? 443 : 8080 }
    var needsPath: Bool { self != .vlessReality }
    var supportsTLS: Bool { false }
}

struct CloudInstallPlan: Codable, Hashable, Sendable {
    var mode: ServerMode = .vlessReality
    var port: Int = 443
    var serverName: String = "www.microsoft.com"
    var wsPath: String = "/seraphim"
    var remark: String = "云端节点"

    var effectivePath: String {
        let trimmed = wsPath.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "/seraphim" }
        return trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
    }
}

// MARK: - 步骤

enum InstallStepState: Sendable {
    case pending
    case running
    case done
    case failed

    var title: String {
        switch self {
        case .pending: return "等待"
        case .running: return "进行中"
        case .done: return "完成"
        case .failed: return "失败"
        }
    }
}

struct InstallStep: Identifiable, Sendable {
    var id = UUID()
    var title: String
    var state: InstallStepState = .pending
    var detail: String = ""
}

// MARK: - SSH 执行

enum SSHRunner {
    /// 跑一段远端脚本，返回合并输出
    @discardableResult
    static func run(
        config: SSHHostConfig,
        script: String,
        timeout: TimeInterval = 300,
        onLine: ((String) -> Void)? = nil
    ) -> ShellResult {
        let host = config.host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else {
            return ShellResult(status: 2, out: "", err: "服务器地址是空的")
        }
        guard config.port > 0, config.port <= 65535 else {
            return ShellResult(status: 2, out: "", err: "SSH 端口不合法")
        }

        let encoded = Data(script.utf8).base64EncodedString()
        let remoteCommand = "echo \(encoded) | base64 -d | bash"

        switch config.authMode {
        case .key:
            return runWithKey(config: config, host: host, remoteCommand: remoteCommand, timeout: timeout, onLine: onLine)
        case .password:
            return runWithPassword(config: config, host: host, remoteCommand: remoteCommand, timeout: timeout, onLine: onLine)
        }
    }

    private static func baseArguments(config: SSHHostConfig, host: String) -> [String] {
        [
            "-p", "\(config.port)",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ConnectTimeout=12",
            "-o", "LogLevel=ERROR",
            "\(config.user)@\(host)"
        ]
    }

    private static func runWithKey(
        config: SSHHostConfig,
        host: String,
        remoteCommand: String,
        timeout: TimeInterval,
        onLine: ((String) -> Void)?
    ) -> ShellResult {
        let key = (config.keyPath as NSString).expandingTildeInPath
        var arguments = ["-i", key, "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes"]
        arguments.append(contentsOf: baseArguments(config: config, host: host))
        arguments.append(remoteCommand)

        return stream("/usr/bin/ssh", arguments, timeout: timeout, onLine: onLine)
    }

    private static func runWithPassword(
        config: SSHHostConfig,
        host: String,
        remoteCommand: String,
        timeout: TimeInterval,
        onLine: ((String) -> Void)?
    ) -> ShellResult {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/expect") else {
            return ShellResult(status: 127, out: "", err: "系统里没有 expect，密码登录用不了，请改用私钥")
        }

        // expect 脚本：密码里的特殊字符要转义，免得被 tcl 解释
        let escapedPassword = config.password
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")

        var sshLine = "/usr/bin/ssh -p \(config.port)"
        sshLine += " -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
        sshLine += " -o ConnectTimeout=12 -o LogLevel=ERROR"
        sshLine += " -o PreferredAuthentications=password -o PubkeyAuthentication=no"
        sshLine += " \(config.user)@\(host)"
        sshLine += " \"\(remoteCommand)\""

        let script = """
        set timeout \(Int(timeout))
        set send_slow {1 .001}
        log_user 1
        spawn \(sshLine)
        expect {
            -re "(?i)password.*:" { send -- "\(escapedPassword)\\r"; exp_continue }
            -re "(?i)permission denied" { puts "__AUTH_FAILED__"; exit 5 }
            -re "(?i)connection refused" { puts "__CONN_REFUSED__"; exit 6 }
            timeout { puts "__TIMEOUT__"; exit 7 }
            eof
        }
        catch wait result
        exit [lindex $result 3]
        """

        let path = NSTemporaryDirectory() + "seraphim-ssh-\(UUID().uuidString).exp"
        do {
            try script.write(toFile: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        } catch {
            return ShellResult(status: 1, out: "", err: "expect 脚本写不出去：\(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(atPath: path) }

        return stream("/usr/bin/expect", [path], timeout: timeout + 20, onLine: onLine)
    }

    /// 流式跑一个进程，逐行回调
    private static func stream(
        _ executable: String,
        _ arguments: [String],
        timeout: TimeInterval,
        onLine: ((String) -> Void)?
    ) -> ShellResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return ShellResult(status: 127, out: "", err: "找不到 \(executable)")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        var collected = ""
        let lock = NSLock()

        func handle(_ data: Data) {
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
            lock.lock()
            collected += text
            lock.unlock()
            guard let onLine else { return }
            for line in text.components(separatedBy: .newlines) where !line.isEmpty {
                onLine(line)
            }
        }

        outPipe.fileHandleForReading.readabilityHandler = { handle($0.availableData) }
        errPipe.fileHandleForReading.readabilityHandler = { handle($0.availableData) }

        do {
            try process.run()
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            return ShellResult(status: 126, out: "", err: error.localizedDescription)
        }

        // 交互式提示不要卡住
        process.standardInput = FileHandle.nullDevice

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            usleep(60_000)
        }
        if process.isRunning {
            process.terminate()
            usleep(200_000)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            lock.lock()
            collected += "\n__LOCAL_TIMEOUT__\n"
            lock.unlock()
        }

        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        handle(outPipe.fileHandleForReading.readDataToEndOfFile())
        handle(errPipe.fileHandleForReading.readDataToEndOfFile())

        lock.lock()
        let text = collected
        lock.unlock()

        return ShellResult(status: process.terminationStatus, out: text, err: "")
    }
}

// MARK: - 云端安装

final class CloudInstaller: ObservableObject {
    @Published private(set) var steps: [InstallStep] = []
    @Published private(set) var running = false
    @Published private(set) var log: [String] = []
    @Published private(set) var node: V2RayNode?
    @Published private(set) var failure: String?

    private var cancelled = false
    private let maxLogLines = 400

    var stepTitles: [String] {
        ["检查服务器", "生成密钥", "安装内核", "写配置并启动", "开放端口", "整理节点链接"]
    }

    private func prepareSteps() {
        steps = stepTitles.map { InstallStep(title: $0) }
        log.removeAll()
        node = nil
        failure = nil
    }

    private func setStep(_ index: Int, state: InstallStepState, detail: String = "") {
        guard index < steps.count else { return }
        steps[index].state = state
        if !detail.isEmpty { steps[index].detail = detail }
    }

    private func append(_ line: String) {
        log.append(line)
        if log.count > maxLogLines { log.removeFirst(log.count - maxLogLines) }
    }

    func cancel() {
        cancelled = true
        append("已取消")
    }

    // MARK: 只检查连通性

    func check(host: SSHHostConfig, completion: @escaping (Bool, String) -> Void) {
        guard !running else { return }
        running = true
        prepareSteps()
        setStep(0, state: .running)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let probe = """
            echo __SERAPHIM_OK__
            echo "arch=$(uname -m)"
            echo "os=$( (cat /etc/os-release 2>/dev/null | head -1) || uname -s )"
            echo "uid=$(id -u)"
            echo "systemd=$(command -v systemctl >/dev/null 2>&1 && echo yes || echo no)"
            echo "unzip=$(command -v unzip >/dev/null 2>&1 && echo yes || echo no)"
            echo "curl=$(command -v curl >/dev/null 2>&1 && echo yes || echo no)"
            command -v xray >/dev/null 2>&1 && echo "xray=$(xray version 2>/dev/null | head -1)" || echo "xray=none"
            """
            let result = SSHRunner.run(config: host, script: probe, timeout: 40) { [weak self] line in
                self?.append(line)
            }
            let output = result.out
            let reachable = output.contains("__SERAPHIM_OK__")

            DispatchQueue.main.async {
                self.running = false
                if reachable {
                    self.setStep(0, state: .done, detail: "连上了")
                    completion(true, self.summarize(output))
                } else {
                    let hint = output.contains("__AUTH_FAILED__") || output.lowercased().contains("permission denied")
                        ? "认证没过，检查用户名、密码或私钥"
                        : (output.contains("__CONN_REFUSED__") ? "端口拒绝连接" : "连不上，检查地址与网络")
                    self.setStep(0, state: .failed, detail: hint)
                    self.failure = hint
                    completion(false, hint)
                }
            }
        }
    }

    private func summarize(_ output: String) -> String {
        var parts: [String] = []
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("arch=") { parts.append("架构 \(trimmed.dropFirst(5))") }
            if trimmed.hasPrefix("os=") { parts.append(String(trimmed.dropFirst(3))) }
            if trimmed.hasPrefix("systemd="), trimmed.hasSuffix("no") { parts.append("没有 systemd") }
            if trimmed.hasPrefix("xray="), !trimmed.hasSuffix("none") { parts.append("已装过内核") }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: 一键安装

    func install(host: SSHHostConfig, plan: CloudInstallPlan, corePath: String) {
        guard !running else { return }
        running = true
        cancelled = false
        prepareSteps()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.performInstall(host: host, plan: plan, corePath: corePath)
            DispatchQueue.main.async { self.running = false }
        }
    }

    private func fail(at step: Int, message: String) {
        DispatchQueue.main.async {
            self.setStep(step, state: .failed, detail: message)
            self.failure = message
        }
    }

    private func performInstall(host: SSHHostConfig, plan: CloudInstallPlan, corePath: String) {
        // 1 探活
        DispatchQueue.main.async { self.setStep(0, state: .running) }
        let probeScript = """
        echo __SERAPHIM_OK__
        echo "arch=$(uname -m)"
        echo "uid=$(id -u)"
        echo "unzip=$(command -v unzip >/dev/null 2>&1 && echo yes || echo no)"
        echo "python3=$(command -v python3 >/dev/null 2>&1 && echo yes || echo no)"
        echo "systemd=$(command -v systemctl >/dev/null 2>&1 && echo yes || echo no)"
        """
        let probe = SSHRunner.run(config: host, script: probeScript, timeout: 40) { [weak self] line in
            self?.append(line)
        }
        guard probe.out.contains("__SERAPHIM_OK__") else {
            let hint = probe.out.contains("__AUTH_FAILED__") ? "认证失败" : "连不上服务器"
            fail(at: 0, message: hint)
            return
        }
        let isRoot = probe.out.contains("uid=0")
        let hasUnzip = probe.out.contains("unzip=yes")
        let hasPython = probe.out.contains("python3=yes")
        guard isRoot else {
            fail(at: 0, message: "需要 root 账号（或能 sudo 的账号）")
            return
        }
        guard hasUnzip || hasPython else {
            fail(at: 0, message: "服务器上没有 unzip，也没有 python3，解不开压缩包")
            return
        }
        let arch = probe.out.components(separatedBy: .newlines)
            .first { $0.hasPrefix("arch=") }?
            .replacingOccurrences(of: "arch=", with: "") ?? ""
        DispatchQueue.main.async {
            self.setStep(0, state: .done, detail: "\(arch) · root")
        }

        if cancelled { return }

        // 2 本地生成密钥
        DispatchQueue.main.async { self.setStep(1, state: .running) }
        let uuid = generateUUID(corePath: corePath)
        var privateKey = ""
        var publicKey = ""
        var shortId = ""
        if plan.mode.needsRealityKeys {
            guard let keys = generateRealityKeys(corePath: corePath) else {
                fail(at: 1, message: "生成 REALITY 密钥失败，检查本机内核能不能跑")
                return
            }
            privateKey = keys.private
            publicKey = keys.public
            shortId = randomHex(bytes: 8)
        }
        DispatchQueue.main.async {
            self.setStep(1, state: .done, detail: plan.mode.needsRealityKeys ? "已生成 UUID 与 REALITY 密钥" : "已生成 UUID")
        }

        if cancelled { return }

        // 3 装内核
        DispatchQueue.main.async { self.setStep(2, state: .running) }
        let installScript = Self.installScript(mode: plan.mode)
        let installResult = SSHRunner.run(config: host, script: installScript, timeout: 420) { [weak self] line in
            self?.append(line)
        }
        if installResult.out.contains("__UNSUPPORTED_ARCH__") {
            fail(at: 2, message: "服务器架构不支持")
            return
        }
        if installResult.out.contains("__DOWNLOAD_FAIL__") {
            fail(at: 2, message: "服务器下不动安装包（GitHub 和镜像都不通），换个方式或手动上传")
            return
        }
        if installResult.out.contains("__NO_UNZIP__") {
            fail(at: 2, message: "服务器上解压工具缺失")
            return
        }
        guard installResult.out.contains("__INSTALLED__") else {
            fail(at: 2, message: "安装没走完，看下面的日志")
            return
        }
        let version = installResult.out.components(separatedBy: .newlines)
            .first { $0.contains("Xray") || $0.contains("v2ray") }?
            .trimmingCharacters(in: .whitespaces) ?? "已安装"
        DispatchQueue.main.async { self.setStep(2, state: .done, detail: version) }

        if cancelled { return }

        // 4 写配置并启动
        DispatchQueue.main.async { self.setStep(3, state: .running) }
        let configJSON = Self.serverConfig(
            plan: plan,
            uuid: uuid,
            privateKey: privateKey,
            shortId: shortId
        )
        let configureScript = Self.configureScript(configJSON: configJSON, plan: plan)
        let configureResult = SSHRunner.run(config: host, script: configureScript, timeout: 120) { [weak self] line in
            self?.append(line)
        }
        guard configureResult.out.contains("__ACTIVE__") else {
            fail(at: 3, message: "服务没起来，看日志里的 systemctl 报错")
            return
        }
        DispatchQueue.main.async { self.setStep(3, state: .done, detail: "服务已在运行") }

        if cancelled { return }

        // 5 防火墙
        DispatchQueue.main.async { self.setStep(4, state: .running) }
        let firewallScript = Self.firewallScript(port: plan.port)
        let firewallResult = SSHRunner.run(config: host, script: firewallScript, timeout: 90) { [weak self] line in
            self?.append(line)
        }
        let listening = firewallResult.out.contains("__LISTENING__")
        DispatchQueue.main.async {
            self.setStep(4, state: .done, detail: listening ? "端口在监听" : "规则已加，端口状态没读到")
        }

        // 6 出节点链接
        DispatchQueue.main.async { self.setStep(5, state: .running) }
        var node = V2RayNode()
        node.remark = plan.remark
        node.address = host.host.trimmingCharacters(in: .whitespaces)
        node.port = plan.port
        node.uuid = uuid
        switch plan.mode {
        case .vlessReality:
            node.proto = .vless
            node.network = .tcp
            node.security = .reality
            node.flow = "xtls-rprx-vision"
            node.sni = plan.serverName
            node.publicKey = publicKey
            node.shortId = shortId
            node.fingerprint = "chrome"
        case .vlessWebSocket, .vmessWebSocket:
            node.proto = plan.mode == .vlessWebSocket ? .vless : .vmess
            node.network = .ws
            node.security = .none
            node.path = plan.effectivePath
            node.host = node.address
        }

        DispatchQueue.main.async {
            self.node = node
            self.setStep(5, state: .done, detail: ShareLink.link(for: node))
            self.append("节点链接：\(ShareLink.link(for: node))")
            self.append("如果连不上，记得去云服务商控制台的安全组里也放行 \(plan.port) 端口")
        }
    }

    // MARK: 脚本

    private static func installScript(mode: ServerMode) -> String {
        let repo = "XTLS/Xray-core"
        return """
        set -e
        ARCH=$(uname -m)
        case "$ARCH" in
          x86_64|amd64) PKG=Xray-linux-64.zip ;;
          aarch64|arm64) PKG=Xray-linux-arm64-v8a.zip ;;
          *) echo "__UNSUPPORTED_ARCH__ $ARCH"; exit 1 ;;
        esac
        BASE="https://github.com/\(repo)/releases/latest/download/$PKG"
        cd /tmp
        rm -f "$PKG"
        OK=0
        for PREFIX in "https://gh-proxy.com/" "https://ghfast.top/" "https://ghproxy.net/" ""; do
          echo "下载尝试：${PREFIX}${BASE}"
          if curl -fsSL --max-time 150 -o "$PKG" "${PREFIX}${BASE}"; then OK=1; break; fi
        done
        if [ "$OK" != "1" ]; then echo "__DOWNLOAD_FAIL__"; exit 2; fi
        rm -rf /tmp/xray-pkg && mkdir -p /tmp/xray-pkg
        if command -v unzip >/dev/null 2>&1; then
          unzip -o "$PKG" -d /tmp/xray-pkg >/dev/null
        elif command -v python3 >/dev/null 2>&1; then
          python3 -m zipfile -e "$PKG" /tmp/xray-pkg
        else
          echo "__NO_UNZIP__"; exit 3
        fi
        install -m 755 /tmp/xray-pkg/xray /usr/local/bin/xray
        mkdir -p /usr/local/etc/xray /usr/local/share/xray
        cp -f /tmp/xray-pkg/geoip.dat /usr/local/share/xray/ 2>/dev/null || true
        cp -f /tmp/xray-pkg/geosite.dat /usr/local/share/xray/ 2>/dev/null || true
        rm -rf /tmp/xray-pkg "$PKG"
        echo "__INSTALLED__"
        /usr/local/bin/xray version | head -2
        """
    }

    private static func serverConfig(plan: CloudInstallPlan, uuid: String, privateKey: String, shortId: String) -> String {
        let inboundStream: JSONValue
        switch plan.mode {
        case .vlessReality:
            inboundStream = .object([
                ("network", .string("tcp")),
                ("security", .string("reality")),
                ("realitySettings", .object([
                    ("show", .bool(false)),
                    ("dest", .string("\(plan.serverName):443")),
                    ("xver", .int(0)),
                    ("serverNames", .array([.string(plan.serverName)])),
                    ("privateKey", .string(privateKey)),
                    ("shortIds", .array([.string(shortId)]))
                ]))
            ])
        case .vlessWebSocket, .vmessWebSocket:
            inboundStream = .object([
                ("network", .string("ws")),
                ("security", .string("none")),
                ("wsSettings", .object([
                    ("path", .string(plan.effectivePath)),
                    ("heartbeatPeriod", .int(0))
                ]))
            ])
        }

        let inboundSettings: JSONValue
        switch plan.mode {
        case .vlessReality, .vlessWebSocket:
            inboundSettings = .object([
                ("clients", .array([
                    .object([
                        ("id", .string(uuid)),
                        ("flow", .string(plan.mode == .vlessReality ? "xtls-rprx-vision" : "")),
                        ("email", .string("seraphim"))
                    ])
                ])),
                ("decryption", .string("none"))
            ])
        case .vmessWebSocket:
            inboundSettings = .object([
                ("clients", .array([
                    .object([
                        ("id", .string(uuid)),
                        ("alterId", .int(0)),
                        ("email", .string("seraphim"))
                    ])
                ]))
            ])
        }

        let config = JSONValue.object([
            ("log", .object([("loglevel", .string("warning"))])),
            ("inbounds", .array([
                .object([
                    ("listen", .string("0.0.0.0")),
                    ("port", .int(plan.port)),
                    ("protocol", .string(plan.mode == .vmessWebSocket ? "vmess" : "vless")),
                    ("settings", inboundSettings),
                    ("streamSettings", inboundStream),
                    ("sniffing", .object([
                        ("enabled", .bool(true)),
                        ("destOverride", .array([.string("http"), .string("tls"), .string("quic")]))
                    ]))
                ])
            ])),
            ("outbounds", .array([
                .object([("protocol", .string("freedom")), ("tag", .string("direct"))]),
                .object([("protocol", .string("blackhole")), ("tag", .string("block"))])
            ])),
            ("routing", .object([
                ("rules", .array([
                    .object([
                        ("type", .string("field")),
                        ("outboundTag", .string("block")),
                        ("protocol", .array([.string("bittorrent")]))
                    ])
                ]))
            ]))
        ])

        return config.render()
    }

    private static func configureScript(configJSON: String, plan: CloudInstallPlan) -> String {
        let encoded = Data(configJSON.utf8).base64EncodedString()
        return """
        set -e
        mkdir -p /usr/local/etc/xray
        echo "\(encoded)" | base64 -d > /usr/local/etc/xray/config.json
        cat > /etc/systemd/system/xray.service <<'UNIT'
        [Unit]
        Description=Xray Service
        After=network.target nss-lookup.target

        [Service]
        User=nobody
        CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
        AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
        NoNewPrivileges=true
        ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
        Restart=on-failure
        RestartPreventExitStatus=23
        LimitNPROC=10000
        LimitNOFILE=1000000

        [Install]
        WantedBy=multi-user.target
        UNIT
        if command -v systemctl >/dev/null 2>&1; then
          systemctl daemon-reload
          systemctl enable xray >/dev/null 2>&1 || true
          systemctl restart xray
          sleep 2
          if systemctl is-active --quiet xray; then
            echo "__ACTIVE__"
          else
            echo "systemctl 状态：$(systemctl is-active xray 2>&1)"
            journalctl -u xray -n 15 --no-pager 2>/dev/null || true
          fi
        else
          pkill -f "xray run" 2>/dev/null || true
          nohup /usr/local/bin/xray run -config /usr/local/etc/xray/config.json >/var/log/xray.log 2>&1 &
          sleep 2
          if pgrep -f "xray run" >/dev/null; then echo "__ACTIVE__"; else echo "没有 systemd，后台启动也没成功"; fi
        fi
        """
    }

    private static func firewallScript(port: Int) -> String {
        """
        if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi active; then
          ufw allow \(port)/tcp >/dev/null 2>&1 || true
          echo "已放行 ufw \(port)/tcp"
        fi
        if command -v firewall-cmd >/dev/null 2>&1; then
          firewall-cmd --permanent --add-port=\(port)/tcp >/dev/null 2>&1 || true
          firewall-cmd --reload >/dev/null 2>&1 || true
          echo "已放行 firewalld \(port)/tcp"
        fi
        iptables -I INPUT -p tcp --dport \(port) -j ACCEPT 2>/dev/null || true
        if ss -tln 2>/dev/null | grep -q ":\(port) "; then echo "__LISTENING__"; fi
        ss -tln 2>/dev/null | grep ":\(port) " || true
        """
    }

    // MARK: 密钥

    private func generateUUID(corePath: String) -> String {
        let result = Shell.run(corePath, ["uuid"], timeout: 8)
        let text = result.combined.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count == 36, text.contains("-") { return text }
        // 内核不支持就本地造一个
        let fallback = Shell.run("/usr/bin/uuidgen", [], timeout: 5).out.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? UUID().uuidString.lowercased() : fallback.lowercased()
    }

    private func generateRealityKeys(corePath: String) -> (private: String, public: String)? {
        let result = Shell.run(corePath, ["x25519"], timeout: 10)
        var privateKey = ""
        var publicKey = ""
        for line in result.combined.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Private key:") || trimmed.hasPrefix("PrivateKey:") {
                privateKey = trimmed.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            }
            if trimmed.hasPrefix("Public key:") || trimmed.hasPrefix("Password (PublicKey):") || trimmed.hasPrefix("Password:") {
                publicKey = trimmed.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            }
        }
        guard !privateKey.isEmpty, !publicKey.isEmpty else { return nil }
        return (privateKey, publicKey)
    }

    private func randomHex(bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { pointer in
            SecRandomCopyBytes(kSecRandomDefault, bytes, pointer.baseAddress!)
        }
        return data.map { String(format: "%02x", $0) }.joined()
    }
}
