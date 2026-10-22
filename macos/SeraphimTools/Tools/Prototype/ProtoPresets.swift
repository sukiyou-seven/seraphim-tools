import Foundation

/// 预设属于哪一段
enum ProtoPresetKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case requirement
    case page
    case component
    case flow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .requirement: return "需求"
        case .page: return "页面"
        case .component: return "组件"
        case .flow: return "流程"
        }
    }

    var systemImage: String {
        switch self {
        case .requirement: return "lightbulb"
        case .page: return "rectangle.3.group"
        case .component: return "square.on.square"
        case .flow: return "arrow.triangle.branch"
        }
    }
}

enum ProtoPresetPayload: Hashable, Sendable {
    case requirement(ProtoRequirementInput)
    case page(ProtoPageInput)
    case component(ProtoComponentInput)
    case flow(ProtoFlowInput)
}

struct ProtoPreset: Identifiable, Hashable, Sendable {
    let id: String
    let kind: ProtoPresetKind
    let title: String
    let summary: String
    let payload: ProtoPresetPayload
}

/// 20 个开箱可用的起点。
///
/// 都是按真实产品写的，不是占位符——填进去的每一条都是那个人真会写进需求里的东西。
/// 用不上的地方直接改，比对着空表单想「我该写什么」快得多。
enum ProtoPresets {

    // MARK: - 全部

    static let all: [ProtoPreset] = requirementPresets + pagePresets + componentPresets + flowPresets

    static func presets(for kind: ProtoPresetKind) -> [ProtoPreset] {
        all.filter { $0.kind == kind }
    }

    static func preset(id: String) -> ProtoPreset? {
        all.first { $0.id == id }
    }

    /// 首次打开流程图时垫的那个例子
    static func firstFlowPreset() -> ProtoFlowInput? {
        if case .flow(let value)? = flowPresets.first?.payload { return value }
        return nil
    }

    // MARK: - 需求（6）

    private static let requirementPresets: [ProtoPreset] = [
        ProtoPreset(
            id: "req-community-shop",
            kind: .requirement,
            title: "社区生鲜小程序",
            summary: "在线下单、到店自提，店员后台看订单",
            payload: .requirement(ProtoRequirementInput(
                name: "小铺鲜生",
                idea: "给社区生鲜店做的微信小程序，居民在线挑菜下单，约好时间去店里自提",
                audience: "小区里 30~50 岁的居民，天天用微信，不愿意再装一个 App；店主不会用电脑，只在手机上管单",
                features: [
                    "按分类浏览商品（蔬菜 / 水果 / 肉禽蛋 / 日用品）",
                    "加入购物车、改数量、删掉不要的",
                    "选自提时段下单（今天下午 / 明天上午）",
                    "微信支付",
                    "查看订单状态（待自提 / 已完成）",
                    "到店出示取货码，店员扫码核销",
                ],
                platform: .miniProgram,
                stack: .unspecified,
                deliverables: [.prd, .prototype],
                constraints: [
                    "微信支付需要商户号，个人主体的小程序用不了，上线前先确认主体资质",
                    "商品图统一压到 200KB 以内，走微信的 CDN",
                    "自提时段要能在后台配，不能写死在代码里",
                    "库存为 0 的商品要自动置灰，而不是等下单才报错",
                ],
                extra: "第一期只做单店，不做多门店也不做配送。优惠券、会员积分、拼团都不在范围内，那是第二期的事，这期别加。"
            ))
        ),
        ProtoPreset(
            id: "req-booking",
            kind: .requirement,
            title: "到店预约（理发店）",
            summary: "选理发师和时段，到点直接剪",
            payload: .requirement(ProtoRequirementInput(
                name: "剪约",
                idea: "理发店的在线预约小程序，顾客挑理发师和时间段，到店不用排队",
                audience: "20~45 岁的上班族，平时只能下班后或周末去，最烦的是到了还得等",
                features: [
                    "按理发师查看他今天和未来三天的可约时段",
                    "选时段提交预约（填姓名和手机号）",
                    "查看我的预约列表，能取消",
                    "预约成功和到点前 1 小时发服务通知",
                    "到店由店员扫码签到",
                    "店员侧看今天的预约清单",
                ],
                platform: .miniProgram,
                stack: .unspecified,
                deliverables: [.prd, .dataModel],
                constraints: [
                    "同一个理发师的同一时段只能被一个人约到，提交时要做冲突校验（两个人同时点要有一个失败）",
                    "服务通知需要用户授权，要用订阅消息而不是模板消息",
                    "取消规则（提前几小时不能取消）要可配置",
                    "理发师临时请假时，要能一键取消他当天的全部预约并通知顾客",
                ],
                extra: ""
            ))
        ),
        ProtoPreset(
            id: "req-kanban",
            kind: .requirement,
            title: "团队任务看板",
            summary: "拖拽改状态，替代 Excel 排期表",
            payload: .requirement(ProtoRequirementInput(
                name: "看板",
                idea: "小团队内部的任务看板，拖卡片就能改状态，用来替掉那张永远不同步的 Excel 排期表",
                audience: "5~20 人的产品研发小组，产品、设计、前端、后端混在一起干活",
                features: [
                    "创建项目，在项目下建任务",
                    "看板视图四列：待办 / 进行中 / 待验证 / 已完成",
                    "拖动卡片在四列之间移动，状态自动更新",
                    "给任务指派负责人、设截止日期、贴标签",
                    "任务详情里能写评论、传附件",
                    "按负责人、标签、截止日期筛",
                    "每天上午推一条「今天该做什么」",
                ],
                platform: .web,
                stack: .react,
                deliverables: [.prd, .dataModel, .tasks],
                constraints: [
                    "内网部署，依赖的任何服务都不能出公网",
                    "附件单个不超过 20MB，类型白名单（图片、PDF、常见文档）",
                    "同时在线最多 50 人，不用考虑高并发和分布式",
                    "拖拽要在弱网下也不丢状态：先本地更新，再把请求补上去",
                ],
                extra: "不要做甘特图，不要做工时统计，就老老实实做好看板和筛选。"
            ))
        ),
        ProtoPreset(
            id: "req-ledger",
            kind: .requirement,
            title: "个人记账 App",
            summary: "三秒记一笔，月底自动出报表",
            payload: .requirement(ProtoRequirementInput(
                name: "记一笔",
                idea: "手机上一个动作就能记下一笔开销，月底自动告诉你钱都花哪了",
                audience: "想搞清楚自己钱花在哪、但坚持不下来记账的年轻人",
                features: [
                    "快速记一笔：金额、分类、备注、日期",
                    "按分类看这个月的支出占比",
                    "看月度趋势，和上个月比多了还是少了",
                    "自定义分类和每月预算，超了要提醒",
                    "把数据导成 CSV",
                    "记错了能改能删",
                ],
                platform: .mobileApp,
                stack: .unspecified,
                deliverables: [.prd, .prototype],
                constraints: [
                    "从打开到记完一笔必须在 3 秒内，进来就直接弹数字键盘",
                    "数据优先存在本地，不上传服务器，不上报任何统计",
                    "分类的颜色和图标用户能自己换",
                    "金额一律用「分」存整数，不要用浮点数",
                ],
                extra: "不要做多币种，不要做账单导入，不要做社交。一个人记账用不着这些。"
            ))
        ),
        ProtoPreset(
            id: "req-campus-market",
            kind: .requirement,
            title: "校园二手交易",
            summary: "同校才看得到的二手转让",
            payload: .requirement(ProtoRequirementInput(
                name: "校园集市",
                idea: "大学校园内的二手交易小程序，只有同一个学校的同学能看到彼此发的东西",
                audience: "在校大学生，毕业季卖东西、开学季买东西，一年两个高峰期",
                features: [
                    "发布闲置：图片、价格、描述、分类",
                    "按分类和校区浏览",
                    "搜关键词",
                    "私信联系卖家（先站内聊，再自己加微信）",
                    "收藏，以及「我发布的」列表",
                    "举报违规内容，被举报的自动下架待审",
                ],
                platform: .miniProgram,
                stack: .unspecified,
                deliverables: [.prd, .prototype],
                constraints: [
                    "必须做内容审核，图片和文字都要过一遍，没过的不展示",
                    "只能看到自己学校的物品，靠学校认证（学号或邮箱）来隔离",
                    "禁止发布涉法物品，要有明显的举报入口和规则页",
                    "发布频率要限制，防止有人刷屏",
                ],
                extra: "交易在站外完成，平台不碰钱，也就不用做支付和担保。这一条要在用户协议里写清楚。"
            ))
        ),
        ProtoPreset(
            id: "req-crm",
            kind: .requirement,
            title: "销售 CRM 后台",
            summary: "客户管理 + 跟进记录 + 今日待办",
            payload: .requirement(ProtoRequirementInput(
                name: "客户管家",
                idea: "给销售团队用的客户管理后台，把客户信息和每次跟进都记下来，主管能看到全组的进展",
                audience: "10~50 人的销售团队；销售只想尽快记完去打电话，主管要看全局和趋势",
                features: [
                    "客户列表：筛选、搜索、批量分配给某个销售",
                    "客户详情页：基本信息 + 跟进记录时间线",
                    "新建 / 编辑客户",
                    "写跟进记录（类型：电话 / 拜访 / 微信；结果：有意向 / 再跟进 / 已放弃）",
                    "今日待办：今天该联系谁",
                    "数据看板：本月新增客户、转化率、人均跟进量",
                    "权限：销售只看自己的客户，主管看全组，管理员看全部",
                ],
                platform: .admin,
                stack: .react,
                deliverables: [.prd, .dataModel, .tasks],
                constraints: [
                    "客户列表默认每页 20 条，数据量到 5000 条时翻页和筛选还是要顺畅",
                    "所有写操作都要留操作日志（谁、什么时候、改了什么）",
                    "导出 Excel 单次上限 1 万行，超了要提示分批导",
                    "手机号、身份证这类字段要做脱敏展示，只有管理员能看全",
                ],
                extra: ""
            ))
        ),
    ]

    // MARK: - 页面（6）

    private static let pagePresets: [ProtoPreset] = [
        ProtoPreset(
            id: "page-goods-list",
            kind: .page,
            title: "商品列表页",
            summary: "两列网格，扫一眼再进详情",
            payload: .page(ProtoPageInput(
                pageName: "商品列表",
                kind: .list,
                purpose: "让用户快速扫过在售商品，二十秒内找到想买的那个，点进详情",
                platform: .miniProgram,
                stack: .unspecified,
                fields: [
                    "商品主图：1:1 比例，两列网格排布",
                    "商品名：最多两行，超出用省略号",
                    "现价：红色、加大字号，是这一条上最显眼的元素",
                    "原价：有折扣时才显示，灰色加删除线",
                    "库存标签：只剩几件时显示「仅剩 N 件」，售罄时整块置灰",
                ],
                actions: [
                    "点商品进详情页",
                    "下拉刷新",
                    "滑到底自动加载下一页",
                    "点顶部分类标签切换分类",
                    "点搜索框去搜索页",
                ],
                states: [.loading, .empty, .error],
                extra: "两列网格，不要做成一行一条的列表样式。"
            ))
        ),
        ProtoPreset(
            id: "page-goods-detail",
            kind: .page,
            title: "商品详情页",
            summary: "轮播 + 规格 + 底部两个按钮",
            payload: .page(ProtoPageInput(
                pageName: "商品详情",
                kind: .detail,
                purpose: "让人把商品看清楚、放下心，然后下单",
                platform: .miniProgram,
                stack: .unspecified,
                fields: [
                    "主图轮播：最多 5 张，底部有小圆点指示",
                    "价格与促销标签",
                    "商品名",
                    "三个卖点，一句话一个",
                    "规格信息：重量 / 产地 / 保质期",
                    "库存和累计销量",
                    "图文详情：一段一段的图和文字",
                    "评价摘要：一个大分数 + 两条精选评价",
                ],
                actions: [
                    "左右滑动看图，点图能全屏放大",
                    "选规格（有规格可选的商品）",
                    "加入购物车",
                    "立即购买",
                    "分享给微信好友",
                    "收藏",
                ],
                states: [.loading, .error, .success],
                extra: "底部固定一栏，左边小图标放「客服」和「购物车」，右边两个按钮放「加入购物车」和「立即购买」。"
            ))
        ),
        ProtoPreset(
            id: "page-expense-form",
            kind: .page,
            title: "报销填报表单",
            summary: "字段分组 + 暂存草稿 + 复用上次",
            payload: .page(ProtoPageInput(
                pageName: "提交报销单",
                kind: .form,
                purpose: "让员工一次填对，减少因为漏东西被财务退回来重填",
                platform: .web,
                stack: .unspecified,
                fields: [
                    "报销类型：下拉选择（差旅 / 办公用品 / 招待 / 其他）",
                    "金额：数字，保留两位小数，不允许负数",
                    "发生日期：日期选择，不能选未来",
                    "事由：多行文本，最多 200 字",
                    "发票照片：最多 9 张，支持拍照和从相册选",
                    "所属部门：根据登录人自动带出，不可改",
                ],
                actions: [
                    "切换报销类型，不同类型显示的必填项不一样",
                    "上传发票照片",
                    "暂存草稿，下次进来接着填",
                    "提交",
                    "一键复用上一次的填写内容",
                ],
                states: [.loading, .error, .success],
                extra: "字段分两组：「基本信息」（类型、金额、日期）和「凭证」（事由、发票），中间加一条分隔。"
            ))
        ),
        ProtoPreset(
            id: "page-dashboard",
            kind: .page,
            title: "运营数据看板",
            summary: "4 个关键数字 + 趋势 + 明细",
            payload: .page(ProtoPageInput(
                pageName: "运营数据看板",
                kind: .dashboard,
                purpose: "早上打开一眼看清昨天的经营情况，有异常能立刻发现",
                platform: .admin,
                stack: .unspecified,
                fields: [
                    "昨日成交额：含和前天比的涨跌百分比",
                    "昨日订单量",
                    "昨日新增用户数",
                    "客单价",
                    "近 7 天成交额趋势：折线图",
                    "各渠道占比：饼图或堆叠条",
                    "成交额 Top 10 商品：表格",
                ],
                actions: [
                    "切换时间范围：今天 / 昨天 / 近 7 天 / 近 30 天",
                    "点指标卡下钻到对应的明细列表",
                    "导出当前视图",
                ],
                states: [.loading, .error, .empty],
                extra: "关键指标只放 4 个，其余挪到下面。数字字号要大，隔两米也能看清。"
            ))
        ),
        ProtoPreset(
            id: "page-login",
            kind: .page,
            title: "登录页",
            summary: "一键登录为主，验证码兜底",
            payload: .page(ProtoPageInput(
                pageName: "登录",
                kind: .auth,
                purpose: "让老用户三秒进来，新用户顺手完成注册",
                platform: .miniProgram,
                stack: .unspecified,
                fields: [
                    "Logo 和一句说明这个产品是干什么的",
                    "手机号输入框",
                    "验证码输入框，右侧是获取按钮",
                    "用户协议与隐私政策的勾选框",
                ],
                actions: [
                    "点「微信一键登录」授权登录",
                    "获取验证码（点了开始 60 秒倒计时）",
                    "提交登录，新手机号直接完成注册",
                    "切换成手机号密码登录",
                    "点协议查看全文",
                ],
                states: [.loading, .error, .success],
                extra: "把「微信一键登录」放在最上面、做得最大，手机号验证码作为备选放下面。"
            ))
        ),
        ProtoPreset(
            id: "page-profile",
            kind: .page,
            title: "个人中心",
            summary: "头像 + 数据概览 + 分组入口",
            payload: .page(ProtoPageInput(
                pageName: "我的",
                kind: .profile,
                purpose: "管理自己的账号，以及找到那几个最常用的入口",
                platform: .miniProgram,
                stack: .unspecified,
                fields: [
                    "头像和昵称，点一下能进去改",
                    "手机号，中间四位打码",
                    "三个数字：订单数 / 收藏数 / 优惠券数",
                    "按主题分组的入口列表",
                ],
                actions: [
                    "编辑个人资料",
                    "进我的订单",
                    "进我的收藏",
                    "进设置",
                    "联系客服",
                    "退出登录",
                ],
                states: [.loading, .error],
                extra: "没登录的时候整页显示登录引导，不要显示一个空头像加几个点不动的入口。"
            ))
        ),
    ]

    // MARK: - 组件（5）

    private static let componentPresets: [ProtoPreset] = [
        ProtoPreset(
            id: "comp-primary-button",
            kind: .component,
            title: "主按钮",
            summary: "带加载态和语气变体，防重复提交",
            payload: .component(ProtoComponentInput(
                name: "主按钮",
                kind: .button,
                purpose: "页面里最重要的那个操作：提交、立即购买、确认下单。同一屏只应该出现一个。",
                platform: .web,
                stack: .unspecified,
                props: [
                    "label: 按钮文字，必填",
                    "tone: 语气，主要 / 次要 / 危险 / 幽灵，默认主要",
                    "size: 尺寸，小 / 中 / 大，默认中",
                    "loading: 是否加载中，默认 false",
                    "disabled: 是否禁用，默认 false",
                    "fullWidth: 是否撑满整行，默认 false",
                ],
                variants: [.size, .tone, .disabled, .loading, .darkMode, .keyboard],
                interactions: [
                    "点下去立刻进入加载态并禁用，防止重复提交",
                    "操作失败时退出加载态、恢复可点，同时给出错误提示",
                    "加载中保持原来的宽度，不要让按钮缩一下导致布局跳",
                    "禁用时指针变成禁止符号，并且说明为什么不能点（hover 提示或旁边的说明文字）",
                ],
                includeA11y: true,
                includeTesting: true,
                extra: ""
            ))
        ),
        ProtoPreset(
            id: "comp-confirm-modal",
            kind: .component,
            title: "二次确认弹窗",
            summary: "危险操作前置确认，遮罩不可关",
            payload: .component(ProtoComponentInput(
                name: "确认弹窗",
                kind: .modal,
                purpose: "危险操作前的二次确认：删除、解绑、退出登录、清空数据",
                platform: .web,
                stack: .unspecified,
                props: [
                    "title: 标题，必填，一句话说清要做什么",
                    "message: 补充说明，讲清楚做了之后有什么后果",
                    "confirmText: 确认按钮文案，默认「确定」",
                    "cancelText: 取消按钮文案，默认「取消」",
                    "tone: 语气，默认 normal；危险操作用 danger",
                ],
                variants: [.tone, .loading, .keyboard, .darkMode],
                interactions: [
                    "点遮罩不关闭——危险操作必须显式选一个",
                    "按 Esc 等于取消",
                    "确认按钮点击后进入加载态，加载中取消按钮也要禁用",
                    "内容太长时只有中间区域滚动，按钮区固定在底部不动",
                ],
                includeA11y: true,
                includeTesting: true,
                extra: "危险语气时，打开弹窗的默认焦点不要落在确认按钮上，防止连按回车误删。"
            ))
        ),
        ProtoPreset(
            id: "comp-login-form",
            kind: .component,
            title: "登录表单",
            summary: "失焦才校验，失败保留账号",
            payload: .component(ProtoComponentInput(
                name: "登录表单",
                kind: .form,
                purpose: "收集账号密码并提交登录，是所有后台系统的入口",
                platform: .web,
                stack: .unspecified,
                props: [
                    "onSubmit: 提交回调，参数是账号和密码",
                    "loading: 由外部控制的提交中状态",
                    "errorMessage: 服务端返回的错误，展示在表单顶部",
                ],
                variants: [.disabled, .loading, .keyboard, .responsive],
                interactions: [
                    "输入过程中不校验，失焦之后再校验格式",
                    "提交失败时保留账号，只清空密码并把焦点移回密码框",
                    "在任意输入框按回车就直接提交",
                    "连续失败 5 次后锁定 1 分钟，并说明还要等多久",
                ],
                includeA11y: true,
                includeTesting: false,
                extra: "错误提示统一说「账号或密码不对」，不要区分是哪一项错了。"
            ))
        ),
        ProtoPreset(
            id: "comp-data-table",
            kind: .component,
            title: "数据表格",
            summary: "排序 / 多选 / 批量操作条",
            payload: .component(ProtoComponentInput(
                name: "数据表格",
                kind: .table,
                purpose: "展示结构化数据，支持排序、筛选和批量操作",
                platform: .admin,
                stack: .unspecified,
                props: [
                    "columns: 列定义数组，每项含标题、字段名、宽度、是否可排序",
                    "rows: 数据行",
                    "loading: 是否加载中",
                    "selectable: 是否开启多选，默认 false",
                    "emptyText: 没有数据时显示的文案",
                ],
                variants: [.density, .loading, .responsive, .darkMode],
                interactions: [
                    "点表头排序：第一次升序、第二次降序、第三次取消排序",
                    "表头的全选框有三态：全选 / 半选 / 未选",
                    "选中行之后顶部浮出批量操作条，取消选择就收起",
                    "单元格内容超长时截断显示，悬停能看到完整内容",
                    "横向滚动时最左侧的列要固定住",
                ],
                includeA11y: false,
                includeTesting: true,
                extra: ""
            ))
        ),
        ProtoPreset(
            id: "comp-image-upload",
            kind: .component,
            title: "图片上传",
            summary: "先本地校验压缩，再传",
            payload: .component(ProtoComponentInput(
                name: "图片上传",
                kind: .upload,
                purpose: "让用户上传凭证照片，支持拖拽和点选两种方式",
                platform: .web,
                stack: .unspecified,
                props: [
                    "maxCount: 最多几张，默认 9",
                    "maxSizeMB: 单张大小上限，默认 5",
                    "accept: 允许的类型，默认只收图片",
                    "onChange: 文件列表变化的回调",
                ],
                variants: [.disabled, .loading, .responsive],
                interactions: [
                    "选中文件当场校验类型和大小，不合格的立刻说清为什么，不要等传完才报错",
                    "上传中显示缩略图和进度环，可以点取消",
                    "失败的那一张单独标红并提供重试，不要整批失败",
                    "文件拖到区域里要有明显的视觉反馈",
                    "点缩略图能放大预览，右上角能删",
                ],
                includeA11y: false,
                includeTesting: true,
                extra: "上传前先在本地压一道，超过 2MB 的图压到 1MB 以内再传。"
            ))
        ),
    ]

    // MARK: - 流程（3）

    private static let flowPresets: [ProtoPreset] = [
        ProtoPreset(
            id: "flow-login",
            kind: .flow,
            title: "手机号登录流程",
            summary: "两次格式校验，失败退回上一步",
            payload: .flow(makeFlow("手机号验证码登录", [
                begin(),
                io("用户输入手机号"),
                judge("手机号格式正确？", elseTo: 1),
                step("发送验证码，按钮进入 60 秒倒计时"),
                io("用户输入验证码"),
                judge("验证码正确？", elseTo: 4),
                store("查询用户，不存在就创建"),
                step("写入登录态，跳转首页"),
                end(),
            ]))
        ),
        ProtoPreset(
            id: "flow-checkout",
            kind: .flow,
            title: "下单支付流程",
            summary: "库存校验 + 支付分支，两条失败各有出口",
            payload: .flow(makeFlow("下单支付流程", [
                begin(),
                step("结算页确认收货信息"),
                judge("库存充足？", elseTo: 7),
                step("生成订单并锁定库存"),
                io("调起微信支付"),
                judge("支付成功？", elseTo: 8),
                store("更新订单状态为已支付"),
                step("提示已售罄，返回购物车"),
                step("订单转「待支付」，24 小时后自动取消"),
            ], terminals: [6, 7]))
        ),
        ProtoPreset(
            id: "flow-leave",
            kind: .flow,
            title: "请假审批流程",
            summary: "按天数分流，主管 + HR 两级",
            payload: .flow(makeFlow("请假审批流程", [
                begin(),
                io("员工提交请假单：类型 / 起止时间 / 事由"),
                step("直属主管审批"),
                judge("主管同意？", elseTo: 8),
                judge("请假超过 1 天？", elseTo: 7),
                step("HR 复核"),
                judge("HR 同意？", elseTo: 8),
                end("结束：通过，写考勤并通知申请人"),
                end("结束：驳回，通知申请人"),
            ]))
        ),
    ]

    // MARK: - 节点构造

    private struct NodeSpec {
        var kind: FlowNodeKind
        var text: String
        var terminal: Bool = false
        var elseIndex: Int?
        var elseLabel: String = "否"
    }

    private static func begin() -> NodeSpec {
        NodeSpec(kind: .start, text: "开始")
    }

    private static func end(_ text: String = "结束") -> NodeSpec {
        NodeSpec(kind: .start, text: text, terminal: true)
    }

    private static func step(_ text: String) -> NodeSpec {
        NodeSpec(kind: .process, text: text)
    }

    private static func io(_ text: String) -> NodeSpec {
        NodeSpec(kind: .io, text: text)
    }

    private static func store(_ text: String) -> NodeSpec {
        NodeSpec(kind: .storage, text: text)
    }

    private static func judge(_ text: String, elseTo: Int?, elseLabel: String = "否") -> NodeSpec {
        NodeSpec(kind: .decision, text: text, elseIndex: elseTo, elseLabel: elseLabel)
    }

    /// 把 NodeSpec 列表变成真正的流程图。
    ///
    /// 分支要用**下标**指定目标，而不是 UUID——预设是静态数据，
    /// 写死 UUID 会让定义变得没法读，也容易抄错。
    private static func makeFlow(
        _ title: String,
        _ specs: [NodeSpec],
        terminals: Set<Int> = []
    ) -> ProtoFlowInput {
        var nodes = specs.map { spec in
            FlowNode(kind: spec.kind, text: spec.text, isTerminal: spec.terminal)
        }
        for index in terminals where nodes.indices.contains(index) {
            nodes[index].isTerminal = true
        }
        for (index, spec) in specs.enumerated() {
            guard let target = spec.elseIndex, nodes.indices.contains(target) else { continue }
            nodes[index].elseTarget = nodes[target].id
            nodes[index].elseLabel = spec.elseLabel
        }
        return ProtoFlowInput(title: title, direction: .topDown, nodes: nodes)
    }
}
