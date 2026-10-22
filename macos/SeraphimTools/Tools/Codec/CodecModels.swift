import CoreFoundation
import Foundation

// MARK: - 字符集

enum TextCharset: String, CaseIterable, Identifiable {
    case utf8
    case utf16
    case utf16LE
    case utf16BE
    case utf32
    case ascii
    case latin1
    case windows1252
    case gb18030
    case big5
    case shiftJIS
    case eucKR
    case macRoman

    var id: String { rawValue }

    var title: String {
        switch self {
        case .utf8: return "UTF-8"
        case .utf16: return "UTF-16（带 BOM）"
        case .utf16LE: return "UTF-16 LE"
        case .utf16BE: return "UTF-16 BE"
        case .utf32: return "UTF-32"
        case .ascii: return "ASCII"
        case .latin1: return "ISO-8859-1"
        case .windows1252: return "Windows-1252"
        case .gb18030: return "GB18030 / GBK"
        case .big5: return "Big5（繁体）"
        case .shiftJIS: return "Shift-JIS（日文）"
        case .eucKR: return "EUC-KR（韩文）"
        case .macRoman: return "Mac Roman"
        }
    }

    var encoding: String.Encoding {
        switch self {
        case .utf8: return .utf8
        case .utf16: return .utf16
        case .utf16LE: return .utf16LittleEndian
        case .utf16BE: return .utf16BigEndian
        case .utf32: return .utf32
        case .ascii: return .ascii
        case .latin1: return .isoLatin1
        case .windows1252: return .windowsCP1252
        case .gb18030: return TextCharset.coreFoundation(.GB_18030_2000)
        case .big5: return TextCharset.coreFoundation(.big5)
        case .shiftJIS: return .shiftJIS
        case .eucKR: return TextCharset.coreFoundation(.EUC_KR)
        case .macRoman: return .macOSRoman
        }
    }

    /// 系统里那批老编码得从 CoreFoundation 借
    private static func coreFoundation(_ value: CFStringEncodings) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(value.rawValue)))
    }
}

// MARK: - 字节分隔符

/// Hex / 二进制这类"逐字节输出"的编码，字节之间怎么隔开
enum ByteSeparator: String, CaseIterable, Identifiable {
    case none
    case space
    case colon
    case dash
    case comma
    case newline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "无"
        case .space: return "空格"
        case .colon: return "冒号"
        case .dash: return "短横"
        case .comma: return "逗号"
        case .newline: return "换行"
        }
    }

    var string: String {
        switch self {
        case .none: return ""
        case .space: return " "
        case .colon: return ":"
        case .dash: return "-"
        case .comma: return ", "
        case .newline: return "\n"
        }
    }
}

// MARK: - 编码算法

enum CodecAlgorithm: String, CaseIterable, Identifiable {
    case base64
    case url
    case hex
    case base32
    case binary
    case octal
    case decimal
    case html
    case unicode
    case jsonString

    var id: String { rawValue }

    var title: String {
        switch self {
        case .base64: return "Base64"
        case .url: return "URL 编码"
        case .hex: return "十六进制"
        case .base32: return "Base32"
        case .binary: return "二进制"
        case .octal: return "八进制"
        case .decimal: return "十进制字节"
        case .html: return "HTML 实体"
        case .unicode: return "Unicode 转义"
        case .jsonString: return "JSON 字符串"
        }
    }

    var systemImage: String {
        switch self {
        case .base64: return "textformat.abc"
        case .url: return "link"
        case .hex: return "number"
        case .base32: return "textformat.123"
        case .binary: return "circle.grid.2x2"
        case .octal: return "circle.grid.3x3"
        case .decimal: return "list.number"
        case .html: return "chevron.left.forwardslash.chevron.right"
        case .unicode: return "character.cursor.ibeam"
        case .jsonString: return "curlybraces"
        }
    }

    var summary: String {
        switch self {
        case .base64: return "把任意字节装进 64 个可见字符里，邮件、图片内联最常用"
        case .url: return "百分号转义，放进 URL 里不会被截断"
        case .hex: return "每字节两个十六进制字符，看二进制数据最直观"
        case .base32: return "只用大写字母和数字 2–7，不区分大小写的场合用它"
        case .binary: return "每字节 8 位 0/1，看位运算和掩码用"
        case .octal: return "每字节三位八进制，Unix 权限位那种写法"
        case .decimal: return "每字节一个 0–255 的十进制数"
        case .html: return "把 & < > 这些符号转成实体，插进网页不会破坏结构"
        case .unicode: return "把非 ASCII 字符转成 \\uXXXX，塞进只认 ASCII 的地方"
        case .jsonString: return "加引号并转义控制字符，直接能贴进 JSON 里"
        }
    }

    /// 一键示例：(原文, 编码结果)。点「示例」按钮填进输入框，省得自己想测试数据。
    var sample: (plain: String, encoded: String) {
        switch self {
        case .base64:
            return ("爸爸的工具箱 🧰", "54i45aaI55qE5bel5YW3566xIPCfpLA=")
        case .url:
            return ("搜索 关键词 & 参数=值", "%E6%90%9C%E7%B4%A2%20%E5%85%B3%E9%94%AE%E8%AF%8D%20%26%20%E5%8F%82%E6%95%B0%3D%E5%80%BC")
        case .hex:
            return ("Seraphim", "53 65 72 61 70 68 69 6D")
        case .base32:
            return ("Hello", "JBSWY3DP")
        case .binary:
            return ("Hi", "01001000 01101001")
        case .octal:
            return ("Hi", "110 151")
        case .decimal:
            return ("Hi", "72 105")
        case .html:
            return ("<a href=\"x\">&</a>", "&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;")
        case .unicode:
            return ("中文 abc", "\\u4E2D\\u6587 abc")
        case .jsonString:
            return ("行1\n行2\t\"引用\"", "\"行1\\n行2\\t\\\"引用\\\"\"")
        }
    }
}

// MARK: - 选项

struct CodecOptions {
    // Base64
    var base64URLSafe = false
    var base64KeepPadding = true
    var base64Wrap76 = false

    // URL
    var urlStrict = true
    /// 解码时是否把 + 当作空格（application/x-www-form-urlencoded 的规矩）
    var urlPlusAsSpace = false

    // Hex / 二进制 / 八进制 / 十进制
    var hexUppercase = true
    var hexPrefix = false
    var separator: ByteSeparator = .none
    /// 每行放几个字节，0 表示不换行
    var wrapEvery = 0

    // HTML
    var htmlNumericOnly = false

    // Unicode
    var unicodeBraced = false
    var unicodeEscapeASCII = false

    // JSON
    var jsonEscapeUnicode = false
}

// MARK: - 错误

enum CodecError: LocalizedError {
    case invalidBase64
    case invalidBase32(String)
    case invalidDigits(radix: Int, width: Int, found: Int)
    case invalidByteValue(String)
    case invalidPercentEncoding
    case invalidUnicodeEscape(String)
    case invalidJSON
    case notValidText(String)

    var errorDescription: String? {
        switch self {
        case .invalidBase64:
            return "这不是合法的 Base64 内容，检查一下是不是复制漏了字符。"
        case .invalidBase32(let token):
            return "“\(token)” 里出现了 Base32 不认识的字符（只允许 A–Z 和 2–7）。"
        case .invalidDigits(let radix, let width, let found):
            return "位数对不上：\(radix) 进制下每 \(width) 个字符代表一个字节，现在有 \(found) 个有效字符。"
        case .invalidByteValue(let token):
            return "“\(token)”不是 0–255 之间的字节值。"
        case .invalidPercentEncoding:
            return "百分号编码不完整，可能是孤立的 % 或者截断的字节。"
        case .invalidUnicodeEscape(let token):
            return "转义序列 “\(token)” 解析不出字符。"
        case .invalidJSON:
            return "这不是合法的 JSON 字符串内容，注意引号和控制字符都需要转义。"
        case .notValidText(let name):
            return "解码出来的字节不是合法的 \(name) 文本，可能内容本身是二进制数据。"
        }
    }
}
