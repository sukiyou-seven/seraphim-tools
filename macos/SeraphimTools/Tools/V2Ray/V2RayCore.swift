import Foundation

// MARK: - 跑命令

struct ShellResult {
    var status: Int32
    var out: String
    var err: String

    var combined: String {
        let e = err.trimmingCharacters(in: .whitespacesAndNewlines)
        return e.isEmpty ? out : out + e
    }

    var ok: Bool { status == 0 }
}

enum Shell {
    @discardableResult
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 15, environment: [String: String]? = nil) -> ShellResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return ShellResult(status: 127, out: "", err: "找不到可执行文件：\(executable)")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            var merged = ProcessInfo.processInfo.environment
            for (key, value) in environment { merged[key] = value }
            process.environment = merged
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return ShellResult(status: 126, out: "", err: error.localizedDescription)
        }

        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            usleep(40_000)
        }
        if process.isRunning {
            process.terminate()
            usleep(120_000)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        _ = group.wait(timeout: .now() + 3)

        return ShellResult(
            status: process.terminationStatus,
            out: String(data: outData, encoding: .utf8) ?? "",
            err: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    /// 只管跑，不管结果
    @discardableResult
    static func fire(_ executable: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
}

// MARK: - 内核

enum CoreKind: String, Sendable {
    case xray
    case v2ray

    var title: String {
        switch self {
        case .xray: return "Xray"
        case .v2ray: return "v2ray"
        }
    }

    var binaryName: String { rawValue }

    var geoEnvironmentKey: String {
        switch self {
        case .xray: return "XRAY_LOCATION_ASSET"
        case .v2ray: return "V2RAY_LOCATION_ASSET"
        }
    }

    /// Release 资产名的前缀（macOS arm64 / x86_64）
    var assetPrefix: String {
        switch self {
        case .xray: return "Xray-macos"
        case .v2ray: return "v2ray-macos"
        }
    }

    var repository: String {
        switch self {
        case .xray: return "XTLS/Xray-core"
        case .v2ray: return "v2fly/v2ray-core"
        }
    }
}

struct CoreCandidate: Identifiable, Hashable, Sendable {
    var path: String
    var kind: CoreKind
    var source: String
    var version: String

    var id: String { path }

    var locationHint: String {
        (path as NSString).deletingLastPathComponent
    }
}

enum CoreLocator {
    /// 工具箱自己的内核目录
    static func managedDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        let dir = base.appendingPathComponent("SeraphimTools/cores", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 运行目录（配置、日志）
    static func runtimeDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        let dir = base.appendingPathComponent("SeraphimTools/runtime", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 按优先级收集候选路径（纯文件系统检查，不跑子进程，主线程安全）
    static func candidatePaths(extraPaths: [String] = []) -> [(path: String, kind: CoreKind, source: String)] {
        var list: [(String, CoreKind, String)] = []

        func consider(_ path: String, kind: CoreKind, source: String) {
            let expanded = (path as NSString).expandingTildeInPath
            guard FileManager.default.isExecutableFile(atPath: expanded) else { return }
            list.append((expanded, kind, source))
        }

        for path in extraPaths where !path.isEmpty {
            let expanded = (path as NSString).expandingTildeInPath
            let kind: CoreKind = expanded.lowercased().contains("v2ray") ? .v2ray : .xray
            consider(expanded, kind: kind, source: "手动指定")
        }

        let managed = managedDirectory()
        let managedSource = BundledCore.isBundled ? "工具箱内置" : "工具箱下载"
        consider(managed.appendingPathComponent("xray").path, kind: .xray, source: managedSource)
        consider(managed.appendingPathComponent("v2ray").path, kind: .v2ray, source: managedSource)

        let home = NSHomeDirectory()
        let v2rayN = "\(home)/Library/Application Support/v2rayN/bin"
        consider("\(v2rayN)/xray/xray", kind: .xray, source: "v2rayN")
        consider("\(v2rayN)/v2ray/v2ray", kind: .v2ray, source: "v2rayN")
        consider("\(v2rayN)/v2fly/v2ray", kind: .v2ray, source: "v2rayN")
        consider("\(v2rayN)/v2fly_v5/v2ray", kind: .v2ray, source: "v2rayN")

        for path in ["/usr/local/bin/xray", "/opt/homebrew/bin/xray", "/usr/local/bin/v2ray", "/opt/homebrew/bin/v2ray"] {
            let kind: CoreKind = path.contains("v2ray") ? .v2ray : .xray
            consider(path, kind: kind, source: "系统路径")
        }

        return list.map { (path: $0.0, kind: $0.1, source: $0.2) }
    }

    /// 找出机器上可用的内核（同步，测试用）
    static func scan(extraPaths: [String] = []) -> [CoreCandidate] {
        candidatePaths(extraPaths: extraPaths).map {
            CoreCandidate(path: $0.path, kind: $0.kind, source: $0.source, version: version(of: $0.path) ?? "")
        }
    }

    /// 并发测版本，界面用（版本检测是跑子进程，不能放主线程）
    static func scanAsync(extraPaths: [String] = []) async -> [CoreCandidate] {
        let paths = candidatePaths(extraPaths: extraPaths)
        let results = await withTaskGroup(of: (Int, CoreCandidate).self) { group in
            for (index, entry) in paths.enumerated() {
                group.addTask {
                    let candidate = CoreCandidate(
                        path: entry.path,
                        kind: entry.kind,
                        source: entry.source,
                        version: version(of: entry.path) ?? ""
                    )
                    return (index, candidate)
                }
            }
            var collected: [(Int, CoreCandidate)] = []
            for await pair in group { collected.append(pair) }
            return collected.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
        return results
    }

    /// 跑内核拿版本号
    static func version(of path: String) -> String? {
        let result = Shell.run(path, ["version"], timeout: 6)
        let text = result.combined
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.lowercased().hasPrefix("xray") || trimmed.lowercased().hasPrefix("v2ray") {
                // Xray 26.3.27 (Xray, Penetrates Everything.) d2758a0
                if let space = trimmed.range(of: " ") {
                    return String(trimmed[space.upperBound...]).components(separatedBy: " ").first ?? trimmed
                }
                return trimmed
            }
        }
        return nil
    }

    /// 找 geosite.dat 所在目录，大陆域名分流要用。
    ///
    /// 只要 geosite.dat——geoip.dat 用不上了：拿 IP 判国内外会被污染的 DNS 带沟里
    /// （详见 XrayConfigBuilder.routing 里的说明），现在分流全看域名。
    static func geoAssetDirectory(near corePath: String) -> String? {
        let candidates = [
            (corePath as NSString).deletingLastPathComponent,
            CoreLocator.managedDirectory().path,
            "\(NSHomeDirectory())/Library/Application Support/v2rayN/bin",
            (corePath as NSString).deletingLastPathComponent + "/../"
        ]
        for dir in candidates {
            let normalized = (dir as NSString).standardizingPath
            if FileManager.default.fileExists(atPath: normalized + "/geosite.dat") {
                return normalized
            }
        }
        return nil
    }
}

// MARK: - 内核下载

enum CoreDownloadError: LocalizedError {
    case noRelease(String)
    case noAsset(String)
    case network(String)
    case unzip(String)

    var errorDescription: String? {
        switch self {
        case .noRelease(let detail): return "拿不到版本信息：\(detail)"
        case .noAsset(let detail): return "release 里没有合适的文件：\(detail)"
        case .network(let detail): return "下载失败：\(detail)"
        case .unzip(let detail): return "解压失败：\(detail)"
        }
    }
}

/// 下载进度回调
typealias DownloadProgressHandler = @Sendable (Double, Int64, Int64) -> Void

final class CoreDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var progressHandler: DownloadProgressHandler?
    private var continuation: CheckedContinuation<Data, Error>?
    private var session: URLSession?

    static let shared = CoreDownloader()

    /// GitHub 直连经常不通，这里挂在镜像前缀上
    private static let mirrors = [
        "https://gh-proxy.com/",
        "https://ghfast.top/",
        "https://ghproxy.net/"
    ]

    /// 问 api.github.com 要最新版本（这个域名通常通）
    static func latestTag(repository: String) async throws -> String {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            throw CoreDownloadError.noRelease("URL 拼装失败")
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw CoreDownloadError.noRelease("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                throw CoreDownloadError.noRelease("响应里没有 tag_name")
            }
            return tag
        } catch let error as CoreDownloadError {
            throw error
        } catch {
            throw CoreDownloadError.noRelease(error.localizedDescription)
        }
    }

    /// 组装 macOS 资产的下载地址（直链 + 镜像备选）
    static func assetURLs(kind: CoreKind, tag: String) -> [String] {
        let arch = machineArchitecture()
        let names = assetNameCandidates(kind: kind, arch: arch)
        var urls: [String] = []
        for name in names {
            let direct = "https://github.com/\(kind.repository)/releases/download/\(tag)/\(name)"
            urls.append(direct)
            for mirror in mirrors {
                urls.append(mirror + direct)
            }
        }
        return urls
    }

    private static func machineArchitecture() -> String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return machine.contains("arm64") || machine.contains("arm") ? "arm64" : "64"
    }

    private static func assetNameCandidates(kind: CoreKind, arch: String) -> [String] {
        switch kind {
        case .xray:
            // Xray 新版资产名：Xray-macos-arm64-v8a.zip / Xray-macos-64.zip
            if arch == "arm64" {
                return ["Xray-macos-arm64-v8a.zip", "Xray-macos-arm64.zip", "Xray-macos-64.zip"]
            }
            return ["Xray-macos-64.zip"]
        case .v2ray:
            if arch == "arm64" {
                return ["v2ray-macos-arm64-v8a.zip", "v2ray-macos-64.zip"]
            }
            return ["v2ray-macos-64.zip"]
        }
    }

    /// 依次尝试直链与镜像，成功即返回
    func download(
        urls: [String],
        progress: DownloadProgressHandler? = nil
    ) async throws -> Data {
        var lastError: String = "没有可用的下载地址"
        for urlText in urls {
            guard let url = URL(string: urlText) else { continue }
            do {
                let data = try await downloadOne(url: url, progress: progress)
                if data.count > 1_000_000 { return data }
                lastError = "下载到的文件太小（\(data.count) 字节）"
            } catch {
                lastError = error.localizedDescription
            }
        }
        throw CoreDownloadError.network(lastError)
    }

    private func downloadOne(url: URL, progress: DownloadProgressHandler?) async throws -> Data {
        progressHandler = progress
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 600
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let task = session.downloadTask(with: url)
            task.resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        defer { self.session?.invalidateAndCancel(); self.session = nil }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
            continuation?.resume(throwing: CoreDownloadError.network("HTTP \(status)"))
            continuation = nil
            return
        }
        do {
            let data = try Data(contentsOf: location)
            continuation?.resume(returning: data)
        } catch {
            continuation?.resume(throwing: CoreDownloadError.network(error.localizedDescription))
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progressHandler?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite),
                         totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { self.session?.invalidateAndCancel(); self.session = nil }
        guard let error else { return }
        continuation?.resume(throwing: CoreDownloadError.network(error.localizedDescription))
        continuation = nil
    }

    /// 下载并解出一个能用的可执行文件，返回它的路径
    static func install(kind: CoreKind, progress: DownloadProgressHandler? = nil) async throws -> String {
        let tag = try await latestTag(repository: kind.repository)
        let urls = assetURLs(kind: kind, tag: tag)
        let data = try await CoreDownloader.shared.download(urls: urls, progress: progress)

        let dir = CoreLocator.managedDirectory()
        let zipURL = dir.appendingPathComponent("\(kind.rawValue)-\(tag).zip")
        try data.write(to: zipURL)

        let unpack = dir.appendingPathComponent("unpack-\(kind.rawValue)", isDirectory: true)
        try? FileManager.default.removeItem(at: unpack)
        try FileManager.default.createDirectory(at: unpack, withIntermediateDirectories: true)

        let result = Shell.run("/usr/bin/ditto", ["-x", "-k", zipURL.path, unpack.path], timeout: 60)
        guard result.ok else {
            throw CoreDownloadError.unzip(result.combined.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // 在解压结果里找可执行文件
        guard let binary = findBinary(in: unpack, name: kind.binaryName) else {
            throw CoreDownloadError.unzip("压缩包里没找到 \(kind.binaryName) 可执行文件")
        }

        let target = dir.appendingPathComponent(kind.binaryName)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: binary, to: target)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)

        // geosite.dat 一起搬过来，大陆域名分流要用
        if let found = findFile(in: unpack, name: "geosite.dat") {
            let dest = dir.appendingPathComponent("geosite.dat")
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.moveItem(at: found, to: dest)
        }

        try? FileManager.default.removeItem(at: unpack)
        try? FileManager.default.removeItem(at: zipURL)

        // 记一笔：这份是下载来的，界面上和内置那份区分开
        BundledCore.writeOrigin("download")

        return target.path
    }

    private static func findBinary(in directory: URL, name: String) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return nil
        }
        for case let url as URL in enumerator {
            if url.lastPathComponent == name,
               let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
               values.isRegularFile == true {
                return url
            }
        }
        return nil
    }

    private static func findFile(in directory: URL, name: String) -> URL? {
        findBinary(in: directory, name: name)
    }
}
