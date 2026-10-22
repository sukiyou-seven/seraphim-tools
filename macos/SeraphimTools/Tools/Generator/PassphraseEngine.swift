import Foundation

// MARK: - 词

/// 词表里的一个词。中文词带拼音——同一个词的拼音能当一份独立的表用，
/// 很多网站不接受非 ASCII 字符，而拼音念出来还是那个词，一样好记。
struct PassphraseWord: Sendable, Equatable {
    let text: String
    let pinyin: String
}

// MARK: - 词表

enum PassphraseWordlist: String, CaseIterable, Identifiable, Sendable {
    case chinese
    case pinyin
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chinese: return "中文常用词"
        case .pinyin: return "拼音"
        case .english: return "英文短词"
        }
    }

    /// 表里的词。三套表的规模不一样，抽词的方式完全一样。
    var words: [String] {
        switch self {
        case .chinese: return Self.chineseWords
        case .pinyin: return Self.pinyinWords
        case .english: return PassphraseTables.english
        }
    }

    private static let chineseWords = PassphraseTables.chinese.map(\.text)
    private static let pinyinWords = PassphraseTables.chinese.map(\.pinyin)

    var count: Int { words.count }

    /// 每个词贡献多少 bit 的不确定性。均匀随机选 N 个之一，就是 log2(N)。
    var bitsPerWord: Double { log2(Double(count)) }

    /// 这套表能不能直接当密码用——中文词不行，很多网站只收 ASCII。
    var isASCII: Bool { self != .chinese }

    var note: String {
        switch self {
        case .chinese: return "全是生活里的双字词，最好记；但不少网站不接受中文，那种地方切到拼音"
        case .pinyin: return "念着还是中文词，写出来是纯字母，哪儿都能用"
        case .english: return "词最多，同样词数比中文更结实；只要会念就记得住"
        }
    }
}

// MARK: - 分隔符

enum PassphraseSeparator: String, CaseIterable, Identifiable, Sendable {
    case dash
    case underscore
    case dot
    case space
    case tight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dash: return "-"
        case .underscore: return "_"
        case .dot: return "."
        case .space: return "空格"
        case .tight: return "不分隔"
        }
    }

    var value: String {
        switch self {
        case .dash: return "-"
        case .underscore: return "_"
        case .dot: return "."
        case .space: return " "
        case .tight: return ""
        }
    }
}

// MARK: - 选项

struct PassphraseOptions: Sendable, Equatable {
    var wordlist: PassphraseWordlist = .chinese
    var wordCount: Int = 7
    var separator: PassphraseSeparator = .dash
    /// 每个词首字母大写。注意这是确定性变换，**不增加强度**，只是看着像个密码。
    var capitalize = false
    /// 末尾追加两位随机数字。
    var tailDigits = false
    /// 末尾追加一个随机符号。
    var tailSymbol = false

    static let wordRange = 3...10

    var clampedWordCount: Int {
        min(max(wordCount, Self.wordRange.lowerBound), min(Self.wordRange.upperBound, wordlist.count))
    }
}

// MARK: - 强度

enum PassphraseLevel: String, CaseIterable, Sendable {
    case weak
    case thin
    case fair
    case strong
    case excellent

    static func forBits(_ bits: Double) -> PassphraseLevel {
        switch bits {
        case ..<35: return .weak
        case ..<50: return .thin
        case ..<70: return .fair
        case ..<85: return .strong
        default: return .excellent
        }
    }

    var title: String {
        switch self {
        case .weak: return "很弱"
        case .thin: return "偏弱"
        case .fair: return "够用"
        case .strong: return "强"
        case .excellent: return "很强"
        }
    }

    /// 这个等级适合放在哪儿。门槛是照着真实攻击成本定的，不吓唬人也不哄人：
    /// 65 bit 对上「GPU 硬打没做哈希防护的库」只有几个月，所以「强」这条线放在 70 bit——
    /// 到这儿才算三种攻击都过 100 年。
    var advice: String {
        switch self {
        case .weak: return "只适合随手注册的论坛小号，真正在意的账号别用"
        case .thin: return "能挡住随手乱试的人，挡不住专门盯着你的。再加一两个词"
        case .fair: return "日常账号够用：邮箱、购物、社交。但要是网站被拖库又没做哈希防护，GPU 几个月就能试出来——重要账号建议再来一个词"
        case .strong: return "三种攻击都过 100 年线，重要账号可以放心用：主邮箱、网盘、密码管理器"
        case .excellent: return "连离线暴力破解都够不着，拿它当主密码正合适"
        }
    }
}

struct PassphraseCrackEstimate: Identifiable, Sendable {
    let id: String
    /// 谁在试
    let scenario: String
    /// 他有多快
    let detail: String
    /// 平均要试多久
    let duration: String
    /// 够不够久（按 100 年这条线看）
    let safe: Bool
}

struct PassphraseStrength: Sendable {
    let bits: Double
    let level: PassphraseLevel
    let crackTimes: [PassphraseCrackEstimate]
    /// 用了「末尾追加数字/符号」这类固定套路。它有随机性、确实加点强度，
    /// 但破解工具会优先照这个套路去试，所以别指望它救场。
    let usesTailPattern: Bool
}

// MARK: - 结果

struct PassphraseResult: Sendable {
    let text: String
    let words: [String]
    let separator: String
    /// 中文词表时的拼音读法，尾部追加的数字符号一样跟着
    let pinyin: String?
    /// 尾部追加的那一段，单独拎出来界面才好标
    let suffix: String
    let bits: Double
    let level: PassphraseLevel
    let crackTimes: [PassphraseCrackEstimate]
    let isASCII: Bool

    var length: Int { text.count }
    var wordCount: Int { words.count }
}

// MARK: - 引擎

enum PassphraseEngine {

    /// 末尾追加时用的符号。刻意避开引号和反斜杠——它们过一道 shell 就得转义，麻烦。
    static let tailSymbols = ["!", "@", "#", "$", "%", "&", "*", "?"]

    // MARK: 生成

    static func generate(_ options: PassphraseOptions) -> PassphraseResult {
        var generator = SystemRandomNumberGenerator()
        return generate(options, using: &generator)
    }

    /// 抽词用「不放回」：同一个密码里两个词不会撞车。
    ///
    /// 除了避免「苹果-苹果」这种看着像 bug 的组合，熵也按不放回的排列精确算——
    /// 512 个词里挑 7 个是 log2(512×511×…×506) ≈ 62.9 bit，而不是 7×9=63 bit 的近似值。
    /// 差别很小，但既然能算准就没必要糊弄。
    static func generate<R: RandomNumberGenerator>(
        _ options: PassphraseOptions,
        using generator: inout R
    ) -> PassphraseResult {
        let pool = options.wordlist.words
        let size = pool.count
        let count = min(max(1, options.wordCount), size)

        // 部分洗牌，只把前 count 个位置定下来
        var indices = Array(pool.indices)
        if count > 0 && size > 1 {
            for slot in 0..<count {
                let pick = Int.random(in: slot..<size, using: &generator)
                indices.swapAt(slot, pick)
            }
        }
        let chosen = Array(indices.prefix(count))

        var words = chosen.map { pool[$0] }
        var pinyinWords: [String]? = options.wordlist == .chinese
            ? chosen.map { PassphraseTables.chinese[$0].pinyin }
            : nil

        if options.capitalize {
            words = words.map(capitalized)
            pinyinWords = pinyinWords?.map(capitalized)
        }

        let suffix = makeSuffix(options, using: &generator)
        let joiner = options.separator.value
        let text = words.joined(separator: joiner) + suffix
        let pinyin = pinyinWords.map { $0.joined(separator: joiner) + suffix }

        var bits = 0.0
        for offset in 0..<count {
            bits += log2(Double(size - offset))
        }
        if options.tailDigits { bits += log2(100.0) }
        if options.tailSymbol { bits += log2(Double(tailSymbols.count)) }

        return PassphraseResult(
            text: text,
            words: words,
            separator: joiner,
            pinyin: pinyin,
            suffix: suffix,
            bits: bits,
            level: PassphraseLevel.forBits(bits),
            crackTimes: crackEstimates(bits: bits),
            isASCII: text.allSatisfy(\.isASCII)
        )
    }

    private static func capitalized(_ word: String) -> String {
        guard let first = word.first else { return word }
        // 汉字大写了还是它自己，所以中文表原样返回
        return String(first).uppercased() + word.dropFirst()
    }

    private static func makeSuffix<R: RandomNumberGenerator>(
        _ options: PassphraseOptions,
        using generator: inout R
    ) -> String {
        var suffix = ""
        if options.tailDigits {
            suffix += "\(Int.random(in: 10...99, using: &generator))"
        }
        if options.tailSymbol {
            let index = Int.random(in: 0..<tailSymbols.count, using: &generator)
            suffix += tailSymbols[index]
        }
        return suffix
    }

    // MARK: 强度

    static func strength(bits: Double, usesTailPattern: Bool) -> PassphraseStrength {
        PassphraseStrength(
            bits: bits,
            level: PassphraseLevel.forBits(bits),
            crackTimes: crackEstimates(bits: bits),
            usesTailPattern: usesTailPattern
        )
    }

    /// 三种现实里的攻击速度。密码长度值不值得，得看对手拿什么在试。
    static let attackProfiles: [(id: String, scenario: String, detail: String, rate: Double)] = [
        ("online", "有人在登录框前慢慢试",
         "限速、验证码、错误锁定都算上，每秒能试 1000 次已经算他厉害", 1_000),
        ("slow", "网站被拖库后离线破解",
         "网站用了 bcrypt 这类慢哈希，每秒 1 万次", 10_000),
        ("fast", "同上，但网站没做哈希防护",
         "GPU 集群硬打 MD5/SHA-1，每秒 1000 亿次", 100_000_000_000),
    ]

    /// 平均破解时间 = 2^(bits-1) / 每秒尝试次数。
    static func crackEstimates(bits: Double) -> [PassphraseCrackEstimate] {
        let hundredYears = 100.0 * 365.25 * 86_400
        return attackProfiles.map { profile in
            let seconds = pow(2.0, bits - 1) / profile.rate
            return PassphraseCrackEstimate(
                id: profile.id,
                scenario: profile.scenario,
                detail: profile.detail,
                duration: humanDuration(seconds: seconds),
                safe: seconds > hundredYears
            )
        }
    }

    /// 把秒数说成人话。到了天文数字就用宇宙年龄当尺子——比「10^25 年」好懂得多。
    static func humanDuration(seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }
        if seconds < 1 { return "眨眼之间" }

        let minute = 60.0
        let hour = minute * 60
        let day = hour * 24
        let month = day * 30.44
        let year = day * 365.25

        if seconds < minute { return "\(Int(seconds.rounded())) 秒" }
        if seconds < hour { return "\(Int((seconds / minute).rounded())) 分钟" }
        if seconds < day { return "\(Int((seconds / hour).rounded())) 小时" }
        if seconds < month { return "\(Int((seconds / day).rounded())) 天" }
        if seconds < year { return "\(Int((seconds / month).rounded())) 个月" }

        let years = seconds / year
        if years < 10 { return String(format: "%.1f 年", years) }
        if years < 10_000 { return "\(Int(years.rounded())) 年" }
        if years < 100_000_000 { return String(format: "%.0f 万年", years / 10_000) }
        if years < 13_800_000_000 { return String(format: "%.0f 亿年", years / 100_000_000) }

        let universes = years / 13_800_000_000
        if universes < 10_000 { return String(format: "约 %.0f 个宇宙年龄", universes) }
        return String(format: "约 10^%.0f 年", log10(years))
    }
}

// MARK: - 纯数字密码

/// 门锁、行李箱、银行卡那种场景用的数字密码。
///
/// 这里必须说清楚：**纯数字密码只在有错误次数限制的地方才有意义**。
/// 4 位数字一共一万种，看起来少，但银行卡只给你 3 次机会，猜中概率 0.03%；
/// 反过来，行李箱密码锁没有次数限制，12 位在 GPU 面前也就十几秒。
/// 所以别拿数字密码去当网站密码用。
enum PINEngine {
    static let lengthChoices = [4, 6, 8, 10, 12]
    static let defaultLength = 6

    /// 被安全报告点名过无数次的弱密码
    static let blocked: Set<String> = [
        "0000", "1111", "2222", "3333", "4444", "5555", "6666", "7777", "8888", "9999",
        "1234", "4321", "0123", "3210", "1212", "2121", "1122", "2211", "1010", "0101",
        "0987", "6789", "2580", "0852", "1472", "1593",
        "12345", "123456", "654321", "111111", "000000", "121212", "112233", "123123",
        "456789", "987654", "159753", "147258", "1111111", "1234567", "7654321",
        "12345678", "11111111", "87654321",
    ]

    static func bits(length: Int) -> Double {
        Double(max(0, length)) * log2(10.0)
    }

    /// 太规则的组合挡不住「按常见套路先试一遍」的人。
    static func isWeak(_ pin: String) -> Bool {
        let digits = Array(pin)
        guard !digits.isEmpty else { return true }
        if blocked.contains(pin) { return true }
        if digits.allSatisfy({ $0 == digits[0] }) { return true }

        let values = digits.compactMap { $0.wholeNumberValue }
        guard values.count == digits.count else { return true }

        // 整串递增或递减：1234、9876
        var ascending = true
        var descending = true
        for index in 1..<values.count {
            let step = values[index] - values[index - 1]
            if step != 1 { ascending = false }
            if step != -1 { descending = false }
        }
        if ascending || descending { return true }

        // 整串是某个片段的重复：1212、121212、123123
        for period in 1..<digits.count where digits.count % period == 0 {
            let unit = Array(digits[0..<period])
            var repeated = true
            var cursor = period
            while cursor < digits.count {
                if Array(digits[cursor..<cursor + period]) != unit {
                    repeated = false
                    break
                }
                cursor += period
            }
            if repeated { return true }
        }
        return false
    }

    static func generate(length: Int, count: Int) -> [String] {
        var generator = SystemRandomNumberGenerator()
        return (0..<max(0, count)).map { _ in
            generate(length: length, using: &generator)
        }
    }

    static func generate<R: RandomNumberGenerator>(
        length: Int,
        using generator: inout R
    ) -> String {
        let size = max(1, length)
        // 弱模式的概率随长度指数下降（4 位时约千分之一），几百次足够撞出来。
        // 真出现极端情况就返回最后一次的结果——那时它至少不是全同或连号。
        var candidate = ""
        for _ in 0..<400 {
            candidate = ""
            for _ in 0..<size {
                candidate.append(Character(String(Int.random(in: 0...9, using: &generator))))
            }
            if !isWeak(candidate) { return candidate }
        }
        return candidate
    }

    /// 四位一组隔开，念给别人听或者照着输都方便。
    static func grouped(_ pin: String) -> String {
        guard pin.count > 4 else { return pin }
        var chunks: [String] = []
        var cursor = pin.startIndex
        while cursor < pin.endIndex {
            let end = pin.index(cursor, offsetBy: 4, limitedBy: pin.endIndex) ?? pin.endIndex
            chunks.append(String(pin[cursor..<end]))
            cursor = end
        }
        return chunks.joined(separator: " ")
    }

    /// 只有几次机会的场景里，被猜中的概率。
    static func lockoutHitChance(length: Int, attempts: Int = 3) -> Double {
        let total = pow(10.0, Double(max(0, length)))
        return Double(attempts) / total
    }
}
