import AppKit
import SwiftUI

/// 本地 Webhook 接收器：一键起一个临时 HTTP 端点，把打进来的请求都记下来给人看。
struct WebhookView: View {
    @AppStorage("webhookPort") private var portText = "8765"
    @AppStorage("webhookReplyStatus") private var replyStatus = 200
    @AppStorage("webhookReplyBody") private var replyBodyText = "{\n  \"ok\": true\n}"
    @AppStorage("webhookAutoStart") private var autoStart = false
    @AppStorage("webhookAutoExpand") private var autoExpand = true

    @StateObject private var server = WebhookServer()
    @State private var toast: String?
    @State private var expandedID: Int?
    @State private var filterText = ""
    @State private var didInit = false

    private var port: UInt16 {
        UInt16(portText.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private var endpointText: String {
        "http://localhost:\(portText.trimmingCharacters(in: .whitespaces))/任意路径"
    }

    private var filteredRequests: [WebhookRequest] {
        let keyword = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return server.requests }
        return server.requests.filter {
            $0.summary.lowercased().contains(keyword)
                || $0.headers.contains { $0.name.lowercased().contains(keyword) || $0.value.lowercased().contains(keyword) }
                || ($0.bodyInspection.pretty?.lowercased().contains(keyword) ?? false)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                controlCard
                requestsCard
            }
            .padding(20)
        }
        .toast($toast)
        .task {
            guard !didInit else { return }
            didInit = true
            if autoStart, port > 0, !server.state.isRunning {
                server.start(port: port, status: replyStatus, body: replyBodyText)
            }
        }
        .onChange(of: server.requests.first?.id) { _, newID in
            if autoExpand, let newID {
                expandedID = newID
            }
        }
    }

    // MARK: 控制卡

    private var controlCard: some View {
        ToolCard(title: "接收服务器", systemImage: "dot.radiowaves.left.and.right") {
            HStack(spacing: 12) {
                statusPill

                HStack(spacing: 6) {
                    Text("端口")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    TextField("8765", text: $portText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5, design: .monospaced))
                        .frame(width: 72)
                        .disabled(server.state.isRunning || server.state.isBusy)
                }

                HStack(spacing: 6) {
                    Text("回个状态码")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Menu("\(replyStatus)") {
                        ForEach([200, 201, 202, 204, 400, 403, 404, 500], id: \.self) { code in
                            Button("\(code)") { replyStatus = code }
                        }
                    }
                    .frame(width: 76)
                    .controlSize(.small)
                    .disabled(server.state.isRunning)
                }

                Spacer(minLength: 0)

                if server.state.isRunning {
                    Button(role: .destructive) {
                        server.stop()
                        toast = "已停止，端点下线"
                    } label: {
                        Label("停止", systemImage: "stop.fill")
                    }
                } else {
                    Button {
                        guard port > 0 else {
                            toast = "端口得是 1-65535 的数字"
                            NSSound.beep()
                            return
                        }
                        expandedID = nil
                        server.start(port: port, status: replyStatus, body: replyBodyText)
                    } label: {
                        Label("启动接收", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button {
                    server.clear()
                } label: {
                    Label("清空", systemImage: "trash")
                }
                .controlSize(.small)
                .disabled(server.requests.isEmpty)
            }

            if server.state.isRunning {
                HStack(spacing: 10) {
                    Text("把回调地址填到对方系统里：")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text(endpointText)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                        .textSelection(.enabled)
                    CopyIconButton(text: endpointText, help: "复制回调地址")
                    Spacer(minLength: 0)
                    Text("本机回环监听，请求不出你的电脑")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            } else if case .failed(let message) = server.state {
                ErrorBanner(message: message)
            } else {
                Text("启动后这个进程会在本机开一个 HTTP 端口，任何 POST / GET 打进来都会被完整记录：请求头、查询串、body（JSON / 表单 / XML 自动格式化）。")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                NetStatTile(title: "已捕获", value: "\(server.requestCount)", hint: "最多保留 200 条")
                NetStatTile(title: "收到字节", value: byteCountShort(server.bytesReceived))
                Toggle("请求到达时提示音", isOn: $server.chimeOnRequest)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
                Toggle("自动展开最新请求", isOn: $autoExpand)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
                Toggle("打开面板时自动恢复接收", isOn: $autoStart)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
                    .onChange(of: autoStart) { _, enabled in
                        // 打开开关的当下就顺手把服务拉起来，少一次点击
                        if enabled, !server.state.isRunning, !server.state.isBusy, port > 0 {
                            server.start(port: port, status: replyStatus, body: replyBodyText)
                        }
                    }
                Spacer(minLength: 0)
            }

            DisclosureGroup("响应体（回给调用方的内容）") {
                TextPane(
                    title: "Response Body",
                    text: $replyBodyText,
                    placeholder: "{\n  \"ok\": true\n}",
                    minHeight: 90
                )
                .disabled(server.state.isRunning)
            }
            .font(.system(size: 11.5))
        }
    }

    private var statusPill: some View {
        Group {
            switch server.state {
            case .running:
                NetStatusPill(text: "运行中 · 端口 \(portText)", tint: .green, systemImage: "circle.fill")
            case .starting:
                NetStatusPill(text: "启动中…", tint: .orange, systemImage: "circle.lefthalf.filled")
            case .failed:
                NetStatusPill(text: "失败", tint: .red, systemImage: "exclamationmark.triangle.fill")
            case .idle:
                NetStatusPill(text: "未启动", tint: .secondary, systemImage: "circle.dashed")
            }
        }
    }

    // MARK: 请求列表

    private var requestsCard: some View {
        ToolCard(title: "捕获到的请求", systemImage: "tray.and.arrow.down") {
            if server.requests.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.questionmark")
                        .foregroundStyle(.tertiary)
                    Text(server.state.isRunning
                         ? "端点开着，等请求进来…可以先用 curl 打一发试试"
                         : "还没启动接收服务器")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        TextField("按路径、请求头、body 内容过滤", text: $filterText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .frame(maxWidth: 320)
                        if !filterText.isEmpty {
                            Button("清除") { filterText = "" }
                                .controlSize(.small)
                        }
                        Spacer(minLength: 0)
                        Text("\(filteredRequests.count) / \(server.requestCount) 条")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(filteredRequests.enumerated()), id: \.element.id) { index, request in
                            requestRow(request)
                            if index < filteredRequests.count - 1 {
                                Divider().opacity(0.3)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.primary.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07))
                    )
                }
            }
        }
    }

    private func requestRow(_ request: WebhookRequest) -> some View {
        let inspection = request.bodyInspection
        let isExpanded = expandedID == request.id

        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedID = isExpanded ? nil : request.id
                }
            } label: {
                HStack(spacing: 10) {
                    methodTag(request.method)
                    Text(request.summary)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    NoticeTag(text: inspection.format, systemImage: "doc.text", tint: .secondary)
                    if request.bodyCount > 0 {
                        Text(byteCountShort(request.bodyCount))
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 6)

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(timeText(request.timestamp))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("来自 \(request.remote) · 回 \(request.replyStatus)")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        NetSectionLabel(title: "请求头", systemImage: "list.bullet", trailing: "\(request.headers.count) 条")
                        Spacer(minLength: 0)
                        CopyIconButton(text: request.curlCommand, help: "复制 curl 重放命令")
                    }
                    if request.headers.isEmpty {
                        Text("没有请求头")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    } else {
                        VStack(spacing: 3) {
                            ForEach(request.headers) { header in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(header.name)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .frame(width: 190, alignment: .leading)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Text(header.value)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }

                    Divider().opacity(0.3)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            NetSectionLabel(
                                title: inspection.format,
                                systemImage: "doc.richtext",
                                trailing: request.bodyCount == 0 ? nil : byteCountShort(request.bodyCount)
                            )
                            Spacer(minLength: 0)
                            if let pretty = inspection.pretty {
                                CopyIconButton(text: pretty, help: "复制 body")
                            }
                        }
                        if let pretty = inspection.pretty {
                            Text(pretty)
                                .font(.system(size: 11.5, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(
                                    Color(nsColor: .textBackgroundColor),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.10))
                                )
                        } else {
                            Text("body 是空的")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.025))
            }
        }
    }

    private func methodTag(_ method: String) -> some View {
        let tint: Color
        switch method {
        case "POST": tint = .accentColor
        case "GET": tint = .green
        case "PUT", "PATCH": tint = .orange
        case "DELETE": tint = .red
        default: tint = .secondary
        }
        return Text(method)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .foregroundStyle(tint)
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

/// 字节数的短写法
private func byteCountShort(_ count: Int) -> String {
    switch count {
    case ..<1024: return "\(count) B"
    case ..<(1024 * 1024): return String(format: "%.1f KB", Double(count) / 1024)
    default: return String(format: "%.2f MB", Double(count) / (1024 * 1024))
    }
}
