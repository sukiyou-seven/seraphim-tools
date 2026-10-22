import Foundation

// MARK: - 说明
//
// 这个工具的四段都围绕同一件事：把「人脑子里的想法」翻译成「AI 能准确接住的文字」。
//
// 一条硬规则贯穿本文件：**所有枚举的 rawValue 都用英文**，中文一律放 `title`。
// rawValue 会被写进 UserDefaults 的 JSON 里当存储键，展示文案随时可能被改，
// 拿中文当键 = 改一次文案就把老数据读废了（工具箱里踩过这个坑）。

// MARK: - 落地形态

/// 东西要做成什么形态。形态不同，交互习惯和约束差得很远，
/// 所以每一项都带一段 `brief` 直接写进提示词——比只丢一个「小程序」三个字有用得多。
enum ProtoPlatform: String, CaseIterable, Identifiable, Codable, Sendable {
    case web
    case miniProgram
    case mobileApp
    case desktop
    case plugin
    case admin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .web: return "网页"
        case .miniProgram: return "微信小程序"
        case .mobileApp: return "移动 App"
        case .desktop: return "桌面应用"
        case .plugin: return "浏览器插件"
        case .admin: return "管理后台"
        }
    }

    var systemImage: String {
        switch self {
        case .web: return "safari"
        case .miniProgram: return "message.fill"
        case .mobileApp: return "iphone"
        case .desktop: return "macbook"
        case .plugin: return "puzzlepiece.extension"
        case .admin: return "tablecells"
        }
    }

    /// 给 AI 的形态说明
    var brief: String {
        switch self {
        case .web: return "响应式网页，桌面和移动浏览器都要能用"
        case .miniProgram: return "微信小程序，单页信息密度低、操作路径要短，必须考虑授权、分享和返回栈"
        case .mobileApp: return "移动端 App，注意安全区、手势返回、横竖屏和弱网离线"
        case .desktop: return "桌面应用，窗口可自由缩放，支持键盘快捷键和多窗口"
        case .plugin: return "浏览器插件，注意弹窗尺寸限制、后台脚本生命周期和权限申请时机"
        case .admin: return "管理后台，以表格、筛选、批量操作和权限为主，信息密度可以高"
        }
    }
}

// MARK: - 技术栈

enum ProtoStack: String, CaseIterable, Identifiable, Codable, Sendable {
    case unspecified
    case react
    case vue
    case vanilla
    case uniApp
    case taro
    case nativeMiniProgram
    case flutter
    case swiftUI
    case lowCode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unspecified: return "不限"
        case .react: return "React"
        case .vue: return "Vue"
        case .vanilla: return "原生 HTML/CSS/JS"
        case .uniApp: return "uni-app"
        case .taro: return "Taro"
        case .nativeMiniProgram: return "原生小程序"
        case .flutter: return "Flutter"
        case .swiftUI: return "SwiftUI"
        case .lowCode: return "低代码平台"
        }
    }

    /// 写进提示词的技术约束
    var brief: String {
        switch self {
        case .unspecified: return ""
        case .react: return "React（函数组件 + Hooks，样式用 CSS Modules 或 Tailwind）"
        case .vue: return "Vue 3（组合式 API + <script setup>）"
        case .vanilla: return "原生 HTML + CSS + JavaScript，不引框架"
        case .uniApp: return "uni-app（用 view/text 等内置组件，注意小程序端能力差异）"
        case .taro: return "Taro（React 语法，编译到小程序）"
        case .nativeMiniProgram: return "微信小程序原生（WXML + WXSS + JS，用 rpx 单位）"
        case .flutter: return "Flutter（Widget 组合，注意约束传递）"
        case .swiftUI: return "SwiftUI（视图拆小，注意 ViewBuilder 嵌套深度）"
        case .lowCode: return "低代码平台配置（不写代码，用平台内置的组件、数据源和事件编排）"
        }
    }
}

// MARK: - 输出物

/// 让 AI 交付什么。每一项都用 `outline` 声明章节骨架——
/// 这是这类提示词真正的价值所在：**先把结构钉死，AI 才不会自由发挥。**
enum ProtoDeliverable: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case prd
    case prototype
    case dataModel
    case lowCode
    case tasks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prd: return "PRD 需求文档"
        case .prototype: return "页面原型描述"
        case .dataModel: return "数据模型"
        case .lowCode: return "低代码配置说明"
        case .tasks: return "任务拆分"
        }
    }

    var systemImage: String {
        switch self {
        case .prd: return "doc.text"
        case .prototype: return "rectangle.3.group"
        case .dataModel: return "cylinder.split.1x2"
        case .lowCode: return "square.grid.2x2"
        case .tasks: return "checklist"
        }
    }

    /// 章节骨架。写进提示词里要求 AI 逐节输出，缺哪节一眼就能看出来。
    var outline: [String] {
        switch self {
        case .prd:
            return [
                "产品定位：一句话说清这是什么、给谁、解决什么问题",
                "目标用户与典型使用场景（2~3 个具体场景，不要写「各类用户」）",
                "功能清单：按 P0（必须有）/ P1（应该有）/ P2（以后再说）分级，每条功能都带验收标准",
                "页面清单与跳转关系（哪个页面能到哪个页面）",
                "非功能需求：性能、数据安全、合规（比如是否需要实名、隐私政策）",
                "里程碑建议：先做什么、后做什么，以及为什么是这个顺序",
                "风险与待确认事项（写清楚你自己不确定的地方）",
            ]
        case .prototype:
            return [
                "页面清单，以及每个页面的目标（用户来这一页是要完成什么）",
                "每个页面自上而下的区域划分：顶部放什么、中间放什么、底部放什么",
                "每个区域里的组件、展示的字段、字段的格式（时间用哪种格式、金额保留几位）",
                "交互行为：点击 / 长按 / 滑动 / 拖拽分别发生什么",
                "页面之间的跳转关系和返回逻辑",
                "加载中 / 空 / 出错 三种状态各自的显示内容",
            ]
        case .dataModel:
            return [
                "实体清单，每个实体一句话说明它代表什么",
                "每个实体的字段表：字段名 / 类型 / 是否必填 / 默认值 / 说明",
                "实体之间的关系（一对一 / 一对多 / 多对多），以及关系怎么存储",
                "需要建索引的字段，以及为什么需要",
                "数据量级估算（这决定了要不要分页、要不要缓存）",
            ]
        case .lowCode:
            return [
                "数据源怎么配：用哪张表 / 哪个接口，字段怎么映射",
                "每个页面用哪些组件、组件绑定哪些字段",
                "事件与逻辑编排：点一下之后按顺序做什么（带条件分支）",
                "变量与状态：哪些数据要跨页面保留",
                "哪些地方低代码做不到、必须写自定义代码",
            ]
        case .tasks:
            return [
                "按可独立交付的粒度拆任务，每个任务控制在半天到两天",
                "每个任务列出要改的文件 / 页面 / 组件",
                "任务之间的依赖顺序，哪些可以并行",
                "每个任务怎么验收（具体到能点哪里、看到什么算完成）",
            ]
        }
    }
}

// MARK: - 页面类型

enum ProtoPageKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case home
    case list
    case detail
    case form
    case dashboard
    case auth
    case onboarding
    case search
    case profile
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "首页 / 工作台"
        case .list: return "列表页"
        case .detail: return "详情页"
        case .form: return "表单页"
        case .dashboard: return "数据看板"
        case .auth: return "登录 / 注册"
        case .onboarding: return "引导页"
        case .search: return "搜索结果页"
        case .profile: return "个人中心"
        case .settings: return "设置页"
        }
    }

    /// 默认的区域划分。用户不用自己想「一页该分几块」，直接用这套起手再改。
    var zones: [String] {
        switch self {
        case .home:
            return [
                "顶部：搜索框 + 消息 / 通知入口",
                "内容区：模块化卡片，按重要程度从上到下排",
                "底部：主操作入口（最想让人点的那一个）",
            ]
        case .list:
            return [
                "顶部：标题 + 搜索 / 筛选入口",
                "内容区：条目列表（明确每条显示哪几个字段）",
                "底部：主操作按钮或分页 / 加载更多",
            ]
        case .detail:
            return [
                "顶部：标题 + 返回 + 更多操作（分享 / 收藏）",
                "摘要区：主图或关键信息概览",
                "正文区：分段的详细内容",
                "底部固定栏：主操作按钮",
            ]
        case .form:
            return [
                "顶部：页面标题 +（分步时）步骤指示",
                "表单区：字段按语义分组，不按数据类型堆在一起",
                "底部：提交 / 取消，说明提交后发生什么",
            ]
        case .dashboard:
            return [
                "顶部：时间范围筛选 + 刷新",
                "指标卡区：4~6 个关键数字，每个都带同比或环比",
                "图表区：一个趋势图 + 一个分布图",
                "明细区：可下钻的表格",
            ]
        case .auth:
            return [
                "品牌区：Logo + 一句说明这个产品是干什么的",
                "输入区：账号 + 密码 / 验证码，登录方式的切换",
                "辅助区：忘记密码、协议勾选、错误提示的位置",
                "底部：第三方登录入口（如果有）",
            ]
        case .onboarding:
            return [
                "示意图区：一张图或一段动效说明价值",
                "文案区：标题 + 一句补充说明",
                "进度区：分页指示点，可跳过",
                "底部：下一步 / 立即开始",
            ]
        case .search:
            return [
                "顶部：搜索框（自动聚焦）+ 取消",
                "未输入时：搜索历史 + 热门词",
                "有结果时：结果列表 + 排序筛选条",
                "无结果时：给出建议词或放宽条件的入口",
            ]
        case .profile:
            return [
                "头部：头像 + 昵称 + 账号标识",
                "数据概览：2~4 个关键数字，点了能跳到对应列表",
                "功能入口：分组排列的列表项",
                "底部：退出登录（危险操作单独放）",
            ]
        case .settings:
            return [
                "按主题分组的选项列表",
                "每一行：标题 + 当前值 + 进入箭头；开关直接就地切换",
                "危险操作（注销、清空数据）单独一组，样式要跟普通项区分开",
            ]
        }
    }

    /// 这类页面最容易做砸的地方，直接写进提示词当约束
    var focus: [String] {
        switch self {
        case .home:
            return ["区分「必须看到」和「可以滑到」的内容", "首屏别塞超过 2 个主行动点，多了等于没有"]
        case .list:
            return ["每条最多 3 个主要字段 + 1 个次要字段，再多就变成表格了", "只有 1 条数据时也要好看", "加载更多用滚动触发还是点按钮，二选一，别混用"]
        case .detail:
            return ["正文的排版比功能重要，行高和段间距要舒服", "底部固定栏不要挡住最后一段内容"]
        case .form:
            return ["校验错误就近显示在字段下方，不要统一堆在顶部", "必填项要有明确标记，且提交前不要提前报错", "提交按钮要在点下去的那一刻就进入加载态，防重复提交"]
        case .dashboard:
            return ["每个数字都要有对比基准，孤零零的数字没有意义", "图表不要为了好看而堆装饰，能被误读的图表不如表格"]
        case .auth:
            return ["错误提示不要区分「账号不存在」和「密码错误」，这两个分开说会泄露账号是否存在", "验证码要有倒计时，且倒计时期间按钮禁用而不是消失"]
        case .onboarding:
            return ["最多 3 屏，超过就是说明书不是引导", "每一屏都要能被跳过，用户随时想直接开始用"]
        case .search:
            return ["输入和出结果之间要有反馈，哪怕只是骨架屏", "空结果页要给出下一步，不能只说「没有找到」"]
        case .profile:
            return ["入口按语义分组，超过 7 个就要考虑收进二级页", "危险操作不要和常用入口挨着"]
        case .settings:
            return ["改完立即生效的，就不要再加一个「保存」按钮", "每一行的说明要讲清改了会发生什么"]
        }
    }
}

// MARK: - 页面状态

enum ProtoPageState: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case loading
    case empty
    case error
    case offline
    case noPermission
    case success

    var id: String { rawValue }

    var title: String {
        switch self {
        case .loading: return "加载中"
        case .empty: return "没有数据"
        case .error: return "出错"
        case .offline: return "断网"
        case .noPermission: return "无权限"
        case .success: return "操作成功"
        }
    }

    var brief: String {
        switch self {
        case .loading: return "首屏用骨架屏，局部刷新用转圈；超过 1 秒才显示，避免闪一下更难受"
        case .empty: return "说清楚为什么空——是还没有数据、被筛掉了、还是没权限，并给一个能点的下一步"
        case .error: return "用人话说发生了什么，配一个重试按钮，再给一个兜底出口（返回上一页）"
        case .offline: return "顶部一条常驻提示条；涉及写入的按钮要禁用并说明原因，不要让人点了才失败"
        case .noPermission: return "说明需要什么权限、怎么申请，不要只显示「无权限」四个字"
        case .success: return "轻量操作给轻提示，重要操作给结果页并带下一步入口"
        }
    }
}

// MARK: - 组件类型

enum ProtoComponentKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case button
    case modal
    case form
    case table
    case card
    case list
    case nav
    case tabs
    case dropdown
    case steps
    case upload
    case toast
    case emptyState
    case skeleton

    var id: String { rawValue }

    var title: String {
        switch self {
        case .button: return "按钮"
        case .modal: return "弹窗 / 对话框"
        case .form: return "表单"
        case .table: return "表格"
        case .card: return "卡片"
        case .list: return "列表 / 信息流"
        case .nav: return "导航 / 标签栏"
        case .tabs: return "标签页"
        case .dropdown: return "下拉菜单"
        case .steps: return "步骤条"
        case .upload: return "上传"
        case .toast: return "轻提示"
        case .emptyState: return "空状态"
        case .skeleton: return "骨架屏"
        }
    }

    /// 这个组件由哪几块组成——漏块是组件做不完整的主要原因
    var parts: [String] {
        switch self {
        case .button:
            return ["容器（点击区域至少 44×44pt，别只让文字可点）", "文字或图标（只放图标的要有无障碍标签）", "加载态（点下去立刻进入，防重复提交）", "禁用态（要说清为什么禁用）"]
        case .modal:
            return ["遮罩层（点击是否关闭要明确，危险操作不关）", "标题区 + 关闭按钮", "内容区（内容长时可滚动，滚动条不要盖住按钮）", "操作区（主操作和取消的位置固定，别随内容移动）"]
        case .form:
            return ["字段分组（按语义分，不按数据类型堆）", "标签与输入框的对齐方式（左对齐标签更利于扫读）", "就近的校验提示", "提交区（禁用条件、加载态、失败后保留已填内容）"]
        case .table:
            return ["表头（可排序的列要有方向指示）", "行（斑马纹或分隔线，只选一种）", "列宽策略（哪些列固定宽、哪些自适应、超长怎么截断）", "批量选择（表头三态：全选/半选/未选）", "空数据与加载中的占位"]
        case .card:
            return ["主信息（一眼能认出来的那一个）", "次要信息（最多 2 条）", "状态标记（标签 / 徽标）", "操作区（悬浮出现还是常驻，二选一）"]
        case .list:
            return ["条目模板", "分隔与分组规则", "加载更多的触发方式", "点击反馈与进入详情的方式"]
        case .nav:
            return ["当前位置的指示（高亮 + 无障碍标记）", "层级深度（超过两级别都摊在底部）", "图标与文字的关系（要不要文字）", "安全区适配"]
        case .tabs:
            return ["标签项的排列方式（等宽还是按内容）", "超出宽度怎么办（可滚动 or 折叠成更多）", "选中指示器", "与内容区的联动（切换是否保持滚动位置）"]
        case .dropdown:
            return ["触发区", "浮层定位（空间不够时往上弹）", "选项的选中态与禁用态", "键盘操作（上下键、回车、Esc 关闭）"]
        case .steps:
            return ["步骤项的三种状态（已完成/进行中/未开始）", "连接线的样式", "当前步骤与标题的对应", "能否点击跳回上一步"]
        case .upload:
            return ["触发区（拖拽 + 点击两种都要有）", "文件类型与大小限制的前置说明", "上传中的进度与取消", "失败重传与已上传列表的删除"]
        case .toast:
            return ["出现位置（固定一处，别乱跑）", "自动消失时长（可关闭，长文案要暂停计时）", "同时出现多条时的堆叠规则", "不要用于必须确认的信息"]
        case .emptyState:
            return ["一张图或图标", "一句话说明为什么空", "一个能点的下一步按钮"]
        case .skeleton:
            return ["骨架形状要和真实内容对齐（否则加载完成时会跳）", "循环动画的节奏（不要闪得太快）", "超过一定时间还没回来就要换成错误态"]
        }
    }

    /// 做这个组件最容易踩的坑
    var focus: [String] {
        switch self {
        case .button: return ["同屏只允许一个主按钮", "禁用按钮要保留在原来的位置，不要隐藏"]
        case .modal: return ["危险操作的确认按钮不要默认聚焦", "嵌套弹窗最多两层，第三层改用页面"]
        case .form: return ["不要在用户还没填完就报错", "长表单要防误触返回，退出前提示未保存"]
        case .table: return ["横向滚动时表头的处理要先想好", "排序和分页是两件事，别混在一个控件里"]
        case .card: return ["卡片内容高度不齐时，操作按钮要对齐到底部"]
        case .list: return ["列表项的点击区域要整行可点", "上拉加载和下拉刷新不要同时触发"]
        case .nav: return ["选中项和未选中项的对比度要够"]
        case .tabs: return ["标签多了不要横向挤压文字，改成可滚动"]
        case .dropdown: return ["选项超过 10 个就要考虑加搜索"]
        case .steps: return ["步骤名过长时截断要有完整提示"]
        case .upload: return ["上传前先校验再传，别传完才说不支持"]
        case .toast: return ["不要用轻提示承载用户必须知道的信息"]
        case .emptyState: return ["空状态不是错误状态，语气要友好"]
        case .skeleton: return ["骨架屏不能比真实内容宽或窄太多"]
        }
    }
}

// MARK: - 变体

enum ProtoVariant: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case size
    case tone
    case disabled
    case loading
    case darkMode
    case responsive
    case keyboard
    case density

    var id: String { rawValue }

    var title: String {
        switch self {
        case .size: return "尺寸"
        case .tone: return "语气 / 颜色"
        case .disabled: return "禁用态"
        case .loading: return "加载态"
        case .darkMode: return "深色模式"
        case .responsive: return "窄屏适配"
        case .keyboard: return "键盘操作"
        case .density: return "疏密两档"
        }
    }

    var brief: String {
        switch self {
        case .size: return "尺寸档位（小 / 中 / 大），明确每档的高度和内边距"
        case .tone: return "语气档位（主要 / 次要 / 危险 / 成功 / 幽灵），说明各自的适用场景"
        case .disabled: return "禁用态：降低对比度、禁用指针事件，并说明为什么禁用"
        case .loading: return "加载态：保留原宽度避免布局跳动，同时禁止重复点击"
        case .darkMode: return "深色模式：全部用语义色，不要写死色值"
        case .responsive: return "窄屏：说明内容怎么折行或隐藏，哪些优先级低的元素先收起"
        case .keyboard: return "键盘：Tab 能聚焦、有可见焦点环、回车触发主操作、Esc 取消"
        case .density: return "疏密两档：舒适（默认）和紧凑（一屏放更多行）"
        }
    }
}

// MARK: - 流程节点

/// 对应 Mermaid 的六种节点形状。`shape` 那段是语法模板，
/// `open`/`close` 之间塞文本，塞之前必须先过一遍转义。
enum FlowNodeKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case start
    case process
    case decision
    case io
    case subroutine
    case storage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .start: return "开始 / 结束"
        case .process: return "处理步骤"
        case .decision: return "判断"
        case .io: return "输入 / 输出"
        case .subroutine: return "子流程"
        case .storage: return "数据存储"
        }
    }

    var shapeName: String {
        switch self {
        case .start: return "圆角"
        case .process: return "矩形"
        case .decision: return "菱形"
        case .io: return "平行四边形"
        case .subroutine: return "双边框"
        case .storage: return "圆柱"
        }
    }

    /// Mermaid 语法里的开合符号
    var delimiters: (open: String, close: String) {
        switch self {
        case .start: return ("([", "])")
        case .process: return ("[", "]")
        case .decision: return ("{", "}")
        case .io: return ("[/", "/]")
        case .subroutine: return ("[[", "]]")
        case .storage: return ("[(", ")]")
        }
    }

    var systemImage: String {
        switch self {
        case .start: return "circle.circle"
        case .process: return "square"
        case .decision: return "diamond"
        case .io: return "arrow.left.arrow.right.square"
        case .subroutine: return "square.on.square"
        case .storage: return "cylinder"
        }
    }

    /// 新加节点时的默认文字，省得留个空白框
    var defaultText: String {
        switch self {
        case .start: return "开始"
        case .process: return "处理步骤"
        case .decision: return "条件成立？"
        case .io: return "输入数据"
        case .subroutine: return "子流程"
        case .storage: return "写入数据库"
        }
    }
}

// MARK: - 流程方向

enum FlowDirection: String, CaseIterable, Identifiable, Codable, Sendable {
    case topDown
    case leftRight
    case bottomUp
    case rightLeft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topDown: return "自上而下"
        case .leftRight: return "从左到右"
        case .bottomUp: return "自下而上"
        case .rightLeft: return "从右到左"
        }
    }

    /// Mermaid 的方向关键字（v11 起 TD 和 TB 等价，用 TD 更主流）
    var mermaid: String {
        switch self {
        case .topDown: return "TD"
        case .leftRight: return "LR"
        case .bottomUp: return "BT"
        case .rightLeft: return "RL"
        }
    }
}

// MARK: - 同一个「否则」选项

/// 判断节点的「否则」分支能指向哪里。
/// 不用裸 UUID 直接表示「不画这条线」——那太容易看错，显式给个选项。
enum FlowElseTarget: Hashable, Sendable {
    case none
    case node(UUID)
}

// MARK: - 流程节点

struct FlowNode: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var kind: FlowNodeKind
    var text: String
    /// 只有判断节点用得上：不满足条件时走到哪。nil 表示不画这条分支。
    var elseTarget: UUID?
    var elseLabel: String
    /// 流程到此为止，不再连向它下面的节点。
    ///
    /// 这一位不能省：节点之间是按顺序自动连线的，如果一条支线走完就该结束，
    /// 不标终止就会被连到后面那个不相关的节点上——图看着像对，逻辑是错的。
    var isTerminal: Bool

    init(
        id: UUID = UUID(),
        kind: FlowNodeKind = .process,
        text: String = "",
        elseTarget: UUID? = nil,
        elseLabel: String = "否",
        isTerminal: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.elseTarget = elseTarget
        self.elseLabel = elseLabel
        self.isTerminal = isTerminal
    }

    // 手写解码：以后加字段时，老数据缺这个键也能读出来，不会整段流程作废
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        kind = (try? container.decode(FlowNodeKind.self, forKey: .kind)) ?? .process
        text = (try? container.decode(String.self, forKey: .text)) ?? ""
        elseTarget = try? container.decodeIfPresent(UUID.self, forKey: .elseTarget)
        elseLabel = (try? container.decode(String.self, forKey: .elseLabel)) ?? "否"
        isTerminal = (try? container.decode(Bool.self, forKey: .isTerminal)) ?? false
    }

    /// 文本没填时给它一个兜底显示名（预览和校验都用）
    var displayText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.defaultText : trimmed
    }

    var isEmptyText: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - 四份输入

struct ProtoRequirementInput: Equatable, Hashable, Codable, Sendable {
    var name: String = ""
    var idea: String = ""
    var audience: String = ""
    /// 一行一个功能
    var features: [String] = []
    var platform: ProtoPlatform = .web
    var stack: ProtoStack = .unspecified
    var deliverables: Set<ProtoDeliverable> = [.prd]
    /// 一行一条约束
    var constraints: [String] = []
    var extra: String = ""

    var isEmpty: Bool {
        // 必须用 whitespacesAndNewlines：只写 .whitespaces 的话，
        // 一个只含换行的输入会被判成「有内容」
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && features.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

struct ProtoPageInput: Equatable, Hashable, Codable, Sendable {
    var pageName: String = ""
    var kind: ProtoPageKind = .list
    var purpose: String = ""
    var platform: ProtoPlatform = .miniProgram
    var stack: ProtoStack = .unspecified
    /// 这个页面要展示 / 收集的数据
    var fields: [String] = []
    /// 用户在这一页能做的操作
    var actions: [String] = []
    var states: Set<ProtoPageState> = [.loading, .empty, .error]
    var extra: String = ""

    var isEmpty: Bool {
        pageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ProtoComponentInput: Equatable, Hashable, Codable, Sendable {
    var name: String = ""
    var kind: ProtoComponentKind = .button
    var purpose: String = ""
    var platform: ProtoPlatform = .web
    var stack: ProtoStack = .unspecified
    /// 一行一个属性，支持 `名字: 说明` 的写法
    var props: [String] = []
    var variants: Set<ProtoVariant> = [.size, .tone, .disabled, .loading]
    /// 一行一条交互
    var interactions: [String] = []
    var includeA11y: Bool = true
    var includeTesting: Bool = true
    var extra: String = ""

    var isEmpty: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ProtoFlowInput: Equatable, Hashable, Codable, Sendable {
    var title: String = ""
    var direction: FlowDirection = .topDown
    var nodes: [FlowNode] = []

    var isEmpty: Bool { nodes.isEmpty }

    /// 至少得有个名字，不然图看起来像半成品
    var effectiveTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "流程图" : trimmed
    }
}

// MARK: - 引擎统一输出

/// 三个文本引擎都返回这个结构，界面就能共用同一张「工具做了什么」卡，
/// 不用为每段各写一套反馈展示。
struct ProtoOutput: Equatable, Sendable {
    var text: String
    /// 工具替你补了什么
    var filled: [String] = []
    /// 必须你自己定，工具不猜
    var todo: [String] = []
    /// 留意
    var notes: [String] = []
    /// 输入本身有问题（比如什么都没填）
    var warnings: [String] = []

    var isEmpty: Bool { text.isEmpty }

    static let empty = ProtoOutput(text: "")
}

// MARK: - 小工具

enum ProtoText {
    /// 多行文本切成非空行，顺便去重（保留首次出现的顺序）
    static func lines(_ text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            // 列表里的重复项对 AI 是噪音，去掉
            if seen.insert(line).inserted {
                out.append(line)
            }
        }
        return out
    }

    /// 把用户输入拆成条目。
    ///
    /// 比按行拆多走一步：如果一行里用顿号 / 逗号并列了好几个短语，就继续拆开。
    /// 判断依据是**每段的长度**——「商品浏览、加入购物车」该拆成两条，
    /// 而「用户能在页面上查看商品详情，并且可以分享」这种是完整句子，不能拆。12 字是分界线。
    static func items(_ text: String) -> [String] {
        var out: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let separators: Set<Character> = ["、", "，", ",", "；", ";"]
            let parts = line
                .split(whereSeparator: { separators.contains($0) })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            if parts.count > 1, parts.allSatisfy({ $0.count <= 12 }) {
                out.append(contentsOf: parts)
            } else {
                out.append(line)
            }
        }

        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    /// 数组拼成「1. xxx」这种编号列表；空数组给一句占位
    static func numbered(_ items: [String], empty: String = "（还没写）") -> String {
        guard !items.isEmpty else { return empty }
        return items.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
    }

    /// 拼成 Markdown 无序列表
    static func bulleted(_ items: [String], indent: String = "") -> String {
        items.map { "\(indent)- \($0)" }.joined(separator: "\n")
    }

    /// 去首尾空白后是否为空
    static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 去掉行尾的「：」，让拼出来的句子不别扭
    static func colonFree(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespaces)
        while result.hasSuffix("：") || result.hasSuffix(":") {
            result.removeLast()
        }
        return result
    }
}
