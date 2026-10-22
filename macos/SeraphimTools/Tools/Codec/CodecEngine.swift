import Foundation

/// 编码解码引擎。纯函数，无状态，方便单独测试。
enum CodecEngine {

    // MARK: - 对外入口

    static func encode(_ text: String, algorithm: CodecAlgorithm, options: CodecOptions) throws -> String {
        guard !text.isEmpty else { return "" }
        switch algorithm {
        case .base64: return base64Encode(text, options: options)
        case .url: return urlEncode(text, options: options)
        case .hex: return byteEncode(text, radix: 16, options: options)
        case .binary: return byteEncode(text, radix: 2, options: options)
        case .octal: return byteEncode(text, radix: 8, options: options)
        case .decimal: return byteEncode(text, radix: 10, options: options)
        case .base32: return base32Encode(Data(text.utf8))
        case .html: return htmlEncode(text, options: options)
        case .unicode: return unicodeEncode(text, options: options)
        case .jsonString: return jsonEncode(text, options: options)
        }
    }

    static func decode(_ text: String, algorithm: CodecAlgorithm, options: CodecOptions) throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }

        // 这几个算法直接产出字符串，剩下的先还原成字节再按文本解释
        switch algorithm {
        case .url: return try urlDecode(text, options: options)
        case .html: return htmlDecode(text)
        case .unicode: return try unicodeDecode(text)
        case .jsonString: return try jsonDecode(text)
        default: break
        }

        let data: Data
        switch algorithm {
        case .base64: data = try base64Decode(text)
        case .hex: data = try byteDecode(text, radix: 16)
        case .binary: data = try byteDecode(text, radix: 2)
        case .octal: data = try byteDecode(text, radix: 8)
        case .decimal: data = try decimalDecode(text)
        case .base32: data = try base32Decode(text)
        default: data = Data()
        }
        guard let string = Self.decodeText(from: data) else {
            throw CodecError.notValidText("UTF-8 / GB18030")
        }
        return string
    }

    /// 字节 → 文本。UTF-8 解不出来时用 GB18030 兜一层（中文场景常见）。
    private static func decodeText(from data: Data) -> String? {
        guard !data.isEmpty else { return "" }
        if let string = String(data: data, encoding: .utf8) { return string }
        return String(data: data, encoding: TextCharset.gb18030.encoding)
    }

    // MARK: - Base64

    static func base64Encode(_ text: String, options: CodecOptions) -> String {
        var result = Data(text.utf8).base64EncodedString()
        if options.base64URLSafe {
            result = result
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
        }
        if !options.base64KeepPadding {
            result = result.replacingOccurrences(of: "=", with: "")
        }
        if options.base64Wrap76 {
            result = wrap(result, every: 76)
        }
        return result
    }

    /// 宽容解码：吃掉 Data URL 前缀、空白、引号，兼容 URL-safe 变体，自动补 padding
    static func base64Decode(_ raw: String) throws -> Data {
        var text = raw
        if let range = text.range(of: "base64,") {
            text = String(text[range.upperBound...])
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'` "))
        text = text.replacingOccurrences(of: "[^A-Za-z0-9+/=_-]", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")

        if text.count % 4 == 1 {
            // 余 1 说明尾部是残缺字符，丢掉再补 padding
            text = String(text.dropLast())
        }
        if text.count % 4 != 0 {
            text += String(repeating: "=", count: 4 - text.count % 4)
        }

        guard let data = Data(base64Encoded: text, options: [.ignoreUnknownCharacters]) else {
            throw CodecError.invalidBase64
        }
        return data
    }

    // MARK: - URL

    static func urlEncode(_ text: String, options: CodecOptions) -> String {
        let allowed: CharacterSet
        if options.urlStrict {
            var set = CharacterSet.alphanumerics
            set.insert(charactersIn: "-._~")
            allowed = set
        } else {
            allowed = .urlQueryAllowed
        }
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    static func urlDecode(_ text: String, options: CodecOptions) throws -> String {
        var body = text
        if options.urlPlusAsSpace {
            body = body.replacingOccurrences(of: "+", with: " ")
        }
        guard let result = body.removingPercentEncoding else {
            throw CodecError.invalidPercentEncoding
        }
        return result
    }

    // MARK: - 字节进制（Hex / 二进制 / 八进制 / 十进制）

    static func byteEncode(_ text: String, radix: Int, options: CodecOptions) -> String {
        let bytes = [UInt8](text.utf8)
        guard !bytes.isEmpty else { return "" }

        var separator = options.separator.string
        // 十六进制连着写很常见（48656C6C6F），但二进制/八进制/十进制不隔开就没法看
        if radix != 16, options.separator == .none { separator = " " }
        // 带 0x 前缀却没有分隔符会糊成一团
        if radix == 16, options.hexPrefix, options.separator == .none { separator = " " }

        let tokens: [String] = bytes.map { byte in
            switch radix {
            case 2:
                return pad(String(byte, radix: 2), to: 8)
            case 8:
                return pad(String(byte, radix: 8), to: 3)
            case 16:
                let hex = pad(String(byte, radix: 16, uppercase: options.hexUppercase), to: 2)
                guard options.hexPrefix else { return hex }
                return (options.hexUppercase ? "0X" : "0x") + hex
            default:
                return String(byte)
            }
        }

        guard options.wrapEvery > 0, options.separator != .newline else {
            return tokens.joined(separator: separator)
        }
        return stride(from: 0, to: tokens.count, by: options.wrapEvery).map { start in
            tokens[start..<min(start + options.wrapEvery, tokens.count)].joined(separator: separator)
        }.joined(separator: "\n")
    }

    static func byteDecode(_ raw: String, radix: Int) throws -> Data {
        let allowed: Set<Character>
        let width: Int
        switch radix {
        case 2:  allowed = Set("01"); width = 8
        case 8:  allowed = Set("01234567"); width = 3
        case 16: allowed = Set("0123456789abcdefABCDEF"); width = 2
        default: throw CodecError.invalidDigits(radix: radix, width: 0, found: 0)
        }

        // 先把 0x / 0X 前缀抠掉，不然 'x' 会被当成噪声，留下的 0 会多出一位
        var cleaned = raw.replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
        cleaned = String(cleaned.filter { allowed.contains($0) })

        guard !cleaned.isEmpty else {
            throw CodecError.invalidDigits(radix: radix, width: width, found: 0)
        }
        guard cleaned.count % width == 0 else {
            throw CodecError.invalidDigits(radix: radix, width: width, found: cleaned.count)
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(cleaned.count / width)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: width)
            let chunk = String(cleaned[index..<next])
            guard let value = UInt8(chunk, radix: radix) else {
                throw CodecError.invalidDigits(radix: radix, width: width, found: cleaned.count)
            }
            bytes.append(value)
            index = next
        }
        return Data(bytes)
    }

    static func decimalDecode(_ raw: String) throws -> Data {
        let tokens = raw.split(whereSeparator: { !$0.isNumber })
        guard !tokens.isEmpty else {
            throw CodecError.invalidDigits(radix: 10, width: 1, found: 0)
        }
        var bytes: [UInt8] = []
        for token in tokens {
            guard let value = Int(token), (0...255).contains(value) else {
                throw CodecError.invalidByteValue(String(token))
            }
            bytes.append(UInt8(value))
        }
        return Data(bytes)
    }

    // MARK: - Base32（RFC 4648）

    private static let base32Alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func base32Encode(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        var result = ""
        var buffer = 0
        var bitsLeft = 0

        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bitsLeft += 8
            while bitsLeft >= 5 {
                bitsLeft -= 5
                let index = (buffer >> bitsLeft) & 0x1F
                result.append(base32Alphabet[index])
            }
            buffer &= (1 << bitsLeft) - 1
        }
        if bitsLeft > 0 {
            let index = (buffer << (5 - bitsLeft)) & 0x1F
            result.append(base32Alphabet[index])
        }
        while result.count % 8 != 0 { result.append("=") }
        return result
    }

    static func base32Decode(_ raw: String) throws -> Data {
        let cleaned = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard !cleaned.isEmpty else {
            throw CodecError.invalidBase32(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12).description)
        }

        var bytes: [UInt8] = []
        var buffer = 0
        var bitsLeft = 0
        for character in cleaned {
            guard let index = base32Alphabet.firstIndex(of: character) else {
                throw CodecError.invalidBase32(String(character))
            }
            buffer = (buffer << 5) | index
            bitsLeft += 5
            if bitsLeft >= 8 {
                bitsLeft -= 8
                bytes.append(UInt8((buffer >> bitsLeft) & 0xFF))
                buffer &= (1 << bitsLeft) - 1
            }
        }
        return Data(bytes)
    }

    // MARK: - HTML 实体

    static func htmlEncode(_ text: String, options: CodecOptions) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default:
                if scalar.value <= 0x7E {
                    // ASCII 可打印字符保持原样，省得满屏都是实体
                    result.unicodeScalars.append(scalar)
                } else if !options.htmlNumericOnly, let name = HTMLNamedEntities.name(for: scalar) {
                    result += "&\(name);"
                } else {
                    result += "&#\(scalar.value);"
                }
            }
        }
        return result
    }

    static func htmlDecode(_ text: String) -> String {
        var result = ""
        var index = text.startIndex

        while let amp = text[index...].firstIndex(of: "&") {
            result += text[index..<amp]
            // 实体最长也就 &CounterClockwiseContourIntegral; 这种，限制一下扫描范围避免吃掉整篇文章
            guard let semicolon = text[amp...].firstIndex(of: ";"),
                  text.distance(from: amp, to: semicolon) <= 32 else {
                result.append("&")
                index = text.index(after: amp)
                continue
            }
            let body = String(text[text.index(after: amp)..<semicolon])
            if let decoded = decodeEntity(body) {
                result += decoded
                index = text.index(after: semicolon)
            } else {
                result.append("&")
                index = text.index(after: amp)
            }
        }
        result += text[index...]
        return result
    }

    private static func decodeEntity(_ body: String) -> String? {
        guard !body.isEmpty else { return nil }
        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            if digits.isEmpty { return nil }
            let value: UInt32?
            if digits.hasPrefix("x") || digits.hasPrefix("X") {
                value = UInt32(digits.dropFirst(), radix: 16)
            } else {
                value = UInt32(digits)
            }
            guard let value, let scalar = Unicode.Scalar(value) else { return nil }
            return String(scalar)
        }
        guard let scalar = HTMLNamedEntities.scalar(forName: body) else { return nil }
        return String(scalar)
    }

    // MARK: - Unicode 转义

    static func unicodeEncode(_ text: String, options: CodecOptions) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            let needsEscape = scalar.value > 0x7E || scalar.value < 0x20 || options.unicodeEscapeASCII
            guard needsEscape else {
                result.unicodeScalars.append(scalar)
                continue
            }
            if options.unicodeBraced {
                result += String(format: "\\u{%X}", scalar.value)
            } else if scalar.value <= 0xFFFF {
                result += String(format: "\\u%04X", scalar.value)
            } else {
                // UTF-16 代理对（JavaScript 那种写法）
                let value = scalar.value - 0x10000
                let high = 0xD800 + (value >> 10)
                let low = 0xDC00 + (value & 0x3FF)
                result += String(format: "\\u%04X\\u%04X", high, low)
            }
        }
        return result
    }

    /// 支持 \uXXXX、\u{XXXXXX}、\U0001F600、\xXX 四种写法，UTF-16 代理对会自动合回去
    static func unicodeDecode(_ text: String) throws -> String {
        let scalars = Array(text.unicodeScalars)
        var units: [UInt16] = []
        var index = 0

        func append(_ scalar: Unicode.Scalar) {
            units.append(contentsOf: Array(String(scalar).utf16))
        }

        while index < scalars.count {
            guard scalars[index] == "\\", index + 1 < scalars.count else {
                append(scalars[index])
                index += 1
                continue
            }

            let marker = scalars[index + 1]

            // \u{1F600}
            if marker == "u", index + 2 < scalars.count, scalars[index + 2] == "{" {
                var cursor = index + 3
                var hex = ""
                while cursor < scalars.count, scalars[cursor] != "}" {
                    hex.unicodeScalars.append(scalars[cursor])
                    cursor += 1
                }
                guard cursor < scalars.count, !hex.isEmpty,
                      let value = UInt32(hex, radix: 16),
                      let scalar = Unicode.Scalar(value) else {
                    throw CodecError.invalidUnicodeEscape("\\u{\(hex)}")
                }
                append(scalar)
                index = cursor + 1
                continue
            }

            // 定长写法：\uXXXX / \UXXXXXXXX / \xXX
            let length: Int
            switch marker {
            case "u": length = 4
            case "U": length = 8
            case "x": length = 2
            default: length = 0
            }

            if length > 0, index + 1 + length <= scalars.count {
                let hexScalars = scalars[(index + 2)..<(index + 2 + length)]
                let hex = String(String.UnicodeScalarView(hexScalars))
                if hex.allSatisfy({ $0.isHexDigit }), let value = UInt32(hex, radix: 16) {
                    if marker == "U" {
                        if let scalar = Unicode.Scalar(value) { append(scalar) }
                    } else {
                        units.append(UInt16(value))
                    }
                    index += 2 + length
                    continue
                }
            }

            // 不是合法转义（比如 Windows 路径 C:\users），原样输出
            append(scalars[index])
            index += 1
        }

        // 顺着 UTF-16 走一遍，孤立的代理单元会被换成替换字符，不会崩
        return String(decoding: units, as: UTF16.self)
    }

    // MARK: - JSON 字符串

    static func jsonEncode(_ text: String, options: CodecOptions) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\u{08}": result += "\\b"
            case "\u{0C}": result += "\\f"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04X", scalar.value)
                } else if options.jsonEscapeUnicode, scalar.value > 0x7E {
                    if scalar.value <= 0xFFFF {
                        result += String(format: "\\u%04X", scalar.value)
                    } else {
                        let value = scalar.value - 0x10000
                        result += String(format: "\\u%04X\\u%04X", 0xD800 + (value >> 10), 0xDC00 + (value & 0x3FF))
                    }
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }

    static func jsonDecode(_ text: String) throws -> String {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wrapped = body.hasPrefix("\"") && body.hasSuffix("\"") && body.count >= 2
            ? body
            : "\"\(body)\""
        // 套一层数组，这样内容是啥都不影响解析
        guard let data = "[\(wrapped)]".data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data),
              let array = parsed as? [Any],
              let first = array.first as? String else {
            throw CodecError.invalidJSON
        }
        return first
    }

    // MARK: - 小工具

    private static func pad(_ string: String, to width: Int) -> String {
        string.count >= width ? string : String(repeating: "0", count: width - string.count) + string
    }

    private static func wrap(_ string: String, every width: Int) -> String {
        guard width > 0, string.count > width else { return string }
        let characters = Array(string)
        return stride(from: 0, to: characters.count, by: width).map { start in
            String(characters[start..<min(start + width, characters.count)])
        }.joined(separator: "\n")
    }
}
