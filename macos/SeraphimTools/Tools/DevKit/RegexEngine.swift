import Foundation

enum RegexError: LocalizedError {
    case invalidPattern(String)
    case tooComplex
    case emptyPattern

    var errorDescription: String? {
        switch self {
        case .invalidPattern(let reason): return "正则语法有问题：\(reason)"
        case .tooComplex: return "这个正则太复杂，引擎算不动了。试试把匹配范围缩小。"
        case .emptyPattern: return "还没填正则表达式。"
        }
    }
}

/// 对 NSRegularExpression 的一层包装，输出便于界面消费的结构。
enum RegexEngine {

    // MARK: - 编译

    static func compile(_ pattern: String, options: RegexOptions) throws -> NSRegularExpression {
        guard !pattern.isEmpty else { throw RegexError.emptyPattern }
        do {
            return try NSRegularExpression(pattern: pattern, options: options.nsOptions)
        } catch {
            let nsError = error as NSError
            let reason = nsError.userInfo[NSLocalizedDescriptionKey] as? String ?? error.localizedDescription
            throw RegexError.invalidPattern(cleanReason(reason))
        }
    }

    /// NSError 的描述里常带一串英文前缀，剥掉留有效信息
    private static func cleanReason(_ reason: String) -> String {
        var text = reason
        if let range = text.range(of: "The value is invalid: ") {
            text = String(text[range.upperBound...])
        }
        if let range = text.range(of: "NSRegularExpression") {
            text = String(text[..<range.lowerBound])
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? reason : trimmed
    }

    // MARK: - 匹配

    static func matches(
        in text: String,
        pattern: String,
        options: RegexOptions,
        limit: Int = 5000
    ) throws -> [RegexMatchInfo] {
        let regex = try compile(pattern, options: options)
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        var results: [RegexMatchInfo] = []
        var index = 1
        regex.enumerateMatches(in: text, options: [], range: full) { result, _, stop in
            guard let result else { return }
            if results.count >= limit {
                stop.pointee = true
                return
            }

            var groups: [RegexGroupInfo] = []
            if result.numberOfRanges > 1 {
                for groupIndex in 1..<result.numberOfRanges {
                    let range = result.range(at: groupIndex)
                    let text: String? = range.location == NSNotFound ? nil : ns.substring(with: range)
                    groups.append(RegexGroupInfo(
                        id: groupIndex,
                        name: nil,
                        text: text,
                        location: range.location == NSNotFound ? -1 : range.location,
                        length: range.length == NSNotFound ? 0 : range.length
                    ))
                }
            }

            let matchedRange = result.range
            results.append(RegexMatchInfo(
                id: index,
                text: ns.substring(with: matchedRange),
                location: matchedRange.location,
                length: matchedRange.length,
                groups: groups
            ))
            index += 1
        }
        return results
    }

    /// 把文本切成"命中段 / 未命中段"，供界面染色
    static func segments(in text: String, matches: [RegexMatchInfo]) -> [RegexSegment] {
        let ns = text as NSString
        var segments: [RegexSegment] = []
        var cursor = 0
        var id = 0

        for match in matches {
            let start = max(cursor, match.location)
            if start > cursor {
                segments.append(RegexSegment(
                    id: id,
                    text: ns.substring(with: NSRange(location: cursor, length: start - cursor)),
                    isMatch: false,
                    matchIndex: nil
                ))
                id += 1
            }
            if match.length > 0, start + match.length <= ns.length {
                segments.append(RegexSegment(
                    id: id,
                    text: ns.substring(with: NSRange(location: start, length: match.length)),
                    isMatch: true,
                    matchIndex: match.id
                ))
                id += 1
            }
            cursor = start + match.length
        }

        if cursor < ns.length {
            segments.append(RegexSegment(
                id: id,
                text: ns.substring(with: NSRange(location: cursor, length: ns.length - cursor)),
                isMatch: false,
                matchIndex: nil
            ))
        }

        if segments.isEmpty, !text.isEmpty {
            segments.append(RegexSegment(id: 0, text: text, isMatch: false, matchIndex: nil))
        }
        return segments
    }

    // MARK: - 替换

    struct ReplaceOutcome: Sendable {
        let output: String
        let count: Int
    }

    /// `template` 用 `$1` `$0` `$<name>` 引用分组；顺手把 `\1` 这种写法也认了。
    static func replace(
        in text: String,
        pattern: String,
        options: RegexOptions,
        template: String,
        limit: Int = 0
    ) throws -> ReplaceOutcome {
        let regex = try compile(pattern, options: options)
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        let translated = translate(template)

        var count = 0
        regex.enumerateMatches(in: text, options: [], range: full) { result, _, _ in
            if result != nil { count += 1 }
        }

        if limit > 0 {
            // 只替换前 limit 处：逐段拼
            var output = ""
            var cursor = 0
            var replaced = 0
            regex.enumerateMatches(in: text, options: [], range: full) { result, _, stop in
                guard let result else { return }
                if replaced >= limit {
                    stop.pointee = true
                    return
                }
                let range = result.range
                output += ns.substring(with: NSRange(location: cursor, length: range.location - cursor))
                let matchText = ns.substring(with: range)
                output += regex.replacementString(
                    for: result,
                    in: text,
                    offset: 0,
                    template: translated
                ) + (matchText.isEmpty ? "" : "")
                cursor = range.location + range.length
                replaced += 1
            }
            output += ns.substring(from: cursor)
            return ReplaceOutcome(output: output, count: replaced)
        }

        let output = regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: full,
            withTemplate: translated
        )
        return ReplaceOutcome(output: output, count: count)
    }

    /// 把 `\1` / `\g<1>` 这类写法统一成 NSRegularExpression 的 `$1`
    private static func translate(_ template: String) -> String {
        var result = ""
        var index = template.startIndex
        while index < template.endIndex {
            let character = template[index]
            if character == "\\", template.index(after: index) < template.endIndex {
                let next = template.index(after: index)
                let nextCharacter = template[next]
                if nextCharacter.isNumber {
                    result.append("$")
                    result.append(nextCharacter)
                    index = template.index(after: next)
                    continue
                }
                if nextCharacter == "n" {
                    result.append("\n")
                    index = template.index(after: next)
                    continue
                }
                if nextCharacter == "t" {
                    result.append("\t")
                    index = template.index(after: next)
                    continue
                }
            }
            result.append(character)
            index = template.index(after: index)
        }
        return result
    }

    // MARK: - 说明

    struct PatternInfo: Sendable {
        let captureGroups: Int
        let namedGroups: [String]
        let hasAnchors: Bool
        let hasLookaround: Bool
        let literalLength: Int
    }

    static func info(_ pattern: String, options: RegexOptions) throws -> PatternInfo {
        let regex = try compile(pattern, options: options)
        let named = NSRegularExpression.namedCaptureGroups(pattern)
        return PatternInfo(
            captureGroups: regex.numberOfCaptureGroups,
            namedGroups: named,
            hasAnchors: pattern.contains("^") || pattern.contains("$"),
            hasLookaround: pattern.contains("(?=") || pattern.contains("(?!") || pattern.contains("(?<=") || pattern.contains("(?<!"),
            literalLength: pattern.count
        )
    }

    // MARK: - 拆分

    static func split(_ text: String, pattern: String, options: RegexOptions, limit: Int = 20) throws -> [String] {
        let regex = try compile(pattern, options: options)
        let ns = text as NSString
        let parts = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
            .prefix(limit)
            .map { ns.substring(with: $0.range) }
        return Array(parts)
    }
}

private extension NSRegularExpression {
    /// 从模式串里把 `(?<name>…)` 的名字抠出来，纯展示用
    static func namedCaptureGroups(_ pattern: String) -> [String] {
        var names: [String] = []
        var index = pattern.startIndex
        while index < pattern.endIndex {
            if pattern[index] == "(",
               pattern.index(after: index) < pattern.endIndex,
               pattern[pattern.index(after: index)] == "?" {
                let after = pattern.index(index, offsetBy: 2, limitedBy: pattern.endIndex) ?? pattern.endIndex
                if after < pattern.endIndex, pattern[after] == "<" {
                    let nameStart = pattern.index(after: after)
                    if let nameEnd = pattern[nameStart...].firstIndex(of: ">") {
                        let name = String(pattern[nameStart..<nameEnd])
                        // (?<= 和 (?<! 是后顾，不是命名分组
                        if !name.hasPrefix("=") && !name.hasPrefix("!") {
                            names.append(name)
                        }
                    }
                }
            }
            index = pattern.index(after: index)
        }
        return names
    }
}
