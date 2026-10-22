import CommonCrypto
import CryptoKit
import Foundation
import Security

/// 加密解密引擎。纯函数，方便单独测试。
enum CryptoEngine {

    // MARK: - 随机

    /// 系统级随机字节（密码学安全）
    static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: max(0, count))
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            var generator = SystemRandomNumberGenerator()
            for index in bytes.indices {
                bytes[index] = UInt8.random(in: 0...255, using: &generator)
            }
        }
        return Data(bytes)
    }

    /// 从给定字符表里随机挑，等概率不偏斜
    static func randomPassword(length: Int, alphabet: String) -> String {
        let characters = Array(alphabet)
        guard !characters.isEmpty, length > 0 else { return "" }
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in characters.randomElement(using: &generator) ?? characters[0] })
    }

    // MARK: - 摘要

    static func digest(_ data: Data, algorithm: HashAlgorithm) -> Data {
        switch algorithm {
        case .md5: return Data(Insecure.MD5.hash(data: data))
        case .sha1: return Data(Insecure.SHA1.hash(data: data))
        case .sha256: return Data(SHA256.hash(data: data))
        case .sha384: return Data(SHA384.hash(data: data))
        case .sha512: return Data(SHA512.hash(data: data))
        case .crc32:
            var value = crc32(data).bigEndian
            return withUnsafeBytes(of: &value) { Data($0) }
        }
    }

    static func digest(_ text: String, algorithm: HashAlgorithm) -> Data {
        digest(Data(text.utf8), algorithm: algorithm)
    }

    static func hmac(_ data: Data, algorithm: HashAlgorithm, key: String) throws -> Data {
        try hmac(data, algorithm: algorithm, keyData: Data(key.utf8))
    }

    /// 密钥是二进制时用这个（JWKS 里的 k、RFC 测试向量都是 base64url 的字节）
    static func hmac(_ data: Data, algorithm: HashAlgorithm, keyData: Data) throws -> Data {
        guard !keyData.isEmpty else { throw CryptoError.emptyKey }
        guard algorithm.supportsHMAC else { throw CryptoError.unsupportedHMAC }
        let symmetricKey = SymmetricKey(data: keyData)
        switch algorithm {
        case .md5:
            return Data(HMAC<Insecure.MD5>.authenticationCode(for: data, using: symmetricKey))
        case .sha1:
            return Data(HMAC<Insecure.SHA1>.authenticationCode(for: data, using: symmetricKey))
        case .sha256:
            return Data(HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey))
        case .sha384:
            return Data(HMAC<SHA384>.authenticationCode(for: data, using: symmetricKey))
        case .sha512:
            return Data(HMAC<SHA512>.authenticationCode(for: data, using: symmetricKey))
        case .crc32:
            throw CryptoError.unsupportedHMAC
        }
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    // MARK: - 对称加密

    /// 密文封装格式：`STM1.<算法>.<salt 或 ->.<base64 payload>`
    ///
    /// 把算法和 salt 一起塞进密文，解密时就不用用户再选一遍参数，
    /// 也能自动认出是口令模式还是原始密钥模式（salt 为空就是后者）。
    private static let envelopePrefix = "STM1"
    private static let pbkdf2Rounds = 100_000

    static func encrypt(
        plaintext: String,
        secret: String,
        source: KeySource,
        algorithm: SymmetricAlgorithm
    ) throws -> String {
        guard !secret.isEmpty else { throw CryptoError.emptyKey }
        let plain = Data(plaintext.utf8)

        let salt = source == .passphrase ? randomBytes(16) : Data()
        let key = try makeKey(secret: secret, salt: salt, source: source)

        let payload: Data
        switch algorithm {
        case .aesGCM:
            let sealed = try AES.GCM.seal(plain, using: key)
            guard let combined = sealed.combined else { throw CryptoError.cipherFailed(-1) }
            payload = combined
        case .chacha:
            let sealed = try ChaChaPoly.seal(plain, using: key)
            payload = sealed.combined
        case .aesCBC:
            let iv = randomBytes(kCCBlockSizeAES128)
            payload = iv + (try aesCBC(plain, key: key, iv: iv, encrypt: true))
        }

        let saltPart = salt.isEmpty ? "-" : salt.base64EncodedString()
        return "\(envelopePrefix).\(algorithm.rawValue).\(saltPart).\(payload.base64EncodedString())"
    }

    static func decrypt(_ ciphertext: String, secret: String) throws -> String {
        guard !secret.isEmpty else { throw CryptoError.emptyKey }

        let compact = ciphertext
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[\\s\\n\\r]", with: "", options: .regularExpression)
        let parts = compact.components(separatedBy: ".")
        guard parts.count == 4, parts[0] == envelopePrefix else {
            throw CryptoError.badCiphertextFormat
        }
        guard let algorithm = SymmetricAlgorithm(rawValue: parts[1]) else {
            throw CryptoError.unknownAlgorithm(parts[1])
        }
        guard let payload = Data(base64Encoded: parts[3]) else {
            throw CryptoError.badCiphertextFormat
        }

        let salt = parts[2] == "-" ? Data() : Data(base64Encoded: parts[2])
        guard let salt else { throw CryptoError.badCiphertextFormat }
        let source: KeySource = salt.isEmpty ? .rawKey : .passphrase
        let key = try makeKey(secret: secret, salt: salt, source: source)

        let plain: Data
        switch algorithm {
        case .aesGCM:
            guard let box = try? AES.GCM.SealedBox(combined: payload) else {
                throw CryptoError.badCiphertextFormat
            }
            guard let opened = try? AES.GCM.open(box, using: key) else {
                throw CryptoError.decryptFailed
            }
            plain = opened
        case .chacha:
            guard let box = try? ChaChaPoly.SealedBox(combined: payload) else {
                throw CryptoError.badCiphertextFormat
            }
            guard let opened = try? ChaChaPoly.open(box, using: key) else {
                throw CryptoError.decryptFailed
            }
            plain = opened
        case .aesCBC:
            let blockSize = kCCBlockSizeAES128
            guard payload.count > blockSize, (payload.count - blockSize) % blockSize == 0 else {
                throw CryptoError.badCiphertextFormat
            }
            let iv = payload.prefix(blockSize)
            let body = payload.dropFirst(blockSize)
            guard let opened = try? aesCBC(Data(body), key: key, iv: Data(iv), encrypt: false) else {
                throw CryptoError.decryptFailed
            }
            plain = opened
        }

        guard let text = String(data: plain, encoding: .utf8) else {
            throw CryptoError.decryptFailed
        }
        return text
    }

    /// 口令 → PBKDF2-SHA256 派生 32 字节；原始密钥 → 直接解析
    static func makeKey(secret: String, salt: Data, source: KeySource) throws -> SymmetricKey {
        if source == .rawKey {
            guard let data = parseRawKey(secret) else { throw CryptoError.badKey }
            guard data.count == 32 else { throw CryptoError.badKeyLength(data.count) }
            return SymmetricKey(data: data)
        }
        guard let derived = deriveKey(passphrase: secret, salt: salt) else {
            throw CryptoError.keyDerivationFailed
        }
        return SymmetricKey(data: derived)
    }

    /// 原始密钥接受 64 位十六进制，或者 Base64 编码的 32 字节
    static func parseRawKey(_ text: String) -> Data? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[\\s:]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)

        let isHex = !cleaned.isEmpty && cleaned.allSatisfy { $0.isHexDigit }
        if isHex, cleaned.count % 2 == 0, let data = Data(hexString: cleaned), !data.isEmpty {
            return data
        }
        if let data = Data(base64Encoded: cleaned, options: [.ignoreUnknownCharacters]), !data.isEmpty {
            return data
        }
        return nil
    }

    static func deriveKey(passphrase: String, salt: Data, rounds: Int = pbkdf2Rounds, length: Int = 32) -> Data? {
        guard !salt.isEmpty else { return nil }
        var derived = Data(count: length)
        let status: Int32 = passphrase.withCString { password in
            salt.withUnsafeBytes { saltBuffer -> Int32 in
                derived.withUnsafeMutableBytes { keyBuffer -> Int32 in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        password,
                        strlen(password),
                        saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(rounds),
                        keyBuffer.bindMemory(to: UInt8.self).baseAddress,
                        length
                    )
                }
            }
        }
        return status == kCCSuccess ? derived : nil
    }

    /// AES-CBC + PKCS7。CryptoKit 不管 CBC，只能借 CommonCrypto。
    private static func aesCBC(_ data: Data, key: SymmetricKey, iv: Data, encrypt: Bool) throws -> Data {
        let keyData = key.withUnsafeBytes { Data($0) }
        var output = Data(count: data.count + kCCBlockSizeAES128)
        var moved = 0

        let status: CCCryptorStatus = output.withUnsafeMutableBytes { outputBuffer in
            data.withUnsafeBytes { dataBuffer in
                keyData.withUnsafeBytes { keyBuffer in
                    iv.withUnsafeBytes { ivBuffer in
                        CCCrypt(
                            CCOperation(encrypt ? kCCEncrypt : kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuffer.baseAddress, keyData.count,
                            ivBuffer.baseAddress,
                            dataBuffer.baseAddress, data.count,
                            outputBuffer.baseAddress, outputBuffer.count,
                            &moved
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { throw CryptoError.cipherFailed(Int(status)) }
        output.removeSubrange(moved...)
        return output
    }

    // MARK: - 古典密码

    /// 凯撒位移。shift 为负就是反向。
    static func caesar(_ text: String, shift: Int) -> String {
        let normalized = ((shift % 26) + 26) % 26
        guard normalized != 0 else { return text }
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 65...90:
                result.unicodeScalars.append(Unicode.Scalar(65 + (scalar.value - 65 + UInt32(normalized)) % 26)!)
            case 97...122:
                result.unicodeScalars.append(Unicode.Scalar(97 + (scalar.value - 97 + UInt32(normalized)) % 26)!)
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    /// 把 25 种位移全列出来，密码题里最好用的一招
    static func caesarAllShifts(_ text: String) -> [(shift: Int, text: String)] {
        (1...25).map { (shift: $0, text: caesar(text, shift: $0)) }
    }

    /// 维吉尼亚。密钥里只取字母，非字母位置不消耗密钥。
    static func vigenere(_ text: String, key: String, decode: Bool) -> String {
        let shifts = key.uppercased().unicodeScalars.compactMap { scalar -> Int? in
            guard (65...90).contains(scalar.value) else { return nil }
            return Int(scalar.value - 65)
        }
        guard !shifts.isEmpty else { return text }

        var result = ""
        var cursor = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 65...90, 97...122:
                let base: UInt32 = scalar.value >= 97 ? 97 : 65
                let offset = Int(scalar.value - base)
                let shift = shifts[cursor % shifts.count] * (decode ? -1 : 1)
                let shifted = ((offset + shift) % 26 + 26) % 26
                result.unicodeScalars.append(Unicode.Scalar(base + UInt32(shifted))!)
                cursor += 1
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    /// 异或加密（同一个操作也是解密）
    static func xorBytes(_ data: Data, key: String) -> Data {
        let keyBytes = [UInt8](key.utf8)
        guard !keyBytes.isEmpty else { return data }
        var output = [UInt8](repeating: 0, count: data.count)
        for (index, byte) in data.enumerated() {
            output[index] = byte ^ keyBytes[index % keyBytes.count]
        }
        return Data(output)
    }

    static func xorEncode(_ text: String, key: String, format: XORFormat) -> String {
        let encrypted = xorBytes(Data(text.utf8), key: key)
        switch format {
        case .hex:
            return encrypted.map { String(format: "%02X", $0) }.joined()
        case .base64:
            return encrypted.base64EncodedString()
        case .text:
            if let string = String(data: encrypted, encoding: .utf8) { return string }
            return encrypted.map { String(format: "%02X", $0) }.joined()
        }
    }

    /// 解密时自动认格式：纯十六进制就当 hex，否则试 Base64，再不行按原样字节处理
    static func xorDecode(_ text: String, key: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = trimmed.replacingOccurrences(of: "[\\s:]", with: "", options: .regularExpression)

        var bytes: Data
        if !compact.isEmpty,
           compact.count % 2 == 0,
           compact.allSatisfy({ $0.isHexDigit }),
           let decoded = Data(hexString: compact) {
            bytes = decoded
        } else if let decoded = Data(base64Encoded: compact, options: [.ignoreUnknownCharacters]), !decoded.isEmpty {
            bytes = decoded
        } else {
            bytes = Data(trimmed.utf8)
        }

        let plain = xorBytes(bytes, key: key)
        if let string = String(data: plain, encoding: .utf8) { return string }
        // 不像文本就按十六进制展示，至少能看出字节
        return plain.map { String(format: "%02X", $0) }.joined()
    }

    // MARK: 摩斯电码

    private static let morseTable: [Character: String] = [
        "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".",
        "F": "..-.", "G": "--.", "H": "....", "I": "..", "J": ".---",
        "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---",
        "P": ".--.", "Q": "--.-", "R": ".-.", "S": "...", "T": "-",
        "U": "..-", "V": "...-", "W": ".--", "X": "-..-", "Y": "-.--",
        "Z": "--..",
        "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
        "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
        ".": ".-.-.-", ",": "--..--", "?": "..--..", "'": ".----.",
        "!": "-.-.--", "/": "-..-.", "(": "-.--.", ")": "-.--.-",
        "&": ".-...", ":": "---...", ";": "-.-.-.", "=": "-...-",
        "+": ".-.-.", "-": "-....-", "_": "..--.-", "\"": ".-..-.",
        "$": "...-..-", "@": ".--.-.",
    ]

    static func morseEncode(_ text: String) -> String {
        let words = text
            .uppercased()
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return words.map { word in
            word.compactMap { morseTable[$0] }.joined(separator: " ")
        }.joined(separator: " / ")
    }

    static func morseDecode(_ text: String) -> String {
        var reverse: [String: Character] = [:]
        for (character, code) in morseTable where reverse[code] == nil {
            reverse[code] = character
        }
        return text
            .components(separatedBy: "/")
            .map { word in
                word.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
                    .compactMap { reverse[String($0)] }
                    .map(String.init)
                    .joined()
            }
            .joined(separator: " ")
    }
}

// MARK: - 十六进制工具

extension Data {
    /// 宽松解析十六进制串（调用方保证只含 hex 字符）
    init?(hexString: String) {
        let characters = Array(hexString)
        guard characters.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(characters.count / 2)
        var index = 0
        while index < characters.count {
            guard let value = UInt8(String(characters[index...index + 1]), radix: 16) else { return nil }
            bytes.append(value)
            index += 2
        }
        self = Data(bytes)
    }
}
