import Foundation

/// 常用正则模板。每个都带一段示例文本，点一下就能拿去试。
enum RegexLibrary {

    static let snippets: [RegexSnippet] = [

        // MARK: 网络
        RegexSnippet(
            id: "url",
            title: "URL",
            pattern: #"https?://[^\s"'<>()]+"#,
            note: "匹配 http/https 链接，遇到空白或引号收尾",
            sample: "文档在 https://example.com/docs/api?v=2 里，图片是 http://cdn.test/a.png?w=200",
            category: "网络"
        ),
        RegexSnippet(
            id: "email",
            title: "邮箱",
            pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
            note: "包含常见用户名与域名部分",
            sample: "联系 dev@seraphim.tools 或 backup.2026@mail.example.co.uk 均可",
            category: "网络"
        ),
        RegexSnippet(
            id: "ipv4",
            title: "IPv4 地址",
            pattern: #"\b(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\b"#,
            note: "每段 0–255，不会把 999.1.1.1 也算进来",
            sample: "网关 192.168.1.1，公网 8.8.8.8，非法值 256.100.1.1 不会被命中",
            category: "网络"
        ),
        RegexSnippet(
            id: "domain",
            title: "域名",
            pattern: #"\b(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}\b"#,
            note: "不含协议头，纯主机名",
            sample: "访问 api.example.com 和 static.cdn.test.org 都能命中",
            category: "网络"
        ),
        RegexSnippet(
            id: "mac",
            title: "MAC 地址",
            pattern: #"\b[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5}\b"#,
            note: "冒号分隔的六段十六进制",
            sample: "网卡 3C:22:FB:1A:9E:07 已启用",
            category: "网络"
        ),
        RegexSnippet(
            id: "port",
            title: "端口号",
            pattern: #"\b(?:6553[0-5]|655[0-2]\d|65[0-4]\d{2}|6[0-4]\d{3}|[1-5]\d{4}|[1-9]\d{0,3})\b"#,
            note: "限定 1–65535，排除 0 和越界值",
            sample: "监听 80、443、8080，错误配置 70000 不会命中",
            category: "网络"
        ),
        RegexSnippet(
            id: "uuid",
            title: "UUID",
            pattern: #"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"#,
            note: "标准 8-4-4-4-12 结构",
            sample: "trace=9f1c2b3a-7d44-4e11-8c2a-5b6e7f8a9b0c 已完成",
            category: "网络"
        ),

        // MARK: 数字
        RegexSnippet(
            id: "integer",
            title: "整数",
            pattern: #"-?\d+"#,
            note: "可带负号",
            sample: "温度 -12 度，库存 340 件，编号 7",
            category: "数字"
        ),
        RegexSnippet(
            id: "float",
            title: "浮点数",
            pattern: #"-?\d+(?:\.\d+)?"#,
            note: "整数部分 + 可选小数部分",
            sample: "单价 19.99，折扣 -3.5，数量 12",
            category: "数字"
        ),
        RegexSnippet(
            id: "money",
            title: "金额（千分位）",
            pattern: #"\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?"#,
            note: "带千分位分隔的金额写法",
            sample: "合同金额 1,250,000.50 元，运费 3,200 元",
            category: "数字"
        ),
        RegexSnippet(
            id: "percent",
            title: "百分比",
            pattern: #"-?\d+(?:\.\d+)?%"#,
            note: "带百分号",
            sample: "增长 12.5%，下跌 -3%，持平 0%",
            category: "数字"
        ),
        RegexSnippet(
            id: "hex",
            title: "十六进制数",
            pattern: #"\b0[xX][0-9A-Fa-f]+\b"#,
            note: "带 0x / 0X 前缀",
            sample: "掩码 0xFF00 与 0x1A2B 都要取出",
            category: "数字"
        ),
        RegexSnippet(
            id: "sci",
            title: "科学计数法",
            pattern: #"-?\d+(?:\.\d+)?[eE][+-]?\d+"#,
            note: "1.2e-5 这种",
            sample: "普朗克常数 6.626e-34，阿伏伽德罗 6.02E23",
            category: "数字"
        ),

        // MARK: 文本
        RegexSnippet(
            id: "chinese",
            title: "中文汉字",
            pattern: #"[\u4e00-\u9fa5]+"#,
            note: "基本汉字区，不含标点",
            sample: "Hello 世界，这是 Seraphim 工具箱。",
            category: "文本"
        ),
        RegexSnippet(
            id: "word",
            title: "英文单词",
            pattern: #"\b[A-Za-z]+\b"#,
            note: "连续的英文字母",
            sample: "The quick brown fox jumps over the lazy dog",
            category: "文本"
        ),
        RegexSnippet(
            id: "whitespace",
            title: "连续空白",
            pattern: #"[ \t]{2,}"#,
            note: "两个以上空格或制表符，用来查出多余缩进",
            sample: "姓名      年龄\t\t城市",
            category: "文本"
        ),
        RegexSnippet(
            id: "emptyline",
            title: "空行",
            pattern: #"^\s*$"#,
            note: "需要勾选多行模式（m）",
            sample: "第一行\n\n第三行\n   \n第五行",
            category: "文本"
        ),
        RegexSnippet(
            id: "trailingspace",
            title: "行尾多余空白",
            pattern: #"[ \t]+$"#,
            note: "需要勾选多行模式（m）",
            sample: "这行末尾有空格   \n这行没有\n这行也有\t",
            category: "文本"
        ),
        RegexSnippet(
            id: "htmltag",
            title: "HTML 标签",
            pattern: #"</?[A-Za-z][^>]*>"#,
            note: "整个标签，含属性",
            sample: #"<div class="card"><span>标题</span></div>"#,
            category: "文本"
        ),
        RegexSnippet(
            id: "colorhex",
            title: "颜色色值",
            pattern: #"#[0-9A-Fa-f]{3,8}\b"#,
            note: "3 / 4 / 6 / 8 位都认",
            sample: "主色 #C9A227，辅色 #FFF，透明叠加 #00000080",
            category: "文本"
        ),
        RegexSnippet(
            id: "bracket",
            title: "括号内容",
            pattern: #"\(([^)]*)\)"#,
            note: "第 1 个分组就是括号里的内容",
            sample: "函数 foo(alpha, beta) 与 bar(42) 都取出参数",
            category: "文本"
        ),

        // MARK: 中国常用
        RegexSnippet(
            id: "mobile",
            title: "手机号",
            pattern: #"1[3-9]\d{9}"#,
            note: "11 位，1 开头第二位 3–9",
            sample: "客户 13812345678，备用 18900001111",
            category: "中国常用"
        ),
        RegexSnippet(
            id: "idcard",
            title: "身份证号",
            pattern: #"[1-9]\d{5}(?:19|20)\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])\d{3}[\dXx]"#,
            note: "18 位，末位可以是 X",
            sample: "证件号 11010119900307123X 已核验",
            category: "中国常用"
        ),
        RegexSnippet(
            id: "plate",
            title: "车牌号",
            pattern: #"[京津沪渝冀豫云辽黑湘皖鲁新苏浙赣鄂桂甘晋蒙陕吉闽贵粤青藏川宁琼使领][A-HJ-NP-Z][A-HJ-NP-Z0-9]{4}[A-HJ-NP-Z0-9挂学警港澳]"#,
            note: "含新能源与特种车牌",
            sample: "京A12345 与 粤B8888D 均在列表中",
            category: "中国常用"
        ),
        RegexSnippet(
            id: "postcode",
            title: "邮政编码",
            pattern: #"\b[1-9]\d{5}\b"#,
            note: "6 位数字，首位非 0",
            sample: "地址邮编 100080，旧编码 510000",
            category: "中国常用"
        ),

        // MARK: 日志与代码
        RegexSnippet(
            id: "logtime",
            title: "日志时间戳",
            pattern: #"\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?"#,
            note: "带毫秒的 ISO 风格时间",
            sample: "2026-10-14 13:08:42.531 INFO  启动完成",
            category: "日志与代码"
        ),
        RegexSnippet(
            id: "loglevel",
            title: "日志级别",
            pattern: #"\b(?:TRACE|DEBUG|INFO|WARN|ERROR|FATAL)\b"#,
            note: "常见的六档级别",
            sample: "12:00:01 WARN 连接超时\n12:00:02 ERROR 重试失败",
            category: "日志与代码"
        ),
        RegexSnippet(
            id: "jsonkey",
            title: "JSON 键",
            pattern: #""([^"\\]|\\.)*"\s*:"#,
            note: "匹配键名与冒号",
            sample: #"{"name": "工具箱", "version": 1, "items": []}"#,
            category: "日志与代码"
        ),
        RegexSnippet(
            id: "semver",
            title: "语义化版本",
            pattern: #"\bv?\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?\b"#,
            note: "支持预发布后缀",
            sample: "升级 v1.2.3 到 2.0.0-rc.1",
            category: "日志与代码"
        ),
        RegexSnippet(
            id: "password",
            title: "强密码规则",
            pattern: #"^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^\w\s]).{12,}$"#,
            note: "至少 12 位，含大小写、数字、符号",
            sample: "Str0ng#Passw0rd",
            category: "日志与代码"
        ),
        RegexSnippet(
            id: "camel",
            title: "驼峰词拆分",
            pattern: #"[A-Z]?[a-z]+|[A-Z]+(?![a-z])|\d+"#,
            note: "把 getUserID2 拆成 get / User / ID / 2",
            sample: "getUserID2AndHTTPStatus",
            category: "日志与代码"
        ),
    ]

    static var categories: [String] {
        var seen: [String] = []
        for snippet in snippets where !seen.contains(snippet.category) {
            seen.append(snippet.category)
        }
        return seen
    }

    static func snippets(in category: String) -> [RegexSnippet] {
        snippets.filter { $0.category == category }
    }

    // MARK: 语法速查

    static let tokens: [RegexToken] = [
        RegexToken(id: "t1", token: ".", meaning: "任意字符（默认不含换行）"),
        RegexToken(id: "t2", token: "\\d", meaning: "数字 0–9"),
        RegexToken(id: "t3", token: "\\D", meaning: "非数字"),
        RegexToken(id: "t4", token: "\\w", meaning: "字母、数字、下划线"),
        RegexToken(id: "t5", token: "\\W", meaning: "非单词字符"),
        RegexToken(id: "t6", token: "\\s", meaning: "空白（空格、制表、换行）"),
        RegexToken(id: "t7", token: "\\S", meaning: "非空白"),
        RegexToken(id: "t8", token: "\\b", meaning: "单词边界"),
        RegexToken(id: "t9", token: "^", meaning: "行首（多行模式下每行都算）"),
        RegexToken(id: "t10", token: "$", meaning: "行尾"),
        RegexToken(id: "t11", token: "*", meaning: "前一项 0 次或多次"),
        RegexToken(id: "t12", token: "+", meaning: "前一项 1 次或多次"),
        RegexToken(id: "t13", token: "?", meaning: "前一项 0 次或 1 次"),
        RegexToken(id: "t14", token: "*?", meaning: "懒惰匹配，能少就少"),
        RegexToken(id: "t15", token: "{2,5}", meaning: "前一项 2 到 5 次"),
        RegexToken(id: "t16", token: "{3}", meaning: "前一项恰好 3 次"),
        RegexToken(id: "t17", token: "[abc]", meaning: "a、b、c 中任意一个"),
        RegexToken(id: "t18", token: "[^abc]", meaning: "除 a、b、c 外任意字符"),
        RegexToken(id: "t19", token: "[a-z0-9]", meaning: "范围内任意字符"),
        RegexToken(id: "t20", token: "(…)", meaning: "捕获分组，结果里单独取"),
        RegexToken(id: "t21", token: "(?:…)", meaning: "只分组不捕获"),
        RegexToken(id: "t22", token: "(?<name>…)", meaning: "命名分组"),
        RegexToken(id: "t23", token: "a|b", meaning: "a 或 b"),
        RegexToken(id: "t24", token: "(?=…)", meaning: "前瞻：后面得跟着它"),
        RegexToken(id: "t25", token: "(?!…)", meaning: "负前瞻：后面不能是它"),
        RegexToken(id: "t26", token: "(?<=…)", meaning: "后顾：前面得是它"),
        RegexToken(id: "t27", token: "(?<!…)", meaning: "负后顾：前面不能是它"),
        RegexToken(id: "t28", token: "\\1", meaning: "反向引用第 1 个分组"),
        RegexToken(id: "t29", token: "\\u4e00", meaning: "按码位匹配字符（汉字区间）"),
    ]

    /// 替换模板的常用占位符说明
    static let templateTokens: [RegexToken] = [
        RegexToken(id: "r1", token: "$0", meaning: "整个匹配到的内容"),
        RegexToken(id: "r2", token: "$1 $2", meaning: "第 1 / 第 2 个捕获分组"),
        RegexToken(id: "r3", token: "$<name>", meaning: "命名分组"),
        RegexToken(id: "r4", token: "\\n \\t", meaning: "换行、制表符"),
    ]
}
