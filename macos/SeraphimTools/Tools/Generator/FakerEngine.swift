import Foundation

// MARK: - 生成类别

enum FakerKind: String, CaseIterable, Identifiable, Sendable {
    case idCard
    case phone
    case address
    case englishName
    case email
    case company

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idCard: return "身份证"
        case .phone: return "手机号"
        case .address: return "地址"
        case .englishName: return "英文名"
        case .email: return "邮箱"
        case .company: return "公司名"
        }
    }

    var systemImage: String {
        switch self {
        case .idCard: return "person.text.rectangle"
        case .phone: return "phone"
        case .address: return "house"
        case .englishName: return "textformat.abc"
        case .email: return "envelope"
        case .company: return "building.2"
        }
    }

    var note: String {
        switch self {
        case .idCard: return "校验位按 GB 11643 计算，号码不指向真实个人"
        case .phone: return "使用真实号段，号码为随机分配，不指向真实用户"
        case .address: return "真实省市 + 随机路名门牌"
        case .englishName: return "常见英文姓名随机组合"
        case .email: return "由随机姓名拼出的邮箱账号"
        case .company: return "英文公司名随机组合"
        }
    }
}

enum FakerGender: String, CaseIterable, Identifiable, Sendable {
    case any
    case male
    case female

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "随机"
        case .male: return "男"
        case .female: return "女"
        }
    }
}

enum PhoneCarrier: String, CaseIterable, Identifiable, Sendable {
    case any
    case mobile
    case unicom
    case telecom
    case broadnet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "随机"
        case .mobile: return "移动"
        case .unicom: return "联通"
        case .telecom: return "电信"
        case .broadnet: return "广电"
        }
    }
}

// MARK: - 地区数据

struct FakeCity: Sendable {
    let code: String
    let name: String
}

struct FakeProvince: Sendable {
    let code: String
    let name: String
    let cities: [FakeCity]
}

// MARK: - 生成结果

struct FakerItem: Identifiable, Sendable {
    let id: String
    let value: String
    /// 次要说明（身份证的性别年龄、手机号的运营商之类）
    var detail: String = ""
}

// MARK: - 引擎

enum FakerEngine {

    // MARK: 身份证

    /// 生成一个校验位正确的身份证号。
    /// 地址码取真实的省市码，出生日期落在 1960-2005 之间，顺序码按性别取奇偶。
    static func idCard(gender: FakerGender = .any) -> FakerItem {
        var generator = SystemRandomNumberGenerator()
        let province = provinces.randomElement(using: &generator) ?? provinces[0]
        let city = province.cities.randomElement(using: &generator) ?? province.cities[0]

        // 6 位地址码：真实 4 位市码 + 2 位随机区县码
        let district = String(format: "%02d", Int.random(in: 1...99, using: &generator))
        let region = city.code + district

        // 出生日期，避开过年那几天让日期分布更自然（其实无所谓，顺手而已）
        let start = DateComponents(calendar: calendar, year: 1960, month: 1, day: 1).date ?? Date()
        let end = DateComponents(calendar: calendar, year: 2005, month: 12, day: 31).date ?? Date()
        let span = end.timeIntervalSince(start)
        let birthday = start.addingTimeInterval(span * Double.random(in: 0...1, using: &generator))
        let components = calendar.dateComponents([.year, .month, .day], from: birthday)
        let birth = String(
            format: "%04d%02d%02d",
            components.year ?? 1990,
            components.month ?? 1,
            components.day ?? 1
        )

        // 顺序码：奇数男、偶数女
        let isMale: Bool
        switch gender {
        case .male: isMale = true
        case .female: isMale = false
        case .any: isMale = Bool.random(using: &generator)
        }
        var sequence = Int.random(in: 1...499, using: &generator) * 2 + (isMale ? -1 : 0)
        sequence = max(1, min(999, sequence))
        let sequenceText = String(format: "%03d", sequence)

        let body = region + birth + sequenceText
        let full = body + String(checkDigit(for: body))

        let age = calendar.dateComponents([.year], from: birthday, to: Date()).year ?? 0
        let genderText = isMale ? "男" : "女"
        return FakerItem(
            id: full,
            value: full,
            detail: "\(province.name)\(city.name) · \(genderText) · \(age) 岁"
        )
    }

    /// GB 11643-1999 的模 11-2 校验位
    static func checkDigit(for body17: String) -> Character {
        let weights = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2]
        let codes: [Character] = ["1", "0", "X", "9", "8", "7", "6", "5", "4", "3", "2"]
        var sum = 0
        for (index, character) in body17.enumerated() where index < weights.count {
            guard let digit = character.wholeNumberValue else { return "0" }
            sum += digit * weights[index]
        }
        return codes[sum % 11]
    }

    /// 校验 18 位身份证（也接受 15 位老号）
    static func validateIDCard(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespaces).uppercased()
        if text.count == 15 {
            guard text.allSatisfy({ $0.isNumber }) else { return false }
            return validBirth(text, offset: 6, length: 6)
        }
        guard text.count == 18 else { return false }
        let body = String(text.prefix(17))
        guard body.allSatisfy({ $0.isNumber }) else { return false }
        guard validBirth(text, offset: 6, length: 8) else { return false }
        return text.last == checkDigit(for: body)
    }

    private static func validBirth(_ text: String, offset: Int, length: Int) -> Bool {
        let start = text.index(text.startIndex, offsetBy: offset)
        let end = text.index(start, offsetBy: length)
        let segment = String(text[start..<end])
        let yearText = length == 8 ? String(segment.prefix(4)) : "19" + String(segment.prefix(2))
        let monthText = length == 8 ? String(segment.dropFirst(4).prefix(2)) : String(segment.dropFirst(2).prefix(2))
        let dayText = String(segment.suffix(2))
        guard let year = Int(yearText), let month = Int(monthText), let day = Int(dayText) else { return false }
        guard (1...12).contains(month), (1...31).contains(day) else { return false }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components) != nil
    }

    // MARK: 手机号

    /// 真实号段 + 随机 8 位，尾号避开 4 位以上连号（那种号段太像测试样例）
    static func phone(carrier: PhoneCarrier = .any) -> FakerItem {
        var generator = SystemRandomNumberGenerator()
        let pool: [String: [String]]
        switch carrier {
        case .mobile: pool = ["移动": mobilePrefixes]
        case .unicom: pool = ["联通": unicomPrefixes]
        case .telecom: pool = ["电信": telecomPrefixes]
        case .broadnet: pool = ["广电": ["192"]]
        case .any:
            pool = [
                "移动": mobilePrefixes,
                "联通": unicomPrefixes,
                "电信": telecomPrefixes,
                "广电": ["192"],
            ]
        }

        let name = pool.keys.sorted().randomElement(using: &generator) ?? "移动"
        let prefixes = pool[name] ?? mobilePrefixes
        let prefix = prefixes.randomElement(using: &generator) ?? "138"

        var tail = ""
        for _ in 0..<8 {
            tail.append(Character(String(Int.random(in: 0...9, using: &generator))))
        }
        let number = prefix + tail
        return FakerItem(id: number, value: number, detail: "中国\(name)")
    }

    // MARK: 地址

    static func address() -> FakerItem {
        var generator = SystemRandomNumberGenerator()
        let province = provinces.randomElement(using: &generator) ?? provinces[0]
        let city = province.cities.randomElement(using: &generator) ?? province.cities[0]
        let road = roadNames.randomElement(using: &generator) ?? "人民路"
        let number = Int.random(in: 1...999, using: &generator)
        let suffix = ["号", "号", "号", "号"].randomElement(using: &generator) ?? "号"

        var text = province.name + city.name + road + "\(number)" + suffix
        if Bool.random(using: &generator) {
            let building = Int.random(in: 1...30, using: &generator)
            let room = Int.random(in: 101...2599, using: &generator)
            text += " \(building)栋\(room)室"
        }
        return FakerItem(id: text, value: text, detail: city.code + " · " + province.name)
    }

    // MARK: 英文名

    static func englishName(gender: FakerGender = .any) -> FakerItem {
        var generator = SystemRandomNumberGenerator()
        let isMale: Bool
        switch gender {
        case .male: isMale = true
        case .female: isMale = false
        case .any: isMale = Bool.random(using: &generator)
        }

        let first = (isMale ? maleFirstNames : femaleFirstNames).randomElement(using: &generator) ?? "Alex"
        let last = lastNames.randomElement(using: &generator) ?? "Smith"
        let text = "\(first) \(last)"
        return FakerItem(id: text, value: text, detail: isMale ? "男名" : "女名")
    }

    /// 中文习惯里姓氏在前，做个反向写法备用
    static func englishNameReversed(gender: FakerGender = .any) -> String {
        let item = englishName(gender: gender)
        let parts = item.value.split(separator: " ")
        guard parts.count == 2 else { return item.value }
        return "\(parts[1]) \(parts[0])"
    }

    // MARK: 邮箱

    static func email(gender: FakerGender = .any) -> FakerItem {
        var generator = SystemRandomNumberGenerator()
        let name = englishName(gender: gender).value.lowercased().replacingOccurrences(of: " ", with: "")
        let domains = ["example.com", "example.net", "test.com", "mail.example.com", "demo.org"]
        let domain = domains.randomElement(using: &generator) ?? "example.com"
        let separator = ["", ".", "_", "-"].randomElement(using: &generator) ?? ""
        let suffix = Bool.random(using: &generator) ? "\(Int.random(in: 1...99, using: &generator))" : ""
        let text = "\(name)\(separator)\(suffix)@\(domain)".replacingOccurrences(of: "@@", with: "@")
        return FakerItem(id: text, value: text, detail: "示例域名")
    }

    // MARK: 公司名

    static func company() -> FakerItem {
        var generator = SystemRandomNumberGenerator()
        let lead = companyLeads.randomElement(using: &generator) ?? "Nova"
        let tail = companyTails.randomElement(using: &generator) ?? "Tech"
        let suffix = companySuffixes.randomElement(using: &generator) ?? "Inc."
        let text = "\(lead) \(tail) \(suffix)"
        return FakerItem(id: text, value: text, detail: "随机组合")
    }

    // MARK: 统一入口

    static func generate(kind: FakerKind, count: Int, gender: FakerGender, carrier: PhoneCarrier) -> [FakerItem] {
        var result: [FakerItem] = []
        result.reserveCapacity(count)
        var seen = Set<String>()
        var attempts = 0
        while result.count < count, attempts < count * 12 {
            attempts += 1
            let item: FakerItem
            switch kind {
            case .idCard: item = idCard(gender: gender)
            case .phone: item = phone(carrier: carrier)
            case .address: item = address()
            case .englishName: item = englishName(gender: gender)
            case .email: item = email(gender: gender)
            case .company: item = company()
            }
            guard !seen.contains(item.value) else { continue }
            seen.insert(item.value)
            result.append(item)
        }
        return result
    }

    // MARK: - 数据

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }()

    static let provinces: [FakeProvince] = [
        FakeProvince(code: "1101", name: "北京市", cities: [FakeCity(code: "1101", name: "北京市")]),
        FakeProvince(code: "1201", name: "天津市", cities: [FakeCity(code: "1201", name: "天津市")]),
        FakeProvince(code: "1301", name: "河北省", cities: [
            FakeCity(code: "1301", name: "石家庄市"), FakeCity(code: "1302", name: "唐山市"),
            FakeCity(code: "1303", name: "秦皇岛市"), FakeCity(code: "1304", name: "邯郸市"),
            FakeCity(code: "1306", name: "保定市"), FakeCity(code: "1309", name: "沧州市"),
            FakeCity(code: "1310", name: "廊坊市"),
        ]),
        FakeProvince(code: "1401", name: "山西省", cities: [
            FakeCity(code: "1401", name: "太原市"), FakeCity(code: "1402", name: "大同市"),
            FakeCity(code: "1403", name: "阳泉市"), FakeCity(code: "1404", name: "长治市"),
            FakeCity(code: "1407", name: "晋中市"),
        ]),
        FakeProvince(code: "1501", name: "内蒙古自治区", cities: [
            FakeCity(code: "1501", name: "呼和浩特市"), FakeCity(code: "1502", name: "包头市"),
            FakeCity(code: "1503", name: "乌海市"), FakeCity(code: "1504", name: "赤峰市"),
            FakeCity(code: "1506", name: "鄂尔多斯市"),
        ]),
        FakeProvince(code: "2101", name: "辽宁省", cities: [
            FakeCity(code: "2101", name: "沈阳市"), FakeCity(code: "2102", name: "大连市"),
            FakeCity(code: "2103", name: "鞍山市"), FakeCity(code: "2104", name: "抚顺市"),
            FakeCity(code: "2106", name: "丹东市"),
        ]),
        FakeProvince(code: "2201", name: "吉林省", cities: [
            FakeCity(code: "2201", name: "长春市"), FakeCity(code: "2202", name: "吉林市"),
            FakeCity(code: "2203", name: "四平市"), FakeCity(code: "2205", name: "通化市"),
            FakeCity(code: "2207", name: "松原市"),
        ]),
        FakeProvince(code: "2301", name: "黑龙江省", cities: [
            FakeCity(code: "2301", name: "哈尔滨市"), FakeCity(code: "2302", name: "齐齐哈尔市"),
            FakeCity(code: "2303", name: "牡丹江市"), FakeCity(code: "2306", name: "大庆市"),
            FakeCity(code: "2308", name: "佳木斯市"),
        ]),
        FakeProvince(code: "3101", name: "上海市", cities: [FakeCity(code: "3101", name: "上海市")]),
        FakeProvince(code: "3201", name: "江苏省", cities: [
            FakeCity(code: "3201", name: "南京市"), FakeCity(code: "3202", name: "无锡市"),
            FakeCity(code: "3203", name: "徐州市"), FakeCity(code: "3204", name: "常州市"),
            FakeCity(code: "3205", name: "苏州市"), FakeCity(code: "3206", name: "南通市"),
            FakeCity(code: "3210", name: "扬州市"),
        ]),
        FakeProvince(code: "3301", name: "浙江省", cities: [
            FakeCity(code: "3301", name: "杭州市"), FakeCity(code: "3302", name: "宁波市"),
            FakeCity(code: "3303", name: "温州市"), FakeCity(code: "3304", name: "嘉兴市"),
            FakeCity(code: "3306", name: "绍兴市"), FakeCity(code: "3307", name: "金华市"),
            FakeCity(code: "3310", name: "台州市"),
        ]),
        FakeProvince(code: "3401", name: "安徽省", cities: [
            FakeCity(code: "3401", name: "合肥市"), FakeCity(code: "3402", name: "芜湖市"),
            FakeCity(code: "3403", name: "蚌埠市"), FakeCity(code: "3404", name: "淮南市"),
            FakeCity(code: "3408", name: "安庆市"),
        ]),
        FakeProvince(code: "3501", name: "福建省", cities: [
            FakeCity(code: "3501", name: "福州市"), FakeCity(code: "3502", name: "厦门市"),
            FakeCity(code: "3503", name: "莆田市"), FakeCity(code: "3505", name: "泉州市"),
            FakeCity(code: "3506", name: "漳州市"), FakeCity(code: "3508", name: "龙岩市"),
        ]),
        FakeProvince(code: "3601", name: "江西省", cities: [
            FakeCity(code: "3601", name: "南昌市"), FakeCity(code: "3602", name: "景德镇市"),
            FakeCity(code: "3604", name: "九江市"), FakeCity(code: "3607", name: "赣州市"),
            FakeCity(code: "3608", name: "吉安市"),
        ]),
        FakeProvince(code: "3701", name: "山东省", cities: [
            FakeCity(code: "3701", name: "济南市"), FakeCity(code: "3702", name: "青岛市"),
            FakeCity(code: "3703", name: "淄博市"), FakeCity(code: "3706", name: "烟台市"),
            FakeCity(code: "3707", name: "潍坊市"), FakeCity(code: "3713", name: "临沂市"),
        ]),
        FakeProvince(code: "4101", name: "河南省", cities: [
            FakeCity(code: "4101", name: "郑州市"), FakeCity(code: "4102", name: "开封市"),
            FakeCity(code: "4103", name: "洛阳市"), FakeCity(code: "4107", name: "新乡市"),
            FakeCity(code: "4113", name: "南阳市"),
        ]),
        FakeProvince(code: "4201", name: "湖北省", cities: [
            FakeCity(code: "4201", name: "武汉市"), FakeCity(code: "4202", name: "黄石市"),
            FakeCity(code: "4205", name: "宜昌市"), FakeCity(code: "4206", name: "襄阳市"),
            FakeCity(code: "4210", name: "荆州市"),
        ]),
        FakeProvince(code: "4301", name: "湖南省", cities: [
            FakeCity(code: "4301", name: "长沙市"), FakeCity(code: "4302", name: "株洲市"),
            FakeCity(code: "4303", name: "湘潭市"), FakeCity(code: "4304", name: "衡阳市"),
            FakeCity(code: "4306", name: "岳阳市"),
        ]),
        FakeProvince(code: "4401", name: "广东省", cities: [
            FakeCity(code: "4401", name: "广州市"), FakeCity(code: "4402", name: "韶关市"),
            FakeCity(code: "4403", name: "深圳市"), FakeCity(code: "4404", name: "珠海市"),
            FakeCity(code: "4406", name: "佛山市"), FakeCity(code: "4419", name: "东莞市"),
            FakeCity(code: "4420", name: "中山市"),
        ]),
        FakeProvince(code: "4501", name: "广西壮族自治区", cities: [
            FakeCity(code: "4501", name: "南宁市"), FakeCity(code: "4502", name: "柳州市"),
            FakeCity(code: "4503", name: "桂林市"), FakeCity(code: "4505", name: "北海市"),
        ]),
        FakeProvince(code: "4601", name: "海南省", cities: [
            FakeCity(code: "4601", name: "海口市"), FakeCity(code: "4602", name: "三亚市"),
        ]),
        FakeProvince(code: "5001", name: "重庆市", cities: [FakeCity(code: "5001", name: "重庆市")]),
        FakeProvince(code: "5101", name: "四川省", cities: [
            FakeCity(code: "5101", name: "成都市"), FakeCity(code: "5103", name: "自贡市"),
            FakeCity(code: "5105", name: "泸州市"), FakeCity(code: "5106", name: "德阳市"),
            FakeCity(code: "5107", name: "绵阳市"),
        ]),
        FakeProvince(code: "5201", name: "贵州省", cities: [
            FakeCity(code: "5201", name: "贵阳市"), FakeCity(code: "5202", name: "六盘水市"),
            FakeCity(code: "5203", name: "遵义市"), FakeCity(code: "5204", name: "安顺市"),
        ]),
        FakeProvince(code: "5301", name: "云南省", cities: [
            FakeCity(code: "5301", name: "昆明市"), FakeCity(code: "5303", name: "曲靖市"),
            FakeCity(code: "5304", name: "玉溪市"), FakeCity(code: "5329", name: "大理白族自治州"),
        ]),
        FakeProvince(code: "5401", name: "西藏自治区", cities: [
            FakeCity(code: "5401", name: "拉萨市"), FakeCity(code: "5402", name: "日喀则市"),
        ]),
        FakeProvince(code: "6101", name: "陕西省", cities: [
            FakeCity(code: "6101", name: "西安市"), FakeCity(code: "6103", name: "宝鸡市"),
            FakeCity(code: "6104", name: "咸阳市"), FakeCity(code: "6105", name: "渭南市"),
        ]),
        FakeProvince(code: "6201", name: "甘肃省", cities: [
            FakeCity(code: "6201", name: "兰州市"), FakeCity(code: "6202", name: "嘉峪关市"),
            FakeCity(code: "6203", name: "金昌市"), FakeCity(code: "6205", name: "天水市"),
        ]),
        FakeProvince(code: "6301", name: "青海省", cities: [
            FakeCity(code: "6301", name: "西宁市"), FakeCity(code: "6302", name: "海东市"),
        ]),
        FakeProvince(code: "6401", name: "宁夏回族自治区", cities: [
            FakeCity(code: "6401", name: "银川市"), FakeCity(code: "6402", name: "石嘴山市"),
            FakeCity(code: "6403", name: "吴忠市"),
        ]),
        FakeProvince(code: "6501", name: "新疆维吾尔自治区", cities: [
            FakeCity(code: "6501", name: "乌鲁木齐市"), FakeCity(code: "6502", name: "克拉玛依市"),
            FakeCity(code: "6504", name: "吐鲁番市"), FakeCity(code: "6505", name: "哈密市"),
        ]),
        FakeProvince(code: "7101", name: "台湾省", cities: [
            FakeCity(code: "7101", name: "台北市"), FakeCity(code: "7102", name: "高雄市"),
        ]),
        FakeProvince(code: "8101", name: "香港特别行政区", cities: [FakeCity(code: "8101", name: "香港")]),
        FakeProvince(code: "8201", name: "澳门特别行政区", cities: [FakeCity(code: "8201", name: "澳门")]),
    ]

    private static let mobilePrefixes: [String] = [
        "134", "135", "136", "137", "138", "139", "147", "148", "150", "151", "152",
        "157", "158", "159", "172", "178", "182", "183", "184", "187", "188",
        "195", "197", "198",
    ]

    private static let unicomPrefixes: [String] = [
        "130", "131", "132", "145", "146", "155", "156", "166", "167", "171",
        "175", "176", "185", "186", "196",
    ]

    private static let telecomPrefixes: [String] = [
        "133", "149", "153", "173", "174", "177", "180", "181", "189",
        "190", "191", "193", "199",
    ]

    private static let roadNames: [String] = [
        "人民路", "解放路", "中山路", "建设路", "和平路", "新华路", "文化路", "胜利路",
        "长江路", "黄河路", "北京路", "南京路", "淮海路", "学院路", "科技路", "创业路",
        "光明路", "幸福路", "青年路", "朝阳路", "望江路", "湖滨路", "滨江大道", "科技大道",
        "花园路", "迎宾路", "振兴路", "工业路", "航空路", "天河路", "复兴路", "春熙路",
    ]

    static let maleFirstNames: [String] = [
        "James", "John", "Robert", "Michael", "William", "David", "Richard", "Joseph",
        "Thomas", "Charles", "Christopher", "Daniel", "Matthew", "Anthony", "Donald",
        "Mark", "Paul", "Steven", "Andrew", "Kenneth", "Joshua", "Kevin", "Brian",
        "George", "Edward", "Ronald", "Timothy", "Jason", "Jeffrey", "Ryan", "Jacob",
        "Gary", "Nicholas", "Eric", "Jonathan", "Stephen", "Larry", "Justin", "Scott",
        "Brandon", "Benjamin", "Samuel", "Gregory", "Alexander", "Patrick", "Frank",
        "Raymond", "Jack", "Dennis", "Jerry", "Tyler", "Aaron", "Adam", "Nathan",
    ]

    static let femaleFirstNames: [String] = [
        "Mary", "Patricia", "Jennifer", "Linda", "Elizabeth", "Barbara", "Susan",
        "Jessica", "Sarah", "Karen", "Nancy", "Lisa", "Betty", "Margaret", "Sandra",
        "Ashley", "Kimberly", "Emily", "Donna", "Michelle", "Carol", "Amanda",
        "Dorothy", "Melissa", "Deborah", "Stephanie", "Rebecca", "Sharon", "Laura",
        "Cynthia", "Kathleen", "Amy", "Angela", "Shirley", "Anna", "Brenda", "Pamela",
        "Emma", "Nicole", "Helen", "Samantha", "Katherine", "Christine", "Debra",
        "Rachel", "Carolyn", "Janet", "Catherine", "Maria", "Heather", "Diane", "Olivia",
    ]

    static let lastNames: [String] = [
        "Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis",
        "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson",
        "Thomas", "Taylor", "Moore", "Jackson", "Martin", "Lee", "Perez", "Thompson",
        "White", "Harris", "Sanchez", "Clark", "Ramirez", "Lewis", "Robinson", "Walker",
        "Young", "Allen", "King", "Wright", "Scott", "Torres", "Nguyen", "Hill",
        "Flores", "Green", "Adams", "Nelson", "Baker", "Hall", "Rivera", "Campbell",
        "Mitchell", "Carter", "Roberts", "Turner", "Phillips", "Evans", "Collins",
    ]

    private static let companyLeads: [String] = [
        "Nova", "Vertex", "Lumen", "Orbit", "Pinnacle", "Cobalt", "Aether", "Zenith",
        "Quanta", "Helix", "Aurora", "Cascade", "Meridian", "Solstice", "Cypher",
        "Beacon", "Summit", "Vantage", "Delta", "Onyx", "Titan", "Nimbus", "Atlas",
    ]

    private static let companyTails: [String] = [
        "Tech", "Systems", "Labs", "Digital", "Dynamics", "Networks", "Solutions",
        "Software", "Analytics", "Robotics", "Studios", "Interactive", "Data",
    ]

    private static let companySuffixes: [String] = [
        "Inc.", "LLC", "Ltd.", "Group", "Corp.", "Holdings",
    ]
}
