import SwiftUI

// MARK: - 自定义厂商

/// 只管「怎么加」，不管「加了哪些」——自定义厂商的卡片和内置厂商一样在网格里，
/// 有完整的检测结果和原始返回，没必要在这儿再列一遍。
struct BalanceCustomSection: View {
    let customs: [CustomProvider]
    var onAdd: () -> Void
    var onEdit: (CustomProvider) -> Void

    var body: some View {
        ToolCard(title: "自定义厂商", systemImage: "person.crop.square") {
            VStack(alignment: .leading, spacing: 10) {
                Text("自建的中转站、公司内部网关这类，官方列表里没有，可以自己填地址。返回的金额字段会被自动识别。\(customs.isEmpty ? "" : "已经加了 \(customs.count) 个，卡片在上面的列表里，点卡片右上角的菜单可以改或删。")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(customs.isEmpty ? "没有的话，可以从这两个常见形态起手：" : "也可以再按模板加一个：")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)

                FlowRow(spacing: 6) {
                    ForEach(BalancePreset.all) { preset in
                        ChipButton(title: preset.title) {
                            onEdit(preset.seed)
                        }
                        .help(preset.help)
                    }
                    ChipButton(title: "从空白开始", isSelected: false) {
                        onAdd()
                    }
                }
            }
        }
    }
}

/// 自定义厂商的常用预设
struct BalancePreset: Identifiable {
    let id: String
    let title: String
    let help: String
    let seed: CustomProvider

    static let all: [BalancePreset] = [
        BalancePreset(
            id: "oneapi",
            title: "one-api / new-api 自建站",
            help: "走 /api/user/self，quota 单位是 1/500000 美元",
            seed: CustomProvider(
                name: "自建站",
                baseURL: "https://你的域名",
                balanceURL: "/api/user/self",
                method: "GET",
                auth: .bearer,
                parser: "oneapi",
                currency: "USD",
                note: "one-api / new-api 自建站：填「系统设置」里的访问令牌（不是 sk- 开头的那个 key），并带上 New-Api-User 头（填你的用户 ID）。quota 字段除以 500000 就是美元。",
                extraHeaders: ["New-Api-User": "1"]
            )
        ),
        BalancePreset(
            id: "billing",
            title: "OpenAI 兼容计费端点",
            help: "很多中转站实现了 /v1/dashboard/billing/subscription",
            seed: CustomProvider(
                name: "中转站",
                baseURL: "https://你的域名",
                balanceURL: "/v1/dashboard/billing/subscription",
                method: "GET",
                auth: .bearer,
                parser: "generic",
                currency: "USD",
                note: "给兼容 ChatGPT-Next-Web 那套计费接口的站点用。这个端点通常只返回总额度（hard_limit_usd），不直接给剩余——想算剩余还得拉 /v1/dashboard/billing/usage 再相减，这里就不替你猜了。"
            )
        ),
    ]
}


// MARK: - 说明

struct BalanceHelpCard: View {
    @Binding var showCustom: Bool
    @Binding var autoRefresh: Bool

    var body: some View {
        ToolCard(title: "关于这个工具", systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 10) {
                item(
                    icon: "yensign.circle.fill", tint: .teal,
                    title: "「可查余额」——官方给了接口，能直接读到钱",
                    body: "目前对照官方文档或实测确认过的有 DeepSeek、月之暗面、硅基流动、OpenRouter。字段名都核过，赠金和充值这种区分会保留下来。"
                )
                item(
                    icon: "questionmark.circle", tint: .orange,
                    title: "「接口未证实」——路径是推测的，可能不存在",
                    body: "智谱和火山方舟的网关在路由之前就统一返回 401，真路径和瞎编的路径响应一模一样，没法证实。填上 key 试一把就行：返回 404 说明它确实没这个接口，不是你的问题。"
                )
                item(
                    icon: "checkmark.shield", tint: .secondary,
                    title: "「仅探活」——查不到钱，只能确认 key 还有效",
                    body: "大多数厂商没有用 API Key 查余额的接口：OpenAI 早就下线了 credit_grants；阿里云、腾讯云、百度云的余额在**云账户**层面，要用 AK/SK 签名才拿得到，跟 API Key 是两回事。所以这些只能发一个免费的 /models 请求验一下 key，余额还得去控制台。"
                )
                item(
                    icon: "lock.shield", tint: .green,
                    title: "Key 存在哪",
                    body: "存进 macOS 钥匙串（和系统「密码」App 里看到的是同一份），不写进任何配置文件。界面只显示掩码，请求时只发给该厂商自己的域名。要清掉的话，删单家或删已经存过的都行。"
                )
                item(
                    icon: "arrow.triangle.branch", tint: .purple,
                    title: "不同币种不混算",
                    body: "概览里的「已知余额合计」是按币种分开列的——人民币和美元直接相加没有意义，宁可给两行也不给一个能看不能用的数字。"
                )

                Divider()

                Toggle(isOn: $autoRefresh) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("打开这个工具时自动检测一遍")
                            .font(.system(size: 11.5))
                        Text("只测已经填了 Key 的厂商，一次会话只测一次，不会反复打接口。")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)

                Toggle(isOn: $showCustom) {
                    Text("显示「自定义厂商」区域")
                        .font(.system(size: 11.5))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
        }
    }

    private func item(icon: String, tint: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                Text(.init(body))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
