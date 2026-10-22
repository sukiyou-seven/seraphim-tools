import Foundation

/// 公网 IP / IP 归属地查询。
///
/// 策略：把选中的接口并发打出去，谁先回来先显示谁的结果——单个接口挂了或超时不影响别的。
/// 归属地接口给的都是"顺带查到"的信息，字段对不齐很正常，所以每个接口的结果独立成一张卡片。
enum IPLookupEngine {

    // MARK: - 对外入口

    /// 查本机在公网上的地址
    static func ownAddress(providers: [IPProvider], timeout: TimeInterval = 8) -> AsyncStream<IPReport> {
        run(providers: providers, target: nil, timeout: timeout)
    }

    /// 查指定 IP 的归属地
    static func geo(ip: String, providers: [IPProvider], timeout: TimeInterval = 8) -> AsyncStream<IPReport> {
        run(providers: providers, target: ip, timeout: timeout)
    }

    private static func run(providers: [IPProvider], target: String?, timeout: TimeInterval) -> AsyncStream<IPReport> {
        AsyncStream { continuation in
            let worker = Task.detached(priority: .userInitiated) {
                await withTaskGroup(of: IPReport.self) { group in
                    for provider in providers {
                        group.addTask { await query(provider: provider, target: target, timeout: timeout) }
                    }
                    for await report in group {
                        if Task.isCancelled {
                            group.cancelAll()
                            break
                        }
                        continuation.yield(report)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    // MARK: - 单个接口

    private static func query(provider: IPProvider, target: String?, timeout: TimeInterval) async -> IPReport {
        let started = Date()
        guard let urlText = endpoint(for: provider, target: target),
              let url = URL(string: urlText) else {
            return failureReport(provider: provider, target: target, message: "这个接口不支持该查询")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("SeraphimTools/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout + 4
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)

        defer { session.finishTasksAndInvalidate() }

        do {
            let (data, response) = try await session.data(for: request)
            let elapsed = Date().timeIntervalSince(started) * 1000
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return failureReport(provider: provider, target: target, message: "接口返回 HTTP \(http.statusCode)")
            }
            return try parse(provider: provider, data: data, target: target, elapsed: elapsed)
        } catch {
            let elapsed = Date().timeIntervalSince(started) * 1000
            return failureReport(
                provider: provider,
                target: target,
                message: friendly(error),
                elapsed: elapsed
            )
        }
    }

    private static func endpoint(for provider: IPProvider, target: String?) -> String? {
        switch provider.id {
        case "ipip":
            return "https://myip.ipip.net"
        case "ipapi":
            guard let target else { return "http://ip-api.com/json/?lang=zh-CN" }
            return "http://ip-api.com/json/\(encode(target))?lang=zh-CN"
        case "ipapiiis":
            guard let target else { return "https://api.ipapi.is/" }
            return "https://api.ipapi.is/?q=\(encode(target))"
        case "ipwho":
            guard let target else { return nil }
            return "https://ipwho.is/\(encode(target))?lang=zh"
        case "ipinfo":
            guard let target else { return "https://ipinfo.io/json" }
            return "https://ipinfo.io/\(encode(target))/json"
        case "icanhazip4":
            return "https://ipv4.icanhazip.com"
        case "icanhazip6":
            return "https://ipv6.icanhazip.com"
        default:
            return nil
        }
    }

    /// IP 里的 `.` 和 `:` 在 URL 里是安全的，别的一条不留
    private static func encode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: ".:-")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    // MARK: - 解析

    private enum LookupError: LocalizedError {
        case message(String)

        var errorDescription: String? {
            switch self {
            case .message(let text): return text
            }
        }
    }

    private static func parse(provider: IPProvider, data: Data, target: String?, elapsed: Double) throws -> IPReport {
        let isOwn = target == nil
        switch provider.id {
        case "ipip":
            return try parseIPIP(provider: provider, data: data, elapsed: elapsed, isOwn: isOwn)
        case "ipapi":
            return try parseIPAPI(provider: provider, data: data, elapsed: elapsed, isOwn: isOwn)
        case "ipapiiis":
            return try parseIPAPIIs(provider: provider, data: data, elapsed: elapsed, isOwn: isOwn)
        case "ipwho":
            return try parseIPWho(provider: provider, data: data, elapsed: elapsed, isOwn: isOwn)
        case "ipinfo":
            return try parseIPInfo(provider: provider, data: data, elapsed: elapsed, isOwn: isOwn)
        case "icanhazip4", "icanhazip6":
            let text = decodeText(data).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !text.contains(" ") else {
                throw LookupError.message("接口返回了看不懂的内容")
            }
            return makeReport(
                provider: provider,
                address: text,
                fields: [
                    IPField("地址族", text.contains(":") ? "IPv6" : "IPv4", highlight: true),
                    IPField("说明", provider.familyHint == .v4 ? "本机 IPv4 出口地址" : "本机 IPv6 出口地址"),
                ],
                elapsed: elapsed,
                isOwn: isOwn
            )
        default:
            throw LookupError.message("没有实现这个接口的解析")
        }
    }

    /// myip.ipip.net：`当前 IP：x.x.x.x  来自于：中国 四川 成都  联通`
    private static func parseIPIP(provider: IPProvider, data: Data, elapsed: Double, isOwn: Bool) throws -> IPReport {
        let text = decodeText(data)
        guard let addressRange = text.range(of: "当前 IP：") ?? text.range(of: "当前IP：") else {
            throw LookupError.message("返回格式变了：\(text.prefix(60))")
        }
        let rest = text[addressRange.upperBound...]
        let address = rest.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).first.map(String.init) ?? ""
        guard !address.isEmpty else { throw LookupError.message("没解析出 IP") }

        var fields: [IPField] = [IPField("地址族", address.contains(":") ? "IPv6" : "IPv4", highlight: true)]

        if let originRange = text.range(of: "来自于：") {
            let origin = text[originRange.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "。."))
            let parts = origin.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            if parts.count >= 3 {
                let isp = parts.last ?? ""
                let region = parts.dropLast().joined(separator: " ")
                fields.append(IPField("归属地", region, highlight: true))
                fields.append(IPField("运营商", isp))
            } else if !origin.isEmpty {
                fields.append(IPField("归属地", origin, highlight: true))
            }
        }
        return makeReport(provider: provider, address: address, fields: fields, elapsed: elapsed, isOwn: isOwn)
    }

    /// ip-api.com：中文 JSON，字段最全
    private static func parseIPAPI(provider: IPProvider, data: Data, elapsed: Double, isOwn: Bool) throws -> IPReport {
        let json = try jsonObject(data)
        if let status = json["status"] as? String, status != "success" {
            let reason = json["message"] as? String ?? "查询失败"
            throw LookupError.message(reason)
        }
        let address = json["query"] as? String ?? "—"
        var fields: [IPField] = [IPField("地址族", address.contains(":") ? "IPv6" : "IPv4", highlight: true)]

        let country = json["country"] as? String ?? ""
        let region = json["regionName"] as? String ?? ""
        let city = json["city"] as? String ?? ""
        let location = [country, region, city].filter { !$0.isEmpty }.joined(separator: " ")
        if !location.isEmpty { fields.append(IPField("归属地", location, highlight: true)) }
        if let zip = json["zip"] as? String, !zip.isEmpty { fields.append(IPField("邮编", zip)) }
        if let isp = json["isp"] as? String, !isp.isEmpty { fields.append(IPField("ISP", isp)) }
        if let org = json["org"] as? String, !org.isEmpty { fields.append(IPField("组织", org)) }
        if let asn = json["as"] as? String, !asn.isEmpty { fields.append(IPField("ASN", asn)) }
        if let zone = json["timezone"] as? String, !zone.isEmpty { fields.append(IPField("时区", zone)) }
        if let lat = json["lat"] as? Double, let lon = json["lon"] as? Double {
            fields.append(IPField("坐标", String(format: "%.4f, %.4f", lat, lon)))
        }
        var marks: [String] = []
        if json["proxy"] as? Bool == true { marks.append("代理") }
        if json["hosting"] as? Bool == true { marks.append("机房") }
        if json["mobile"] as? Bool == true { marks.append("移动网络") }
        if !marks.isEmpty { fields.append(IPField("标记", marks.joined(separator: " · "))) }
        return makeReport(provider: provider, address: address, fields: fields, elapsed: elapsed, isOwn: isOwn)
    }

    /// api.ipapi.is
    private static func parseIPAPIIs(provider: IPProvider, data: Data, elapsed: Double, isOwn: Bool) throws -> IPReport {
        let json = try jsonObject(data)
        if json["is_bogon"] as? Bool == true {
            throw LookupError.message("这是保留 / 内网地址，公网查不到归属")
        }
        let address = json["ip"] as? String ?? "—"
        var fields: [IPField] = [IPField("地址族", address.contains(":") ? "IPv6" : "IPv4", highlight: true)]

        let country = json["country"] as? String ?? ""
        let region = json["region"] as? String ?? ""
        let city = json["city"] as? String ?? ""
        let location = [country, region, city].filter { !$0.isEmpty }.joined(separator: " ")
        if !location.isEmpty { fields.append(IPField("归属地", location, highlight: true)) }
        if let company = json["company"] as? String, !company.isEmpty { fields.append(IPField("公司", company)) }
        if let asn = json["asn"] as? String, !asn.isEmpty { fields.append(IPField("ASN", asn)) }
        if let zone = json["timezone"] as? String, !zone.isEmpty { fields.append(IPField("时区", zone)) }
        if let lat = json["lat"] as? Double, let lon = json["lon"] as? Double {
            fields.append(IPField("坐标", String(format: "%.4f, %.4f", lat, lon)))
        }
        if let type = json["type"] as? String, !type.isEmpty { fields.append(IPField("类型", type)) }
        return makeReport(provider: provider, address: address, fields: fields, elapsed: elapsed, isOwn: isOwn)
    }

    /// ipwho.is
    private static func parseIPWho(provider: IPProvider, data: Data, elapsed: Double, isOwn: Bool) throws -> IPReport {
        let json = try jsonObject(data)
        if json["success"] as? Bool == false {
            throw LookupError.message(json["message"] as? String ?? "查询失败")
        }
        let address = json["ip"] as? String ?? "—"
        var fields: [IPField] = [
            IPField("地址族", json["type"] as? String ?? (address.contains(":") ? "IPv6" : "IPv4"), highlight: true)
        ]
        let country = json["country"] as? String ?? ""
        let region = json["region"] as? String ?? ""
        let city = json["city"] as? String ?? ""
        let location = [country, region, city].filter { !$0.isEmpty }.joined(separator: " ")
        if !location.isEmpty { fields.append(IPField("归属地", location, highlight: true)) }
        if let connection = json["connection"] as? [String: Any] {
            if let isp = connection["isp"] as? String, !isp.isEmpty { fields.append(IPField("ISP", isp)) }
            if let org = connection["org"] as? String, !org.isEmpty { fields.append(IPField("组织", org)) }
            if let asn = connection["asn"] as? Int { fields.append(IPField("ASN", "AS\(asn)")) }
        }
        if let timezone = json["timezone"] as? [String: Any] {
            var texts: [String] = []
            if let id = timezone["id"] as? String { texts.append(id) }
            if let utc = timezone["utc"] as? String { texts.append("UTC\(utc)") }
            if !texts.isEmpty { fields.append(IPField("时区", texts.joined(separator: " "))) }
        }
        return makeReport(provider: provider, address: address, fields: fields, elapsed: elapsed, isOwn: isOwn)
    }

    /// ipinfo.io
    private static func parseIPInfo(provider: IPProvider, data: Data, elapsed: Double, isOwn: Bool) throws -> IPReport {
        let json = try jsonObject(data)
        if let error = json["error"] as? [String: Any] {
            throw LookupError.message(error["message"] as? String ?? "查询失败")
        }
        let address = json["ip"] as? String ?? "—"
        var fields: [IPField] = [IPField("地址族", address.contains(":") ? "IPv6" : "IPv4", highlight: true)]
        let country = json["country"] as? String ?? ""
        let region = json["region"] as? String ?? ""
        let city = json["city"] as? String ?? ""
        let location = [country, region, city].filter { !$0.isEmpty }.joined(separator: " / ")
        if !location.isEmpty { fields.append(IPField("归属地", location, highlight: true)) }
        if let org = json["org"] as? String, !org.isEmpty { fields.append(IPField("组织", org)) }
        if let hostname = json["hostname"] as? String, !hostname.isEmpty { fields.append(IPField("反向域名", hostname)) }
        if let zone = json["timezone"] as? String, !zone.isEmpty { fields.append(IPField("时区", zone)) }
        if let loc = json["loc"] as? String, !loc.isEmpty { fields.append(IPField("坐标", loc.replacingOccurrences(of: ",", with: ", "))) }
        return makeReport(provider: provider, address: address, fields: fields, elapsed: elapsed, isOwn: isOwn)
    }

    // MARK: - 工具

    private static func makeReport(
        provider: IPProvider,
        address: String,
        fields: [IPField],
        elapsed: Double,
        isOwn: Bool
    ) -> IPReport {
        let family = address.contains(":") ? "IPv6" : "IPv4"
        return IPReport(
            id: "\(provider.id)-\(address)",
            provider: provider.name,
            providerNote: provider.note,
            family: address == "—" ? "—" : family,
            address: address,
            fields: fields,
            elapsed: elapsed,
            isOwnAddress: isOwn
        )
    }

    private static func failureReport(
        provider: IPProvider,
        target: String?,
        message: String,
        elapsed: Double = 0
    ) -> IPReport {
        IPReport(
            id: "\(provider.id)-failed",
            provider: provider.name,
            providerNote: provider.note,
            family: "—",
            address: "—",
            fields: [IPField("失败原因", message)],
            elapsed: elapsed,
            isOwnAddress: target == nil
        )
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let preview = decodeText(data).prefix(80)
            throw LookupError.message("返回的不是 JSON：\(preview)")
        }
        return object
    }

    /// 接口偶尔会给 GB18030（国内那个就是），UTF-8 解不出来兜一层
    private static func decodeText(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))) {
            return text
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func friendly(_ error: Error) -> String {
        if let lookup = error as? LookupError { return lookup.errorDescription ?? "查询失败" }
        return NetErrorText.friendly(error)
    }
}
