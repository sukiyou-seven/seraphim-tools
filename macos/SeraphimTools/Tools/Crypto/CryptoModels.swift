import Foundation

// MARK: - 摘要算法

enum HashAlgorithm: String, CaseIterable, Identifiable {
    case md5
    case sha1
    case sha256
    case sha384
    case sha512
    case crc32

    var id: String { rawValue }

    var title: String {
        switch self {
        case .md5: return "MD5"
        case .sha1: return "SHA-1"
        case .sha256: return "SHA-256"
        case .sha384: return "SHA-384"
        case .sha512: return "SHA-512"
        case .crc32: return "CRC32"
        }
    }

    var digestLength: Int {
        switch self {
        case .md5: return 16
        case .sha1: return 20
        case .sha256: return 32
        case .sha384: return 48
        case .sha512: return 64
        case .crc32: return 4
        }
    }

    /// 已经被攻破或不再推荐用于安全用途的算法，界面上要提醒
    var isWeak: Bool {
        self == .md5 || self == .sha1
    }

    /// CRC32 是校验和不是密码学摘要，配 HMAC 没有意义
    var supportsHMAC: Bool {
        self != .crc32
    }

    var summary: String {
        switch self {
        case .md5: return "速度最快，但碰撞已经被玩烂了，只适合校验完整性"
        case .sha1: return "曾经的标准，现在也不安全了，新项目别用"
        case .sha256: return "当前最通用的选择，签名、校验、去重都用它"
        case .sha384: return "SHA-512 截断版，强度够、长度不夸张"
        case .sha512: return "64 字节摘要，追求强度就用它"
        case .crc32: return "32 位校验和，用于检测传输错误，抗不了恶意篡改"
        }
    }
}

// MARK: - 对称加密

enum SymmetricAlgorithm: String, CaseIterable, Identifiable {
    case aesGCM = "aes-gcm"
    case aesCBC = "aes-cbc"
    case chacha = "chacha20"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aesGCM: return "AES-256-GCM"
        case .aesCBC: return "AES-256-CBC"
        case .chacha: return "ChaCha20-Poly1305"
        }
    }

    var isAuthenticated: Bool {
        self != .aesCBC
    }

    var summary: String {
        switch self {
        case .aesGCM: return "带认证的现代标准，改一个字节都解得开不了，首选"
        case .aesCBC: return "老派但兼容性最好，注意它不防篡改"
        case .chacha: return "软件实现比 AES 快，移动端和没有 AES 加速的机器上更合适"
        }
    }
}

/// 密钥来源
enum KeySource: String, CaseIterable, Identifiable {
    case passphrase
    case rawKey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .passphrase: return "口令"
        case .rawKey: return "原始密钥"
        }
    }
}

// MARK: - 古典密码

enum ClassicCipher: String, CaseIterable, Identifiable {
    case caesar
    case rot13
    case vigenere
    case xor
    case morse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .caesar: return "凯撒密码"
        case .rot13: return "ROT13"
        case .vigenere: return "维吉尼亚"
        case .xor: return "异或 XOR"
        case .morse: return "摩斯电码"
        }
    }

    /// 需要密钥 / 位移的密码，界面上要显示对应的输入框
    var needsKey: Bool {
        self == .vigenere || self == .xor
    }

    var needsShift: Bool {
        self == .caesar
    }

    var summary: String {
        switch self {
        case .caesar: return "把字母表整体平移几位，暴力破解只需要试 25 次"
        case .rot13: return "凯撒位移 13 的特例，加一次解一次，天生自逆"
        case .vigenere: return "用密钥字母决定每个位置的位移量，破译要难得多"
        case .xor: return "逐字节异或，密钥重复使用。加密解密是同一个操作"
        case .morse: return "点和划的编码，字母之间空格、单词之间斜杠"
        }
    }
}

// MARK: - XOR 输出格式

enum XORFormat: String, CaseIterable, Identifiable {
    case hex
    case base64
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hex: return "十六进制"
        case .base64: return "Base64"
        case .text: return "原样文本"
        }
    }
}

// MARK: - 错误

enum CryptoError: LocalizedError {
    case emptyInput
    case unsupportedHMAC
    case keyDerivationFailed
    case badKey
    case badKeyLength(Int)
    case cipherFailed(Int)
    case badCiphertextFormat
    case unknownAlgorithm(String)
    case decryptFailed
    case emptyKey

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "先输入点内容。"
        case .unsupportedHMAC:
            return "CRC32 不是密码学摘要，没法配 HMAC。"
        case .keyDerivationFailed:
            return "密钥派生失败了，换个口令试试。"
        case .badKey:
            return "密钥读不出来。原始密钥要填 64 位十六进制，或者 Base64 编码的 32 字节。"
        case .badKeyLength(let length):
            return "密钥长度不对：AES-256 需要 32 字节，当前是 \(length) 字节。"
        case .cipherFailed(let status):
            return "加解密失败（CommonCrypto 状态码 \(status)）。"
        case .badCiphertextFormat:
            return "密文格式不对，应该是以 STM1. 开头的完整内容，检查是不是复制漏了。"
        case .unknownAlgorithm(let name):
            return "密文标记的算法 “\(name)” 这个版本还不认识。"
        case .decryptFailed:
            return "解不开。要么口令错了，要么内容被改动过、或者复制不完整。"
        case .emptyKey:
            return "密钥不能是空的。"
        }
    }
}
