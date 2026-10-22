import CryptoKit
import Foundation
import Security

// MARK: - 算法

/// JWT 的 alg。分三类：HMAC 对称、RSA、ECDSA。
enum JWTAlgorithm: String, CaseIterable, Identifiable, Sendable {
    case hs256 = "HS256"
    case hs384 = "HS384"
    case hs512 = "HS512"
    case rs256 = "RS256"
    case rs384 = "RS384"
    case rs512 = "RS512"
    case ps256 = "PS256"
    case ps384 = "PS384"
    case ps512 = "PS512"
    case es256 = "ES256"
    case es384 = "ES384"
    case es512 = "ES512"
    case none = "none"

    var id: String { rawValue }

    var family: String {
        switch self {
        case .hs256, .hs384, .hs512: return "HMAC"
        case .rs256, .rs384, .rs512: return "RSA"
        case .ps256, .ps384, .ps512: return "RSA-PSS"
        case .es256, .es384, .es512: return "ECDSA"
        case .none: return "无签名"
        }
    }

    /// 对称密钥是"密钥"，非对称是"私钥/公钥"
    var isSymmetric: Bool {
        switch self {
        case .hs256, .hs384, .hs512: return true
        default: return false
        }
    }

    var isSigned: Bool { self != .none }

    var note: String {
        switch self {
        case .hs256, .hs384, .hs512:
            return "\(family) + SHA-\(hashBits)：双方共用一个密钥，适合内部服务"
        case .rs256, .rs384, .rs512:
            return "RSA PKCS#1 v1.5 + SHA-\(hashBits)：私钥签名、公钥验签，JWKS 里最常见"
        case .ps256, .ps384, .ps512:
            return "RSA-PSS + SHA-\(hashBits)：比 PKCS#1 v1.5 更严谨的 RSA 填充"
        case .es256, .es384, .es512:
            return "ECDSA P-\(curveBits) + SHA-\(hashBits)：签名短、速度快"
        case .none:
            return "不签名。生产环境出现它基本等于没做校验，看到就要警惕"
        }
    }

    private var hashBits: String {
        switch self {
        case .hs256, .rs256, .ps256, .es256: return "256"
        case .hs384, .rs384, .ps384, .es384: return "384"
        default: return "512"
        }
    }

    private var curveBits: String {
        switch self {
        case .es256: return "256"
        case .es384: return "384"
        default: return "521"
        }
    }

    var hash: HashAlgorithm? {
        switch self {
        case .hs256, .rs256, .ps256, .es256: return .sha256
        case .hs384, .rs384, .ps384, .es384: return .sha384
        case .hs512, .rs512, .ps512, .es512: return .sha512
        case .none: return nil
        }
    }
}

// MARK: - 密钥格式

/// 对称密钥的写法。JWKS 里的 k 是 base64url 的字节，直接当文本用会算错。
enum JWTKeyFormat: String, CaseIterable, Identifiable, Sendable {
    case text
    case base64
    case hex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: return "文本"
        case .base64: return "Base64"
        case .hex: return "Hex"
        }
    }

    func data(from text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .text:
            return Data(trimmed.utf8)
        case .base64:
            // 顺手兼容 base64url：JWKS 的 k、RFC 测试向量里的密钥都是不带填充的那种，
            // 而 Data(base64Encoded:) 要求长度是 4 的倍数，得先把 = 补回去
            var normalized = trimmed
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
                .replacingOccurrences(of: "=", with: "")
            let remainder = normalized.count % 4
            if remainder > 0 { normalized += String(repeating: "=", count: 4 - remainder) }
            return Data(base64Encoded: normalized)
        case .hex:
            var bytes: [UInt8] = []
            var index = trimmed.startIndex
            while index < trimmed.endIndex {
                let next = trimmed.index(index, offsetBy: 2, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
                guard let byte = UInt8(trimmed[index..<next], radix: 16) else { return nil }
                bytes.append(byte)
                index = next
            }
            return bytes.isEmpty ? nil : Data(bytes)
        }
    }
}

// MARK: - 解析结果

/// 一段（header / payload）解出来的东西
struct JWTSegment {
    var raw: String                 // base64url 解出来的原文
    var pretty: String              // 美化后（是 JSON 才美化）
    var object: [String: Any]?      // 解析成功的 JSON 对象
    var isJSON: Bool { object != nil }
}

enum JWTClaimStatus: Sendable {
    case ok
    case warn
    case bad
    case info
}

struct JWTClaim: Identifiable, Sendable {
    var key: String
    var value: String
    var meaning: String
    var status: JWTClaimStatus

    var id: String { key }
}

struct JWTToken {
    var raw: String
    var header: JWTSegment
    var payload: JWTSegment
    var signature: Data
    var signingInput: String
    var algorithm: JWTAlgorithm?
    var algorithmRaw: String
    var keyID: String?
    var type: String?

    var signatureBase64URL: String {
        JWTEngine.base64URLEncode(signature)
    }

    /// 签名那一段的长度（字节）
    var signatureLength: Int { signature.count }
}

enum JWTError: LocalizedError {
    case empty
    case notThreeParts(Int)
    case badBase64(String)
    case badJSON(String, String)
    case unknownAlgorithm(String)
    case keyRequired(String)
    case badKey(String)
    case signFailed(String)

    var errorDescription: String? {
        switch self {
        case .empty: return "先把 token 贴进来"
        case .notThreeParts(let count):
            return "JWT 应该是 3 段（用 . 分隔），现在只有 \(count) 段——是不是复制漏了？"
        case .badBase64(let part): return "\(part) 段不是合法的 base64url 编码"
        case .badJSON(let part, let text): return "\(part) 段不是合法 JSON：\(text)"
        case .unknownAlgorithm(let name): return "不认识的算法 \"\(name)\""
        case .keyRequired(let hint): return "\(hint)"
        case .badKey(let reason): return "密钥读不出来：\(reason)"
        case .signFailed(let reason): return "签名失败：\(reason)"
        }
    }
}

enum JWTVerifyResult: Sendable {
    case valid(String)
    case invalid(String)
    case unsupported(String)
    case badKey(String)
    case noSignature
    case notAttempted

    var isPass: Bool { if case .valid = self { return true }; return false }

    var text: String {
        switch self {
        case .valid(let note), .invalid(let note), .unsupported(let note), .badKey(let note): return note
        case .noSignature: return "没有签名"
        case .notAttempted: return "还没验"
        }
    }
}

// MARK: - 引擎

enum JWTEngine {

    // MARK: base64url

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64URLDecode(_ text: String) throws -> Data {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // 补回被去掉的 =
        let remainder = value.count % 4
        if remainder > 0 { value += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: value) else {
            throw JWTError.badBase64(text.prefix(12) + "…")
        }
        return data
    }

    // MARK: 解码

    static func decode(_ input: String) throws -> JWTToken {
        var raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        guard !raw.isEmpty else { throw JWTError.empty }

        // 整段 Authorization 头粘进来也认：Bearer / token= 这类前缀先剥掉
        if let space = raw.firstIndex(of: " ") {
            let prefix = raw[raw.startIndex..<space].lowercased()
            if prefix == "bearer" || prefix == "jwt" || prefix == "token" {
                raw = String(raw[raw.index(after: space)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        if raw.lowercased().hasPrefix("token=") {
            raw = String(raw.dropFirst("token=".count)).trimmingCharacters(in: .whitespaces)
        }

        let pieces = raw.components(separatedBy: ".")
        guard pieces.count >= 2 else { throw JWTError.notThreeParts(pieces.count) }

        let headerText = pieces[0]
        let payloadText = pieces[1]
        let signatureText = pieces.count > 2 ? pieces[2] : ""

        let header = try segment(headerText, part: "header")
        let payload = try segment(payloadText, part: "payload")

        let algRaw = (header.object?["alg"] as? String) ?? ""
        let algorithm = JWTAlgorithm(rawValue: algRaw)
        let signature = signatureText.isEmpty ? Data() : try base64URLDecode(signatureText)

        return JWTToken(
            raw: raw,
            header: header,
            payload: payload,
            signature: signature,
            signingInput: headerText + "." + payloadText,
            algorithm: algorithm,
            algorithmRaw: algRaw,
            keyID: header.object?["kid"] as? String,
            type: header.object?["typ"] as? String
        )
    }

    private static func segment(_ text: String, part: String) throws -> JWTSegment {
        guard let data = try? base64URLDecode(text), let raw = String(data: data, encoding: .utf8) else {
            throw JWTError.badBase64(part)
        }
        var object: [String: Any]?
        var pretty = raw
        if let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            object = parsed
            pretty = JSONBeautifier.pretty(raw) ?? raw
        }
        return JWTSegment(raw: raw, pretty: pretty, object: object)
    }

    // MARK: 声明体检

    /// 标准声明 + 常见私有声明的解释
    static func claims(of token: JWTToken, now: Date = Date()) -> [JWTClaim] {
        guard let object = token.payload.object else { return [] }
        var keys = Array(object.keys)
        // 时间类的排前面，其余按字母序
        let priority = ["iss", "sub", "aud", "exp", "nbf", "iat", "jti", "scope", "azp", "sid"]
        keys.sort { lhs, rhs in
            let a = priority.firstIndex(of: lhs) ?? priority.count
            let b = priority.firstIndex(of: rhs) ?? priority.count
            return a == b ? lhs < rhs : a < b
        }

        return keys.map { key in
            let value = object[key]
            var text = display(value)
            var meaning = claimMeaning(key, value: value, now: now)
            var status: JWTClaimStatus = .info

            if let seconds = numericDate(value, key: key) {
                let date = Date(timeIntervalSince1970: seconds)
                text = "\(Int(seconds))  →  \(formatter.string(from: date))"
                switch key {
                case "exp":
                    let remain = date.timeIntervalSince(now)
                    if remain < 0 {
                        status = .bad
                        meaning = "过期时间：已经过期 \(humanDuration(-remain))"
                    } else {
                        status = remain < 300 ? .warn : .ok
                        meaning = "过期时间：还有 \(humanDuration(remain)) 失效"
                    }
                case "nbf":
                    let remain = date.timeIntervalSince(now)
                    if remain > 0 {
                        status = .warn
                        meaning = "生效时间：还要等 \(humanDuration(remain)) 才生效"
                    } else {
                        status = .ok
                        meaning = "生效时间：已生效"
                    }
                case "iat":
                    status = .ok
                    meaning = "签发时间：\(humanDuration(now.timeIntervalSince(date)))前签发"
                default:
                    break
                }
            } else if key == "scope" || key == "scopes" {
                let items = (value as? String)?.split(separator: " ").count
                    ?? (value as? [Any])?.count ?? 0
                status = .info
                meaning = "权限范围：\(items) 项"
            }

            return JWTClaim(key: key, value: text.isEmpty ? "—" : text, meaning: meaning, status: status)
        }
    }

    /// 整体结论：这个 token 现在算不算有效（只看时间，不看签名）
    static func timeVerdict(of token: JWTToken, now: Date = Date()) -> (text: String, status: JWTClaimStatus) {
        guard let object = token.payload.object else {
            return ("payload 不是 JSON 对象，没法判断有效期", .info)
        }
        if let exp = numericDate(object["exp"], key: "exp") {
            let date = Date(timeIntervalSince1970: exp)
            if date < now {
                return ("已过期（\(humanDuration(now.timeIntervalSince(date)))前）", .bad)
            }
            if let nbf = numericDate(object["nbf"], key: "nbf"), Date(timeIntervalSince1970: nbf) > now {
                return ("还没到生效时间", .warn)
            }
            return ("在有效期内，还有 \(humanDuration(date.timeIntervalSince(now)))", .ok)
        }
        if token.signature.isEmpty {
            return ("没有过期时间（exp），也没有签名——这类 token 谁拿到都能用", .warn)
        }
        return ("payload 里没有 exp，不会过期", .warn)
    }

    private static func claimMeaning(_ key: String, value: Any?, now: Date) -> String {
        switch key {
        case "iss": return "签发者（issuer）：谁发的这个 token"
        case "sub": return "主体（subject）：token 代表谁"
        case "aud": return "接收方（audience）：发给谁的，对不上就该拒收"
        case "exp": return "过期时间（expiration）"
        case "nbf": return "生效时间（not before）"
        case "iat": return "签发时间（issued at）"
        case "jti": return "唯一编号（JWT ID），防重放用"
        case "scope", "scopes": return "权限范围"
        case "azp": return "授权方（authorized party）"
        case "sid": return "会话编号"
        case "client_id": return "客户端标识"
        case "email": return "邮箱"
        case "name", "preferred_username": return "用户名"
        case "roles", "role", "groups": return "角色 / 用户组"
        case "nonce": return "一次性随机串，防重放"
        case "at_hash": return "access_token 的摘要，OIDC 用来校验"
        case "typ": return "类型"
        default: return "自定义声明"
        }
    }

    private static func numericDate(_ value: Any?, key: String? = nil) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let number = value as? NSNumber { return number.doubleValue }
        // 字符串只在明确是时间声明时才按时间戳解释：RFC 7519 的 NumericDate 是 JSON 数值，
        // 但有些实现确实用字符串。不能把 sub:"1234567890" 这类误判成日期。
        if let text = value as? String, let number = Double(text),
           let key, ["exp", "nbf", "iat", "auth_time", "updated_at"].contains(key) {
            return number
        }
        return nil
    }

    private static func display(_ value: Any?) -> String {
        guard let value else { return "null" }
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        if let array = value as? [Any] {
            return array.map { display($0) }.joined(separator: ", ")
        }
        if let object = value as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "\(value)"
    }

    private static func humanDuration(_ seconds: TimeInterval) -> String {
        let value = abs(seconds)
        switch value {
        case ..<1: return "不到 1 秒"
        case ..<60: return String(format: "%.0f 秒", value)
        case ..<3600: return String(format: "%.0f 分钟", value / 60)
        case ..<86400: return String(format: "%.1f 小时", value / 3600)
        case ..<2_592_000: return String(format: "%.1f 天", value / 86400)
        default: return String(format: "%.1f 年", value / 31_557_600)
        }
    }

    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    // MARK: 验签

    static func verify(_ token: JWTToken, keyText: String, keyFormat: JWTKeyFormat = .text) -> JWTVerifyResult {
        guard let algorithm = token.algorithm else {
            return .unsupported("header 里的 alg 是 \"\(token.algorithmRaw)\"，不认识这个算法")
        }
        guard algorithm.isSigned else {
            return .noSignature
        }
        guard !token.signature.isEmpty else {
            return .invalid("alg 写着 \(algorithm.rawValue)，但第三段是空的")
        }

        let key = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return .unsupported(algorithm.isSymmetric
                ? "验 HS 签名需要填密钥（就是签名时用的那个）"
                : "验 \(algorithm.rawValue) 需要填公钥（PEM 或证书）")
        }

        let message = Data(token.signingInput.utf8)

        if algorithm.isSymmetric {
            guard let keyData = keyFormat.data(from: key) else {
                return .badKey("密钥按 \(keyFormat.title) 解不出来")
            }
            guard let expected = try? CryptoEngine.hmac(message, algorithm: algorithm.hash ?? .sha256, keyData: keyData) else {
                return .invalid("HMAC 计算失败")
            }
            return constantTimeEqual(expected, token.signature)
                ? .valid("HMAC-\(algorithm.hash?.title ?? "") 校验通过")
                : .invalid("签名对不上：密钥不对，或者 token 被改过")
        }

        switch algorithm {
        case .es256, .es384, .es512:
            return verifyECDSASignature(token: token, algorithm: algorithm, keyText: key, message: message)
        default:
            return verifyRSASignature(token: token, algorithm: algorithm, keyText: key, message: message)
        }
    }

    private static func verifyECDSASignature(
        token: JWTToken, algorithm: JWTAlgorithm, keyText: String, message: Data
    ) -> JWTVerifyResult {
        let signature = token.signature
        switch algorithm {
        case .es256:
            guard let key = loadECPublic(P256.Signing.PublicKey.self, from: keyText) else {
                return .badKey(describeKeyProblem(keyText))
            }
            guard let sig = try? P256.Signing.ECDSASignature(rawRepresentation: signature) else {
                return .invalid("签名长度不对：ES256 应该是 64 字节，现在是 \(signature.count)")
            }
            return key.isValidSignature(sig, for: message) ? .valid("ECDSA P-256 校验通过") : .invalid("签名对不上")
        case .es384:
            guard let key = loadECPublic(P384.Signing.PublicKey.self, from: keyText) else {
                return .badKey(describeKeyProblem(keyText))
            }
            guard let sig = try? P384.Signing.ECDSASignature(rawRepresentation: signature) else {
                return .invalid("签名长度不对：ES384 应该是 96 字节，现在是 \(signature.count)")
            }
            return key.isValidSignature(sig, for: message) ? .valid("ECDSA P-384 校验通过") : .invalid("签名对不上")
        default:
            guard let key = loadECPublic(P521.Signing.PublicKey.self, from: keyText) else {
                return .badKey(describeKeyProblem(keyText))
            }
            guard let sig = try? P521.Signing.ECDSASignature(rawRepresentation: signature) else {
                return .invalid("签名长度不对：ES512 应该是 132 字节，现在是 \(signature.count)")
            }
            return key.isValidSignature(sig, for: message) ? .valid("ECDSA P-521 校验通过") : .invalid("签名对不上")
        }
    }

    /// 从 PEM 公钥 / 证书里取出 EC 公钥。CryptoKit 只认 PEM 和 DER，证书要先经过 Security 转一道。
    private static func loadECPublic<K: ECPublicKeyProtocol>(_ type: K.Type, from text: String) -> K? {
        if let key = try? K(pemRepresentation: text) { return key }
        if let data = pemBody(text), let key = try? K(derRepresentation: data) { return key }
        // 证书：用 Security 抠出公钥，再转成 x9.63 交给 CryptoKit
        if let secKey = certificatePublicKey(text),
           let raw = SecKeyCopyExternalRepresentation(secKey, nil) as Data?,
           let key = try? K(x963Representation: raw) {
            return key
        }
        return nil
    }

    private static func verifyRSASignature(
        token: JWTToken, algorithm: JWTAlgorithm, keyText: String, message: Data
    ) -> JWTVerifyResult {
        guard let key = loadRSAPublic(keyText) else {
            return .badKey(describeKeyProblem(keyText))
        }
        let secAlgorithm: SecKeyAlgorithm
        switch algorithm {
        case .rs256: secAlgorithm = .rsaSignatureMessagePKCS1v15SHA256
        case .rs384: secAlgorithm = .rsaSignatureMessagePKCS1v15SHA384
        case .rs512: secAlgorithm = .rsaSignatureMessagePKCS1v15SHA512
        case .ps256: secAlgorithm = .rsaSignatureMessagePSSSHA256
        case .ps384: secAlgorithm = .rsaSignatureMessagePSSSHA384
        default: secAlgorithm = .rsaSignatureMessagePSSSHA512
        }

        guard SecKeyIsAlgorithmSupported(key, .verify, secAlgorithm) else {
            return .unsupported("这把公钥不支持 \(algorithm.rawValue)，类型或长度不对")
        }
        var error: Unmanaged<CFError>?
        let ok = SecKeyVerifySignature(key, secAlgorithm, message as CFData, token.signature as CFData, &error)
        if ok { return .valid("RSA \(algorithm.family) 校验通过") }
        let reason = error.map { ($0.takeRetainedValue() as Error).localizedDescription } ?? "签名对不上"
        return .invalid(reason)
    }

    private static func loadRSAPublic(_ text: String) -> SecKey? {
        if let key = certificatePublicKey(text) { return key }
        guard let der = pemBody(text) ?? Data(base64Encoded: text) else { return nil }
        let bytes = [UInt8](der)
        // SPKI 外面套了一层，抠出里面的 PKCS#1；裸的 PKCS#1 直接用
        let pkcs1 = RSADER.pkcs1(from: bytes) ?? bytes
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]
        return SecKeyCreateWithData(Data(pkcs1) as CFData, attributes as CFDictionary, nil)
    }

    private static func certificatePublicKey(_ text: String) -> SecKey? {
        guard text.contains("BEGIN CERTIFICATE"), let der = pemBody(text) else { return nil }
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else { return nil }
        return SecCertificateCopyKey(certificate)
    }

    /// PEM 解出 DER。没有 PEM 头就当裸 base64 试一把。
    private static func pemBody(_ text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("-----BEGIN") else {
            return Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters)
        }
        let lines = trimmed.components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") }
            .joined()
            .replacingOccurrences(of: " ", with: "")
        return Data(base64Encoded: lines, options: .ignoreUnknownCharacters)
    }

    /// 密钥读不出来时给一句人话
    private static func describeKeyProblem(_ text: String) -> String {
        if text.contains("BEGIN CERTIFICATE") {
            return "证书读不出来，确认是完整的 PEM（含 BEGIN/END 两行）"
        }
        if text.contains("PRIVATE KEY") {
            return "这是私钥。验签要用公钥（PUBLIC KEY）或证书"
        }
        if text.contains("BEGIN") {
            return "认不出的 PEM 块，看看是不是复制时漏了头尾"
        }
        return "认不出的密钥格式，支持 PEM 公钥 / PEM 证书 / 裸 base64 DER"
    }

    private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(lhs, rhs) { diff |= a ^ b }
        return diff == 0
    }

    // MARK: 签名

    /// 用 header + payload 拼出 token。payloadJSON 必须是 JSON 对象。
    static func sign(
        payloadJSON: String,
        algorithm: JWTAlgorithm,
        keyText: String,
        keyFormat: JWTKeyFormat = .text,
        kid: String = "",
        extraHeader: [String: String] = [:]
    ) throws -> String {
        let payload = payloadJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { throw JWTError.empty }
        guard let payloadData = payload.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: payloadData)) as? [String: Any] != nil else {
            throw JWTError.badJSON("payload", "得是一个 JSON 对象，比如 {\"sub\":\"123\"}")
        }

        var header: [String: Any] = ["alg": algorithm.rawValue, "typ": "JWT"]
        if !kid.isEmpty { header["kid"] = kid }
        for (key, value) in extraHeader where !value.isEmpty { header[key] = value }

        guard let headerData = try? JSONSerialization.data(withJSONObject: header, options: [.sortedKeys]),
              let headerText = String(data: headerData, encoding: .utf8) else {
            throw JWTError.signFailed("header 拼不出来")
        }

        let signingInput = base64URLEncode(Data(headerText.utf8)) + "." + base64URLEncode(payloadData)
        let message = Data(signingInput.utf8)

        if algorithm == .none {
            return signingInput + "."
        }

        let key = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw JWTError.keyRequired(algorithm.isSymmetric
                ? "\(algorithm.rawValue) 需要一个密钥（随便一长串，越长越好）"
                : "\(algorithm.rawValue) 需要私钥（PEM，PKCS#8 或 PKCS#1 都行）")
        }

        let signature: Data
        if algorithm.isSymmetric {
            guard let keyData = keyFormat.data(from: key) else {
                throw JWTError.badKey("密钥按 \(keyFormat.title) 解不出来")
            }
            signature = try CryptoEngine.hmac(message, algorithm: algorithm.hash ?? .sha256, keyData: keyData)
        } else if algorithm.family == "ECDSA" {
            signature = try signECDSA(message: message, algorithm: algorithm, keyText: key)
        } else {
            signature = try signRSA(message: message, algorithm: algorithm, keyText: key)
        }

        return signingInput + "." + base64URLEncode(signature)
    }

    private static func signECDSA(message: Data, algorithm: JWTAlgorithm, keyText: String) throws -> Data {
        switch algorithm {
        case .es256:
            guard let key = loadECPrivate(P256.Signing.PrivateKey.self, from: keyText) else { throw JWTError.badKey("P-256 私钥读不出来") }
            return try key.signature(for: message).rawRepresentation
        case .es384:
            guard let key = loadECPrivate(P384.Signing.PrivateKey.self, from: keyText) else { throw JWTError.badKey("P-384 私钥读不出来") }
            return try key.signature(for: message).rawRepresentation
        default:
            guard let key = loadECPrivate(P521.Signing.PrivateKey.self, from: keyText) else { throw JWTError.badKey("P-521 私钥读不出来") }
            return try key.signature(for: message).rawRepresentation
        }
    }

    private static func loadECPrivate<K: ECPrivateKeyProtocol>(_ type: K.Type, from text: String) -> K? {
        if let key = try? K(pemRepresentation: text) { return key }
        if let data = pemBody(text), let key = try? K(derRepresentation: data) { return key }
        return nil
    }

    private static func signRSA(message: Data, algorithm: JWTAlgorithm, keyText: String) throws -> Data {
        guard let key = loadRSAPrivate(keyText) else {
            throw JWTError.badKey("RSA 私钥读不出来，支持 PKCS#8（BEGIN PRIVATE KEY）和 PKCS#1（BEGIN RSA PRIVATE KEY）")
        }
        let secAlgorithm: SecKeyAlgorithm
        switch algorithm {
        case .rs256: secAlgorithm = .rsaSignatureMessagePKCS1v15SHA256
        case .rs384: secAlgorithm = .rsaSignatureMessagePKCS1v15SHA384
        case .rs512: secAlgorithm = .rsaSignatureMessagePKCS1v15SHA512
        case .ps256: secAlgorithm = .rsaSignatureMessagePSSSHA256
        case .ps384: secAlgorithm = .rsaSignatureMessagePSSSHA384
        default: secAlgorithm = .rsaSignatureMessagePSSSHA512
        }
        guard SecKeyIsAlgorithmSupported(key, .sign, secAlgorithm) else {
            throw JWTError.signFailed("这把私钥不支持 \(algorithm.rawValue)")
        }
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, secAlgorithm, message as CFData, &error) else {
            let reason = error.map { ($0.takeRetainedValue() as Error).localizedDescription } ?? "未知错误"
            throw JWTError.signFailed(reason)
        }
        return signature as Data
    }

    private static func loadRSAPrivate(_ text: String) -> SecKey? {
        guard let der = pemBody(text) ?? Data(base64Encoded: text) else { return nil }
        let bytes = [UInt8](der)
        // PKCS#8 外面套了一层，抠出里面的 PKCS#1
        let pkcs1 = RSADER.pkcs1(from: bytes) ?? bytes
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        return SecKeyCreateWithData(Data(pkcs1) as CFData, attributes as CFDictionary, nil)
    }

    /// 生成一对 RSA / EC 密钥，方便本地试签名
    static func generateKeyPair(algorithm: JWTAlgorithm) throws -> (privateKey: String, publicKey: String) {
        switch algorithm {
        case .es256, .es384, .es512:
            if algorithm == .es256 {
                let key = P256.Signing.PrivateKey()
                return (key.pemRepresentation, key.publicKey.pemRepresentation)
            } else if algorithm == .es384 {
                let key = P384.Signing.PrivateKey()
                return (key.pemRepresentation, key.publicKey.pemRepresentation)
            } else {
                let key = P521.Signing.PrivateKey()
                return (key.pemRepresentation, key.publicKey.pemRepresentation)
            }
        default:
            let attributes: [String: Any] = [
                kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                kSecAttrKeySizeInBits as String: 2048,
            ]
            var error: Unmanaged<CFError>?
            guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
                let reason = error.map { ($0.takeRetainedValue() as Error).localizedDescription } ?? "未知错误"
                throw JWTError.signFailed(reason)
            }
            guard let publicKey = SecKeyCopyPublicKey(privateKey),
                  let privateData = SecKeyCopyExternalRepresentation(privateKey, nil) as Data?,
                  let publicData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
                throw JWTError.signFailed("导不出密钥")
            }
            return (wrapPEM(privateData, label: "RSA PRIVATE KEY"), wrapPEM(publicData, label: "RSA PUBLIC KEY"))
        }
    }

    private static func wrapPEM(_ data: Data, label: String) -> String {
        let base64 = data.base64EncodedString()
        var lines: [String] = []
        var index = base64.startIndex
        while index < base64.endIndex {
            let next = base64.index(index, offsetBy: 64, limitedBy: base64.endIndex) ?? base64.endIndex
            lines.append(String(base64[index..<next]))
            index = next
        }
        return "-----BEGIN \(label)-----\n" + lines.joined(separator: "\n") + "\n-----END \(label)-----"
    }
}

// MARK: - 密钥协议（让上面几个泛型函数能同时适配 P-256/384/521）
//
// 签名按 CryptoKit 的 swiftinterface 抄的：全是 throws，DER 收 RandomAccessCollection<UInt8>。

protocol ECPublicKeyProtocol {
    init(pemRepresentation: String) throws
    init<D: ContiguousBytes>(x963Representation: D) throws
    init<D: RandomAccessCollection>(derRepresentation: D) throws where D.Element == UInt8
}

protocol ECPrivateKeyProtocol {
    init(pemRepresentation: String) throws
    init<D: RandomAccessCollection>(derRepresentation: D) throws where D.Element == UInt8
}

extension P256.Signing.PublicKey: ECPublicKeyProtocol {}
extension P384.Signing.PublicKey: ECPublicKeyProtocol {}
extension P521.Signing.PublicKey: ECPublicKeyProtocol {}
extension P256.Signing.PrivateKey: ECPrivateKeyProtocol {}
extension P384.Signing.PrivateKey: ECPrivateKeyProtocol {}
extension P521.Signing.PrivateKey: ECPrivateKeyProtocol {}

// MARK: - DER 小工具

/// 只干一件事：把 SPKI / PKCS#8 外壳剥掉，取出里面的 PKCS#1 RSA 密钥。
///
/// RSA 在 CryptoKit 里没有，只能走 Security；而 SecKeyCreateWithData 要的是 PKCS#1，
/// 大家从 openssl 导出来的却是外面裹了一层的 SPKI / PKCS#8，所以得自己剥。
enum RSADER {

    /// 剥壳。返回 nil 表示本来就该原样用（裸 PKCS#1）。
    static func pkcs1(from der: [UInt8]) -> [UInt8]? {
        guard let outer = readTLV(der, at: 0), outer.tag == 0x30 else { return nil }
        let children = readChildren(Array(der[outer.contentStart..<outer.end]))

        // PKCS#8 私钥：SEQUENCE { INTEGER, SEQUENCE, OCTET STRING }
        if let octet = children.first(where: { $0.tag == 0x04 }) {
            return octet.content
        }
        // SPKI 公钥：SEQUENCE { SEQUENCE, BIT STRING }
        if let bits = children.first(where: { $0.tag == 0x03 }) {
            // BIT STRING 第一个字节是"没用到的位数"，正常是 0
            guard bits.content.count > 1 else { return nil }
            return Array(bits.content.dropFirst())
        }
        // 裸 PKCS#1：顶层 SEQUENCE 里全是 INTEGER
        return nil
    }

    private static func readChildren(_ bytes: [UInt8]) -> [(tag: UInt8, content: [UInt8])] {
        var result: [(tag: UInt8, content: [UInt8])] = []
        var index = 0
        while let tlv = readTLV(bytes, at: index) {
            result.append((tlv.tag, Array(bytes[tlv.contentStart..<tlv.end])))
            if tlv.end <= index { break }        // 防死循环
            index = tlv.end
        }
        return result
    }

    /// 读一个 TLV：标签、内容起点、内容长度、整体结束位置
    static func readTLV(_ bytes: [UInt8], at index: Int) -> (tag: UInt8, contentStart: Int, end: Int)? {
        guard index >= 0, index < bytes.count else { return nil }
        var cursor = index
        var tag = bytes[cursor]
        cursor += 1
        // 高位全是 1 表示多字节标签，RSA/EC 密钥里见不到，直接跳过
        if tag & 0x1F == 0x1F {
            while cursor < bytes.count, bytes[cursor] & 0x80 != 0 { cursor += 1 }
            cursor += 1
            tag = bytes[index]
        }
        guard cursor < bytes.count else { return nil }
        var length = Int(bytes[cursor])
        cursor += 1
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard count > 0, count <= 4, cursor + count <= bytes.count else { return nil }
            length = 0
            for _ in 0..<count {
                length = (length << 8) | Int(bytes[cursor])
                cursor += 1
            }
        }
        guard cursor + length <= bytes.count else { return nil }
        return (tag, cursor, cursor + length)
    }
}
