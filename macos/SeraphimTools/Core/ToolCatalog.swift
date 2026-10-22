import SwiftUI

/// 工具分类。新增分类直接往这里加 case 即可。
enum ToolCategory: String, CaseIterable, Identifiable {
    case code = "编码与识别"
    case image = "图像与媒体"
    case dev = "开发辅助"
    case product = "AI 创作"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .code: return "square.grid.3x3.square"
        case .image: return "photo.on.rectangle.angled"
        case .dev: return "hammer"
        case .product: return "sparkles"
        }
    }
}

/// 一个工具条目。视图通过闭包延迟构造，避免一次性把整个工具箱都实例化。
struct ToolItem: Identifiable {
    let id: String
    let title: String
    let summary: String
    let systemImage: String
    let tint: Color
    let category: ToolCategory
    let makeView: () -> AnyView

    init(
        id: String,
        title: String,
        summary: String,
        systemImage: String,
        tint: Color = .accentColor,
        category: ToolCategory,
        @ViewBuilder content: @escaping () -> some View
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.systemImage = systemImage
        self.tint = tint
        self.category = category
        self.makeView = { AnyView(content()) }
    }
}

/// 工具注册表。
///
/// **添加新工具只需要在 `all` 里追加一行**，侧边栏和详情页会自动带上。
enum ToolCatalog {
    static let all: [ToolItem] = [
        ToolItem(
            id: "qrcode",
            title: "二维码",
            summary: "生成与识别 QR Code",
            systemImage: "qrcode",
            tint: .indigo,
            category: .code,
            content: { QRCodeToolView() }
        ),
        ToolItem(
            id: "codec",
            title: "编码解码",
            summary: "Base64 · URL · Hex · HTML 实体 · 字符集转换",
            systemImage: "arrow.left.arrow.right",
            tint: .blue,
            category: .code,
            content: { CodecToolView() }
        ),
        ToolItem(
            id: "crypto",
            title: "加密解密",
            summary: "哈希 · HMAC · AES · ChaCha20 · 古典密码 · 随机生成",
            systemImage: "lock.shield",
            tint: .pink,
            category: .dev,
            content: { CryptoToolView() }
        ),
        ToolItem(
            id: "image",
            title: "图像处理",
            summary: "转换 · 压缩 · 缩放 · 裁剪 · 水印 · Base64",
            systemImage: "photo.on.rectangle.angled",
            tint: .teal,
            category: .image,
            content: { ImageToolView() }
        ),
        ToolItem(
            id: "devkit",
            title: "开发辅助",
            summary: "时间戳 · 颜色取色 · 中国色 · 正则 · 端口检测",
            systemImage: "hammer.fill",
            tint: .orange,
            category: .dev,
            content: { DevToolView() }
        ),
        ToolItem(
            id: "netkit",
            title: "网络工具",
            summary: "IP 查询 · Ping/Telnet · HTTP 请求 · cURL · DNS",
            systemImage: "network",
            tint: .green,
            category: .dev,
            content: { NetToolView() }
        ),
        ToolItem(
            id: "v2ray",
            title: "v2ray 代理",
            summary: "本地代理 · 节点链接解析 · 云端一键安装",
            systemImage: "shield.lefthalf.filled",
            tint: .purple,
            category: .dev,
            content: { V2RayView() }
        ),
        ToolItem(
            id: "units",
            title: "单位换算",
            summary: "单位互转 · 鞋码衣服尺码对照（欧码 / 美码 / 国内码）",
            systemImage: "arrow.left.arrow.right.square",
            tint: .mint,
            category: .dev,
            content: { UnitToolView() }
        ),
        ToolItem(
            id: "calendar",
            title: "日历与定时",
            summary: "农历互转 · 日期差 · 工作日 · cron 表达式",
            systemImage: "calendar.badge.clock",
            tint: .red,
            category: .dev,
            content: { CalendarToolView() }
        ),
        ToolItem(
            id: "generator",
            title: "生成器",
            summary: "测试数据 · 短 UUID · Snowflake ID 生成与解析",
            systemImage: "dice",
            tint: .brown,
            category: .dev,
            content: { GeneratorToolView() }
        ),
        ToolItem(
            id: "picker",
            title: "屏幕取色",
            summary: "系统吸管 · 截屏放大取色 · 色值历史",
            systemImage: "eyedropper.halffull",
            tint: .cyan,
            category: .dev,
            content: { PickerToolView() }
        ),
        ToolItem(
            id: "gitpal",
            title: "Git 助手",
            summary: "一键克隆 · 一键推送（GitHub / Gitee）",
            systemImage: "arrow.triangle.branch",
            tint: .blue,
            category: .dev,
            content: { GitToolView() }
        ),
        ToolItem(
            id: "sshkey",
            title: "SSH 密钥",
            summary: "查看 · 生成 · 权限体检 · agent · known_hosts",
            systemImage: "key.horizontal",
            tint: .yellow,
            category: .dev,
            content: { SSHKeyToolView() }
        ),
        ToolItem(
            id: "autoclick",
            title: "鼠标连点",
            summary: "鼠标连点 · 键盘连发 · 全局快捷键启停",
            systemImage: "cursorarrow.click.2",
            tint: .orange,
            category: .dev,
            content: { AutoClickerView() }
        ),
        ToolItem(
            id: "prompts",
            title: "提示词",
            summary: "模板库 · 压缩省 token · 一句话扩写成结构化提示词",
            systemImage: "wand.and.sparkles",
            tint: .purple,
            category: .product,
            content: { PromptToolView() }
        ),
        ToolItem(
            id: "balance",
            title: "API 余额",
            summary: "各家大模型 Key 余额与存活检测 · Key 存钥匙串",
            systemImage: "creditcard",
            tint: .teal,
            category: .dev,
            content: { BalanceToolView() }
        ),
        ToolItem(
            id: "proto",
            title: "原型助手",
            summary: "需求转提示词 · 页面原型 · 组件规格 · Mermaid 流程图",
            systemImage: "pencil.and.ruler",
            tint: .indigo,
            category: .product,
            content: { ProtoToolView() }
        ),
    ]

    static func tool(id: String?) -> ToolItem? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    static func tools(in category: ToolCategory) -> [ToolItem] {
        all.filter { $0.category == category }
    }
}
