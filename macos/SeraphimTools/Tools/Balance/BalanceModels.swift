import Foundation

// MARK: - 能力

/// 这张卡点「检测」之后会发生什么。
///
/// 这一层刻意分得很清楚：大部分厂商**根本没有**用 API key 查余额的接口，
/// 硬去猜一个地址只会给出 404。与其糊一个假数字，不如老实说清楚能做到什么。
enum BalanceCapability: String, Codable, Sendable {
    /// 有余额接口，能直接读到钱
    case balance
    /// 没有余额接口，只做一次免费探活确认 key 还有效
    case probe

    var title: String {
        switch self {
        case .balance: return "可查余额"
        case .probe: return "仅探活"
        }
    }

    var systemImage: String {
        switch self {
        case .balance: return "yensign.circle.fill"
        case .probe: return "checkmark.shield"
        }
    }
}

/// 接口被证实的程度。
///
/// 余额端点的探测有个坑：智谱、火山方舟这类网关会在**路由之前**统一返回 401，
/// 真路径和瞎编的路径响应一模一样，所以「返回 401」并不能证明接口存在。
/// 这里如实标注，返回 404 时界面会告诉用户「这家没提供余额接口」而不是报一个看不懂的错。
enum BalanceConfidence: String, Codable, Sendable {
    /// 官方文档写明，或实测用「真路径 401 / 假路径 404」对照确认
    case verified
    /// 按同类厂商的路径形态推测，可能不存在
    case unverified

    var title: String {
        switch self {
        case .verified: return "已证实"
        case .unverified: return "未证实"
        }
    }
}

/// 把 key 放在哪里
enum BalanceAuthStyle: String, Codable, Sendable, CaseIterable {
    case bearer      // Authorization: Bearer <key>
    case xApiKey     // x-api-key: <key>
    case query       // 拼在 URL 的 ?key=<key>

    var title: String {
        switch self {
        case .bearer: return "Authorization: Bearer"
        case .xApiKey: return "x-api-key"
        case .query: return "URL 参数 key"
        }
    }
}

// MARK: - 端点

/// 一个可调用的接口。path 可以是相对 baseURL 的路径，也可以直接写完整 URL。
struct BalanceEndpoint: Hashable, Sendable {
    var path: String
    var method: String = "GET"
    var headers: [String: String] = [:]

    func url(base: String, key: String, auth: BalanceAuthStyle) -> URL? {
        var full: String
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            full = path
        } else {
            let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
            let trimmedPath = path.hasPrefix("/") ? path : "/" + path
            full = trimmedBase + trimmedPath
        }
        if auth == .query {
            let separator = full.contains("?") ? "&" : "?"
            full += separator + "key=" + (key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key)
        }
        return URL(string: full)
    }
}

// MARK: - 厂商

struct BalanceProvider: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var subtitle: String
    /// 官网 / 平台域名，用来展示和给控制台链接兜底
    var baseURL: String
    var capability: BalanceCapability
    var confidence: BalanceConfidence
    var auth: BalanceAuthStyle
    /// 按 key 前缀猜厂商用（可空）
    var keyPrefixes: [String]
    var keyPlaceholder: String
    /// 去哪申请 key
    var keyPageURL: String
    /// 去哪看余额 / 用量
    var consoleURL: String
    /// 余额接口（capability == .balance 时必有）
    var balance: BalanceEndpoint?
    /// 免费探活接口
    var probe: BalanceEndpoint?
    /// 探活接口是不是**需要鉴权**的。
    ///
    /// 绝大多数 `/models` 都要带 key，返回 200 就证明 key 是好的；但有个别站点的
    /// `/models` 是公开的，不带 key 也给 200——那种情况只能说明网络通，证明不了
    /// key 有效，这里如实区分，别让用户以为验过了。
    var probeVerifiesKey: Bool = true
    /// 解析器标识
    var parser: String
    /// 默认币种
    var currency: String
    /// 一句话说明：能不能查、有什么坑
    var note: String
    /// 自定义厂商（用户自己加的）
    var isCustom: Bool = false
    /// 自定义厂商要额外带的请求头
    var extraHeaders: [String: String] = [:]

    var domain: String {
        URL(string: baseURL)?.host ?? baseURL
    }

    /// 检测时会打哪个接口
    var effectiveEndpoint: BalanceEndpoint? {
        capability == .balance ? balance : probe
    }
}

// MARK: - 金额

/// 一条金额。用 kind 让界面知道该怎么排——「总余额」和「已用」不是一个量级的东西。
struct BalanceAmount: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case available   // 可用余额（多数厂商的主数字）
        case total       // 总额度
        case remaining   // 剩余（额度 − 已用）
        case granted     // 赠金
        case recharge    // 充值 / 现金
        case used        // 已用 / 已花费
        case limit       // 额度上限
        case other

        var title: String {
            switch self {
            case .available: return "可用余额"
            case .total: return "总额度"
            case .remaining: return "剩余"
            case .granted: return "赠金"
            case .recharge: return "充值"
            case .used: return "已用"
            case .limit: return "额度上限"
            case .other: return "其他"
            }
        }

        /// 是不是「花掉的钱」——红绿方向相反，不能混排
        var isSpending: Bool { self == .used }
    }

    var kind: Kind
    var label: String
    var value: Double
    var currency: String
    var isPrimary: Bool

    var id: String { "\(kind.rawValue)|\(label)" }
}

/// 响应里被展平的一个字段
struct BalanceField: Identifiable, Hashable, Sendable {
    var path: String
    var name: String
    var value: String
    var isMoney: Bool

    var id: String { path }
}

// MARK: - 结果

enum BalanceStatus: String, Sendable {
    case ok
    case unconfigured
    case unauthorized
    case notFound
    case exhausted
    case rateLimited
    case serverError
    case networkError
    case parseFailed
    case malformed

    var isSuccess: Bool { self == .ok }

    /// 是不是「值得用户去处理」的状态
    var needsAttention: Bool {
        switch self {
        case .ok, .unconfigured: return false
        default: return true
        }
    }

    var systemImage: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .unconfigured: return "circle.dashed"
        case .unauthorized: return "lock.trianglebadge.exclamationmark"
        case .notFound: return "questionmark.circle"
        case .exhausted: return "exclamationmark.triangle.fill"
        case .rateLimited: return "hourglass"
        case .serverError: return "exclamationmark.icloud"
        case .networkError: return "wifi.exclamationmark"
        case .parseFailed: return "doc.questionmark"
        case .malformed: return "xmark.circle"
        }
    }
}

struct BalanceReport: Identifiable, Sendable {
    var providerID: String
    var status: BalanceStatus
    var httpStatus: Int
    var latencyMS: Int
    /// 主结论，一句话
    var headline: String
    /// 补充说明
    var detail: String
    var amounts: [BalanceAmount]
    var fields: [BalanceField]
    var rawBody: String
    var queriedAt: Date
    /// 这次走的是探活而不是余额接口
    var usedProbe: Bool

    var id: String { providerID }

    var primaryAmount: BalanceAmount? {
        amounts.first { $0.isPrimary } ?? amounts.first
    }

    var secondaryAmounts: [BalanceAmount] {
        let primaryID = primaryAmount?.id
        return amounts.filter { $0.id != primaryID }
    }
}

// MARK: - 自定义厂商

/// 用户自己加的厂商 / 中转站。
///
/// 只存「怎么调」，**不存 key**——key 一律进钥匙串。
struct CustomProvider: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    /// 余额查询地址（可写相对路径，配合 baseURL；也可直接写完整 URL）
    var balanceURL: String
    var baseURL: String
    var method: String
    var authRaw: String
    var parser: String
    var currency: String
    var note: String
    var createdAt: Date
    /// 额外请求头。one-api / new-api 这类自建站要靠 `New-Api-User` 才认人，
    /// 没有这个就只能返回 401，所以留个口子。
    var extraHeaders: [String: String]

    var auth: BalanceAuthStyle {
        BalanceAuthStyle(rawValue: authRaw) ?? .bearer
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        baseURL: String,
        balanceURL: String,
        method: String = "GET",
        auth: BalanceAuthStyle = .bearer,
        parser: String = "generic",
        currency: String = "CNY",
        note: String = "",
        extraHeaders: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.balanceURL = balanceURL
        self.method = method
        self.authRaw = auth.rawValue
        self.parser = parser
        self.currency = currency
        self.note = note
        self.extraHeaders = extraHeaders
        self.createdAt = createdAt
    }

    // 手写解码：少一个字段就整条读不出来太脆了，全字段容错
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? "未命名"
        balanceURL = (try? c.decode(String.self, forKey: .balanceURL)) ?? ""
        baseURL = (try? c.decode(String.self, forKey: .baseURL)) ?? ""
        method = (try? c.decode(String.self, forKey: .method)) ?? "GET"
        authRaw = (try? c.decode(String.self, forKey: .authRaw)) ?? BalanceAuthStyle.bearer.rawValue
        parser = (try? c.decode(String.self, forKey: .parser)) ?? "generic"
        currency = (try? c.decode(String.self, forKey: .currency)) ?? "CNY"
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        extraHeaders = (try? c.decode([String: String].self, forKey: .extraHeaders)) ?? [:]
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
    }

    /// 转成统一的厂商结构
    var asProvider: BalanceProvider {
        BalanceProvider(
            id: "custom:" + id,
            name: name,
            subtitle: "自定义",
            baseURL: baseURL,
            capability: .balance,
            confidence: .unverified,
            auth: auth,
            keyPrefixes: [],
            keyPlaceholder: "这个站点给你的密钥",
            keyPageURL: baseURL,
            consoleURL: baseURL,
            balance: BalanceEndpoint(path: balanceURL, method: method),
            probe: nil,
            parser: parser,
            currency: currency,
            note: note.isEmpty ? "自定义厂商：按你填的地址请求，返回的 JSON 会被自动识别金额字段。" : note,
            isCustom: true,
            extraHeaders: extraHeaders
        )
    }
}
