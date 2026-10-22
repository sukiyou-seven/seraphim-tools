import Foundation
import CoreGraphics

// MARK: - 尺码数据
//
// 换算的难点从来不是算术，是「同一个数字在不同体系里不是一回事」。
// 所以每张表都以**量出来的净尺寸**当轴心（脚长 / 胸围 / 腰围 / 身高），
// 标号再围着它排。买衣服鞋子最靠谱的一步永远是先量身体，不是对着标号猜。

extension SizeEngine {

    // MARK: - 列的公共定义

    enum Col {
        // 鞋
        static let foot = SizeColumn(
            id: "foot", title: "脚长 cm", aliases: ["脚长", "足长", "foot"],
            width: 78, isMeasurement: true
        )
        static let cnShoe = SizeColumn(
            id: "cnShoe", title: "中国码 mm", aliases: ["中国", "国内", "国标", "cn", "毫米", "mm"],
            width: 76, isMeasurement: true
        )
        static let eu = SizeColumn(
            id: "eu", title: "欧码", aliases: ["欧洲", "欧洲码", "欧", "eu"], width: 54
        )
        static let usMen = SizeColumn(
            id: "usMen", title: "美码 男", aliases: ["美码男", "美男", "us男", "usm"], width: 64
        )
        static let usWomen = SizeColumn(
            id: "usWomen", title: "美码 女", aliases: ["美码女", "美女", "us女", "usw"], width: 64
        )
        static let us = SizeColumn(
            id: "us", title: "美码", aliases: ["美国", "美国码", "美", "us"], width: 58
        )
        static let uk = SizeColumn(
            id: "uk", title: "英码", aliases: ["英国", "英国码", "英", "uk"], width: 54
        )

        // 衣服
        static let cnType = SizeColumn(
            id: "cnType", title: "中国号型", aliases: ["号型", "中国号型", "国标号型"],
            width: 92, isMeasurement: true
        )
        static let cn = SizeColumn(
            id: "cn", title: "中国码", aliases: ["中国", "国内", "国内码", "cn"], width: 58
        )
        static let intl = SizeColumn(
            id: "intl", title: "国际码", aliases: ["国际", "欧美码", "字母码", "intl"], width: 58
        )
        static let fr = SizeColumn(
            id: "fr", title: "法码", aliases: ["法国", "法国码", "fr"],
            width: 54, visibleByDefault: false
        )
        static let it = SizeColumn(
            id: "it", title: "意码", aliases: ["意大利", "意大利码", "it"],
            width: 54, visibleByDefault: false
        )
        static let bust = SizeColumn(
            id: "bust", title: "净胸围 cm", aliases: ["胸围", "净胸围", "bust"],
            width: 74, isMeasurement: true
        )
        static let waist = SizeColumn(
            id: "waist", title: "净腰围 cm", aliases: ["腰围", "净腰围", "waist"],
            width: 74, isMeasurement: true
        )
        static let hip = SizeColumn(
            id: "hip", title: "净臀围 cm", aliases: ["臀围", "净臀围", "hip"],
            width: 74, isMeasurement: true
        )
        static let jeans = SizeColumn(
            id: "jeans", title: "牛仔裤 W in", aliases: ["牛仔裤", "牛仔", "英寸", "寸"],
            width: 82, isMeasurement: true
        )
        static let usPants = SizeColumn(
            id: "usPants", title: "美码 / 英码 in", aliases: ["美码", "英码", "美国", "英国", "w"],
            width: 96, isMeasurement: true
        )
        static let height = SizeColumn(
            id: "height", title: "中国码（身高）", aliases: ["中国码", "身高", "中国", "国内", "cm"],
            width: 116, isMeasurement: true
        )
        static let age = SizeColumn(
            id: "age", title: "参考年龄", aliases: ["年龄", "岁数", "age"], width: 74
        )
    }

    // MARK: - 全部表

    static let charts: [SizeChart] = [
        adultShoes, kidsShoes,
        womenTops, womenBottoms, menTops, menBottoms, kidsClothes,
    ]

    // MARK: - 鞋：换算公式
    //
    // 鞋码之所以让人头大，是因为各体系各自定起点定刻度，而且刻度之间**除不尽**：
    // 欧码一格 2/3 cm，美码英码一格 1/3 英寸（0.847cm）。所以不存在一张「每格都对齐」
    // 的表——只能挑一个体系当行序，其余按公式就近取。
    //
    // 这里挑欧码当行序，因为中国人口语里的「42 码」说的就是它；反过来按脚长排行，
    // 欧码列会长出 39、40、42 这种空洞，用户搜自己脚上那个码直接搜不到。
    //
    //   EU   = 1.5 × 脚长cm + 2.5    巴黎点，1 点 = 2/3 cm，含鞋楦余量
    //   US男 = 3 × 脚长in − 22.5     大麦粒，1 码 = 1/3 英寸
    //   US女 = US男 + 1.5            同一双脚，女鞋标号大 1.5
    //   UK   = 3 × 脚长in − 23
    //
    // 这四式跟真实的鞋标逐行对得上：EUR 40 ↔ 脚长 25.0 ↔ US 7；EUR 42 ↔ 26.5 ↔ US 8.5；
    // EUR 44 ↔ 28.0 ↔ US 10；女鞋 US W 8.5 ↔ 脚长 25.0 ↔ EUR 40。都不是凑出来的。

    /// 欧码 → 脚长（厘米）。行序由欧码定，脚长是算出来的。
    static func footLength(eu: Double) -> Double {
        (eu - 2.5) / 1.5
    }

    /// 脚长（厘米）→ 美码男 / 美码女 / 英码
    static func usUKCode(footCM: Double) -> (usMen: Double, usWomen: Double, uk: Double) {
        let inches = footCM / 2.54
        return (
            usMen: roundHalf(inches * 3 - 22.5),
            usWomen: roundHalf(inches * 3 - 21),
            uk: roundHalf(inches * 3 - 23)
        )
    }

    /// 中国码（GB/T 3293）就是脚长的毫米数，按 5mm 一档取最近的
    static func chinaShoeCode(footCM: Double) -> String {
        String(Int((footCM * 10 / 5).rounded() * 5))
    }

    static let adultShoes = SizeChart(
        id: "adultShoe",
        title: "成人鞋码",
        group: .shoe,
        systemImage: "shoe",
        pivotColumnID: "foot",
        columns: [Col.foot, Col.cnShoe, Col.eu, Col.usMen, Col.usWomen, Col.uk],
        rows: (0...28).map { index -> SizeRow in
            let eu = 34.0 + Double(index) * 0.5
            let foot = footLength(eu: eu)
            let code = usUKCode(footCM: foot)
            return SizeRow(
                id: "adult-\(index)",
                values: [
                    "foot": sizeText(foot),
                    "cnShoe": chinaShoeCode(footCM: foot),
                    "eu": sizeText(eu),
                    "usMen": sizeText(code.usMen),
                    "usWomen": sizeText(code.usWomen),
                    "uk": sizeText(code.uk),
                ],
                pivot: foot
            )
        },
        measure: [
            "靠墙平踩一张纸，脚跟顶住墙，笔身垂直画出最长脚趾的端点",
            "量脚跟到脚尖的距离就是脚长；两只脚都量，按大的那只买",
            "下午或傍晚量——走了一天脚会涨，早上量容易买紧",
        ],
        notes: [
            "中国码（GB/T 3293）就是脚长的毫米数，260 代表脚长 260mm；日码是同一个量的厘米写法（26.0），跟表里的脚长列一模一样。",
            "**国产鞋和欧洲品牌的鞋，同一个脚长能差一个码，这是买鞋最常踩的坑。** 网上流传的国内对照表把脚长 260mm 对到「42 码」，比真实欧洲码小一档（欧码 42 其实对应脚长 26.5cm）——因为国产鞋楦留的余量更大。所以平时穿国产 42 的人，买按 EUR 标的国际品牌常常要 42.5 甚至 43。本表的欧码按巴黎点标准算，和鞋标上的 EUR 一致。",
            "美码分男女，也是这一页最容易翻车的地方：同一双脚，女鞋要比男鞋大 1.5 个号（女 9 ≈ 男 7.5）。买中性款、男女同款、或者海淘时特别容易踩。",
            "同一列里的值只是公式算出来的标准对应，各家版型仍有出入——运动鞋、皮鞋、靴子的鞋楦余量差得不少，同一个人在不同品牌之间差半码很常见。",
            "买鞋留 0.5–1cm 余量（约一根手指宽），脚趾顶到头走两步，前掌挤不挤才是关键。",
        ]
    )

    // MARK: - 鞋：儿童

    /// 儿童鞋的欧码沿用成人那套公式；美码 / 英码另起一套起点
    /// （13 号之后进入青少年码 1Y、2Y…，所以同一个数字在不同区段含义完全不同）。
    static func kidsUSCode(footCM: Double) -> String {
        let raw = roundHalf(footCM / 2.54 * 3 - 9.5)
        if raw <= 13 { return sizeText(raw) }
        return sizeText(raw - 12.5) + "Y"
    }

    static func kidsUKCode(footCM: Double) -> String {
        let raw = roundHalf(footCM / 2.54 * 3 - 10.5)
        if raw <= 13 { return sizeText(raw) }
        return sizeText(raw - 12.5) + "Y"
    }

    /// 脚长 → 大致年龄。儿童鞋标号各家差得远，说年龄反而好沟通。
    private static let kidAgeBreaks: [(Double, String)] = [
        (11.0, "1 岁"), (12.5, "1.5 岁"), (13.5, "2 岁"), (14.5, "2.5 岁"),
        (15.5, "3 岁"), (16.5, "4 岁"), (17.5, "5 岁"), (18.5, "6 岁"),
        (19.5, "7 岁"), (20.5, "8 岁"), (21.5, "9 岁"), (22.5, "10 岁"),
    ]

    static func kidAge(footCM: Double) -> String {
        for (upper, text) in kidAgeBreaks where footCM < upper { return text }
        return "10 岁以上"
    }

    static let kidsShoes = SizeChart(
        id: "kidsShoe",
        title: "儿童鞋码",
        group: .shoe,
        systemImage: "figure.child",
        pivotColumnID: "foot",
        columns: [Col.foot, Col.cnShoe, Col.eu, Col.us, Col.uk, Col.age],
        rows: (0...28).map { index -> SizeRow in
            let eu = 20.0 + Double(index) * 0.5
            let foot = footLength(eu: eu)
            return SizeRow(
                id: "kidshoe-\(index)",
                values: [
                    "foot": sizeText(foot),
                    "cnShoe": chinaShoeCode(footCM: foot),
                    "eu": sizeText(eu),
                    "us": kidsUSCode(footCM: foot),
                    "uk": kidsUKCode(footCM: foot),
                    "age": kidAge(footCM: foot),
                ],
                pivot: foot
            )
        },
        measure: [
            "让孩子站直踩在纸上，脚跟顶墙，画出最长脚趾的端点",
            "量脚长，再留 0.5–1cm 余量——太紧会顶脚，太大不跟脚容易绊倒",
            "每 2–3 个月量一次，3 岁前长得尤其快",
        ],
        notes: [
            "童鞋的国际码各品牌差异最大，优先按**脚长**选，别只看标号。表里给的是标准对应，实际下单前扫一眼品牌自己的尺码表更稳妥。",
            "美码 13 号之后进入青少年码（1Y、2Y…），所以「13」和「1Y」其实是紧挨着的——同一个数字在不同区段含义完全不同。",
            "脚长超过 21cm 左右就可以直接看成人鞋码表了，青少年鞋和成人鞋的尺码已经接上。",
            "参考年龄只是大概——同龄孩子的脚能差两三个码，量脚长才算数。",
        ]
    )

    // MARK: - 女装上衣（含连衣裙）

    static let womenTops = SizeChart(
        id: "womenTop",
        title: "女装上衣",
        group: .clothing,
        systemImage: "tshirt",
        pivotColumnID: "bust",
        columns: [Col.cnType, Col.cn, Col.intl, Col.eu, Col.us, Col.uk, Col.fr, Col.it, Col.bust, Col.waist],
        rows: [
            row("wt-0", cnType: "150/76A", cn: "XS", intl: "XXS", eu: "32", us: "0", uk: "4", fr: "34", it: "36", bust: 76, waist: 62),
            row("wt-1", cnType: "155/80A", cn: "S", intl: "XS", eu: "34", us: "2", uk: "6", fr: "36", it: "38", bust: 80, waist: 66),
            row("wt-2", cnType: "160/84A", cn: "M", intl: "S", eu: "36", us: "4", uk: "8", fr: "38", it: "40", bust: 84, waist: 70),
            row("wt-3", cnType: "165/88A", cn: "L", intl: "M", eu: "38", us: "6", uk: "10", fr: "40", it: "42", bust: 88, waist: 74),
            row("wt-4", cnType: "170/92A", cn: "XL", intl: "L", eu: "40", us: "8", uk: "12", fr: "42", it: "44", bust: 92, waist: 78),
            row("wt-5", cnType: "175/96A", cn: "XXL", intl: "XL", eu: "42", us: "10", uk: "14", fr: "44", it: "46", bust: 96, waist: 82),
            row("wt-6", cnType: "180/100A", cn: "3XL", intl: "XXL", eu: "44", us: "12", uk: "16", fr: "46", it: "48", bust: 100, waist: 86),
            row("wt-7", cnType: "185/104A", cn: "4XL", intl: "3XL", eu: "46", us: "14", uk: "18", fr: "48", it: "50", bust: 104, waist: 90),
        ],
        measure: [
            "胸围量最丰满处一圈，软尺水平、不勒不松，穿薄内衣量",
            "腰围量腰部最细处（一般在肚脐上方），正常呼吸别收腹",
            "身高光脚靠墙量，号型里的第一个数字要的就是它",
        ],
        notes: [
            "中国号型来自 GB/T 1335：斜杠前是身高、后面是净胸围加体型代号。A 是标准体（胸腰差 14–18cm），Y 偏瘦、B 偏丰满、C 更丰满。160/84A 读作「身高 160 上下、净胸围 84 上下、标准体」。",
            "**国内标码普遍比国际码大一档**：同样身材，国内吊牌写 M，欧美吊牌往往写 S。所以别拿 S/M/L 直接对，看净胸围最稳。",
            "欧码和美码之间没有精确公式，这里的对应按人体净尺寸对齐（欧码 36 ↔ 净胸围 84cm），是通行的对应关系。",
            "买欧洲品牌注意区分：法国码 = 欧码 + 2，意大利码 = 欧码 + 4（欧码 38 = 法码 40 = 意码 42）。这两列默认收起了，点上面的标签展开。",
            "连衣裙还要看身高对长度的影响；宽松版型可以按净胸围选小一档，修身版型宁大勿小。",
        ]
    )

    // MARK: - 女装下装（裤 / 裙）

    static let womenBottoms = SizeChart(
        id: "womenBottom",
        title: "女装下装",
        group: .clothing,
        systemImage: "figure.stand",
        pivotColumnID: "waist",
        columns: [Col.cnType, Col.cn, Col.intl, Col.eu, Col.us, Col.uk, Col.fr, Col.it, Col.waist, Col.hip, Col.jeans],
        rows: [
            row("wb-0", cnType: "150/60A", cn: "XS", intl: "XXS", eu: "32", us: "0", uk: "4", fr: "34", it: "36", waist: 60, hip: 84, jeans: "24"),
            row("wb-1", cnType: "155/64A", cn: "S", intl: "XS", eu: "34", us: "2", uk: "6", fr: "36", it: "38", waist: 64, hip: 88, jeans: "25"),
            row("wb-2", cnType: "160/68A", cn: "M", intl: "S", eu: "36", us: "4", uk: "8", fr: "38", it: "40", waist: 68, hip: 92, jeans: "27"),
            row("wb-3", cnType: "165/72A", cn: "L", intl: "M", eu: "38", us: "6", uk: "10", fr: "40", it: "42", waist: 72, hip: 96, jeans: "28"),
            row("wb-4", cnType: "170/76A", cn: "XL", intl: "L", eu: "40", us: "8", uk: "12", fr: "42", it: "44", waist: 76, hip: 100, jeans: "30"),
            row("wb-5", cnType: "175/80A", cn: "XXL", intl: "XL", eu: "42", us: "10", uk: "14", fr: "44", it: "46", waist: 80, hip: 104, jeans: "31"),
            row("wb-6", cnType: "180/84A", cn: "3XL", intl: "XXL", eu: "44", us: "12", uk: "16", fr: "46", it: "48", waist: 84, hip: 108, jeans: "33"),
        ],
        measure: [
            "腰围量腰部最细处一圈，别收腹也别吸气",
            "臀围量臀部最丰满处一圈，软尺保持水平",
            "裤长从腰侧沿腿外侧量到脚踝，比尺码更容易踩坑",
        ],
        notes: [
            "下装按**净腰围**选最稳；臀围只要差得不太多，一般版型都能穿下。",
            "牛仔裤（美码 W）按英寸卖，1 英寸 = 2.54cm。腰围厘米数除以 2.54 就是大致英寸数，例如 68cm ≈ 27 英寸。",
            "高腰、中腰、低腰的腰位不同，同一个标号的实际腰围能差 2–3cm——买之前确认腰位，比确认尺码更管用。",
            "有弹力的面料可以按小一档选，无弹的西装料、牛仔布宁可大一点。",
        ]
    )

    // MARK: - 男装上衣

    static let menTops = SizeChart(
        id: "menTop",
        title: "男装上衣",
        group: .clothing,
        systemImage: "tshirt",
        pivotColumnID: "bust",
        columns: [Col.cnType, Col.cn, Col.intl, Col.eu, Col.us, Col.uk, Col.bust, Col.waist],
        rows: [
            row("mt-0", cnType: "160/80A", cn: "XS", intl: "XXS", eu: "42", us: "32", uk: "32", bust: 80, waist: 68),
            row("mt-1", cnType: "165/84A", cn: "S", intl: "XS", eu: "44", us: "34", uk: "34", bust: 84, waist: 72),
            row("mt-2", cnType: "170/88A", cn: "M", intl: "S", eu: "46", us: "36", uk: "36", bust: 88, waist: 76),
            row("mt-3", cnType: "175/92A", cn: "L", intl: "M", eu: "48", us: "38", uk: "38", bust: 92, waist: 80),
            row("mt-4", cnType: "180/96A", cn: "XL", intl: "L", eu: "50", us: "40", uk: "40", bust: 96, waist: 84),
            row("mt-5", cnType: "185/100A", cn: "XXL", intl: "XL", eu: "52", us: "42", uk: "42", bust: 100, waist: 88),
            row("mt-6", cnType: "190/104A", cn: "3XL", intl: "XXL", eu: "54", us: "44", uk: "44", bust: 104, waist: 92),
        ],
        measure: [
            "胸围量腋下最丰满处一圈，软尺水平，手臂自然下垂",
            "腰围量腰部最细处，A 体型的男装号型里，腰围通常比胸围小 12cm 左右",
            "衬衫另看领围：软尺绕脖子根部一圈，留一根手指的余量",
        ],
        notes: [
            "中国号型 170/88A 读作「身高 170 上下、净胸围 88 上下、标准体」。男装 A 体型的胸腰差约 12–16cm。",
            "欧码和美码差 10：欧码 48 = 美码 38，两者都指向同一个胸围。**这个规律只对男装成立**，女装不是这么算的。",
            "欧美男装的字母码也普遍比国内小一档：同样身材国内穿 L，欧美常常是 M。",
            "买衬衫、西装外套时还要看肩宽和袖长——胸围对了肩线不对照样不能穿。",
            "卫衣、T 恤这类宽松版型，按净胸围选到大一档通常更舒服；正装按净胸围贴身选。",
        ]
    )

    // MARK: - 男装下装

    static let menBottoms = SizeChart(
        id: "menBottom",
        title: "男装下装",
        group: .clothing,
        systemImage: "figure.stand",
        pivotColumnID: "waist",
        columns: [Col.cnType, Col.cn, Col.intl, Col.eu, Col.usPants, Col.waist, Col.hip, Col.jeans],
        rows: [
            row("mb-0", cnType: "165/68A", cn: "XS", intl: "XXS", eu: "42", usPants: "W27", waist: 68, hip: 92, jeans: "27"),
            row("mb-1", cnType: "170/72A", cn: "S", intl: "XS", eu: "44", usPants: "W28", waist: 72, hip: 96, jeans: "28"),
            row("mb-2", cnType: "175/76A", cn: "M", intl: "S", eu: "46", usPants: "W30", waist: 76, hip: 100, jeans: "30"),
            row("mb-3", cnType: "180/80A", cn: "L", intl: "M", eu: "48", usPants: "W31", waist: 80, hip: 104, jeans: "31"),
            row("mb-4", cnType: "185/84A", cn: "XL", intl: "L", eu: "50", usPants: "W33", waist: 84, hip: 108, jeans: "33"),
            row("mb-5", cnType: "190/88A", cn: "XXL", intl: "XL", eu: "52", usPants: "W35", waist: 88, hip: 112, jeans: "35"),
        ],
        measure: [
            "腰围量腰部最细处一圈，别收腹；裤子腰线高低不同，量的时候对准常穿的裤腰高度",
            "臀围量臀部最丰满处一圈",
            "裤长（inseam）从裆缝沿内侧量到脚踝，比腰围更容易买错",
        ],
        notes: [
            "男裤的美码直接就是腰围英寸数（W32 = 腰围 32 英寸 ≈ 81cm），比上衣好选得多。表里给的是实测换过来的英寸数，实际下单取最接近的**偶数号**（W30、W32、W34…）往往更合。",
            "欧码（法码）和英寸的换算：欧码 46 = W30，48 = W32，50 = W34，52 = W36。",
            "裤长同样按英寸标（30、32、34），比尺码更容易忽略——腰围对了裤长不对还是穿不了。",
            "牛仔裤会稍微撑开，紧一点能穿；西装裤和休闲布裤按实际腰围选，别指望变形。",
        ]
    )

    // MARK: - 童装

    static let kidsClothes = SizeChart(
        id: "kidsCloth",
        title: "童装",
        group: .clothing,
        systemImage: "figure.child",
        pivotColumnID: "height",
        columns: [Col.height, Col.eu, Col.us, Col.uk, Col.age],
        rows: [
            row("kc-0", height: "80", eu: "80", us: "12-18M", uk: "12-18M", age: "1 岁"),
            row("kc-1", height: "90", eu: "92", us: "2T", uk: "2 岁", age: "2 岁"),
            row("kc-2", height: "100", eu: "104", us: "3T", uk: "3 岁", age: "3 岁"),
            row("kc-3", height: "110", eu: "110", us: "4T", uk: "4 岁", age: "4 岁"),
            row("kc-4", height: "120", eu: "116", us: "5", uk: "5 岁", age: "5–6 岁"),
            row("kc-5", height: "130", eu: "128", us: "7", uk: "7 岁", age: "7–8 岁"),
            row("kc-6", height: "140", eu: "140", us: "8", uk: "8 岁", age: "9–10 岁"),
            row("kc-7", height: "150", eu: "152", us: "10", uk: "10 岁", age: "11–12 岁"),
            row("kc-8", height: "160", eu: "164", us: "12", uk: "12 岁", age: "13–14 岁"),
        ],
        measure: [
            "身高光脚靠墙量，脚跟、臀、后脑贴墙，眼睛平视",
            "体重和胸围也量一下——同样身高偏胖偏瘦要往上或往下取一档",
            "孩子长得快，按当前身高买，不用刻意买大",
        ],
        notes: [
            "中国童装码就是身高：100 码适合身高 95–105cm 的孩子（一般取 ±5cm 一个号）。",
            "欧码也是身高体系，只是标准身高点不同（98、104、110、116、128、140、152、164）。",
            "美码 / 英码用年龄加字母：T 是 toddler（幼儿），2T 就是给 2 岁左右的尺寸。跨度大，同一个 4T 在不同品牌能差半个号。",
            "童装不要贪大：太大不保暖、活动也碍事，而且还没穿合身就小了。按身高量着买最划算。",
        ]
    )

    // MARK: - 行构造的语法糖
    //
    // 服装表是一格一格的约定，不是公式算出来的，所以老老实实铺开写。
    // 这个工厂只负责把可选的列（法码 / 意码 / 牛仔裤）补成字典。

    private static func row(
        _ id: String,
        cnType: String? = nil,
        cn: String? = nil,
        intl: String? = nil,
        height: String? = nil,
        eu: String? = nil,
        us: String? = nil,
        usPants: String? = nil,
        uk: String? = nil,
        fr: String? = nil,
        it: String? = nil,
        bust: Int? = nil,
        waist: Int? = nil,
        hip: Int? = nil,
        jeans: String? = nil,
        age: String? = nil,
        pivot: Double? = nil
    ) -> SizeRow {
        var values: [String: String] = [:]
        if let cnType { values["cnType"] = cnType }
        if let cn { values["cn"] = cn }
        if let intl { values["intl"] = intl }
        if let eu { values["eu"] = eu }
        if let us { values["us"] = us }
        if let usPants { values["usPants"] = usPants }
        if let uk { values["uk"] = uk }
        if let fr { values["fr"] = fr }
        if let it { values["it"] = it }
        if let height { values["height"] = height }
        if let bust { values["bust"] = "\(bust)" }
        if let waist { values["waist"] = "\(waist)" }
        if let hip { values["hip"] = "\(hip)" }
        if let jeans { values["jeans"] = jeans }
        if let age { values["age"] = age }

        // 轴心默认取净尺寸那一列；显式传了就听显式的。
        // 这里不能写成一条 `?? map ?? map ?? flatMap ?? 0` 的长链——
        // 类型检查器会在这种混合重载的表达式上超时。
        var center = pivot ?? 0
        if center == 0 {
            if let bust {
                center = Double(bust)
            } else if let waist {
                center = Double(waist)
            } else if let height, let value = Double(height) {
                center = value
            }
        }
        return SizeRow(id: id, values: values, pivot: center)
    }
}
