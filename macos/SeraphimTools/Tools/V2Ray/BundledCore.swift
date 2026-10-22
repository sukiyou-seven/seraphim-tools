import Darwin
import Foundation

/// 随 App 一起分发的内核。
///
/// 代理工具让用户先去装个 v2rayN 才能用，这事本身就不合理——所以工具箱自带一份
/// Xray（macOS arm64，含 geosite 分流数据），第一次要用的时候解到 Application Support 里，
/// 之后一直用它，用户不需要自己下载任何东西。
enum BundledCore {

    /// 资源包名。Intel 机器没有内置包，会退回到在线下载那条路。
    static var resourceName: String? {
        #if arch(arm64)
        return "xray-core-macos-arm64"
        #else
        return nil
        #endif
    }

    static var packageURL: URL? {
        guard let name = resourceName else { return nil }
        return Bundle.main.url(forResource: name, withExtension: "zip")
    }

    static var isAvailable: Bool { packageURL != nil }

    /// 托管目录里那份内核的路径
    static var installedPath: String {
        CoreLocator.managedDirectory().appendingPathComponent("xray").path
    }

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: installedPath)
    }

    enum InstallError: LocalizedError {
        case noPackage
        case unpack(String)
        case missingBinary

        var errorDescription: String? {
            switch self {
            case .noPackage: return "这个机型没有内置内核，需要在线下载一份"
            case .unpack(let detail): return "解压失败：\(detail)"
            case .missingBinary: return "压缩包里没有 xray 可执行文件"
            }
        }
    }

    /// 装了就直接用，没装（或要求重装）就从 App 资源里解一份出来
    @discardableResult
    static func ensureInstalled(force: Bool = false) throws -> String {
        let directory = CoreLocator.managedDirectory()
        let binary = directory.appendingPathComponent("xray")
        let geosite = directory.appendingPathComponent("geosite.dat")

        if !force,
           FileManager.default.isExecutableFile(atPath: binary.path),
           FileManager.default.fileExists(atPath: geosite.path) {
            return binary.path
        }

        guard let packageURL else { throw InstallError.noPackage }

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("seraphim-core-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        // ditto 认得 zip 里的权限位，比 unzip 稳
        let result = Shell.run("/usr/bin/ditto", ["-x", "-k", packageURL.path, staging.path], timeout: 120)
        guard result.ok else {
            throw InstallError.unpack(result.combined.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let unpacked = staging.appendingPathComponent("xray")
        guard FileManager.default.fileExists(atPath: unpacked.path) else {
            throw InstallError.missingBinary
        }

        try? FileManager.default.removeItem(at: binary)
        try FileManager.default.moveItem(at: unpacked, to: binary)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

        // bundle 里带出来的文件可能挂着隔离标记，不去掉的话一执行就被 Gatekeeper 拦下
        clearQuarantine(binary)

        // geosite.dat 是做大陆直连分流用的，一起搬过去
        let unpackedGeosite = staging.appendingPathComponent("geosite.dat")
        if FileManager.default.fileExists(atPath: unpackedGeosite.path) {
            try? FileManager.default.removeItem(at: geosite)
            try? FileManager.default.moveItem(at: unpackedGeosite, to: geosite)
        }

        writeOrigin("bundled")
        return binary.path
    }

    // MARK: 来源标记

    private static var originFile: URL {
        CoreLocator.managedDirectory().appendingPathComponent("origin.txt")
    }

    /// 这份内核是内置的还是自己下的，界面上要交代清楚
    static func origin() -> String {
        (try? String(contentsOf: originFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "bundled"
    }

    static var isBundled: Bool { origin() != "download" }

    static func writeOrigin(_ value: String) {
        try? value.write(to: originFile, atomically: true, encoding: .utf8)
    }

    private static func clearQuarantine(_ url: URL) {
        url.path.withCString { path in
            _ = removexattr(path, "com.apple.quarantine", 0)
        }
    }
}
