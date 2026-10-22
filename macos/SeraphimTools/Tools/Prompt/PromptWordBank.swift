import Foundation

// MARK: - 词
//
// 绘图提示词的实际用法是英文更稳（主流模型对英文的理解和权重都更好），
// 所以词库全部做成中英对照，切「英文」或「中英对照」时直接换一列取。

struct PromptTerm: Sendable {
    let zh: String
    let en: String

    init(_ zh: String, _ en: String) {
        self.zh = zh
        self.en = en
    }
}

/// 主体类别：认出是哪一类，就能补上这一类特有的细节。
/// 「一只猫」和「一把椅子」该补的细节完全不是一回事。
struct PromptConcept: Sendable {
    let key: String
    let keywords: [String]
    /// 这一类的通用细节补充，按"值得写的程度"排序，详尽档取前面几条
    let details: [PromptTerm]
    /// 这类主体的默认风格（没指定风格时用）
    let style: PromptTerm
}

enum PromptWordBank {

    // MARK: 主体类别

    static let concepts: [PromptConcept] = [
        PromptConcept(
            key: "人物",
            keywords: ["人", "男", "女", "女孩", "男孩", "老人", "孩子", "儿童", "模特", "少女", "大叔",
                       "脸", "肖像", "半身", "全身", "头", "portrait", "girl", "boy", "woman", "man"],
            details: [
                PromptTerm("面部结构准确、五官比例自然", "accurate facial anatomy, natural proportions"),
                PromptTerm("皮肤质感真实，可见细纹与毛孔", "realistic skin texture, visible pores and fine lines"),
                PromptTerm("自然表情，眼神有情绪", "natural expression, expressive eyes"),
                PromptTerm("发丝层次分明，边缘有碎发", "detailed hair strands, fine flyaway hair"),
                PromptTerm("手部姿势自然，指节结构正确", "natural hand pose, correct knuckle structure"),
            ],
            style: PromptTerm("人像摄影", "portrait photography")
        ),
        PromptConcept(
            key: "动物",
            keywords: ["猫", "狗", "鸟", "马", "虎", "狮", "熊", "兔", "狐", "鹿", "鲸", "鱼", "龙",
                       "动物", "cat", "dog", "bird", "horse", "tiger", "animal", "fox"],
            details: [
                PromptTerm("毛发质感清晰，可见绒毛与光泽", "detailed fur texture with fine hairs and sheen"),
                PromptTerm("眼睛有眼神光，瞳孔结构准确", "catchlight in the eyes, accurate pupil structure"),
                PromptTerm("姿态自然放松，符合该物种的体态", "natural relaxed pose, anatomically correct for the species"),
                PromptTerm("鼻子与爪子的质感细节", "detailed nose and paw texture"),
                PromptTerm("胡须根根分明", "individual whiskers clearly visible"),
            ],
            style: PromptTerm("野生动物摄影", "wildlife photography")
        ),
        PromptConcept(
            key: "食物",
            keywords: ["食物", "菜", "饭", "面", "蛋糕", "咖啡", "茶", "水果", "甜点", "火锅", "汉堡",
                       "food", "cake", "coffee", "dessert", "fruit"],
            details: [
                PromptTerm("食材纹理清晰，断面层次分明", "clear food texture, distinct cross-section layers"),
                PromptTerm("表面有光泽或蒸汽，看着是刚做好的", "glossy surface or rising steam, freshly made look"),
                PromptTerm("摆盘讲究，留白与配色舒服", "thoughtful plating with balanced negative space"),
                PromptTerm("餐具与桌面材质呼应", "tableware and table surface materials in harmony"),
            ],
            style: PromptTerm("美食摄影", "food photography")
        ),
        PromptConcept(
            key: "产品",
            keywords: ["产品", "手机", "相机", "表", "鞋", "包", "瓶", "包装", "耳机", "电脑", "车",
                       "product", "phone", "watch", "shoe", "bottle", "car"],
            details: [
                PromptTerm("材质质感真实，可辨金属 / 玻璃 / 皮革的差别", "authentic material feel — metal, glass and leather clearly distinguishable"),
                PromptTerm("边缘锐利，倒角与接缝清晰", "crisp edges, visible chamfers and seams"),
                PromptTerm("表面反光有形状，不是一片死白", "shaped reflections on the surface, not blown-out highlights"),
                PromptTerm("投影方向统一，落在干净背景上", "consistent shadow direction on a clean backdrop"),
            ],
            style: PromptTerm("商业产品摄影", "commercial product photography")
        ),
        PromptConcept(
            key: "风景",
            keywords: ["风景", "山", "海", "森林", "草原", "日落", "日出", "星空", "湖", "云", "城市",
                       "街道", "建筑", "室内", "房间", "landscape", "mountain", "sea", "city", "forest"],
            details: [
                PromptTerm("大气透视正确，远近层次分明", "correct atmospheric perspective, clear depth layers"),
                PromptTerm("前景有细节、中景有主体、远景有余韵", "detailed foreground, clear midground subject, receding background"),
                PromptTerm("天气与时间感明确", "unmistakable weather and time of day"),
                PromptTerm("云层与光影方向一致", "clouds and light direction consistent"),
            ],
            style: PromptTerm("风光摄影", "landscape photography")
        ),
        PromptConcept(
            key: "抽象概念",
            keywords: ["抽象", "概念", "插画", "图标", "标志", "logo", "图案", "纹理", "背景",
                       "abstract", "icon", "pattern", "background"],
            details: [
                PromptTerm("主体居中，轮廓明确", "centered subject with a clear silhouette"),
                PromptTerm("色彩对比克制，只有两三个主色", "restrained palette, two or three main colors"),
                PromptTerm("形状语言统一，没有多余的装饰", "consistent shape language, no superfluous ornament"),
                PromptTerm("背景干净，主体与背景分离清晰", "clean background, subject clearly separated"),
            ],
            style: PromptTerm("扁平插画", "flat vector illustration")
        ),
    ]

    /// 通用细节（认不出主体类别时用）
    static let genericDetails: [PromptTerm] = [
        PromptTerm("主体清晰锐利，结构准确", "sharp, structurally accurate subject"),
        PromptTerm("材质与表面细节真实", "authentic material and surface detail"),
        PromptTerm("光影关系明确，有体积感", "clear light and shadow with a sense of volume"),
        PromptTerm("背景不抢主体，层次分明", "background supports the subject, clear layering"),
    ]

    // MARK: 风格

    static let styles: [PromptTerm] = [
        PromptTerm("写实摄影", "photorealistic photography"),
        PromptTerm("电影感", "cinematic film still"),
        PromptTerm("3D 渲染", "3D render, octane, unreal engine"),
        PromptTerm("二次元动漫", "anime illustration, cel shading"),
        PromptTerm("赛博朋克", "cyberpunk, neon, blade runner style"),
        PromptTerm("水彩", "watercolor painting, soft washes"),
        PromptTerm("油画", "oil painting, visible brushstrokes"),
        PromptTerm("扁平插画", "flat vector illustration"),
        PromptTerm("像素风", "pixel art"),
        PromptTerm("复古胶片", "vintage film photo, grain"),
        PromptTerm("粘土定格", "claymation, stop-motion look"),
        PromptTerm("极简主义", "minimalism, lots of negative space"),
    ]

    /// 用户输入里出现这些词，说明他自己已经指定风格了，就不要再叠加默认风格
    static let styleKeywords: [String] = [
        "写实", "照片", "摄影", "电影", "胶片", "3d", "渲染", "动漫", "二次元", "漫画", "插画",
        "水彩", "油画", "素描", "国画", "水墨", "赛博", "朋克", "蒸汽", "像素", "粘土", "极简",
        "扁平", "矢量", "手绘", "涂鸦", "写意", "photorealistic", "cinematic", "anime", "render",
    ]

    // MARK: 光线

    static let lighting: [PromptTerm] = [
        PromptTerm("黄金时刻的暖侧光，长投影", "golden hour side light, long shadows"),
        PromptTerm("柔和的窗光，光线自然过渡", "soft window light, gentle falloff"),
        PromptTerm("逆光轮廓光，主体边缘发亮", "backlit rim light, glowing edges"),
        PromptTerm("伦勃朗光，面部明暗对比明确", "Rembrandt lighting, strong facial contrast"),
        PromptTerm("霓虹灯光，冷暖双色对比", "neon lighting, warm and cool color contrast"),
        PromptTerm("体积光穿透，可见光束与浮尘", "volumetric light beams with floating dust"),
        PromptTerm("蓝调时刻，天空与灯光平衡", "blue hour, balanced sky and artificial light"),
        PromptTerm("顶光或硬光，投影边界清晰", "hard top light, crisp shadow edges"),
    ]

    // MARK: 构图

    static let compositions: [PromptTerm] = [
        PromptTerm("中景，主体占画面三分之二，浅景深", "medium shot, subject fills two thirds, shallow depth of field"),
        PromptTerm("特写，细节充满画面，背景虚化", "close-up, detail fills the frame, blurred background"),
        PromptTerm("全景，交代主体与环境的关系", "wide shot, subject and environment both readable"),
        PromptTerm("低角度仰拍，主体显得有分量", "low angle shot, subject appears imposing"),
        PromptTerm("鸟瞰视角，强调布局与秩序", "bird's eye view, emphasising layout and order"),
        PromptTerm("过肩视角，带入第一人称感", "over-the-shoulder shot, first-person feel"),
        PromptTerm("三分法构图，主体落在交叉点", "rule of thirds, subject on an intersection"),
        PromptTerm("中心对称构图，庄重稳定", "centered symmetrical composition, formal and stable"),
    ]

    // MARK: 色彩

    static let colors: [PromptTerm] = [
        PromptTerm("暖色调，橙黄主导，氛围亲切", "warm palette, orange and amber dominant"),
        PromptTerm("冷色调，蓝青主导，氛围冷静", "cool palette, blue and teal dominant"),
        PromptTerm("低饱和莫兰迪色，克制高级", "desaturated Morandi palette, restrained and refined"),
        PromptTerm("高对比撞色，视觉冲击强", "high-contrast complementary colors"),
        PromptTerm("单色调，只用同一色相的深浅变化", "monochromatic, one hue in varying values"),
        PromptTerm("自然大地色，沉稳耐看", "natural earth tones"),
    ]

    // MARK: 画质（按详细程度分档）

    static func quality(_ detail: ExpandDetail) -> PromptTerm {
        switch detail {
        case .brief:
            return PromptTerm("高细节", "highly detailed")
        case .standard:
            return PromptTerm("高细节，专业水准，8K", "highly detailed, professional, 8K")
        case .rich:
            return PromptTerm("超高细节，锐利对焦，专业调色，8K 分辨率，获奖级作品",
                              "ultra detailed, tack sharp, professionally color graded, 8K, award-winning")
        }
    }

    // MARK: 负向提示词

    static func negative(_ detail: ExpandDetail) -> [PromptTerm] {
        let base = [
            PromptTerm("低分辨率", "lowres"),
            PromptTerm("模糊", "blurry"),
            PromptTerm("变形", "deformed"),
            PromptTerm("水印", "watermark"),
            PromptTerm("文字", "text"),
        ]
        guard detail != .brief else { return base }
        let more = [
            PromptTerm("多余肢体", "extra limbs"),
            PromptTerm("多余手指", "extra fingers"),
            PromptTerm("五官扭曲", "distorted face"),
        ]
        guard detail == .rich else { return base + more }
        return base + more + [
            PromptTerm("过曝", "overexposed"),
            PromptTerm("死黑", "crushed blacks"),
            PromptTerm("杂乱背景", "cluttered background"),
        ]
    }

    // MARK: 文案 / 内容类的线索词

    /// 平台线索：认出平台就能把语气和长度定得更准
    struct Cue: Sendable {
        let keywords: [String]
        let value: String
    }

    static let platformCues: [Cue] = [
        Cue(keywords: ["小红书", "种草"], value: "小红书"),
        Cue(keywords: ["公众号", "推文"], value: "微信公众号"),
        Cue(keywords: ["抖音"], value: "抖音"),
        Cue(keywords: ["视频号"], value: "视频号"),
        Cue(keywords: ["b站", "bilibili", "哔哩"], value: "B 站"),
        Cue(keywords: ["知乎"], value: "知乎"),
        Cue(keywords: ["微博"], value: "微博"),
        Cue(keywords: ["淘宝", "天猫", "详情页"], value: "淘宝 / 天猫详情页"),
        Cue(keywords: ["亚马逊", "amazon", "跨境"], value: "Amazon"),
        Cue(keywords: ["领英", "linkedin"], value: "LinkedIn"),
        Cue(keywords: ["朋友圈"], value: "朋友圈"),
    ]

    static let audienceCues: [Cue] = [
        Cue(keywords: ["学生", "考生"], value: "在校学生"),
        Cue(keywords: ["宝妈", "妈妈", "育儿"], value: "有孩子的家长"),
        Cue(keywords: ["程序员", "开发", "工程师"], value: "开发者"),
        Cue(keywords: ["老板", "管理者", "高管", "领导"], value: "管理者"),
        Cue(keywords: ["新手", "入门", "小白"], value: "完全新手"),
        Cue(keywords: ["老人", "长辈", "父母"], value: "中老年用户"),
        Cue(keywords: ["同事", "团队", "内部"], value: "团队同事"),
        Cue(keywords: ["客户", "甲方", "to b", "tob"], value: "企业客户"),
    ]

    /// 语言线索：认出来就用它，认不出留待补
    static let languageCues: [Cue] = [
        Cue(keywords: ["python", "pandas", "django", "flask"], value: "Python"),
        Cue(keywords: ["swift", "swiftui", "ios", "macos"], value: "Swift"),
        Cue(keywords: ["javascript", "js", "node", "npm", "react", "vue", "前端"], value: "JavaScript / TypeScript"),
        Cue(keywords: ["java", "spring"], value: "Java"),
        Cue(keywords: ["go", "golang"], value: "Go"),
        Cue(keywords: ["rust"], value: "Rust"),
        Cue(keywords: ["c++", "cpp"], value: "C++"),
        Cue(keywords: ["sql", "数据库", "查询"], value: "SQL"),
        Cue(keywords: ["shell", "bash", "脚本"], value: "Shell"),
    ]

    /// 领域线索（文案 / PPT 用）
    static let domainCues: [Cue] = [
        Cue(keywords: ["数码", "手机", "电脑", "耳机"], value: "数码产品"),
        Cue(keywords: ["护肤", "美妆", "彩妆", "口红"], value: "美妆护肤"),
        Cue(keywords: ["健身", "减脂", "运动", "跑步"], value: "运动健身"),
        Cue(keywords: ["教育", "课程", "培训", "学习"], value: "教育培训"),
        Cue(keywords: ["金融", "理财", "保险", "基金"], value: "金融理财"),
        Cue(keywords: ["医疗", "健康", "养生"], value: "医疗健康"),
        Cue(keywords: ["旅游", "旅行", "酒店", "民宿"], value: "旅游出行"),
        Cue(keywords: ["食品", "零食", "饮料", "茶"], value: "食品饮料"),
        Cue(keywords: ["家居", "家具", "收纳"], value: "家居生活"),
        Cue(keywords: ["母婴", "婴儿", "童装"], value: "母婴用品"),
    ]

    /// 所有线索词凑一起，判断用户有没有自己写过风格 / 光线 / 构图
    static func containsAny(_ text: String, _ terms: [PromptTerm]) -> Bool {
        let lowered = text.lowercased()
        return terms.contains { term in
            lowered.contains(term.zh.lowercased()) || lowered.contains(term.en.lowercased())
        }
    }

    static func firstMatch(_ cues: [Cue], in text: String) -> String? {
        let lowered = text.lowercased()
        return cues.first { cue in
            cue.keywords.contains { lowered.contains($0.lowercased()) }
        }?.value
    }
}
