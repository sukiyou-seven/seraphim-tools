import Foundation

/// 余额解析引擎。
///
/// 全是纯函数：给一个响应体，出一组金额。这样它能在命令行里直接单测，
/// 不用起 UI、不用真的拿着谁家的 key。
///
/// 设计上分两条路：
/// 1. **具名解析器** —— 已经核对过字段的厂商，走精确路径，连「赠金 / 充值」这种
///    区分都保留下来；
/// 2. **通用深扫** —— 不认识的响应（自建站、厂商改了字段名），把 JSON 整个展平，
///    挑出名字像钱的字段。宁可给一个带原始字段名的粗略结果，也不要因为路径变了
///    就报「解析失败」。
enum BalanceEngine {

    // MARK: - 厂商

    static func provider(id: String, customs: [CustomProvider] = []) -> BalanceProvider? {
        if let builtin = BalanceProviders.builtins.first(where: { $0.id == id }) { return builtin }
        return customs.first { "custom:" + $0.id == id }?.asProvider
    }

    static func allProviders(customs: [CustomProvider]) -> [BalanceProvider] {
        BalanceProviders.builtins + customs.map(\.asProvider)
    }

    /// 按 key 的形状猜是哪家。
    ///
    /// `sk-` 前缀太常见了，所以按前缀长度从长到短比——`sk-or-` 必须赢过 `sk-`。
    /// 猜不中很正常（一大批厂商都用 `sk-`），此时返回 nil，由界面让用户自己选。
    static func guessProvider(forKey key: String) -> String? {
        candidates(forKey: key).first
    }

    static func candidates(forKey key: String) -> [String] {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var matches: [(prefix: String, id: String)] = []
        for provider in BalanceProviders.builtins {
            for prefix in provider.keyPrefixes where trimmed.hasPrefix(prefix) {
                matches.append((prefix, provider.id))
            }
        }
        return matches
            .sorted { $0.prefix.count > $1.prefix.count }
            .map(\.id)
    }

    /// 掩码展示
    static func mask(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.count <= 8 {
            return String(repeating: "•", count: trimmed.count)
        }
        return trimmed.prefix(4) + "••••••••" + trimmed.suffix(4)
    }

    // MARK: - 主入口

    struct Interpretation: Sendable {
        var status: BalanceStatus
        var amounts: [BalanceAmount]
        var fields: [BalanceField]
        var headline: String
        var detail: String
    }

    /// 解析一个响应
    static func interpret(
        provider: BalanceProvider,
        body: String,
        httpStatus: Int,
        usedProbe: Bool
    ) -> Interpretation {
        // ── 先看 HTTP 层 ──
        switch httpStatus {
        case 200...299:
            break
        case 401, 403:
            return Interpretation(
                status: .unauthorized,
                amounts: [], fields: [],
                headline: "Key 无效或没有权限",
                detail: "对方返回 \(httpStatus)。检查一下 key 有没有复制全（前后别带空格）、是不是这个平台的、有没有被停用。要是确认 key 没问题，可能是这个 key 没开通查询权限。"
            )
        case 404:
            return Interpretation(
                status: .notFound,
                amounts: [], fields: [],
                headline: "这家没有这个接口",
                detail: "对方返回 404。\(provider.capability == .balance ? "说明它确实没提供用 key 查余额的接口（不是你的问题），余额只能去控制台看。" : "探活地址可能变了。")"
            )
        case 429:
            return Interpretation(
                status: .rateLimited,
                amounts: [], fields: [],
                headline: "请求太频繁",
                detail: "对方返回 429。等一会儿再试，或者别开「全部检测」连点。"
            )
        case 500...599:
            return Interpretation(
                status: .serverError,
                amounts: [], fields: [],
                headline: "对方服务出错",
                detail: "返回 \(httpStatus)，这是平台侧的问题，跟你无关，过一会儿再试。"
            )
        default:
            break
        }

        // ── 402 或正文里写着欠费，也都算「余额耗尽」──
        if httpStatus == 402 || looksExhausted(body) {
            return Interpretation(
                status: .exhausted,
                amounts: [], fields: flatten(bodyText: body),
                headline: "余额已耗尽",
                detail: "对方明确说钱不够了。原话：\(snippet(body))"
            )
        }

        // ── 解析 JSON ──
        guard let object = json(from: body) else {
            if (200...299).contains(httpStatus) && usedProbe {
                return Interpretation(
                    status: .ok, amounts: [], fields: [],
                    headline: "Key 有效",
                    detail: "探活通过（这家没有余额接口，查不到具体金额）。"
                )
            }
            return Interpretation(
                status: .parseFailed,
                amounts: [], fields: [],
                headline: "返回的不是 JSON",
                detail: "状态码 \(httpStatus)，但正文解析不出 JSON。原样：\(snippet(body))"
            )
        }

        let fields = flatten(object)
        var amounts = parseAmounts(
            parser: provider.parser,
            object: object,
            fields: fields,
            defaultCurrency: provider.currency
        )
        var detail = ""

        // ── 探活模式：只要 2xx 就算通过 ──
        if usedProbe {
            if provider.probeVerifiesKey {
                return Interpretation(
                    status: .ok, amounts: [], fields: fields,
                    headline: "Key 有效",
                    detail: "探活通过，这把 Key 对方认。\(provider.note)"
                )
            }
            return Interpretation(
                status: .ok, amounts: [], fields: fields,
                headline: "接口可达（没能验证 Key）",
                detail: "这个探活地址不带 Key 也返回 200，所以只能说明网络通，证明不了 Key 有效。\(provider.note)"
            )
        }

        // ── 余额模式 ──
        // 具名解析器（deepseek / moonshot / …）认过字段，走的是精确路径；其余一律靠深扫，
        // 深扫出来的结果字段名是原文，得提醒用户自己核一眼。
        let usedNamedParser = provider.parser != "generic" && provider.parser != "probe"
        if amounts.isEmpty {
            amounts = genericAmounts(fields: fields, defaultCurrency: provider.currency)
        }
        if !amounts.isEmpty && !usedNamedParser {
            detail = "没匹配到已知的字段结构，从返回里自动挑出了看起来像金额的字段——数值应该是对的，但名字是原文，自己核对一下。"
        }

        if amounts.isEmpty {
            return Interpretation(
                status: .parseFailed,
                amounts: [], fields: fields,
                headline: "没找到余额字段",
                detail: "请求成功了，但响应里没有认出金额。展开原始返回看看——可能是这家改了字段名，或者这个 key 没有查余额的权限。"
            )
        }

        // 余额归零要单独说，这是用户最想知道的
        guard let primary = amounts.first(where: { $0.isPrimary }) ?? amounts.first else {
            return Interpretation(
                status: .parseFailed, amounts: [], fields: fields,
                headline: "没找到余额字段", detail: detail
            )
        }

        let spent = primary.value <= 0.000_000_1 && !primary.kind.isSpending
        let inArrears = primary.value < -0.000_000_1

        // 0 和负数分开说：0 是「用完了」，负数说明已经欠费，把这个数本身显示出来更有用
        let headline: String
        if spent && !inArrears {
            headline = "余额已用完"
        } else {
            headline = money(primary.value, currency: primary.currency)
        }

        if detail.isEmpty {
            if inArrears {
                detail = "\(primary.label) 是负数，说明已经欠费了，再调用会被直接拒绝。"
            } else if spent {
                detail = "\(primary.label) 已经是 0，再去调用会直接报余额不足。"
            } else {
                detail = "\(primary.label) \(money(primary.value, currency: primary.currency))"
            }
        }

        // 有些接口会额外给一个「还能不能用」的开关
        if let available = boolValue(object, key: "is_available"), available == false, !spent {
            detail += " 接口里 is_available 是 false，意思是当前余额已经不足以发起调用了。"
        }

        return Interpretation(
            status: spent ? .exhausted : .ok,
            amounts: amounts, fields: fields,
            headline: headline, detail: detail
        )
    }

    // MARK: - 具名解析器

    private static func parseAmounts(
        parser: String,
        object: Any,
        fields: [BalanceField],
        defaultCurrency: String
    ) -> [BalanceAmount] {
        switch parser {
        case "deepseek": return deepseekAmounts(object)
        case "moonshot": return moonshotAmounts(object)
        case "siliconflow": return siliconflowAmounts(object)
        case "openrouter": return openrouterAmounts(object)
        case "oneapi": return oneAPIAmounts(object)
        case "generic": return genericAmounts(fields: fields, defaultCurrency: defaultCurrency)
        default: return genericAmounts(fields: fields, defaultCurrency: defaultCurrency)
        }
    }

    /// `{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"110.00","granted_balance":"10.00","topped_up_balance":"100.00"}]}`
    private static func deepseekAmounts(_ object: Any) -> [BalanceAmount] {
        guard let root = object as? [String: Any],
              let infos = root["balance_infos"] as? [[String: Any]],
              !infos.isEmpty else { return [] }

        var out: [BalanceAmount] = []
        for (index, info) in infos.enumerated() {
            // 多币种时只把第一个当主数字
            let isFirst = index == 0
            let currency = (info["currency"] as? String) ?? "CNY"
            func add(_ rawKey: String, kind: BalanceAmount.Kind, label: String, primary: Bool) {
                guard let value = doubleValue(info[rawKey]) else { return }
                out.append(BalanceAmount(
                    kind: kind, label: label, value: value,
                    currency: currency, isPrimary: primary
                ))
            }
            add("total_balance", kind: .available, label: "总余额（含赠金+充值）", primary: isFirst)
            add("granted_balance", kind: .granted, label: "赠金余额", primary: false)
            add("topped_up_balance", kind: .recharge, label: "充值余额", primary: false)
        }
        return out
    }

    /// `{"code":0,"data":{"available_balance":49.58894,"voucher_balance":46.58893,"cash_balance":3.00001},"status":true}`
    private static func moonshotAmounts(_ object: Any) -> [BalanceAmount] {
        guard let root = object as? [String: Any],
              let data = root["data"] as? [String: Any] else { return [] }

        var out: [BalanceAmount] = []
        func add(_ rawKey: String, kind: BalanceAmount.Kind, label: String, primary: Bool) {
            guard let value = doubleValue(data[rawKey]) else { return }
            out.append(BalanceAmount(kind: kind, label: label, value: value, currency: "CNY", isPrimary: primary))
        }
        add("available_balance", kind: .available, label: "可用余额", primary: true)
        add("voucher_balance", kind: .granted, label: "代金券余额", primary: false)
        add("cash_balance", kind: .recharge, label: "现金余额", primary: false)
        return out
    }

    /// `{"code":20000,"status":true,"data":{"balance":"0.88","chargeBalance":"0.88","totalBalance":"0.88"}}`
    private static func siliconflowAmounts(_ object: Any) -> [BalanceAmount] {
        guard let root = object as? [String: Any],
              let data = root["data"] as? [String: Any] else { return [] }

        var out: [BalanceAmount] = []
        let available = doubleValue(data["balance"])
        let total = doubleValue(data["totalBalance"])
        let charge = doubleValue(data["chargeBalance"])

        if let available {
            out.append(BalanceAmount(kind: .available, label: "可用余额", value: available, currency: "CNY", isPrimary: true))
        }
        // 这三个字段常常是同一个数，重复显示只是噪声
        if let total, total != available {
            out.append(BalanceAmount(kind: .total, label: "总余额", value: total, currency: "CNY", isPrimary: false))
        }
        if let charge, charge != available, charge != total {
            out.append(BalanceAmount(kind: .recharge, label: "充值余额", value: charge, currency: "CNY", isPrimary: false))
        }
        return out
    }

    /// `{"data":{"total_credits":10.5,"total_usage":1.2}}`
    ///
    /// 这家给的是「总共充了多少」和「花了多少」，剩余得自己减——不替用户算，
    /// 用户就得自己算，所以这里直接算好并把三项都列出来。
    private static func openrouterAmounts(_ object: Any) -> [BalanceAmount] {
        guard let root = object as? [String: Any],
              let data = root["data"] as? [String: Any] else { return [] }

        let credits = doubleValue(data["total_credits"])
        let usage = doubleValue(data["total_usage"])
        guard credits != nil || usage != nil else { return [] }

        var out: [BalanceAmount] = []
        if let credits {
            out.append(BalanceAmount(kind: .total, label: "总充值", value: credits, currency: "USD", isPrimary: false))
        }
        if let usage {
            out.append(BalanceAmount(kind: .used, label: "已用", value: usage, currency: "USD", isPrimary: false))
        }
        if let credits, let usage {
            out.insert(
                BalanceAmount(kind: .remaining, label: "剩余（总充值 − 已用）", value: credits - usage, currency: "USD", isPrimary: true),
                at: 0
            )
        } else if let credits {
            out.insert(BalanceAmount(kind: .remaining, label: "剩余", value: credits, currency: "USD", isPrimary: true), at: 0)
        }
        return out
    }

    /// one-api / new-api 自建站：`{"data":{"quota":500000,"used_quota":1000}}`
    ///
    /// 这里的 quota 不是钱，是内部单位，500000 = $1。
    private static func oneAPIAmounts(_ object: Any) -> [BalanceAmount] {
        guard let root = object as? [String: Any] else { return [] }
        let data = (root["data"] as? [String: Any]) ?? root

        let perUnit = 500_000.0
        var out: [BalanceAmount] = []
        if let quota = doubleValue(data["quota"]) {
            out.append(BalanceAmount(
                kind: .available, label: "剩余额度",
                value: quota / perUnit, currency: "USD", isPrimary: true
            ))
        }
        if let used = doubleValue(data["used_quota"]) {
            out.append(BalanceAmount(
                kind: .used, label: "已用",
                value: used / perUnit, currency: "USD", isPrimary: false
            ))
        }
        return out
    }

    // MARK: - 通用深扫

    /// 挑名字像钱的字段。宁可多给几个也不要漏——名字一律保留原样，用户能对上。
    static func genericAmounts(fields: [BalanceField], defaultCurrency: String) -> [BalanceAmount] {
        var out: [BalanceAmount] = []
        var seen = Set<String>()

        for field in fields {
            // 注意用 doubleValue 而不是 Double(field.value)：字段值已经被转成文本了，
            // 而 `Double("1,234.56")` 是 nil——带千分位、带货币符号的数字全都会被漏掉。
            guard field.isMoney, let value = doubleValue(field.value) else { continue }
            let normalized = normalize(field.name)
            guard !usageKeys.contains(normalized) else { continue }
            let key = "\(field.path)=\(field.value)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            let kind = kindFor(normalized)
            out.append(BalanceAmount(
                kind: kind,
                label: field.path,
                value: value,
                currency: currencyFor(field: field, fields: fields) ?? defaultCurrency,
                isPrimary: false
            ))
        }

        // 排序：可用余额优先，其次总额度 / 剩余，最后才是已用和额度
        let order: [BalanceAmount.Kind: Int] = [
            .available: 0, .remaining: 1, .total: 2, .granted: 3,
            .recharge: 4, .other: 5, .used: 6, .limit: 7,
        ]
        out.sort { (order[$0.kind] ?? 5, $0.label) < (order[$1.kind] ?? 5, $1.label) }

        // 第一个非「已用」的当主数字
        if let index = out.firstIndex(where: { !$0.kind.isSpending }) {
            out[index].isPrimary = true
        } else if !out.isEmpty {
            out[0].isPrimary = true
        }
        return out
    }

    private static func kindFor(_ normalized: String) -> BalanceAmount.Kind {
        if normalized.contains("used") || normalized.contains("usage") || normalized.contains("cost")
            || normalized.contains("spend") || normalized.contains("consum") || normalized.contains("expense")
            || normalized.contains("deduct") {
            return .used
        }
        if normalized.contains("limit") || normalized == "quota" || normalized.contains("maxquota") {
            return .limit
        }
        if normalized.contains("grant") || normalized.contains("voucher")
            || normalized.contains("bonus") || normalized.contains("gift") {
            return .granted
        }
        if normalized.contains("recharge") || normalized.contains("charge")
            || normalized.contains("cash") || normalized.contains("topup")
            || normalized.contains("toppedup") {
            return .recharge
        }
        if normalized.contains("remain") || normalized.contains("left") || normalized.contains("surplus") {
            return .remaining
        }
        if normalized.contains("total") {
            return .total
        }
        return .available
    }

    /// 同一个对象里常有个 `currency` 兄弟字段，用它比猜准
    private static func currencyFor(field: BalanceField, fields: [BalanceField]) -> String? {
        guard let dot = field.path.lastIndex(of: ".") else {
            // 顶层字段：找顶层的 currency
            if let top = fields.first(where: { normalize($0.name) == "currency" || normalize($0.name) == "unit" }) {
                let value = top.value.uppercased()
                if ["CNY", "USD", "EUR", "HKD", "JPY"].contains(value) { return value }
            }
            return nil
        }
        let parent = String(field.path[..<dot])
        let candidate = parent + ".currency"
        if let sibling = fields.first(where: { $0.path == candidate }) {
            let value = sibling.value.uppercased()
            if ["CNY", "USD", "EUR", "HKD", "JPY"].contains(value) { return value }
        }
        return nil
    }

    // MARK: - JSON 展平

    static func json(from text: String) -> Any? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// 把嵌套 JSON 拉成 `a.b[0].c` 这样的路径列表
    static func flatten(_ object: Any, maxDepth: Int = 5) -> [BalanceField] {
        var out: [BalanceField] = []

        func walk(_ node: Any, path: String, depth: Int) {
            guard depth <= maxDepth else { return }
            if let dict = node as? [String: Any] {
                for key in dict.keys.sorted() {
                    let child = dict[key]!
                    let childPath = path.isEmpty ? key : path + "." + key
                    walk(child, path: childPath, depth: depth + 1)
                }
            } else if let array = node as? [Any] {
                for (index, child) in array.enumerated() {
                    let childPath = "\(path)[\(index)]"
                    walk(child, path: childPath, depth: depth + 1)
                }
            } else {
                let text = stringValue(node)
                let name = path.split(separator: ".").last.map(String.init) ?? path
                out.append(BalanceField(
                    path: path,
                    name: name,
                    value: text,
                    isMoney: isMoneyKey(name) && doubleValue(node) != nil
                ))
            }
        }

        walk(object, path: "", depth: 0)
        return out
    }

    /// 把响应体也当作一份「字段」返回，方便界面展示原始内容
    private static func flatten(bodyText: String) -> [BalanceField] {
        guard let object = json(from: bodyText) else { return [] }
        return flatten(object)
    }

    // MARK: - 请求头文本

    /// 把「一行一个 `名字: 值`」的文本解析成字典。
    /// 容忍 `名字=值`、中文全角冒号、空行和 `#` 注释——用户是手打进来的。
    static func parseHeaders(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            let separators: Set<Character> = [":", "=", "："]
            guard let index = line.firstIndex(where: { separators.contains($0) }) else { continue }

            let name = String(line[line.startIndex..<index]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: index)...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            out[name] = value
        }
        return out
    }

    static func formatHeaders(_ headers: [String: String]) -> String {
        headers.keys.sorted().map { "\($0): \(headers[$0] ?? "")" }.joined(separator: "\n")
    }

    // MARK: - 值处理

    private static let moneyKeys: Set<String> = [
        "balance", "balances", "availablebalance", "totalbalance", "remainingbalance",
        "rechargebalance", "chargebalance", "cashbalance", "voucherbalance", "grantedbalance",
        "toppedupbalance", "credit", "credits", "totalcredits", "remainingcredits",
        "remaining", "available", "availableamount", "totalamount", "amount",
        "money", "fund", "wallet", "left", "surplus", "quota", "remainingquota",
        "accountbalance", "userbalance", "softlimit",
    ]

    private static let usageKeys: Set<String> = [
        "usage", "used", "totalusage", "usedquota", "cost", "totalcost",
        "spend", "spent", "consumption", "consumed", "expense",
        "deduction", "totalconsumption", "requestcount", "requestcounttotal",
    ]

    private static let limitKeys: Set<String> = [
        "limit", "totallimit", "hardlimit", "maxquota", "totalquota",
    ]

    static func normalize(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func isMoneyKey(_ name: String) -> Bool {
        let normalized = normalize(name)
        if moneyKeys.contains(normalized) { return true }
        if usageKeys.contains(normalized) { return true }
        if limitKeys.contains(normalized) { return true }
        // `xxxBalance` / `xxxCredit` 这种拼法也认
        if normalized.hasSuffix("balance") || normalized.hasSuffix("credit") { return true }
        // 只要含这些「钱的名词」，像 `used_amount`、`recharge_quota`、`wallet` 都能认出来
        if moneyNouns.contains(where: { normalized.contains($0) }) { return true }
        // `hard_limit_usd` / `total_available_cny` 这类「钱 + 币种后缀」的写法。
        // 中转站（ChatGPT-Next-Web 那套计费端点）大量用这种命名，漏了就什么都认不出来。
        if currencySuffixes.contains(where: { normalized.hasSuffix($0) }),
           moneyWords.contains(where: { normalized.contains($0) }) {
            return true
        }
        return false
    }

    private static let moneyNouns = ["balance", "credit", "quota", "amount", "wallet", "fund", "money"]

    private static let currencySuffixes = ["usd", "cny", "rmb", "eur", "hkd", "jpy"]

    private static let moneyWords = [
        "balance", "credit", "quota", "amount", "limit", "money",
        "fund", "wallet", "remain", "available", "usage", "used", "cost", "spend",
    ]

    /// 真·布尔判定。
    ///
    /// 不能用 `is Bool`：JSONSerialization 里的数字 0 和 1 桥接成 NSNumber 之后，
    /// `is Bool` 也是 true（NSNumber 的桥接就是这么宽），于是 `balance: 0` 会被当成
    /// 布尔丢掉——偏偏余额是 0 恰恰是用户最关心的时刻。得去问 CoreFoundation
    /// 它到底是 kCFBoolean 还是普通数字。
    private static func isBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    /// 数字、数字字符串都收；布尔不要
    static func doubleValue(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if isBoolean(value) { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let text = value as? String {
            let cleaned = text
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "¥", with: "")
                .replacingOccurrences(of: "$", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return nil }
            // 只接受纯粹的数字形状，避免把 "normal" 这种状态词当金额
            let allowed = CharacterSet(charactersIn: "0123456789.+-eE")
            guard cleaned.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
            return Double(cleaned)
        }
        return nil
    }

    private static func boolValue(_ object: Any, key: String) -> Bool? {
        guard let dict = object as? [String: Any] else { return nil }
        if let value = dict[key] as? Bool { return value }
        if let text = dict[key] as? String {
            if text.lowercased() == "true" { return true }
            if text.lowercased() == "false" { return false }
        }
        return nil
    }

    /// 「余额不够」这件事各家措辞五花八门，只能一起认
    static func looksExhausted(_ body: String) -> Bool {
        let lowered = body.lowercased()
        let signals = [
            "insufficient balance", "insufficient_quota", "insufficient quota",
            "insufficient user quota", "exceeded your current quota", "credit balance is too low",
            "no credit", "out of credits", "billing hard limit",
            "余额不足", "欠费", "余额已用完", "账户余额不足", "配额不足", "已超额度",
        ]
        return signals.contains { lowered.contains($0.lowercased()) }
    }

    private static func stringValue(_ value: Any) -> String {
        if let text = value as? String { return text }
        if isBoolean(value) {
            return (value as? NSNumber)?.boolValue == true ? "true" : "false"
        }
        if let number = value as? NSNumber {
            // 整数就别显示成 8.8
            let double = number.doubleValue
            if double == double.rounded(), abs(double) < 1e15 {
                return String(Int64(double))
            }
            return String(double)
        }
        return "\(value)"
    }

    private static func snippet(_ body: String, limit: Int = 200) -> String {
        let squashed = body.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if squashed.isEmpty { return "（空响应）" }
        if squashed.count <= limit { return squashed }
        return String(squashed.prefix(limit)) + "…"
    }

    // MARK: - 金额格式化

    static func symbol(_ currency: String) -> String {
        switch currency.uppercased() {
        case "CNY", "RMB", "¥", "元": return "¥"
        case "USD", "$": return "$"
        case "EUR", "€": return "€"
        case "HKD": return "HK$"
        case "JPY", "JP¥": return "¥"
        case "": return ""
        default: return currency.uppercased() + " "
        }
    }

    /// 金额 + 币种符号。小额多给两位小数，不然 `0.0004` 会显示成 `0.00`。
    static func money(_ value: Double, currency: String) -> String {
        let decimals = (value != 0 && abs(value) < 0.01) ? 4 : 2
        return symbol(currency) + number(value, decimals: decimals)
    }

    static func number(_ value: Double, decimals: Int = 2) -> String {
        let text = String(format: "%.\(decimals)f", value)
        let negative = text.hasPrefix("-")
        let body = negative ? String(text.dropFirst()) : text

        let parts = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let integerPart = String(parts.first ?? "0")
        let fractionPart = parts.count > 1 ? String(parts[1]) : ""

        var grouped = ""
        for (index, character) in integerPart.reversed().enumerated() {
            if index > 0 && index % 3 == 0 { grouped.append(",") }
            grouped.append(character)
        }
        let integer = String(grouped.reversed())

        let result = fractionPart.isEmpty ? integer : integer + "." + fractionPart
        return negative ? "-" + result : result
    }
}
