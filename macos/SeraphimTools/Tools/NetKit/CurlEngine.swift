import Foundation

/// curl 命令生成器 + 反向解析器。
///
/// 生成这头不复杂，麻烦的是 shell 引号：值里有单引号时得写成 `'\''`，
/// 没引号就会在粘贴执行时被 shell 吃掉半截——所以这里一律走显式引号规则。
/// 反解析那头要认 `-H'x: y'`、`-XPOST`、`-sL` 这些"贴在一起"的写法，不然用户从浏览器
/// 复制的命令根本解析不动。
enum CurlEngine {

    // MARK: - 生成

    static func command(for request: CurlRequest, style: CurlStyle = .multiLine) -> String {
        var parts: [String] = ["curl"]
        let method = request.method.uppercased()

        if request.headOnly {
            parts.append("-I")
        } else if !method.isEmpty, method != "GET" {
            parts.append("-X \(method)")
        }

        if !request.url.isEmpty {
            parts.append(shellQuote(request.url))
        }

        var headerLines: [(String, String)] = []
        for header in request.headers where header.isEnabled {
            let name = header.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            headerLines.append((name, header.value))
        }

        // JSON 模式帮用户把 Content-Type 补上：curl 的 -d 默认会声明成表单类型，不补就对不上
        if request.bodyMode == .json,
           !headerLines.contains(where: { $0.0.lowercased() == "content-type" }) {
            headerLines.append(("Content-Type", "application/json"))
        }

        if request.authMode == .bearer, !request.bearerToken.isEmpty,
           !headerLines.contains(where: { $0.0.lowercased() == "authorization" }) {
            headerLines.append(("Authorization", "Bearer \(request.bearerToken)"))
        }

        for (name, value) in headerLines {
            parts.append("-H \(shellQuote("\(name): \(value)"))")
        }

        if request.authMode == .basic, !request.username.isEmpty {
            let credential = request.password.isEmpty ? request.username : "\(request.username):\(request.password)"
            parts.append("-u \(shellQuote(credential))")
        }

        if !request.cookies.isEmpty {
            parts.append("-b \(shellQuote(request.cookies))")
        }
        if !request.userAgent.isEmpty {
            parts.append("-A \(shellQuote(request.userAgent))")
        }
        if !request.referer.isEmpty {
            parts.append("-e \(shellQuote(request.referer))")
        }

        switch request.bodyMode {
        case .none:
            break
        case .json:
            let text = request.rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { parts.append("-d \(shellQuote(text))") }
        case .raw:
            if !request.rawBody.isEmpty { parts.append("--data-raw \(shellQuote(request.rawBody))") }
        case .form:
            for field in request.dataFields where field.isEnabled && !field.name.isEmpty {
                let payload = field.value.isEmpty ? field.name : "\(field.name)=\(field.value)"
                parts.append("--data-urlencode \(shellQuote(payload))")
            }
        case .multipart:
            for field in request.dataFields where field.isEnabled && !field.name.isEmpty {
                parts.append("-F \(shellQuote("\(field.name)=\(field.value)"))")
            }
            for field in request.fileFields where field.isEnabled && !field.name.isEmpty {
                let path = field.value.trimmingCharacters(in: .whitespaces)
                guard !path.isEmpty else { continue }
                parts.append("-F \(shellQuote("\(field.name)=@\(path)"))")
            }
        }

        let isPretty = style == .pretty

        if request.followRedirects {
            parts.append("-L")
        }
        if request.insecure {
            parts.append("-k")
        }
        if !isPretty {
            if request.compressed { parts.append("--compressed") }
            if request.includeHeaders { parts.append("-i") }
            if request.verbose { parts.append("-v") }
            if request.silent { parts.append("-s") }
            if !request.connectTimeout.isEmpty { parts.append("--connect-timeout \(request.connectTimeout)") }
            if !request.maxTime.isEmpty { parts.append("-m \(request.maxTime)") }
        }
        if !request.outputFile.isEmpty {
            parts.append("-o \(shellQuote(request.outputFile))")
        }

        switch style {
        case .singleLine, .pretty:
            return parts.joined(separator: " ")
        case .multiLine:
            guard parts.count > 1 else { return parts.joined(separator: " ") }
            let head = parts[0] + " " + parts[1]
            let rest = parts.dropFirst(2).map { "  " + $0 }
            return ([head] + rest).joined(separator: " \\\n")
        }
    }

    /// 单引号包裹，内部单引号按 shell 规矩拆开重拼；纯安全字符才裸奔
    static func shellQuote(_ text: String) -> String {
        if text.isEmpty { return "''" }
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.insert(charactersIn: ",./:@%+=_-")
        if text.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            return text
        }
        return "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// 从 HTTP 请求器的表单导出一份 curl 表单
    static func request(from spec: HTTPRequestSpec) -> CurlRequest {
        var request = CurlRequest()
        request.url = spec.url
        request.method = spec.method
        request.headers = spec.headers
        request.followRedirects = spec.followRedirects
        request.insecure = spec.allowInsecureTLS
        request.dataFields = spec.formFields
        request.fileFields = spec.fileFields
        switch spec.bodyMode {
        case .none: request.bodyMode = .none
        case .json: request.bodyMode = .json; request.rawBody = spec.rawBody
        case .raw: request.bodyMode = .raw; request.rawBody = spec.rawBody
        case .form: request.bodyMode = .form
        case .multipart: request.bodyMode = .multipart
        }
        return request
    }

    // MARK: - 反解析

    static func parse(_ text: String) -> CurlParseResult {
        var request = CurlRequest()
        var warnings: [String] = []
        var unknown: [String] = []
        var dataParts: [String] = []
        var urlEncodedFields: [(String, String)] = []
        var multipartFields: [(String, String)] = []
        var sawData = false

        let tokens = tokenize(text)
        guard !tokens.isEmpty else {
            warnings.append("没读到内容，先粘一条 curl 命令进来")
            return CurlParseResult(request: request, warnings: warnings, unknown: unknown)
        }

        let valueShortFlags: Set<String> = ["-X", "-H", "-d", "-F", "-u", "-b", "-A", "-e", "-o", "-m", "-T", "-x", "-w", "-E", "--url", "-c"]
        let booleanShortFlags: Set<Character> = ["L", "k", "i", "I", "s", "S", "v", "G", "O", "N", "f", "J", "g"]

        var index = 0
        var sawCurl = false

        while index < tokens.count {
            var token = tokens[index]
            index += 1

            if !sawCurl, token == "curl" || token.hasSuffix("/curl") {
                sawCurl = true
                continue
            }

            // --flag=value 形式
            if token.hasPrefix("--"), let equals = token.firstIndex(of: "=") {
                let flag = String(token[token.startIndex..<equals])
                let value = String(token[token.index(after: equals)...])
                token = "\(flag)\u{1}\(value)"
            }

            var inlineValue: String?
            if let separator = token.firstIndex(of: "\u{1}") {
                inlineValue = String(token[token.index(after: separator)...])
                token = String(token[token.startIndex..<separator])
            }

            func takeValue() -> String? {
                if let inlineValue { return inlineValue }
                guard index < tokens.count else { return nil }
                let value = tokens[index]
                index += 1
                return value
            }

            // -XPOST / -H'x: y' 这类粘在一起的短选项
            if inlineValue == nil, token.hasPrefix("-"), !token.hasPrefix("--"), token.count > 2 {
                let flag = String(token.prefix(2))
                let rest = String(token.dropFirst(2))
                if valueShortFlags.contains(flag) {
                    token = flag
                    inlineValue = rest
                } else {
                    // 布尔短选项可以连写：-sL / -kL
                    let letters = Array(token.dropFirst())
                    if letters.allSatisfy(booleanShortFlags.contains) {
                        for letter in letters {
                            apply(flag: "-\(letter)", value: nil, request: &request, unknown: &unknown, sawData: &sawData, dataParts: &dataParts, urlEncodedFields: &urlEncodedFields, multipartFields: &multipartFields, warnings: &warnings)
                        }
                        continue
                    }
                }
            }

            switch token {
            case "-X", "--request":
                request.method = (takeValue() ?? "").uppercased()
            case "-H", "--header":
                guard let raw = takeValue() else { break }
                if let colon = raw.firstIndex(of: ":") {
                    let name = String(raw[raw.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
                    let value = String(raw[raw.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    request.headers.append(NetPair(name: name, value: value))
                } else {
                    warnings.append("请求头「\(raw)」没有冒号，已跳过")
                }
            case "-d", "--data", "--data-raw", "--data-binary":
                if let value = takeValue() {
                    if value.hasPrefix("@") {
                        warnings.append("--data-binary @文件 不支持，已跳过 \(value)")
                    } else {
                        dataParts.append(value)
                        sawData = true
                    }
                }
            case "--data-urlencode":
                if let value = takeValue() {
                    if let equals = value.firstIndex(of: "=") {
                        let name = String(value[value.startIndex..<equals])
                        let fieldValue = String(value[value.index(after: equals)...])
                        urlEncodedFields.append((name, fieldValue))
                    } else {
                        urlEncodedFields.append((value, ""))
                    }
                    sawData = true
                }
            case "-F", "--form":
                if let value = takeValue() {
                    if let equals = value.firstIndex(of: "=") {
                        let name = String(value[value.startIndex..<equals])
                        let fieldValue = String(value[value.index(after: equals)...])
                        multipartFields.append((name, fieldValue))
                        sawData = true
                    }
                }
            case "-u", "--user":
                if let value = takeValue() {
                    if let colon = value.firstIndex(of: ":") {
                        request.username = String(value[value.startIndex..<colon])
                        request.password = String(value[value.index(after: colon)...])
                    } else {
                        request.username = value
                    }
                    request.authMode = .basic
                }
            case "-b", "--cookie":
                if let value = takeValue() {
                    if value.hasPrefix("@") {
                        warnings.append("cookie 文件 \(value) 不支持，已忽略")
                    } else {
                        request.cookies = value
                    }
                }
            case "-A", "--user-agent":
                request.userAgent = takeValue() ?? ""
            case "-e", "--referer":
                request.referer = takeValue() ?? ""
            case "-o", "--output":
                request.outputFile = takeValue() ?? ""
            case "--connect-timeout":
                request.connectTimeout = takeValue() ?? ""
            case "-m", "--max-time":
                request.maxTime = takeValue() ?? ""
            case "--url":
                request.url = takeValue() ?? ""
            case "-L", "--location":
                request.followRedirects = true
            case "-k", "--insecure":
                request.insecure = true
            case "--compressed":
                request.compressed = true
            case "-i", "--include":
                request.includeHeaders = true
            case "-I", "--head":
                request.headOnly = true
                request.method = "HEAD"
            case "-s", "--silent":
                request.silent = true
            case "-sS":
                request.silent = true
            case "-v", "--verbose":
                request.verbose = true
            case "--data-ascii", "-G":
                warnings.append("\(token) 已忽略（这条命令用的是 GET 拼参数写法）")
            default:
                if token.hasPrefix("-") {
                    unknown.append(token)
                    if valueShortFlags.contains(token) { _ = takeValue() }
                } else if request.url.isEmpty {
                    request.url = token
                } else {
                    warnings.append("多出来的参数「\(token)」已忽略")
                }
            }
        }

        // 组装 body
        if !multipartFields.isEmpty {
            request.bodyMode = .multipart
            for (name, value) in multipartFields {
                if value.hasPrefix("@") {
                    request.fileFields.append(NetPair(name: name, value: String(value.dropFirst())))
                } else {
                    request.dataFields.append(NetPair(name: name, value: value))
                }
            }
        } else if !urlEncodedFields.isEmpty {
            request.bodyMode = .form
            request.dataFields = urlEncodedFields.map { NetPair(name: $0.0, value: $0.1) }
            if urlEncodedFields.contains(where: { $0.1.contains("%") }) {
                warnings.append("--data-urlencode 的值里含 %，本工具按原文处理，不会被二次编码")
            }
        } else if !dataParts.isEmpty {
            let joined = dataParts.joined(separator: "&")
            let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                request.bodyMode = .json
                request.rawBody = joined
            } else if joined.contains("="), !joined.contains("\n") {
                request.bodyMode = .form
                request.dataFields = joined.split(separator: "&").map { piece in
                    let text = String(piece)
                    guard let equals = text.firstIndex(of: "=") else { return NetPair(name: text, value: "") }
                    return NetPair(
                        name: decodeForm(String(text[text.startIndex..<equals])),
                        value: decodeForm(String(text[text.index(after: equals)...]))
                    )
                }
            } else {
                request.bodyMode = .raw
                request.rawBody = joined
            }
        } else if sawData {
            request.bodyMode = .none
        }

        // 方法推断：curl 默认 GET，带 body 时按 POST
        if request.headOnly {
            request.method = "HEAD"
        } else if request.method.isEmpty {
            request.method = sawData ? "POST" : "GET"
        } else if request.method == "GET", sawData {
            warnings.append("命令里没写 -X，但带了 -d，curl 实际会按 POST 发送")
            request.method = "POST"
        }

        if request.url.isEmpty {
            warnings.append("没找到 URL")
        }

        return CurlParseResult(request: request, warnings: warnings, unknown: unknown)
    }

    /// 给连写的布尔短选项复用
    private static func apply(
        flag: String,
        value: String?,
        request: inout CurlRequest,
        unknown: inout [String],
        sawData: inout Bool,
        dataParts: inout [String],
        urlEncodedFields: inout [(String, String)],
        multipartFields: inout [(String, String)],
        warnings: inout [String]
    ) {
        switch flag {
        case "-L": request.followRedirects = true
        case "-k": request.insecure = true
        case "-i": request.includeHeaders = true
        case "-I": request.headOnly = true; request.method = "HEAD"
        case "-s", "-S": request.silent = true
        case "-v": request.verbose = true
        case "-f", "-N", "-g": break
        default: unknown.append(flag)
        }
    }

    private static func decodeForm(_ text: String) -> String {
        text
            .replacingOccurrences(of: "+", with: " ")
            .removingPercentEncoding ?? text
    }

    // MARK: - 分词

    /// 按 shell 规矩分词：认单引号、双引号、反斜杠续行与转义
    static func tokenize(_ text: String) -> [String] {
        enum Quote {
            case none
            case single
            case double
        }

        var tokens: [String] = []
        var current = ""
        var hasCurrent = false
        var quote: Quote = .none
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]

            switch quote {
            case .none:
                if character == "\\" {
                    let next = text.index(after: index)
                    guard next < text.endIndex else {
                        index = next
                        continue
                    }
                    let escaped = text[next]
                    if escaped == "\n" {
                        index = text.index(after: next)
                        continue
                    }
                    current.append(escaped)
                    hasCurrent = true
                    index = text.index(after: next)
                    continue
                }
                if character == "'" {
                    quote = .single
                    hasCurrent = true
                    index = text.index(after: index)
                    continue
                }
                if character == "\"" {
                    quote = .double
                    hasCurrent = true
                    index = text.index(after: index)
                    continue
                }
                if character == " " || character == "\t" || character == "\n" || character == "\r" {
                    if hasCurrent {
                        tokens.append(current)
                        current = ""
                        hasCurrent = false
                    }
                    index = text.index(after: index)
                    continue
                }
                current.append(character)
                hasCurrent = true
                index = text.index(after: index)

            case .single:
                if character == "'" {
                    quote = .none
                } else {
                    current.append(character)
                }
                index = text.index(after: index)

            case .double:
                if character == "\\" {
                    let next = text.index(after: index)
                    guard next < text.endIndex else {
                        index = next
                        continue
                    }
                    let escaped = text[next]
                    if escaped == "\n" {
                        index = text.index(after: next)
                        continue
                    }
                    if escaped == "\"" || escaped == "\\" || escaped == "$" || escaped == "`" {
                        current.append(escaped)
                    } else {
                        current.append("\\")
                        current.append(escaped)
                    }
                    index = text.index(after: next)
                    continue
                }
                if character == "\"" {
                    quote = .none
                    index = text.index(after: index)
                    continue
                }
                current.append(character)
                index = text.index(after: index)
            }
        }

        if hasCurrent { tokens.append(current) }
        return tokens
    }
}
