import Foundation

// MARK: - JSON 美化
//
// 自己写的而不是用 JSONSerialization：一是要保住键的原始顺序（配置类 JSON 顺序有意义），
// 二是遇到残缺 JSON 时能老实返回 nil，不要硬美化出一段看起来对其实错了的东西。
// 网络工具的响应体、Webhook 收到的 body、JWT 的 header/payload 都用它。

enum JSONBeautifier {

    static func isJSONLike(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return false }
        return first == "{" || first == "["
    }

    static func pretty(_ text: String, indent: String = "  ") -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "{" || first == "[" else { return nil }

        var output = ""
        var depth = 0
        var inString = false
        var escaped = false
        var index = trimmed.startIndex

        func newline(_ level: Int) {
            output += "\n" + String(repeating: indent, count: max(0, level))
        }

        while index < trimmed.endIndex {
            let character = trimmed[index]

            if inString {
                output.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                index = trimmed.index(after: index)
                continue
            }

            switch character {
            case "\"":
                inString = true
                output.append(character)
            case "{", "[":
                depth += 1
                output.append(character)
                let next = trimmed.index(after: index)
                if next < trimmed.endIndex, let upcoming = trimmed[next...].first(where: { !$0.isWhitespace }), upcoming == "}" || upcoming == "]" {
                    // 空对象 / 空数组，不换行
                } else {
                    newline(depth)
                }
            case "}", "]":
                depth -= 1
                let previous = output.last
                if previous != "{", previous != "[", previous != " ", previous != "\n" {
                    newline(depth)
                }
                output.append(character)
            case ",":
                output.append(character)
                newline(depth)
            case ":":
                output.append(": ")
            case " ", "\n", "\t", "\r":
                break
            default:
                output.append(character)
            }
            index = trimmed.index(after: index)
        }

        // 括号没配平或者字符串没闭合，说明不是完整 JSON，别硬美化
        guard depth == 0, !inString else { return nil }
        return output
    }
}
